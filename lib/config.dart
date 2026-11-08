// Cloud (Supabase) settings for login and cross-device sync.
//
// Fill these in with your project's values from the Supabase dashboard
// (Project Settings → API Keys), or pass them at build time:
//   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
//               --dart-define=SUPABASE_KEY=sb_publishable_...
//
// Use the *publishable* key (or the legacy "anon" key). It is meant to be
// shipped inside apps: your data is protected by the row-level security
// rules in supabase/schema.sql, not by this key.
// NEVER put the secret / service_role key here.
//
// If left empty, the app runs fully offline with no login.

class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: '',
  );

  /// Country code added to 10-digit phone numbers.
  static const defaultCountryCode = '+91';

  static bool get cloudEnabled =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
