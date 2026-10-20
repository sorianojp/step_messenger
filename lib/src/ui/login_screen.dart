import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/session.dart';
import '../theme.dart';
import 'widgets.dart';

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
    if (kDebugMode) {
      debugPrint(
        '[ui] LoginScreen build (user ${session.user?.id}, '
        'saved ${session.hasSavedSession}, '
        'session #${identityHashCode(session)})',
      );
    }
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = brandText(context);
    // Same card, copy and order as the web sign-in page (pages/auth/login.tsx).
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    decoration: BoxDecoration(
                      color: dark ? StepPalette.cardDark : StepPalette.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: stepShadowSmall,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Semantics(
                              label: 'Uhoo!',
                              image: true,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/logo.png',
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Uhoo!',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontSize: 18, height: 1.2),
                                ),
                                Text(
                                  'STEP Messages',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        Text(
                          'Welcome back',
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(fontSize: 24),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use your STEP account to access your school conversations.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.7,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (session.error != null) ...[
                          const SizedBox(height: 28),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: dark
                                    ? const Color(0x66450a0a)
                                    : const Color(0xfffef2f2),
                                borderRadius: BorderRadius.circular(
                                  StepShape.radiusMedium,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 16,
                                    color: dark
                                        ? const Color(0xfffecaca)
                                        : const Color(0xff991b1b),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      session.error!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: dark
                                            ? const Color(0xfffecaca)
                                            : const Color(0xff991b1b),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: session.busy
                                ? null
                                : () => session.hasSavedSession
                                      ? session.restore()
                                      : session.signIn(),
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
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                      ),
                                    ],
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
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'You’ll sign in securely on STEP and return here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.7,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Having trouble? ',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      InkWell(
                        onTap: () => openSupportPage(context),
                        child: Text(
                          'Get support',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: brand,
                          ),
                        ),
                      ),
                    ],
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
