# Privacy Notes

This project is an open-source fitness training app prototype. If you self-host and run it, you control the data stack.

## What Data Is Processed

- Activity data (workouts, splits, distance, pace, timestamps)
- Training and nutrition plans
- User-entered notes/profile fields
- Strava-linked metadata (when connected)

## Where Data Lives

- Local device: SQLite (app cache/history)
- Cloud (optional): Firestore under `users/{uid}/...` when `ENABLE_FIREBASE=true`
- AI provider (optional): prompt content sent for feedback generation

## Plaintext Concern (Important)

Data in Firestore is readable to project admins in Firebase Console. This is normal for backend operators unless you add application-level encryption.

What protects users by default:

- Firebase Authentication
- Firestore security rules (owner-only access by UID)
- Transport encryption (HTTPS/TLS)

What is not provided by default:

- End-to-end encryption where even project admins cannot read user content

If you require that model, encrypt sensitive fields client-side before upload.

## Production Guidance

- Never ship client secrets in the mobile app.
- Use backend token exchange for OAuth providers.
- Keep Firestore rules strict and tested.
- Apply API key restrictions in provider consoles.
- Prefer proxying AI calls through your backend for rate limits, auditing, and key protection.

## Open-Source Safety Model

Publishing this repository should expose code and setup instructions, not your private credentials or paid infrastructure.

Contributors should use:

- Their own Firebase project
- Their own Strava app/backend endpoints
- Their own AI provider keys
