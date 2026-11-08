import 'package:flutter/material.dart';

import '../services/auth_service.dart';

enum OtpChannelKind { email, phone }

/// Two-step form: enter email/phone → "Send code" → enter code → "Verify".
class OtpForm extends StatefulWidget {
  final OtpChannelKind channel;
  final Future<void> Function(String target) onSend;
  final Future<void> Function(String target, String code) onVerify;
  final String verifyLabel;

  const OtpForm({
    super.key,
    required this.channel,
    required this.onSend,
    required this.onVerify,
    this.verifyLabel = 'Verify & continue',
  });

  @override
  State<OtpForm> createState() => _OtpFormState();
}

class _OtpFormState extends State<OtpForm> {
  final _target = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  bool get _isEmail => widget.channel == OtpChannelKind.email;

  @override
  void didUpdateWidget(OtpForm old) {
    super.didUpdateWidget(old);
    if (old.channel != widget.channel) {
      _target.clear();
      _code.clear();
      _codeSent = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final v = _target.text.trim();
    final ok = _isEmail
        ? AuthService.looksLikeEmail(v)
        : AuthService.looksLikePhone(v);
    if (!ok) {
      setState(() => _error = _isEmail
          ? 'Enter a valid email address.'
          : 'Enter a valid mobile number.');
      return;
    }
    await _run(() async {
      await widget.onSend(v);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the code you received.');
      return;
    }
    await _run(() => widget.onVerify(_target.text.trim(), code));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _target,
          enabled: !_codeSent && !_busy,
          keyboardType:
              _isEmail ? TextInputType.emailAddress : TextInputType.phone,
          autofillHints: [
            _isEmail ? AutofillHints.email : AutofillHints.telephoneNumber
          ],
          decoration: InputDecoration(
            labelText: _isEmail ? 'Email address' : 'Mobile number',
            hintText: _isEmail ? 'you@example.com' : '98765 43210',
            prefixIcon: Icon(_isEmail ? Icons.email_outlined : Icons.phone),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _codeSent ? null : _send(),
        ),
        if (_codeSent) ...[
          const SizedBox(height: 8),
          Text(
            _isEmail
                ? 'We emailed a code to ${_target.text.trim()}.'
                : 'We sent an SMS code to '
                    '${AuthService.normalizePhone(_target.text)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 10,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: 'Code',
              prefixIcon: Icon(Icons.password),
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _verify(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : (_codeSent ? _verify : _send),
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_codeSent ? widget.verifyLabel : 'Send code'),
        ),
        if (_codeSent)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _codeSent = false;
                      _code.clear();
                      _error = null;
                    }),
            child: Text(_isEmail
                ? 'Use a different email / resend'
                : 'Use a different number / resend'),
          ),
      ],
    );
  }
}
