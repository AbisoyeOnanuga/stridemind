# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Repository engineering baseline: versioning, contribution, ADR/feature templates, PR template, CI.

### Changed
- Training plan history reliability and action UX.
- Theme switch responsiveness.

### Fixed
- Deleted training plan no longer reappears from cloud restore flow.
- Dashboard empty after upgrade: SQLite/JSON sometimes return integers as `double`; safe int parsing added in activity and training-plan code paths so the app no longer crashes with "type 'double' is not a subtype of type 'int?'". Legacy DB schema gaps (e.g. `source`, `gear_type`, `archived`) are applied at runtime so older installs migrate without reinstall.
- CI: test step no longer fails when the repo has no `test/` directory.

