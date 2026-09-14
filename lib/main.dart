import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/data/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionController();
  runApp(UhooApp(session: session));
  session.restore();
}
