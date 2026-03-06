# Security Checklist (Pre-Release)

## Critical

- Do not ship app builds that contain `STRAVA_CLIENT_SECRET`.
- Do not bundle `.env` in Flutter assets.
- Rotate all previously exposed keys/secrets immediately.
- Deploy restrictive Firestore rules before release.

## Runtime Configuration

Pass config at build/run time via `--dart-define`:

- `ENABLE_FIREBASE` (`false` for local-only mode)
- `STRAVA_CLIENT_ID`
- `STRAVA_REDIRECT_URI`
- `STRAVA_TOKEN_EXCHANGE_URL`
- `STRAVA_TOKEN_REFRESH_URL`
- `STRAVA_WEBHOOK_BASE_URL`
- `GEMINI_API_KEY` (recommended to move behind backend for production)

## Strava OAuth

- Production should use backend endpoints for token exchange/refresh.
- Insecure direct OAuth is allowed only for local prototyping by setting:
  `ALLOW_INSECURE_DIRECT_STRAVA_OAUTH=true`

## Firestore

- Rules file: `firestore.rules`
- Deploy with Firebase CLI:
  - `firebase use <project-id>`
  - `firebase deploy --only firestore:rules`

Rules should ensure users only read/write their own `users/{uid}` data.

## Firebase Project Isolation

- Public template files should not point to your personal Firebase project.
- Keep placeholder values in `firebase_options.dart` and `google-services.json`.
- When enabling Firebase, replace them with values from your own Firebase project.
- Keep `ENABLE_FIREBASE=false` by default for public/local-only runs.

Firebase API keys in `firebase_options.dart` / `google-services.json` are project identifiers, not secrets.
Still lock them down when you configure your own project:

- Restrict API key usage in Google Cloud Console.
- Restrict OAuth redirect URIs and authorized domains.
- Keep Firebase Auth and Firestore rules strict.

## AI Data Handling

- Current app can call Gemini directly when `GEMINI_API_KEY` is provided.
- For production privacy/compliance, prefer proxying AI requests through your backend:
  - key never leaves server
  - request auditing/rate-limits
  - centralized policy checks/redaction
