# Changelog

## 0.2.0-beta

- Transactional install, upgrade and uninstall with mandatory preflight and
  automatic full-target rollback.
- Self-contained schema-2 installation state and migration from legacy 0.1.0
  manifests.
- Installed uninstaller that no longer depends on the source checkout.
- Exact, fuzz-free patch matching for administrator and user templates.
- Private temporary files and lifecycle locking for root operations.
- Debian 10/11/12 CI matrix with upstream and legacy myVesta fixtures.
- Compatibility claims split into live-verified and CI/fixture-tested status.

## 0.1.0

- Initial installable patch structure.
- Domain-level PHP-FPM state and commands.
- Conservative RAM/CPU/pool resource advisor.
- Native MyVesta-style web page and integration patches.
- Installer conflict detection, backups and rollback path.
