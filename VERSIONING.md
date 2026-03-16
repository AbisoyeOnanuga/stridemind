# Versioning Policy

This project follows [Semantic Versioning](https://semver.org/) using `MAJOR.MINOR.PATCH`.

- `MAJOR`: incompatible API/behavior changes.
- `MINOR`: backward-compatible feature additions.
- `PATCH`: backward-compatible fixes, refactors, performance, docs.

## Rules

1. Every release is tagged in git as `vX.Y.Z`.
2. Every release updates `CHANGELOG.md`.
3. Breaking changes require:
   - migration notes in `CHANGELOG.md`
   - an ADR in `docs/adr/`
4. Mobile builds should embed the app version from this policy.

## Pre-release labels

Use pre-release tags for test channels:

- `v1.4.0-beta.1`
- `v1.4.0-rc.1`

