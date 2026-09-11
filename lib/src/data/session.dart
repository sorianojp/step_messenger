import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'models.dart';
import 'realtime.dart';

class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  static const officialBaseUrl = 'https://messenger.udd.edu.ph';

  SessionController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    WidgetsBinding.instance.addObserver(this);
  }
  final FlutterSecureStorage _storage;
  ApiClient? _api;
  ApiClient get api => _api!;
  Person? user;
  List<Team> teams = [];
  Team? team;
  RealtimeClient? realtime;
  Json? _realtimeConfig;
  bool loading = true;
  bool busy = false;
  bool foreground = true;
  String? error;
  String get baseUrl => officialBaseUrl;
  ThemeMode themeMode = ThemeMode.system;
  String get teamPath => '/api/teams/${Uri.encodeComponent(team!.slug)}';
  bool get hasSavedSession => _api?.token != null;

  void _configure(String? token) {
    _api?.close();
    _api = ApiClient(baseUrl: officialBaseUrl)
      ..token = token
      ..onUnauthorized = expire;
  }

  Future<void> restore() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final stored = await _storage.read(key: 'step.session');
      final preferredTheme = await _storage.read(key: 'step.theme');
      themeMode =
          ThemeMode.values.where((t) => t.name == preferredTheme).firstOrNull ??
          ThemeMode.system;
      if (stored != null) {
        final data = jsonDecode(stored) as Json;
        final savedServer = data['server'] as String?;
        if (savedServer == null || savedServer == officialBaseUrl) {
          _configure(data['token'] as String);
          await _bootstrap(preferredTeam: data['team_id'] as int?);
        } else {
          // Tokens issued by a previously configured server must never be sent
          // to the official deployment.
          await _storage.delete(key: 'step.session');
        }
      }
    } catch (e) {
      if (kDebugMode && e is PlatformException) {
        debugPrint(
          'Secure session restoration failed: ${e.code}: ${e.message}',
        );
      }
      error = e is ApiException
          ? e.message
          : 'Could not restore your session. Please try again.';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> signIn() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      _configure(null);
      final random = Random.secure();
      final verifier = base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      final challenge = base64UrlEncode(
        sha256.convert(utf8.encode(verifier)).bytes,
      ).replaceAll('=', '');
      final start = await api.request(
        'POST',
        '/api/mobile/auth/start',
        body: {
          'code_challenge': challenge,
          'device_name': 'STEP Messenger · ${Platform.operatingSystem}',
        },
      );
      final authorization = Uri.parse(start['authorization_url'] as String);
      if (authorization.origin != Uri.parse(officialBaseUrl).origin) {
        throw const ApiException(
          'The server sign-in address does not match. Contact your school administrator.',
        );
      }
      final result = Uri.parse(
        await FlutterWebAuth2.authenticate(
          url: authorization.toString(),
          callbackUrlScheme: 'stepmessenger',
        ),
      );
      if (result.scheme != 'stepmessenger' ||
          result.host != 'auth' ||
          result.queryParameters['state'] != start['state']) {
        throw const ApiException(
          'The sign-in response was invalid. Please try again.',
        );
      }
      if (result.queryParameters['error'] != null ||
          result.queryParameters['code'] == null) {
        throw const ApiException(
          'STEP could not complete sign-in. Please try again.',
        );
      }
      final response = await api.request(
        'POST',
        '/api/mobile/auth/exchange',
        body: {
          'code': result.queryParameters['code'],
          'code_verifier': verifier,
        },
      );
      api.token = response['token'] as String;
      await _save();
      await _bootstrap();
    } on PlatformException catch (e) {
      error = e.code == 'CANCELED'
          ? 'Sign-in was cancelled.'
          : 'Unable to open STEP sign-in. Please try again.';
    } catch (e) {
      error = e is ApiException
          ? e.message
          : 'Unable to sign in. Please try again.';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> _bootstrap({int? preferredTeam}) async {
    final data = await api.request('GET', '/api/mobile/session');
    user = Person(data['user'] as Json);
    teams = records(data['teams']).map(Team.new).toList();
    _realtimeConfig = data['realtime'] as Json?;
    final selected = preferredTeam ?? user!.json['current_team_id'];
    team =
        teams.where((t) => t.id == selected).firstOrNull ?? teams.firstOrNull;
    _connectRealtime();
    await _save();
  }

  Future<void> selectTeam(Team selected) async {
    team = selected;
    _connectRealtime();
    notifyListeners();
    await _save();
  }

  void _connectRealtime() {
    realtime?.dispose();
    realtime = null;
    if (_realtimeConfig?['key'] != null && team != null) {
      // Web reads "who is online" from this presence channel, not from
      // last_seen_at, so mobile has to join it or it looks permanently offline.
      realtime = RealtimeClient(api, _realtimeConfig!)
        ..subscribe('presence-teams.${team!.id}.presence');
      if (foreground) realtime!.start();
    }
  }

  Future<void> _save() => _storage.write(
    key: 'step.session',
    value: jsonEncode({
      'server': officialBaseUrl,
      'token': api.token,
      'team_id': team?.id,
    }),
  );

  Future<void> signOut() async {
    if (api.token != null) await api.request('DELETE', '/api/mobile/session');
    await forgetSession();
  }

  Future<void> forgetSession() async {
    realtime?.dispose();
    realtime = null;
    if (_api != null) _api!.token = null;
    user = null;
    teams = [];
    team = null;
    await _storage.delete(key: 'step.session');
    try {
      final temp = await getTemporaryDirectory();
      final attachments = Directory('${temp.path}/step_messenger');
      if (await attachments.exists()) await attachments.delete(recursive: true);
    } catch (_) {
      /* The OS also expires temporary files. */
    }
    notifyListeners();
  }

  void expire() {
    error = 'Your session expired. Please sign in again.';
    forgetSession();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _storage.write(key: 'step.theme', value: mode.name);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      realtime?.start();
    } else {
      realtime?.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    realtime?.dispose();
    _api?.close();
    super.dispose();
  }
}
