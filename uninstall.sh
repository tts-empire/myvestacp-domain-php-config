#!/bin/bash
set -e

VESTA_ROOT="${VESTA_ROOT:-/usr/local/vesta}"
STATE_ROOT="${MYVESTA_DOMAIN_PHP_STATE:-/var/lib/myvesta-domain-php-config}"
MANIFEST="$STATE_ROOT/installed.manifest"
[[ "$(id -u)" = 0 ]] || { echo 'ERROR: run as root' >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo 'Patch is not installed'; exit 0; }

while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if [[ "$item" = PATCH:* ]]; then
        patch_file="${item#PATCH:}"
        if [[ -f "$patch_file" ]] && patch --dry-run --reverse -p0 -d / < "$patch_file" >/tmp/myvesta-domain-php-check 2>&1; then
            patch --reverse -p0 -d / < "$patch_file"
        fi
    fi
done < "$MANIFEST"

backup_root=""
[[ -f "$STATE_ROOT/last_backup" ]] && backup_root="$(cat "$STATE_ROOT/last_backup")"
while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    [[ "$target" = PATCH:* ]] && continue
    if [[ -n "$backup_root" && -f "$backup_root$target" ]]; then
        install -D -m 0755 "$backup_root$target" "$target"
    elif [[ "$target" = "$VESTA_ROOT/web/edit/domain-php-config/index.php" || "$target" = "$VESTA_ROOT/web/templates/admin/edit_domain_php_config.html" || "$target" = "$VESTA_ROOT/bin/myvesta-domain-php-common.sh" || "$target" = "$VESTA_ROOT/bin/v-list-domain-php-config" || "$target" = "$VESTA_ROOT/bin/v-change-domain-php-config" || "$target" = "$VESTA_ROOT/bin/v-reapply-domain-php-config" || "$target" = "$VESTA_ROOT/bin/v-suggest-domain-php-config" || "$target" = "$VESTA_ROOT/bin/v-check-domain-php-config-patch" ]]; then
        rm -f -- "$target"
    else
        rm -f -- "$target"
    fi
done < "$MANIFEST"

echo "Patch code removed. Domain state was retained at $STATE_ROOT/domains."
