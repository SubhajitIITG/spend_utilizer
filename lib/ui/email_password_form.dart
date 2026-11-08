import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Email + password form with "Sign in" and "Create account" modes.
///
/// In [saveOnly] mode (turning a guest into a permanent account) it only
/// shows "Create account" fields and a single save button.
class EmailPasswordForm extends StatefulWidget {
  final Future<void> Function(String email, String password)? onSignIn;
  final Future<void> Function(String email, String password) onCreate;
  final bool saveOnly;
  final String createLabel;

  const EmailPasswordForm({
    super.key,
    this.onSignIn,
    required this.onCreate,
    this.saveOnly = false,
    this.createLabel = 'Create account',
  });

  @override
  State<EmailPasswordForm> createState() => _EmailPasswordFormState();
}

class _EmailPasswordFormState extends State<EmailPasswordForm> {
  static const minPasswordLength = 6;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _creating = widget.saveOnly;
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (!AuthService.looksLikeEmail(_email.text)) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }
    if (_creating && _password.text != _confirm.text) {
      return 'The two passwords don\'t match.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      if (_creating) {
        await widget.onCreate(email, _password.text);
      } else {
        await widget.onSignIn!(email, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_show,
            autofillHints: [
              _creating ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: _creating
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: (_) => _creating ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _creating
                  ? 'At least $minPasswordLength characters'
                  : null,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide password' : 'Show password',
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          if (_creating) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: !_show,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_creating ? widget.createLabel : 'Sign in'),
          ),
          if (!widget.saveOnly)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _creating = !_creating;
                      _error = null;
                    }),
              child: Text(
                _creating
                    ? 'Already have an account? Sign in'
                    : 'New here? Create an account',
              ),
            ),
        ],
      ),
    );
  }
}
