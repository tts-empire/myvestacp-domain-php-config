# MyVestaCP Domain PHP Config

Installable domain-level PHP-FPM configuration for existing MyVestaCP servers.

The patch follows the existing MyVesta web dialect and does not replace the panel. It adds a native-style section to the domain editor, stores settings outside generated pool files, reapplies them after web rebuilds, and validates the selected PHP-FPM service before restarting it.

## Compatibility

The tested matrix is Debian 10, 11 and 12. PHP versions are discovered from `/etc/php/<version>/fpm` and the domain's existing MyVesta PHP-version helper; no PHP version is hardcoded.

Debian 13 is not enabled automatically until the installed MyVesta release declares support for it.

## Install

```sh
sudo ./install.sh
sudo /usr/local/vesta/bin/v-check-domain-php-config-patch
```

The installer creates backups and refuses to patch a modified MyVesta file when it cannot apply the integration safely. It does not change any global `php.ini`.

## CLI

```sh
v-list-domain-php-config example.com json
v-suggest-domain-php-config example.com json
v-change-domain-php-config example.com memory_limit 512M yes
```

## Resource advisor

The advisor estimates a PHP-FPM budget from RAM, CPU, swap, active pools and a safety reserve. It treats `pm.max_children` as the concurrency multiplier and never applies suggestions to other domains automatically.

## Removal

```sh
sudo ./uninstall.sh
```

Domain state is retained under `/var/lib/myvesta-domain-php-config/domains` so it can be restored if the patch is reinstalled.
