abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const environment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'production',
  );
  static const passwordRecoveryUrl = String.fromEnvironment(
    'PASSWORD_RECOVERY_URL',
    defaultValue:
        'https://ahla-shabab-management-os.vercel.app/mobile-redirect',
  );

  /// Non-production escape hatch that lets the app skip the release-gate network
  /// check (e.g. for UI previews on web without a live backend). Ignored in
  /// production so it can never weaken the real gate.
  static const bypassReleaseGate = bool.fromEnvironment('BYPASS_RELEASE_GATE');

  static bool get releaseGateBypassed =>
      bypassReleaseGate && environment != 'production';

  static void validate() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY dart-define.',
      );
    }
  }
}
