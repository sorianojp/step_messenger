import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/data/push_notifications.dart';
import 'src/data/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pushNotifications = PushNotificationService();
  await pushNotifications.initialize();
  final session = SessionController(pushNotifications: pushNotifications);
  runApp(UhooApp(session: session));
  session.restore();
}
