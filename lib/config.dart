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
// If set to empty strings, the app runs fully offline with no login.

class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ugzzzephftxfhgjyldma.supabase.co',
  );

  /// Public "anon" key: safe to ship in the app (access is limited by the
  /// row-level security rules in supabase/schema.sql).
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6'
        'InVnenp6ZXBoZnR4ZmhnanlsZG1hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQxMDc3Mj'
        'gsImV4cCI6MjEwOTY4MzcyOH0.fG0o8VUr_ZJl6N8ww9BoOn9dX8SU8ZjlkmC3UB3RykI',
  );

  /// Phone (SMS code) login. Off: it needs a paid SMS provider connected
  /// in Supabase (and DLT registration for Indian numbers). Set to true
  /// once that is set up and the Email/Phone switch comes back.
  static const phoneLoginEnabled = false;

  /// Country code added to 10-digit phone numbers.
  static const defaultCountryCode = '+91';

  static bool get cloudEnabled =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
