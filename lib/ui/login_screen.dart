import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'otp_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  OtpChannelKind _channel = OtpChannelKind.email;
  bool _guestBusy = false;
  String? _guestError;

  Future<void> _guest(AuthService auth) async {
    setState(() {
      _guestBusy = true;
      _guestError = null;
    });
    try {
      await auth.signInAsGuest();
    } catch (e) {
      if (mounted) setState(() => _guestError = AuthService.errorText(e));
    } finally {
      if (mounted) setState(() => _guestBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService?>()!;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: scheme.primary,
                    child: const Text('₹',
                        style: TextStyle(fontSize: 36, color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  Text('Spend Utilizer',
                      style: t.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to keep your spending in sync on your phone, '
                    'Windows, Mac and Linux.',
                    style: t.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<OtpChannelKind>(
                    segments: const [
                      ButtonSegment(
                          value: OtpChannelKind.email,
                          icon: Icon(Icons.email_outlined),
                          label: Text('Email')),
                      ButtonSegment(
                          value: OtpChannelKind.phone,
                          icon: Icon(Icons.phone),
                          label: Text('Phone')),
                    ],
                    selected: {_channel},
                    onSelectionChanged: (s) =>
                        setState(() => _channel = s.first),
                  ),
                  const SizedBox(height: 16),
                  OtpForm(
                    channel: _channel,
                    onSend: _channel == OtpChannelKind.email
                        ? auth.sendEmailCode
                        : auth.sendPhoneCode,
                    onVerify: _channel == OtpChannelKind.email
                        ? auth.verifyEmailCode
                        : auth.verifyPhoneCode,
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: t.bodySmall),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _guestBusy ? null : () => _guest(auth),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Continue as guest'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start right away. You can add your email or phone '
                    'later to use the same data on other devices.',
                    style: t.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (_guestError != null) ...[
                    const SizedBox(height: 8),
                    Text(_guestError!,
                        style: TextStyle(color: scheme.error),
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
