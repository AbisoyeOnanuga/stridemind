# Contributing

## Branch and PR workflow

1. Create a branch from `main`.
2. Keep PRs focused and small.
3. Fill out the PR template completely.
4. Wait for CI to pass before merge.

## Commit style

Use clear, intent-first messages. Preferred prefixes:

- `feat:` new functionality
- `fix:` bug fix
- `perf:` performance improvements
- `refactor:` structural changes without behavior change
- `docs:` documentation only
- `test:` test changes

## Definition of Done

- App behavior verified for touched flows.
- `flutter analyze` passes.
- `flutter test` passes.
- Changelog updated for user-visible changes.
- If architecture changes, add/update ADR in `docs/adr/`.

## AI/Agentic coding guardrails

- Never commit secrets (`.env`, local define files, credentials).
- Document assumptions and risks in PR.
- Include test evidence (commands + results).
- Prefer incremental, reviewable changes over large rewrites.

## CI worker failures (GitHub-hosted runners)

Occasional "worker" failures are infrastructure noise, not code regressions. Best-practice triage:

1. Re-run failed jobs once.
2. If the same step fails again, treat as code/config and fix before merge.
3. In public template issues, include the workflow run URL, failing job name, and exact failing step so maintainers can reproduce quickly.

