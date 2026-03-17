# StrideMind 🏃‍♂️

**StrideMind** is a smart running and endurance training companion app built with Flutter. It integrates with Strava to deliver adaptive daily workout recommendations based on your training plan, recovery metrics, and fueling needs.

## 🚀 Features

- Sync workouts from Strava
- Analyze pace, cadence, heart rate, and terrain
- AI-driven workout adjustments based on recovery and fatigue
- Fueling guidance (pre/intra/post-run)
- User logs for pain, sleep, and effort

## Platform Support

- Android: primary tested target in this template.
- iOS: scaffold included; additional Apple signing/provisioning and testing are required before release.
- Web: scaffold included; additional web testing/hosting setup is required before release.

## 📱 Getting Started

### Prerequisites
- Flutter SDK
- Android Studio or emulator
- Strava developer account (for API access)

### Installation
```bash
git clone https://github.com/yourusername/stridemind.git
cd stridemind
flutter pub get
flutter run
```

### Secure Configuration (required)
Do not embed secrets in app assets. This project now expects runtime config via `--dart-define`.

Example:
```bash
flutter run \
  --dart-define=ENABLE_FIREBASE=false \
  --dart-define=STRAVA_CLIENT_ID=... \
  --dart-define=STRAVA_REDIRECT_URI=stridemind://redirect \
  --dart-define=STRAVA_TOKEN_EXCHANGE_URL=https://YOUR_BACKEND/strava/oauth/token \
  --dart-define=STRAVA_TOKEN_REFRESH_URL=https://YOUR_BACKEND/strava/oauth/refresh \
  --dart-define=STRAVA_WEBHOOK_BASE_URL=https://YOUR_BACKEND \
  --dart-define=GEMINI_API_KEY=...
```

Important:
- `STRAVA_CLIENT_SECRET` must never be shipped in production mobile builds.
- Use backend token exchange/refresh endpoints for Strava OAuth.
- Set `ENABLE_FIREBASE=false` to run local-only mode without any Firebase project.
- To enable Firebase, set `ENABLE_FIREBASE=true` and replace Firebase config files with your own project values.
- For post-workout push notifications (Strava webhook → FCM), see `NOTIFICATIONS.md`.
- For local prototype only, insecure direct exchange can be enabled with:
  `--dart-define=ALLOW_INSECURE_DIRECT_STRAVA_OAUTH=true`
  (never use for release).

### Firestore Access Rules
Firestore rules are included in `firestore.rules` and should be deployed before release.

See `SECURITY.md` for security guidance and `PRIVACY.md` for data-handling notes.

### Optional: enable Firebase in your own project

Public template defaults to local-only mode (`ENABLE_FIREBASE=false`).

If you want Firebase features:

1. Create your own Firebase project
2. Replace `lib/firebase_options.dart` and `android/app/google-services.json` with your project config
3. Update `.firebaserc` with your project ID
4. Run with `--dart-define=ENABLE_FIREBASE=true`

### Easier local debug (no repeated typing)

You can keep local debug convenient without committing secrets:

1. Copy `config/dart_defines.local.example.json` to `config/dart_defines.local.json`
2. Fill your local values
3. Run:

```powershell
.\scripts\run_debug.ps1
```

This wraps `flutter run --dart-define-from-file=...` so you don't type all defines each time.
`config/dart_defines.local.json` is git-ignored.
