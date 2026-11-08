import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Thin wrapper around Supabase Auth with the three sign-in options:
/// email + password, phone (SMS) code, and guest (anonymous).
///
/// Email uses a password rather than an emailed code: on Supabase's free
/// plan the email template can't be edited to include a code without
/// setting up a custom SMTP server.
class AuthService extends ChangeNotifier {
  final GoTrueClient _auth;
  StreamSubscription<AuthState>? _sub;

  AuthService(this._auth) {
    _sub = _auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  User? get user => _auth.currentUser;
  bool get signedIn => user != null;
  bool get isGuest => user?.isAnonymous ?? false;

  String get displayName {
    final u = user;
    if (u == null) return '';
    if ((u.email ?? '').isNotEmpty) return u.email!;
    if ((u.phone ?? '').isNotEmpty) return '+${u.phone!.replaceAll('+', '')}';
    return 'Guest';
  }

  /// Turns "98765 43210" into "+919876543210".
  static String normalizePhone(String input) {
    var p = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (!p.startsWith('+')) {
      if (p.startsWith('0')) p = p.substring(1);
      p = '${AppConfig.defaultCountryCode}$p';
    }
    return p;
  }

  static bool looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  static bool looksLikePhone(String s) =>
      RegExp(r'^\+\d{8,15}$').hasMatch(normalizePhone(s));

  // ---- Sign in

  /// Thrown when the Supabase project still asks new users to confirm their
  /// email (turn off "Confirm email" in the Email provider settings).
  static const confirmEmailRequired = 'confirm-email-required';

  Future<void> signInWithPassword(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signUpWithPassword(String email, String password) async {
    final res = await _auth.signUp(email: email.trim(), password: password);
    // No session means the project requires email confirmation first.
    if (res.session == null) {
      throw const AuthException(confirmEmailRequired);
    }
  }

  Future<void> sendPhoneCode(String phone) =>
      _auth.signInWithOtp(phone: normalizePhone(phone));

  Future<void> verifyPhoneCode(String phone, String code) => _auth.verifyOTP(
    phone: normalizePhone(phone),
    token: code.trim(),
    type: OtpType.sms,
  );

  Future<void> signInAsGuest() => _auth.signInAnonymously();

  // ---- Upgrade a guest to a permanent account (keeps the same data)

  /// Gives a guest account an email + password so it can be used on other
  /// devices. The data stays because it's the same account.
  Future<void> linkEmailPassword(String email, String password) async {
    final res = await _auth.updateUser(
      UserAttributes(email: email.trim(), password: password),
    );
    // If the project requires confirming email changes, the email isn't
    // attached yet.
    if ((res.user?.email ?? '').toLowerCase() != email.trim().toLowerCase()) {
      throw const AuthException(confirmEmailRequired);
    }
  }

  Future<void> linkPhone(String phone) =>
      _auth.updateUser(UserAttributes(phone: normalizePhone(phone)));

  Future<void> verifyLinkPhone(String phone, String code) => _auth.verifyOTP(
    phone: normalizePhone(phone),
    token: code.trim(),
    type: OtpType.phoneChange,
  );

  Future<void> signOut() => _auth.signOut();

  /// Human-friendly error text.
  static String errorText(Object e) {
    final raw = e is AuthException ? e.message : e.toString();
    if (RegExp(
      r'SocketException|ClientException|Failed host lookup|'
      r'Connection (refused|reset|timed out)|Network is unreachable',
    ).hasMatch(raw)) {
      return 'Can\'t reach the server. Check your internet connection and '
          'try again.';
    }
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('anonymous sign-ins are disabled')) {
        return 'Guest login is turned off for this app\'s server.';
      }
      if (m.contains('sms') && m.contains('provider')) {
        return 'Phone login isn\'t set up on the server yet. '
            'Use email or guest for now.';
      }
      if (m.contains('invalid login credentials')) {
        return 'Wrong email or password.';
      }
      if (m.contains('already registered') ||
          m.contains('already been registered') ||
          m.contains('already exists')) {
        return 'This email already has an account. Tap "Already have an '
            'account? Sign in" below.';
      }
      if (m == confirmEmailRequired || m.contains('email not confirmed')) {
        return 'The server is asking for email confirmation. In Supabase, '
            'open Authentication → Sign In / Providers → Email, turn OFF '
            '"Confirm email", save, and try again.';
      }
      if (m.contains('password')) return e.message; // e.g. too weak/short
      if (m.contains('expired') || m.contains('invalid')) {
        return 'That code is wrong or has expired. Request a new one.';
      }
      if (m.contains('rate') || m.contains('seconds')) {
        return 'Please wait a minute before requesting another code.';
      }
      return e.message;
    }
    return raw;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
