import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'firebase_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (FirebaseConfig.isConfigured && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: FirebaseConfig.options);
  }
}

class PushDestination {
  const PushDestination({required this.teamId, required this.conversationId});

  final int teamId;
  final int conversationId;

  static PushDestination? fromData(Map<String, dynamic> data) {
    final teamId = int.tryParse('${data['team_id'] ?? ''}');
    final conversationId = int.tryParse('${data['conversation_id'] ?? ''}');
    if (teamId == null || conversationId == null) return null;
    return PushDestination(teamId: teamId, conversationId: conversationId);
  }
}

class PushNotificationService {
  static const _tokenRetryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  static const _channel = AndroidNotificationChannel(
    'uhoo_messages',
    'Messages',
    description: 'New messages and conversation updates',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  final _opened = StreamController<PushDestination>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  ApiClient? _api;
  PushDestination? _pending;
  bool _available = false;
  bool _syncing = false;
  bool _syncAgain = false;
  Timer? _tokenRetryTimer;
  int _tokenRetryIndex = 0;

  Stream<PushDestination> get opened => _opened.stream;
  bool get hasPending => _pending != null;

  void _trace(String step) {
    if (kDebugMode) debugPrint('[push] $step');
  }

  Future<void> initialize() async {
    if (!FirebaseConfig.isConfigured || kIsWeb) {
      _trace('initialize: skipped (not a configured mobile platform)');
      return;
    }
    _trace('initialize: start');
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null) return;
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) {
              _receiveOpen(Map<String, dynamic>.from(decoded));
            }
          } on FormatException {
            // Ignore notifications that were not produced by Uhoo!.
          }
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen(_showForegroundNotification),
      );
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => _receiveOpen(message.data),
        ),
      );
      _subscriptions.add(
        FirebaseMessaging.instance.onTokenRefresh.listen((_) => _syncToken()),
      );
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) _receiveOpen(initialMessage.data);
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      final localPayload = localLaunch?.notificationResponse?.payload;
      if ((localLaunch?.didNotificationLaunchApp ?? false) &&
          localPayload != null) {
        final decoded = jsonDecode(localPayload);
        if (decoded is Map) {
          _receiveOpen(Map<String, dynamic>.from(decoded));
        }
      }
      _available = true;
      _trace('initialize: ready');
    } catch (error) {
      _trace('initialize: FAILED ($error)');
    }
  }

  Future<void> bind(ApiClient api) async {
    _api = api;
    _tokenRetryTimer?.cancel();
    _tokenRetryTimer = null;
    _tokenRetryIndex = 0;
    if (!_available) {
      _trace('bind: skipped, push never initialized');
      return;
    }
    _trace('bind: requesting permission');
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      _trace('bind: permission ${settings.authorizationStatus.name}');
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _syncToken();
      }
    } catch (error) {
      _trace('bind: FAILED ($error)');
    }
  }

  void unbind() {
    _api = null;
    _tokenRetryTimer?.cancel();
    _tokenRetryTimer = null;
    _tokenRetryIndex = 0;
  }

  PushDestination? takePending() {
    final destination = _pending;
    _pending = null;
    return destination;
  }

  Future<void> _syncToken() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    final api = _api;
    if (!_available || api?.token == null) {
      _trace('syncToken: skipped (available $_available, '
          'signed in ${api?.token != null})');
      return;
    }
    _syncing = true;
    try {
      // On Apple platforms, Firebase cannot issue an FCM token until APNs has
      // finished registering this installation. Permission may resolve before
      // that asynchronous registration callback arrives.
      if (Platform.isIOS) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        _trace('syncToken: APNs token ${apns == null ? 'NULL' : 'present'}');
        if (apns == null) {
          _scheduleTokenSync();
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      _trace('syncToken: FCM token ${token == null || token.isEmpty ? 'NULL' : '${token.substring(0, 12)}…'}');
      if (token == null || token.isEmpty || _api != api) return;
      await api!.request(
        'PUT',
        '/api/mobile/push-token',
        body: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'device_name': 'Uhoo! · ${Platform.operatingSystem}',
        },
      );
      _trace('syncToken: registered with the server');
      _tokenRetryTimer?.cancel();
      _tokenRetryTimer = null;
      _tokenRetryIndex = 0;
    } catch (error) {
      _trace('syncToken: FAILED ($error)');
      if (Platform.isIOS) _scheduleTokenSync();
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_syncToken());
      }
    }
  }

  void _scheduleTokenSync() {
    if (_api == null || _tokenRetryTimer?.isActive == true) return;
    if (_tokenRetryIndex >= _tokenRetryDelays.length) {
      if (kDebugMode) {
        debugPrint(
          'APNs did not provide a device token. Check the Push Notifications '
          'capability and the provisioning profile, then reopen the app.',
        );
      }
      return;
    }
    final delay = _tokenRetryDelays[_tokenRetryIndex++];
    _trace('syncToken: retrying in ${delay.inSeconds}s');
    _tokenRetryTimer = Timer(delay, () {
      _tokenRetryTimer = null;
      unawaited(_syncToken());
    });
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final destination = PushDestination.fromData(message.data);
    await _local.show(
      id:
          message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
      title: notification.title,
      body: notification.body,
      payload: jsonEncode(message.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          groupKey: destination == null
              ? null
              : 'conversation-${destination.conversationId}',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          threadIdentifier: destination == null
              ? null
              : 'conversation-${destination.conversationId}',
        ),
      ),
    );
  }

  void _receiveOpen(Map<String, dynamic> data) {
    final destination = PushDestination.fromData(data);
    if (destination == null) return;
    _pending = destination;
    _opened.add(destination);
  }

  void dispose() {
    _tokenRetryTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _opened.close();
  }
}
