import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/data/push_notifications.dart';
import 'src/data/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pushNotifications = PushNotificationService();
  final session = SessionController(pushNotifications: pushNotifications);

  runApp(UhooApp(session: session));
  await pushNotifications.initialize().timeout(
    const Duration(seconds: 10),
    onTimeout: () => debugPrint('[startup] push initialization timed out'),
  );
  session.restore();
}
