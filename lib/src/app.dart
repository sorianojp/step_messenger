import 'dart:async';
import 'package:flutter/material.dart';
import 'data/models.dart';
import 'data/push_notifications.dart';
import 'data/session.dart';
import 'theme.dart';
import 'ui/chat_screen.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

class UhooApp extends StatefulWidget {
  const UhooApp({super.key, required this.session});
  final SessionController session;

  @override
  State<UhooApp> createState() => _UhooAppState();
}

class _UhooAppState extends State<UhooApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<PushDestination>? _notificationOpens;
  bool _openingNotification = false;
  bool _openScheduled = false;
  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _notificationOpens = session.pushNotifications.opened.listen((_) {
      _scheduleNotificationOpen();
    });
  }

  void _scheduleNotificationOpen() {
    if (_openScheduled || !mounted) return;
    _openScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openScheduled = false;
      _openPendingNotification();
    });
  }

  Future<void> _openPendingNotification() async {
    if (_openingNotification || session.user == null) return;
    final destination = session.pushNotifications.takePending();
    if (destination == null) return;
    _openingNotification = true;
    try {
      final targetTeam = session.teams
          .where((team) => team.id == destination.teamId)
          .firstOrNull;
      if (targetTeam == null) return;
      if (session.team?.id != targetTeam.id) {
        await session.selectTeam(targetTeam);
        await WidgetsBinding.instance.endOfFrame;
      }
      final response = await session.api.request(
        'GET',
        '${session.teamPath}/conversations/${destination.conversationId}',
      );
      if (!mounted || session.user == null) return;
      final data = response['data'];
      if (data is! Map) return;
      final conversation = Conversation(Map<String, dynamic>.from(data));
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      navigator.popUntil((route) => route.isFirst);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: '/conversations/${conversation.id}'),
            builder: (_) =>
                ChatScreen(session: session, conversation: conversation),
          ),
        ),
      );
    } catch (error) {
      final context = _navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open notification: $error')),
        );
      }
    } finally {
      _openingNotification = false;
      if (session.pushNotifications.hasPending) {
        _scheduleNotificationOpen();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (session.user != null && session.pushNotifications.hasPending) {
        _scheduleNotificationOpen();
      }
      return MaterialApp(
        // Replacing the navigator removes protected routes on session expiry.
        key: ValueKey(session.user?.id),
        navigatorKey: _navigatorKey,
        title: 'Uhoo!',
        debugShowCheckedModeBanner: false,
        theme: stepTheme(Brightness.light),
        darkTheme: stepTheme(Brightness.dark),
        themeMode: session.themeMode,
        home: session.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : session.user == null
            ? LoginScreen(session: session)
            : HomeScreen(key: ValueKey(session.team?.id), session: session),
      );
    },
  );

  @override
  void dispose() {
    _notificationOpens?.cancel();
    super.dispose();
  }
}
