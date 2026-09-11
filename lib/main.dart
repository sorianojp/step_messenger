import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/data/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionController();
  runApp(StepMessengerApp(session: session));
  session.restore();
}
