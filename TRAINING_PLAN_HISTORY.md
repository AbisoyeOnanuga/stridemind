# Training plan completion & history (design notes)

## Current behavior

- **Final week complete:** When the user marks the final week as complete, the plan is stored with `completedAt` (timestamp). A dialog congratulates them; the plan remains for reference. "Mark incomplete" on the final week clears `completedAt` and steps back one week.
- **Data:** Plans (including `completedAt`) are saved locally via `TrainingPlanService`. No Firestore sync for plans is implemented yet.

## Open design decisions

### 1. Deleting previous training history (recommended approach)

- **Option A:** Users can delete individual plans (or "archive" them). Keeps the app tidy; some users prefer a clean slate.
- **Option B:** Plans are never deleted; they are part of athlete history. The AI coach and analytics can reference past plans.
- **Recommendation (adopted):** Support *archiving* (hide from active list, keep in DB) and optional *delete* for a plan. Default to keeping history for coach context. This bridges user choice (delete/archive) with preserving athlete history where desired, and fits storage-budget handling (e.g. "archive oldest" when at cap).

### 2. AI coach and plan history

- **Use case:** Coach can say "You completed a 12‑week marathon plan in March" or "Your last plan targeted 5K; this one is HM."
- **Implementation (done):** When building the coach prompt, the app calls `TrainingPlanService.getPlanHistorySummaryForCoach()` which returns a short summary of all *non-archived* plans (name, goal, active/completed, completedAt date). This is passed into `PromptService.buildFeedbackPrompt(..., planHistorySummary: ...)` and included in the prompt under "Training plan history". The coach can reference past completed plans and the current active one.
- **When history is used:** Every time the user requests feedback on the Coach page, the prompt is built with the current plan history summary. So as soon as a plan is marked complete (or any non-archived plan exists), it is included in the next coach request.
- **Privacy:** Archived plans are excluded (getPlanHistorySummaryForCoach uses `getAllPlans(includeArchived: false)`). Deleted plans are removed from the DB and no longer appear.

### 3. Database and Firestore

- **Local (SQLite):** Plans are already stored; `completedAt` is in the JSON. No schema change if you only add this field to existing documents.
- **Firestore (future):** If you sync plans to Firestore for backup or multi-device, include `completedAt`. Same rules as above: completed/archived plans can be synced but excluded from "active" lists and optionally from coach context if the user prefers.

### 4. Storage budget & limits (plan ahead, avoid surprise)

Storage is finite; we need explicit budgets and methods so the first user who hits a limit isn’t the one “testing” failure, and Firestore cost stays predictable.

**Hypothetical budget constants (tune when implementing):**

| Scope | Suggested cap | Purpose |
|-------|----------------|---------|
| Local (device) | e.g. `MAX_PLANS_LOCAL = 50` (or 100) | Avoid SQLite/bloat; device space is finite. |
| Firestore | e.g. `MAX_PLANS_FIRESTORE_PER_USER = 20` (or 30) | Control read/write cost and doc count. |

**Methods to implement:**

1. **Before save (new plan or sync):** Check current count (local and/or remote). If at or over cap: don’t fail silently; either prompt user (“Archive or delete an old plan to add this one”) or auto-archive oldest plan (by `createdAt` or `completedAt`) and then save. Prefer user choice when possible.
2. **Soft warning:** When count reaches e.g. 80% of cap, show a one-time or dismissible message: “You have many plans. You can archive old ones to free space and keep history.”
3. **Device out-of-space edge case:** Wrap local DB writes in try/catch; on storage/disk-full errors, show a clear message: “Device storage is full. Free space or archive/delete old plans,” and do not corrupt data (e.g. roll back or skip the write).
4. **Firestore:** Rate-limit or batch syncs; on quota/cost alerts (or 429), back off and optionally sync later. Cap per-user document count using `MAX_PLANS_FIRESTORE_PER_USER`: when at cap, sync only by replacing oldest synced plan (or prompt to archive/delete) so cost doesn’t grow unbounded.

**Philosophy:** Athlete history is valuable; limits are about safe guardrails, not arbitrarily hiding it. Prefer “show last N in list” + “View all / archived” in UI, and use the cap to decide what to keep locally vs. sync, and when to prompt or auto-archive.

## Summary

- **Shipped:** Final-week completion sets `completedAt`, shows a completion dialog, and "Plan complete" state with option to "Mark incomplete." Plan history dialog: set active, archive, restore, delete. Plan history is included in the AI coach prompt (non-archived plans only); archived/deleted plans are excluded. UI note in Plan history: "Non-archived plans (including completed) are used for coach context."
- **Store behaviour:** Reusing a previous plan = set it active via Plan history ("Set active"). Archiving hides it from the default list and from coach context; restore brings it back. Delete removes it from DB and coach context. The store is prepared for this flow.
- **Next steps (as needed):** (1) If you add Firestore sync, include `completedAt` and apply the same visibility rules. (2) Implement storage-budget constants and the methods in §4 (count checks, soft warning, device full handling, Firestore cap) if not already done.
