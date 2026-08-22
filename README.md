# myVesta Domain PHP Config

[![Version](https://img.shields.io/badge/version-0.2.0--beta-0969da.svg)](CHANGELOG.md)
[![Project status](https://img.shields.io/badge/status-beta-f59e0b.svg)](#project-status)
[![Tests](https://github.com/tts-empire/myvestacp-domain-php-config/actions/workflows/test.yml/badge.svg)](https://github.com/tts-empire/myvestacp-domain-php-config/actions/workflows/test.yml)
[![myVesta](https://img.shields.io/badge/myVesta-extension-2f363d.svg)](https://myvestacp.com/)
[![Debian](https://img.shields.io/badge/Debian-10%20%7C%2011%20%7C%2012-a81d33.svg?logo=debian&logoColor=white)](docs/compatibility.md)
[![PHP-FPM](https://img.shields.io/badge/PHP--FPM-auto--detected-777bb4.svg?logo=php&logoColor=white)](#compatibility)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-22a699.svg)](LICENSE)

Installable, domain-level PHP-FPM configuration for existing
[myVesta](https://myvestacp.com/) servers. It extends the panel in place; it does
not require a myVesta reinstall and does not replace the control panel.

The extension adds a native-style **PHP** action to every web-domain row,
immediately before **WordPress**. Administrators and domain owners can inspect the
effective PHP settings, compare them with suggestions calculated specifically for
that server, and save validated per-domain overrides.

> [!IMPORTANT]
> `v0.2.0-beta` is the first public pre-release. Install the immutable tagged
> version, inspect the source, and run the installer locally. Do not install it
> through an unaudited `curl | bash` command.

## Quick start

Clone the published beta tag and run the preflight before installing:

```bash
mkdir -p "$HOME/src"
cd "$HOME/src"
git clone --branch v0.2.0-beta --depth 1 \
  https://github.com/tts-empire/myvestacp-domain-php-config.git
cd myvestacp-domain-php-config
sudo ./install.sh --dry-run
sudo ./install.sh
sudo /usr/local/vesta/bin/v-check-domain-php-config-patch
```

Read the detailed [download](#download) and [installation](#installation)
sections before using this on a production server.

## Features

- Native myVesta-style page and domain-list action for administrators and users.
- Separate **Actual setting** and **Suggested setting** values.
- Suggestions based on the server's RAM, CPU count, PHP-FPM pools and safety
  reserve; they are not generic PHP defaults.
- Per-domain PHP and PHP-FPM overrides stored outside generated pool files.
- Automatic reapplication after myVesta rebuilds web-domain configuration.
- Transactional validation, rollback and at most one PHP-FPM restart per save.
- Transactional installer, upgrade and uninstall with mandatory preflight,
  timestamped backups and automatic rollback.
- No changes to any global `php.ini`.

## Screenshot

### Domain PHP-FPM settings

[![myVesta domain PHP-FPM configuration page](docs/assets/domain-php-config.png)](docs/assets/domain-php-config.png)

### PHP action in the WEB domain list

[![PHP action highlighted in the myVesta WEB domain list](docs/assets/domain-list-php-action.png)](docs/assets/domain-list-php-action.png)

Both screenshots are rendered from the actual myVesta templates and stylesheet
using fully synthetic documentation data. They contain no production domain,
hostname, account name, IP address or measured server value. The red outline is a
documentation annotation and does not appear in the installed panel.

## Project status

Version `0.2.0-beta` is published as a GitHub pre-release, deployed and
live-verified on Debian 10. Debian 11 and 12 run the same static, transaction and
complete lifecycle suite in CI containers; they are not described as
live-verified until the extension has completed a real installation on those
operating systems. Locally modified myVesta templates can still differ, so always
run the preflight.

There is currently no packaged `.deb`. Installation uses the checksummed release
archive or an exact tagged Git checkout. After installation, the lifecycle state
and exact reverse patches are self-contained under
`/var/lib/myvesta-domain-php-config/install/`; uninstall does not depend on the
original checkout.

## Compatibility

| Component | Requirement |
| --- | --- |
| Operating system | Debian 10, 11 or 12 |
| Control panel | An existing myVesta installation |
| myVesta root | Exactly `/usr/local/vesta` |
| PHP | One or more PHP-FPM versions under `/etc/php/<version>/fpm` |
| Required commands | `bash`, `patch`, `flock`, standard GNU/Linux utilities |
| Permissions | `root` or an account with working `sudo` access |

PHP versions are discovered from the server and from myVesta's domain PHP helper;
the extension does not hardcode PHP 8.1 or 8.2. Debian 13 is not currently claimed
as supported. See the complete [compatibility matrix](docs/compatibility.md).

## Download

Open the [`v0.2.0-beta` release page](https://github.com/tts-empire/myvestacp-domain-php-config/releases/tag/v0.2.0-beta)
to review the release notes and assets. Choose one download method below. Run the
download as your normal administrative account and use `sudo` only for the
installation commands.

### Option A: checksummed release archive (recommended)

Download the versioned archive and its SHA-256 checksum, verify it, and extract
it:

```bash
mkdir -p "$HOME/src"
cd "$HOME/src"
curl -fLO https://github.com/tts-empire/myvestacp-domain-php-config/releases/download/v0.2.0-beta/myvestacp-domain-php-config-v0.2.0-beta.tar.gz
curl -fLO https://github.com/tts-empire/myvestacp-domain-php-config/releases/download/v0.2.0-beta/myvestacp-domain-php-config-v0.2.0-beta.tar.gz.sha256
sha256sum --check myvestacp-domain-php-config-v0.2.0-beta.tar.gz.sha256
tar -xzf myvestacp-domain-php-config-v0.2.0-beta.tar.gz
cd myvestacp-domain-php-config-v0.2.0-beta
```

The checksum command must report `OK`. Stop if it does not.

### Option B: clone the exact Git tag

Clone the repository into a working directory:

```bash
mkdir -p "$HOME/src"
cd "$HOME/src"
git clone --branch v0.2.0-beta --depth 1 \
  https://github.com/tts-empire/myvestacp-domain-php-config.git
cd myvestacp-domain-php-config
```

## Installation

### 1. Run the non-destructive preflight

From the project directory:

```bash
sudo ./install.sh --dry-run
```

The preflight checks the operating system, required myVesta commands, PHP-FPM pool
layout and whether every integration patch is exactly applicable or already
applied. A successful run ends with:

```text
Preflight OK: no files changed
```

If it reports `patch conflict`, stop. Do not force the patch: the installed
myVesta templates differ from the supported dialect and require compatibility
review.

### 2. Install the extension

```bash
sudo ./install.sh
```

The installer will:

1. repeat the same preflight while holding the lifecycle lock;
2. create a timestamped backup under
   `/var/lib/myvesta-domain-php-config/backups/`;
3. install the PHP configuration commands and panel page;
4. add the PHP action to the administrator and user domain lists;
5. add the reapply hook to myVesta's web-domain rebuild command;
6. migrate legacy `0.1.0` installation state when present;
7. run the installed health check and automatically roll back every changed file
   if any stage fails;
8. preserve managed domain settings under
   `/var/lib/myvesta-domain-php-config/domains/`.

The final output prints the exact backup directory created for that run. myVesta
installations outside `/usr/local/vesta` are intentionally rejected because the
control panel itself and its command ecosystem assume that standard path.

### 3. Verify the installation

```bash
sudo /usr/local/vesta/bin/v-check-domain-php-config-patch
```

The command exits with status `0` when all required checks pass. Review every
`WARN` or `FAIL` before using the configuration page.

### 4. Open the page in myVesta

1. Sign in to myVesta as an administrator or domain owner.
2. Open **WEB**.
3. Locate the required domain.
4. Select **PHP**, immediately before the **WordPress** action.
5. Review **Actual setting** and **Suggested setting** before saving.

Suggested values are calculated from the resources detected on that specific
server. They are editable recommendations and are never applied automatically.

## Managed settings

| PHP setting | Purpose |
| --- | --- |
| `memory_limit` | Per-request PHP memory ceiling |
| `max_execution_time` | Maximum script execution time |
| `max_input_time` | Maximum request input parsing time |
| `post_max_size` | Maximum POST body size |
| `upload_max_filesize` | Maximum uploaded file size |
| `max_input_vars` | Maximum number of request input variables |
| `max_file_uploads` | Maximum simultaneous uploaded files |
| `pm` | PHP-FPM process-manager mode |
| `pm.max_children` | Maximum concurrent workers for the domain |
| `pm.max_requests` | Requests handled before recycling a worker |

Saving multiple fields is one transaction. The extension validates the generated
pool configuration before restarting the corresponding PHP-FPM service and rolls
back the pool and saved state if validation or restart fails.

## Updating

Choose the new version from the project's GitHub Releases page. For a Git
checkout, fetch the tags, check out the exact new release tag, and run the same
preflight before upgrading. Replace the example tag with the release being
installed:

```bash
cd "$HOME/src/myvestacp-domain-php-config"
git fetch --tags --prune
git checkout --detach v0.2.0-beta
sudo ./upgrade.sh --dry-run
sudo ./upgrade.sh
sudo /usr/local/vesta/bin/v-check-domain-php-config-patch
```

For a release archive or ZIP installation, download and extract the new version
into a separate directory, enter it, and run the three `upgrade.sh` and
verification commands above. The new source directory does not need to reuse the
installation path of an older version.

Each installation or upgrade performs an internal mandatory preflight, creates a
new timestamped backup and restores all changed targets if a patch, copy or final
health check fails.

## Command-line usage

The web interface is the normal entry point. The installed CLI commands are useful
for automation and diagnosis:

```bash
# Inspect saved and effective values
sudo /usr/local/vesta/bin/v-list-domain-php-config example.com json

# Calculate server-specific suggestions without applying them
sudo /usr/local/vesta/bin/v-suggest-domain-php-config example.com json

# Change one value and restart the matching PHP-FPM service
sudo /usr/local/vesta/bin/v-change-domain-php-config \
  example.com memory_limit 512M yes

# Apply several changes atomically and reset one override
sudo /usr/local/vesta/bin/v-update-domain-php-config \
  example.com yes \
  set memory_limit 512M \
  set pm.max_children 8 \
  reset max_input_vars
```

Use `no` instead of `yes` only when an external maintenance procedure will validate
and restart PHP-FPM afterward.

## Uninstalling

Run the installed uninstall preflight first:

```bash
sudo /usr/local/vesta/bin/v-uninstall-domain-php-config --dry-run
sudo /usr/local/vesta/bin/v-uninstall-domain-php-config
```

The repository wrapper `sudo ./uninstall.sh` invokes the same installed
uninstaller. The extension code and integration patches are removed
transactionally, even when the original checkout no longer exists. Per-domain
state is deliberately retained under `/var/lib/myvesta-domain-php-config/domains/`,
allowing it to be restored after a reinstall. Timestamped backups also remain
available.

## Safety notes

- Back up the server or create a provider snapshot before modifying a production
  control panel.
- Run `--dry-run` after every myVesta update and before every extension upgrade.
- Never force a failed patch or overwrite a locally modified panel template.
- Do not set `VESTA_ROOT`; only `/usr/local/vesta` is supported publicly.
- The extension changes per-domain FPM pools; it does not edit global `php.ini`
  files.
- Resource suggestions are planning estimates, not guaranteed or kernel-enforced
  limits.

## Documentation

- [Architecture](docs/architecture.md)
- [Compatibility matrix](docs/compatibility.md)
- [Changelog](CHANGELOG.md)

## Support and contributions

Use the dedicated GitHub forms to submit a
[reproducible bug](https://github.com/tts-empire/myvestacp-domain-php-config/issues/new?template=bug_report.yml)
or a
[compatibility report](https://github.com/tts-empire/myvestacp-domain-php-config/issues/new?template=compatibility_report.yml).
Include the Debian release, myVesta version or commit, enabled PHP-FPM versions,
the preflight output and the verification output. Remove hostnames, usernames,
IP addresses, credentials and other private server data before posting.

Pull requests should preserve myVesta's existing visual and command conventions,
remain compatible with the supported Debian matrix, and include relevant static or
transaction tests.

## License

This project is licensed under the
[GNU General Public License v3.0 or later](LICENSE), consistently with the
myVesta/VestaCP codebase it extends.
