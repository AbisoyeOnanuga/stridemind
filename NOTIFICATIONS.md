# Post-workout notifications

Push after you record or upload an activity on Strava: *"Great workout, &lt;name&gt;! Tell the AI coach how it went..."*

**Flow:** Strava → webhook to **your backend** → backend finds the user’s FCM token in Firestore → backend sends FCM to the app.

No secrets in the app repo. Backend secrets stay in backend env; app receives only the backend base URL via dart-define (e.g. `STRAVA_WEBHOOK_BASE_URL`).

---

## Scope: public vs private

- **Public repo:** No backend URL in code (default empty). Notifications are off until you deploy your own backend and set the URL at build time. This doc describes how to implement and connect that backend on any host (Vercel, Cloud Run, etc.).
- **Private repo:** Same app; you may use a dedicated backend (e.g. Vercel) and keep env vars only in that deployment. Rotate any secrets (verify token, client secret) if they were ever exposed during setup.

---

## Backend contract (for any host)

To support this feature, your backend must:

1. **Webhook endpoint** (GET + POST)  
   - **GET:** Strava subscription verification. Query params: `hub.mode`, `hub.verify_token`, `hub.challenge`. If `hub.verify_token` matches your configured token, respond with `{ "hub.challenge": "<hub.challenge>" }`.  
   - **POST:** Strava sends activity events (JSON body with `owner_id`, `object_id`, `object_type`, etc.). Look up Firebase UID by Strava athlete ID (e.g. Firestore `users` where `stravaProfile.id == owner_id`). Load FCM tokens from `users/{uid}/device_tokens`, then send a data message (e.g. FCM Admin SDK) with `activityId` and optional title/body.

2. **Register-device endpoint** (POST)  
   - Accept `Authorization: Bearer <Firebase ID token>` and JSON body `{ "token": "<FCM token>", "strava_athlete_id": <number> }`.  
   - Verify the ID token; optionally resolve target UID by `strava_athlete_id` (same query as webhook) and verify the token’s user owns that Strava ID.  
   - Write the FCM token to `users/{targetUid}/device_tokens/{token}` (and optionally `strava_athlete_id` so the webhook and registration use the same UID).

3. **Secrets (server-side only)**  
   - Firebase service account (to read Firestore and send FCM).  
   - Strava verify token (for webhook GET).  
   - Never commit these; use platform env (e.g. Vercel env vars).

Reference implementations exist in a separate backend repo (e.g. Next.js on Vercel). The app only needs the backend’s **base URL** at build time (`STRAVA_WEBHOOK_BASE_URL`); no secrets in the app.

---

## Prerequisites

- **Firebase:** Project with Android (and optionally iOS) app, Cloud Messaging enabled.
- **Strava API:** Your app’s package name / redirect URI configured.
- **Backend:** Deployed (Vercel, Cloud Run, or other) implementing the contract above.

---

## 1. Backend (your host)

Deploy your backend. Set **environment variables** on the host (never in the app repo):

| Variable | Purpose |
|----------|---------|
| `FIREBASE_SERVICE_ACCOUNT_BASE64` | Firebase service account JSON, base64-encoded. Used to read Firestore and send FCM. |
| `STRAVA_VERIFY_TOKEN` | Random string. Must match the value you use when creating the Strava webhook subscription. |

Redeploy after setting or changing these.

---

## 2. Strava webhook subscription

Strava has no “Subscribe” button in the dashboard; create the subscription via the API once.

- **Callback URL:** `https://<your-backend-host>/api/strava-webhook` (or the path your backend uses). No trailing slash.
- **Verify token:** Same value as your backend’s `STRAVA_VERIFY_TOKEN`.

**Create subscription:**

- **PowerShell:** From the app repo (pass your own values; do not commit them):
  ```powershell
  .\scripts\subscribe_strava_webhook.ps1 `
    -VerifyToken "YOUR_VERIFY_TOKEN_VALUE" `
    -ClientSecret "YOUR_STRAVA_CLIENT_SECRET" `
    -ClientId "YOUR_STRAVA_CLIENT_ID" `
    -CallbackUrl "https://YOUR_BACKEND_HOST/api/strava-webhook"
  ```

- **Manual:** POST to `https://www.strava.com/api/v3/push_subscriptions` with `Content-Type: application/x-www-form-urlencoded` and body: `client_id`, `client_secret`, `callback_url`, `verify_token`.

---

## 3. App configuration and first run

1. **Dart-defines** (e.g. `config/dart_defines.local.json`, gitignored):
   - `ENABLE_FIREBASE` = `"true"`
   - `STRAVA_WEBHOOK_BASE_URL` = `"https://<your-backend-host>"` (no trailing slash)

   Do not commit this file.

2. **Firebase / Android:** In Firebase Console, add your app’s **package name** and **SHA-1** (and SHA-256). Debug SHA-1: `cd android && ./gradlew signingReport`. Update `android/app/google-services.json` if you use the downloadable config.

3. Run the app with those defines.

4. In the app: sign in, connect Strava, allow notifications. Then open **Settings → Post-workout notifications** and tap the tile to register this device (snackbar shows success/failure).

---

## 4. Test

1. Create a new activity in Strava (record or manual).
2. You should get a push: *"Great workout, &lt;firstname&gt;! Tell the AI coach how it went..."*
3. Tap the notification to open the app.

---

## Troubleshooting

**Backend logs** (after creating a Strava activity):

| Log | Meaning |
|-----|--------|
| "Received Strava webhook event" | Webhook called. If missing, check subscription and callback URL. |
| "No user found for Strava ID …" | Strava profile not in Firestore. Connect Strava in app, then **Settings → Post-workout notifications**. |
| "No device tokens found for user: …" | No FCM token for that user. **Settings → Post-workout notifications**; be signed in as the account with Strava connected. |
| "FCM post-workout notification sent" | Push sent; check device notification settings. |

**App:** "Device registered successfully" → create a test activity. "Cannot register device, user not logged in" → sign in, then use Settings tile.

**Android:** `DEVELOPER_ERROR` or "Unknown calling package name" → In Firebase, confirm package name and SHA-1 for your keystore; update `google-services.json`; rebuild; then **Settings → Post-workout notifications** and test again.

**Re-register:** After reinstall or different user, tap **Settings → Post-workout notifications**, then create one new Strava activity.

---

## Checklist

- [ ] Backend: `FIREBASE_SERVICE_ACCOUNT_BASE64`, `STRAVA_VERIFY_TOKEN` set on host; redeployed.
- [ ] Strava: subscription created; callback URL and verify token match backend.
- [ ] App: `ENABLE_FIREBASE=true`, `STRAVA_WEBHOOK_BASE_URL` in dart-defines (gitignored).
- [ ] Firebase: Android package name and SHA-1 (and `google-services.json`) correct.
- [ ] App: signed in, Strava connected, notifications allowed; Settings tile tapped.
- [ ] New Strava activity → push received.

---

## Where it lives (reference)

| Location | Role |
|----------|------|
| `lib/services/notification_api_service.dart` | Registers FCM token with backend; sends `strava_athlete_id` when available. |
| `lib/services/fcm_service.dart` | FCM init, permission, register device, handle incoming messages. |
| `lib/pages/home_page.dart` | Calls `FcmService().initialize(...)`. |
| `lib/pages/splash_page.dart` | Holds `FcmService`, calls `fcmService.initialize(...)` when Firebase + Strava ready. |
| Backend (separate repo or service): webhook route | Receives Strava events; looks up user by Strava ID; sends FCM. |
| Backend: register-device route | Stores FCM token under user the webhook will look up when `strava_athlete_id` is sent. |

