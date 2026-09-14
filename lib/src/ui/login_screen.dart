import 'package:flutter/material.dart';
import '../data/session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final SessionController session;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: 'Uhoo!',
                    image: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 144,
                        height: 144,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Your school.\nOne conversation away.',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Stay close to your school community. Messages, class updates, and the people who matter — all in one place.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 36),
                  if (session.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          session.error!,
                          style: TextStyle(color: colors.error, height: 1.5),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: session.busy
                          ? null
                          : () => session.hasSavedSession
                                ? session.restore()
                                : session.signIn(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: session.busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      session.hasSavedSession
                                          ? 'Reconnect'
                                          : 'Continue with STEP',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  if (session.hasSavedSession)
                    Center(
                      child: TextButton(
                        onPressed: session.forgetSession,
                        child: const Text('Use another account'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sign in securely with your existing STEP account. Your school manages your account and role.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 64),
                  const Divider(),
                  const SizedBox(height: 18),
                  Text(
                    'A little closer. A lot more connected.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
