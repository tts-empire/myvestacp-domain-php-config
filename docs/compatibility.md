# Compatibility matrix

| Debian | MyVesta status | Patch policy |
|---|---|---|
| 10 Buster | legacy upstream support | live-verified and CI-tested |
| 11 Bullseye | supported upstream | CI and fixture tested; live verification pending |
| 12 Bookworm | recommended upstream | CI and fixture tested; live verification pending |
| 13 Trixie | outside this beta matrix | rejected by the installer |

The patch requires a MyVesta installation with:

- the standard `/usr/local/vesta` installation root;
- `/usr/local/vesta/bin/v-search-domain-owner`;
- `/usr/local/vesta/bin/v-get-php-version-of-domain`;
- `/usr/local/vesta/bin/v-rebuild-web-domains`;
- PHP-FPM pools under `/etc/php/<version>/fpm/pool.d`.

The panel PHP must be able to parse the existing MyVesta PHP syntax. The new code intentionally avoids typed properties, arrow functions and other PHP 7.4+ syntax so that the panel remains usable on Debian 10 installations.

The CI matrix runs PHP syntax checks plus transaction and complete lifecycle tests
inside Debian 10, 11 and 12 containers. Lifecycle coverage includes clean install,
idempotent reinstall, legacy-state migration, injected failure rollback, conflict
detection, upgrade behavior and checkout-independent uninstall. The template
fixtures are tied to a documented upstream myVesta commit and the live-verified
legacy Debian 10 dialect.

Container coverage validates the extension against each userspace and PHP parser;
it is not represented as a completed production installation. Compatibility
reports must therefore distinguish `live-verified` from `CI/fixture-tested`.
