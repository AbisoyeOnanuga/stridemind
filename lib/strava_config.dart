// Strava config: supply values via --dart-define at build/run (see README).
// No secrets in this file; never commit .env or dart_defines.local.json.
const String stravaClientId =
    String.fromEnvironment('STRAVA_CLIENT_ID', defaultValue: '');
const String stravaClientSecret =
    String.fromEnvironment('STRAVA_CLIENT_SECRET', defaultValue: '');
const String stravaRedirectUri =
    String.fromEnvironment('STRAVA_REDIRECT_URI', defaultValue: 'stridemind://redirect');
const String stravaTokenExchangeUrl =
    String.fromEnvironment('STRAVA_TOKEN_EXCHANGE_URL', defaultValue: '');
const String stravaTokenRefreshUrl =
    String.fromEnvironment('STRAVA_TOKEN_REFRESH_URL', defaultValue: '');
const bool allowInsecureDirectStravaOAuth = bool.fromEnvironment(
  'ALLOW_INSECURE_DIRECT_STRAVA_OAUTH',
  defaultValue: false,
);
