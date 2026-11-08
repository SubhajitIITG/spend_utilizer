import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:spend_utilizer/services/auth_service.dart';
import 'package:spend_utilizer/ui/login_screen.dart';
import 'package:spend_utilizer/ui/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal stand-in for the Supabase Auth server.
class FakeAuthServer {
  final Map<String, String> passwords = {};
  bool requireEmailConfirmation = false;
  final List<String> calls = [];

  Map<String, dynamic> _user(String email, {bool anon = false}) => {
    'id': 'user-${email.hashCode.abs()}',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': email,
    'is_anonymous': anon,
    'created_at': '2026-11-08T00:00:00Z',
    'app_metadata': {'provider': anon ? 'anonymous' : 'email'},
    'user_metadata': <String, dynamic>{},
  };

  Map<String, dynamic> _session(Map<String, dynamic> user) => {
    'access_token': 'token-${user['id']}',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
    'refresh_token': 'refresh',
    'user': user,
  };

  http.Response _json(int code, Object body) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json'},
  );

  late final client = MockClient((req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    final body = req.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(req.body) as Map<String, dynamic>;
    if (req.method == 'POST' && path.endsWith('/signup')) {
      final email = body['email'] as String?;
      if (email == null) {
        return _json(200, _session(_user('', anon: true)));
      }
      if (passwords.containsKey(email)) {
        return _json(422, {
          'code': 'user_already_exists',
          'msg': 'User already registered',
        });
      }
      passwords[email] = body['password'] as String;
      final user = _user(email);
      return _json(200, requireEmailConfirmation ? user : _session(user));
    }
    if (req.method == 'POST' && path.endsWith('/token')) {
      final email = body['email'] as String;
      if (passwords[email] != body['password']) {
        return _json(400, {
          'error': 'invalid_grant',
          'error_description': 'Invalid login credentials',
        });
      }
      return _json(200, _session(_user(email)));
    }
    if (req.method == 'PUT' && path.endsWith('/user')) {
      final email = body['email'] as String;
      passwords[email] = body['password'] as String;
      final user = _user(email);
      if (requireEmailConfirmation) {
        user['email'] = '';
        user['new_email'] = email;
      }
      return _json(200, user);
    }
    return _json(404, {'msg': 'not found'});
  });
}

AuthService serviceFor(FakeAuthServer server) => AuthService(
  GoTrueClient(
    url: 'http://fake.local/auth/v1',
    httpClient: server.client,
    flowType: AuthFlowType.implicit,
    autoRefreshToken: false,
  ),
);

void main() {
  test('create account, sign out, sign in again', () async {
    final server = FakeAuthServer();
    final auth = serviceFor(server);
    await auth.signUpWithPassword(' me@example.com ', 'secret123');
    expect(auth.signedIn, isTrue);
    expect(auth.displayName, 'me@example.com');
    await auth.signOut();
    expect(auth.signedIn, isFalse);

    await expectLater(
      auth.signInWithPassword('me@example.com', 'wrong-pass'),
      throwsA(
        isA<AuthException>().having(
          (e) => AuthService.errorText(e),
          'text',
          'Wrong email or password.',
        ),
      ),
    );
    await auth.signInWithPassword('me@example.com', 'secret123');
    expect(auth.signedIn, isTrue);
  });

  test('second sign-up with same email gets a clear message', () async {
    final server = FakeAuthServer();
    final auth = serviceFor(server);
    await auth.signUpWithPassword('me@example.com', 'secret123');
    await auth.signOut();
    try {
      await auth.signUpWithPassword('me@example.com', 'other123');
      fail('should throw');
    } catch (e) {
      expect(AuthService.errorText(e), contains('already has an account'));
    }
  });

  test('server still requiring email confirmation is explained', () async {
    final server = FakeAuthServer()..requireEmailConfirmation = true;
    final auth = serviceFor(server);
    try {
      await auth.signUpWithPassword('me@example.com', 'secret123');
      fail('should throw');
    } catch (e) {
      expect(AuthService.errorText(e), contains('Confirm email'));
    }
    expect(auth.signedIn, isFalse);
  });

  test('guest can be upgraded to email + password', () async {
    final server = FakeAuthServer();
    final auth = serviceFor(server);
    await auth.signInAsGuest();
    expect(auth.isGuest, isTrue);
    await auth.linkEmailPassword('me@example.com', 'secret123');
    expect(server.calls, contains('PUT /auth/v1/user'));
    expect(server.passwords['me@example.com'], 'secret123');
  });

  testWidgets('login screen: create account and wrong password', (
    tester,
  ) async {
    final server = FakeAuthServer();
    final auth = serviceFor(server);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService?>.value(
        value: auth,
        child: MaterialApp(
          theme: royalTheme(Brightness.light),
          home: const LoginScreen(),
        ),
      ),
    );
    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Continue as guest'), findsOneWidget);

    // Switch to "Create account".
    await tap(find.text('New here? Create an account'));
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'me@example.com');
    await tester.enterText(fields.at(1), 'secret123');
    await tester.enterText(fields.at(2), 'different');
    await tap(find.widgetWithText(FilledButton, 'Create account'));
    expect(find.text('The two passwords don\'t match.'), findsOneWidget);

    await tester.enterText(fields.at(2), 'secret123');
    await tap(find.widgetWithText(FilledButton, 'Create account'));
    expect(auth.signedIn, isTrue);

    // Sign out and try a wrong password on the sign-in form.
    await auth.signOut();
    await tap(find.text('Already have an account? Sign in'));
    await tester.enterText(find.byType(TextField).at(1), 'nope1234');
    await tap(find.widgetWithText(FilledButton, 'Sign in'));
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(auth.signedIn, isFalse);
  });
}
