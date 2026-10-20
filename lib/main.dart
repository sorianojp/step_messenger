import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/app.dart';
import 'src/data/push_notifications.dart';
import 'src/data/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [
      ('Inter', 'OFL-Inter.txt'),
      ('Plus Jakarta Sans', 'OFL-PlusJakartaSans.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  final pushNotifications = PushNotificationService();
  final session = SessionController(pushNotifications: pushNotifications);

  runApp(UhooApp(session: session));
  await pushNotifications.initialize().timeout(
    const Duration(seconds: 10),
    onTimeout: () => debugPrint('[startup] push initialization timed out'),
  );
  session.restore();
}
