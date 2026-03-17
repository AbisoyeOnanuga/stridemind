# Security Checklist (Pre-Release)

## Security Posture (Pre-Publish Sanity Check)

- **Secrets not in repo:** All secrets (Strava client secret, Gemini API key, tokens, backend URLs) are supplied at build/run via `--dart-define` or from gitignored files (`.env`, `config/dart_defines.local.json`). The committed `lib/strava_config.dart` and similar files only use `String.fromEnvironment(..., defaultValue: '')` — no literal keys.
- **Public repo:** Firebase/Strava/Gemini config use placeholders or empty defaults; clone-and-build does not touch your infrastructure. `ENABLE_FIREBASE=false` by default.
- **No backdoors:** No hardcoded credentials, no hidden endpoints; optional features (e.g. webhook) only activate when the user supplies a base URL.
- **Defence in depth:** Firestore rules, API key restrictions (when you use your own project), and backend token exchange for production are documented and recommended.

Software cannot be fully secure; the measures above aim to block common threats (secret leakage, accidental use of your keys by others, unauthorised access) without introducing backdoors or unintended external access.

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

## Post-workout notifications (optional)

If you enable `STRAVA_WEBHOOK_BASE_URL`, the app will register device FCM tokens with **your backend** so it can send a push after Strava activities.

- Setup and backend contract live in `NOTIFICATIONS.md`.
- Do not commit: Strava verify token, Firebase service account JSON, Strava client secret, or backend URLs.

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
