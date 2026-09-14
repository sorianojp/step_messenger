import 'package:flutter/material.dart';
import 'data/session.dart';
import 'theme.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

class UhooApp extends StatelessWidget {
  const UhooApp({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => MaterialApp(
      // Replacing the navigator removes protected routes on session expiry.
      key: ValueKey(session.user?.id),
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
    ),
  );
}
