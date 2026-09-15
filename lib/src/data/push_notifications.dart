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

  Stream<PushDestination> get opened => _opened.stream;
  bool get hasPending => _pending != null;

  Future<void> initialize() async {
    if (!FirebaseConfig.isConfigured || kIsWeb) return;
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
    } catch (error) {
      if (kDebugMode) debugPrint('Push notifications unavailable: $error');
    }
  }

  Future<void> bind(ApiClient api) async {
    _api = api;
    if (!_available) return;
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
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _syncToken();
      }
    } catch (error) {
      if (kDebugMode) debugPrint('Push permission/token failed: $error');
    }
  }

  void unbind() {
    _api = null;
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
    if (!_available || api?.token == null) return;
    _syncing = true;
    try {
      final token = await FirebaseMessaging.instance.getToken();
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
    } catch (error) {
      if (kDebugMode) debugPrint('Push token registration failed: $error');
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_syncToken());
      }
    }
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
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _opened.close();
  }
}
