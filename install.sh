#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
VESTA_ROOT="${VESTA_ROOT:-/usr/local/vesta}"
STATE_ROOT="${MYVESTA_DOMAIN_PHP_STATE:-/var/lib/myvesta-domain-php-config}"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_ROOT="$STATE_ROOT/backups/$STAMP"
DRY_RUN=no

if [[ "${1:-}" = "--dry-run" ]]; then
    DRY_RUN=yes
fi

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" = 0 ]] || die "run as root"
[[ -d "$VESTA_ROOT/bin" && -d "$VESTA_ROOT/web" ]] || die "MyVesta not found at $VESTA_ROOT"
[[ -f /etc/os-release ]] || die "cannot identify operating system"
. /etc/os-release
[[ "$ID" = debian ]] || die "only Debian is supported by this release"
case "$VERSION_ID" in 10|11|12) ;; *) echo "WARNING: Debian $VERSION_ID is not in the tested matrix" >&2 ;; esac
[[ -x "$VESTA_ROOT/bin/v-search-domain-owner" ]] || die "unsupported MyVesta: v-search-domain-owner missing"
[[ -x "$VESTA_ROOT/bin/v-get-php-version-of-domain" ]] || die "unsupported MyVesta: PHP version helper missing"
[[ -f "$VESTA_ROOT/web/templates/admin/edit_web.html" ]] || die "MyVesta admin edit_web template missing"
[[ -f "$VESTA_ROOT/web/templates/user/edit_web.html" ]] || die "MyVesta user edit_web template missing"
command -v patch >/tmp/myvesta-domain-php-check 2>&1 || die "patch command is required"

if [[ "$DRY_RUN" = yes ]]; then
    for patch_file in "$REPO_ROOT"/patches/*.patch; do
        patch --dry-run --fuzz=3 --forward -p0 -d / < "$patch_file" >/tmp/myvesta-domain-php-check 2>&1 || patch --dry-run --fuzz=3 --reverse -p0 -d / < "$patch_file" >/tmp/myvesta-domain-php-check 2>&1 || die "patch conflict: $patch_file"
        echo "Preflight OK: $patch_file"
    done
    echo "Preflight OK: no files changed"
    exit 0
fi

install -d -m 0750 "$STATE_ROOT" "$STATE_ROOT/domains" "$BACKUP_ROOT"
printf '%s\n' "$BACKUP_ROOT" > "$STATE_ROOT/last_backup"
manifest="$STATE_ROOT/installed.manifest"
touch "$manifest"

backup_and_install() {
    local source="$1" target="$2"
    if [[ -e "$target" ]]; then
        install -D -m 0600 "$target" "$BACKUP_ROOT$target"
    fi
    install -D -m 0755 "$source" "$target"
    grep -Fxq "$target" "$manifest" 2>/dev/null || printf '%s\n' "$target" >> "$manifest"
}

backup_and_install "$REPO_ROOT/lib/domain-php-common.sh" "$VESTA_ROOT/bin/myvesta-domain-php-common.sh"
for command_file in v-list-domain-php-config v-change-domain-php-config v-reapply-domain-php-config v-suggest-domain-php-config v-check-domain-php-config-patch; do
    backup_and_install "$REPO_ROOT/bin/$command_file" "$VESTA_ROOT/bin/$command_file"
done
install -d -m 0755 "$VESTA_ROOT/web/edit/domain-php-config"
install -m 0644 "$REPO_ROOT/web/edit/domain-php-config/index.php" "$VESTA_ROOT/web/edit/domain-php-config/index.php"
install -m 0644 "$REPO_ROOT/web/templates/admin/edit_domain_php_config.html" "$VESTA_ROOT/web/templates/admin/edit_domain_php_config.html"
printf '%s\n' "$VESTA_ROOT/web/edit/domain-php-config/index.php" "$VESTA_ROOT/web/templates/admin/edit_domain_php_config.html" >> "$manifest"

apply_patch_file() {
    local patch_file="$1"
    local target="$2"
    local marker="$3"
    if grep -Fq "$marker" "$target"; then
        echo "Already applied: $patch_file"
        return 0
    fi
    if ! patch --batch --fuzz=3 --forward -p0 -d / < "$patch_file"; then
        die "conflict detected while applying $patch_file"
    fi
    printf 'PATCH:%s\n' "$patch_file" >> "$manifest"
}

apply_patch_file "$REPO_ROOT/patches/edit_web.html.add-link.patch" \
    "$VESTA_ROOT/web/templates/admin/edit_web.html" \
    'PHP Domain Configuration'
apply_patch_file "$REPO_ROOT/patches/v-rebuild-web-domains.add-hook.patch" \
    "$VESTA_ROOT/bin/v-rebuild-web-domains" \
    'v-reapply-domain-php-config'
apply_patch_file "$REPO_ROOT/patches/edit_web_user.html.add-link.patch" \
    "$VESTA_ROOT/web/templates/user/edit_web.html" \
    'PHP Domain Configuration'

echo "Installed MyVesta domain PHP configuration patch."
echo "Backup: $BACKUP_ROOT"
echo "Run: $VESTA_ROOT/bin/v-check-domain-php-config-patch"
