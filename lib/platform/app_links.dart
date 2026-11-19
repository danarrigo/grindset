/// Public distribution only. Never put GitHub or Supabase admin tokens here.
abstract final class AppLinks {
  static final confirmation = Uri.parse(
    'https://danarrigo.github.io/grindset-releases/confirmed/',
  );
  static final resetPassword = Uri.parse(
    'https://danarrigo.github.io/grindset-releases/reset-password/',
  );
  static final updateFeed = Uri.parse(
    'https://danarrigo.github.io/grindset-releases/latest.json',
  );
  static final releases = Uri.parse(
    'https://github.com/danarrigo/grindset-releases/releases',
  );
}
