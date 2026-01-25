import 'package:supabase_flutter/supabase_flutter.dart';

class AppSupabase {
  static bool _initialized = false;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    if (_initialized) return;

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> ensureAnonSignIn() async {
    final session = client.auth.currentSession;
    if (session == null) {
      await client.auth.signInAnonymously();
    }
  }
}
