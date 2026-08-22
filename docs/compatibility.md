# Compatibility matrix

| Debian | MyVesta status | Patch policy |
|---|---|---|
| 10 Buster | legacy supported | supported and tested |
| 11 Bullseye | supported | supported and tested |
| 12 Bookworm | recommended by current MyVesta site | primary target |
| 13 Trixie | depends on MyVesta release | installer warns and does not claim support |

The patch requires a MyVesta installation with:

- `/usr/local/vesta/bin/v-search-domain-owner`;
- `/usr/local/vesta/bin/v-get-php-version-of-domain`;
- `/usr/local/vesta/bin/v-rebuild-web-domains`;
- PHP-FPM pools under `/etc/php/<version>/fpm/pool.d`.

The panel PHP must be able to parse the existing MyVesta PHP syntax. The new code intentionally avoids typed properties, arrow functions and other PHP 7.4+ syntax so that the panel remains usable on Debian 10 installations.
