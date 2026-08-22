#!/bin/bash
set -Eeuo pipefail

PROJECT_VERSION='0.2.0-beta'
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
VESTA_ROOT="${VESTA_ROOT:-/usr/local/vesta}"
STATE_ROOT="${MYVESTA_DOMAIN_PHP_STATE:-/var/lib/myvesta-domain-php-config}"
PHP_ETC_ROOT="${MYVESTA_DOMAIN_PHP_ETC:-/etc/php}"
OS_RELEASE_FILE="${MYVESTA_DOMAIN_PHP_OS_RELEASE:-/etc/os-release}"
ALLOW_CUSTOM_ROOT="${MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT:-no}"
INSTALL_STATE="$STATE_ROOT/install"
LEGACY_MANIFEST="$STATE_ROOT/installed.manifest"
DRY_RUN=no

declare -a MANAGED_SOURCES=(
    "$REPO_ROOT/lib/domain-php-common.sh"
    "$REPO_ROOT/bin/v-list-domain-php-config"
    "$REPO_ROOT/bin/v-change-domain-php-config"
    "$REPO_ROOT/bin/v-update-domain-php-config"
    "$REPO_ROOT/bin/v-reapply-domain-php-config"
    "$REPO_ROOT/bin/v-suggest-domain-php-config"
    "$REPO_ROOT/bin/v-check-domain-php-config-patch"
    "$REPO_ROOT/bin/v-uninstall-domain-php-config"
    "$REPO_ROOT/web/edit/domain-php-config/index.php"
    "$REPO_ROOT/web/templates/admin/edit_domain_php_config.html"
)
declare -a MANAGED_TARGETS=(
    "$VESTA_ROOT/bin/myvesta-domain-php-common.sh"
    "$VESTA_ROOT/bin/v-list-domain-php-config"
    "$VESTA_ROOT/bin/v-change-domain-php-config"
    "$VESTA_ROOT/bin/v-update-domain-php-config"
    "$VESTA_ROOT/bin/v-reapply-domain-php-config"
    "$VESTA_ROOT/bin/v-suggest-domain-php-config"
    "$VESTA_ROOT/bin/v-check-domain-php-config-patch"
    "$VESTA_ROOT/bin/v-uninstall-domain-php-config"
    "$VESTA_ROOT/web/edit/domain-php-config/index.php"
    "$VESTA_ROOT/web/templates/admin/edit_domain_php_config.html"
)
declare -a MANAGED_MODES=(0755 0755 0755 0755 0755 0755 0755 0755 0644 0644)

declare -a PATCH_NAMES=(
    edit_web.html.add-link.patch
    edit_web_user.html.add-link.patch
    v-rebuild-web-domains.add-hook.patch
    list_web_admin.add-php-link.patch
    list_web_user.add-php-link.patch
)
declare -a PATCH_TARGETS=(
    "$VESTA_ROOT/web/templates/admin/edit_web.html"
    "$VESTA_ROOT/web/templates/user/edit_web.html"
    "$VESTA_ROOT/bin/v-rebuild-web-domains"
    "$VESTA_ROOT/web/templates/admin/list_web.html"
    "$VESTA_ROOT/web/templates/user/list_web.html"
)
declare -a PATCH_MARKERS=(
    'PHP Domain Configuration'
    'PHP Domain Configuration'
    'v-reapply-domain-php-config'
    '/edit/domain-php-config/'
    '/edit/domain-php-config/'
)
declare -a PATCH_FUZZ=(0 0 0 0 0)

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    echo 'Usage: install.sh [--dry-run]'
}

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 64
fi
if [[ $# -eq 1 ]]; then
    [[ "$1" = --dry-run ]] || { usage >&2; exit 64; }
    DRY_RUN=yes
fi

if [[ "$VESTA_ROOT" != /usr/local/vesta && "$ALLOW_CUSTOM_ROOT" != yes ]]; then
    die 'myVesta installations outside /usr/local/vesta are not supported'
fi

patch_status() {
    local index="$1"
    local patch_file="$REPO_ROOT/patches/${PATCH_NAMES[$index]}"
    local target="${PATCH_TARGETS[$index]}"
    local marker="${PATCH_MARKERS[$index]}"
    local fuzz="${PATCH_FUZZ[$index]}"

    if grep -Fq "$marker" "$target"; then
        if patch --batch --forward --no-backup-if-mismatch --dry-run --reverse --fuzz="$fuzz" -p3 -d "$VESTA_ROOT" < "$patch_file" >/dev/null 2>&1; then
            echo applied
            return 0
        fi
        echo conflict
        return 1
    fi
    if patch --batch --no-backup-if-mismatch --dry-run --forward --fuzz="$fuzz" -p3 -d "$VESTA_ROOT" < "$patch_file" >/dev/null 2>&1; then
        echo applicable
        return 0
    fi
    echo conflict
    return 1
}

validate_existing_state() {
    local disposition target original patch_name marker fuzz
    [[ -e "$INSTALL_STATE" ]] || return 0
    [[ -f "$INSTALL_STATE/schema-version" ]] || die 'partial installation state: schema-version is missing'
    [[ "$(cat "$INSTALL_STATE/schema-version")" = 2 ]] || die 'unsupported installation-state schema'
    [[ -s "$INSTALL_STATE/files.manifest" ]] || die 'partial installation state: file manifest is missing'
    [[ -s "$INSTALL_STATE/patches.manifest" ]] || die 'partial installation state: patch manifest is missing'

    while IFS=$'\t' read -r disposition target original; do
        [[ -n "$target" ]] || continue
        case "$target" in "$VESTA_ROOT"/*) ;; *) die "unsafe installed file target: $target" ;; esac
        case "$disposition" in
            created) ;;
            restore)
                [[ "$original" = originals/* ]] || die "unsafe original path for $target"
                [[ -e "$INSTALL_STATE/$original" || -L "$INSTALL_STATE/$original" ]] || die "original file missing for $target"
                ;;
            *) die "invalid file disposition for $target" ;;
        esac
    done < "$INSTALL_STATE/files.manifest"

    while IFS=$'\t' read -r patch_name target marker fuzz; do
        [[ -n "$patch_name" ]] || continue
        case "$target" in "$VESTA_ROOT"/*) ;; *) die "unsafe installed patch target: $target" ;; esac
        [[ -f "$INSTALL_STATE/patches/$patch_name" ]] || die "installed patch copy missing: $patch_name"
    done < "$INSTALL_STATE/patches.manifest"
}

preflight() {
    local source target index status os_id os_version version version_dir
    local fpm_binary_found=no
    [[ "$(id -u)" = 0 ]] || die 'run as root'
    [[ -d "$VESTA_ROOT/bin" && -d "$VESTA_ROOT/web" ]] || die "myVesta not found at $VESTA_ROOT"
    [[ -f "$OS_RELEASE_FILE" ]] || die 'cannot identify operating system'
    os_id="$(sed -n 's/^ID=//p' "$OS_RELEASE_FILE" | tr -d '"' | head -1)"
    os_version="$(sed -n 's/^VERSION_ID=//p' "$OS_RELEASE_FILE" | tr -d '"' | head -1)"
    [[ "$os_id" = debian ]] || die 'only Debian is supported by this release'
    case "$os_version" in
        10|11|12) ;;
        *) die "Debian ${os_version:-unknown} is not supported by this beta" ;;
    esac

    for command_name in patch flock install mktemp cp mv grep awk sed tr head php; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name command is required"
    done
    [[ -x "$VESTA_ROOT/bin/v-search-domain-owner" ]] || die 'unsupported myVesta: v-search-domain-owner missing'
    [[ -x "$VESTA_ROOT/bin/v-get-php-version-of-domain" ]] || die 'unsupported myVesta: v-get-php-version-of-domain missing'
    [[ -x "$VESTA_ROOT/bin/v-rebuild-web-domains" ]] || die 'unsupported myVesta: v-rebuild-web-domains missing'
    validate_existing_state

    for source in "${MANAGED_SOURCES[@]}"; do
        [[ -f "$source" ]] || die "project file missing: $source"
    done
    php -l "$REPO_ROOT/web/edit/domain-php-config/index.php" >/dev/null || die 'panel controller does not pass PHP lint'
    php -l "$REPO_ROOT/web/templates/admin/edit_domain_php_config.html" >/dev/null || die 'panel template does not pass PHP lint'

    shopt -s nullglob
    local pool_directories=("$PHP_ETC_ROOT"/*/fpm/pool.d)
    shopt -u nullglob
    [[ ${#pool_directories[@]} -gt 0 ]] || die "no PHP-FPM pool directory found under $PHP_ETC_ROOT"
    for version_dir in "${pool_directories[@]}"; do
        version="$(basename "$(dirname "$(dirname "$version_dir")")")"
        if command -v "php-fpm${version}" >/dev/null 2>&1 || [[ -x "/usr/sbin/php-fpm${version}" ]]; then
            fpm_binary_found=yes
            break
        fi
    done
    [[ "$fpm_binary_found" = yes ]] || die 'no PHP-FPM binary matches the configured pool directories'

    for index in "${!PATCH_NAMES[@]}"; do
        target="${PATCH_TARGETS[$index]}"
        [[ -f "$target" ]] || die "myVesta patch target missing: $target"
        status="$(patch_status "$index")" || die "patch conflict: ${PATCH_NAMES[$index]}"
        printf 'Preflight OK: %-44s %s\n' "${PATCH_NAMES[$index]}" "$status"
    done
}

preflight
if [[ "$DRY_RUN" = yes ]]; then
    echo 'Preflight OK: no files changed'
    exit 0
fi

install -d -m 0750 "$STATE_ROOT" "$STATE_ROOT/domains" "$STATE_ROOT/backups"
exec 9>"$STATE_ROOT/.lifecycle.lock"
flock -x 9 || die 'cannot acquire lifecycle lock'

# Recheck while holding the lock so a concurrent panel update cannot invalidate
# the earlier preflight between validation and mutation.
preflight

BACKUP_ROOT="$(mktemp -d "$STATE_ROOT/backups/$(date +%Y%m%d%H%M%S).XXXXXX")"
TRANSACTION_MANIFEST="$BACKUP_ROOT/transaction.manifest"
STAGING_STATE="$(mktemp -d "$STATE_ROOT/.install-state.XXXXXX")"
transaction_started=yes
committed=no

backup_target() {
    local target="$1"
    local destination="$BACKUP_ROOT/targets$target"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$(dirname "$destination")"
        cp -a -- "$target" "$destination"
        printf 'existing\t%s\n' "$target" >> "$TRANSACTION_MANIFEST"
    else
        printf 'missing\t%s\n' "$target" >> "$TRANSACTION_MANIFEST"
    fi
}

restore_transaction() {
    local kind target source
    [[ -f "$TRANSACTION_MANIFEST" ]] || return 0
    while IFS=$'\t' read -r kind target; do
        [[ -n "$target" ]] || continue
        case "$target" in
            "$VESTA_ROOT"/*|"$STATE_ROOT"/*) ;;
            *) echo "ERROR: refusing unsafe rollback target: $target" >&2; continue ;;
        esac
        if [[ "$kind" = existing ]]; then
            source="$BACKUP_ROOT/targets$target"
            rm -rf -- "$target"
            mkdir -p "$(dirname "$target")"
            cp -a -- "$source" "$target"
        else
            rm -rf -- "$target"
        fi
    done < "$TRANSACTION_MANIFEST"
}

finish_transaction() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [[ "${committed:-no}" != yes && "${transaction_started:-no}" = yes ]]; then
        echo 'Installation failed; restoring every changed target.' >&2
        restore_transaction || true
        echo "Rollback backup retained at: $BACKUP_ROOT" >&2
    fi
    [[ -n "${STAGING_STATE:-}" && -d "${STAGING_STATE:-}" ]] && rm -rf -- "$STAGING_STATE"
    exit "$status"
}
trap finish_transaction EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

declare -A backed_up=()
for target in "${MANAGED_TARGETS[@]}" "${PATCH_TARGETS[@]}" "$INSTALL_STATE" "$LEGACY_MANIFEST" "$STATE_ROOT/last_backup"; do
    if [[ -z "${backed_up[$target]:-}" ]]; then
        backup_target "$target"
        backed_up[$target]=yes
    fi
done

mkdir -p "$STAGING_STATE/patches" "$STAGING_STATE/originals" "$STAGING_STATE/tools"
legacy_install=no
if [[ -f "$INSTALL_STATE/schema-version" ]]; then
    [[ "$(cat "$INSTALL_STATE/schema-version")" = 2 ]] || die 'unsupported installation-state schema'
    cp -a "$INSTALL_STATE/." "$STAGING_STATE/"
elif [[ -f "$LEGACY_MANIFEST" ]]; then
    legacy_install=yes
    cp -a "$LEGACY_MANIFEST" "$STAGING_STATE/legacy-installed.manifest"
fi

touch "$STAGING_STATE/files.manifest"
for index in "${!MANAGED_TARGETS[@]}"; do
    target="${MANAGED_TARGETS[$index]}"
    if grep -Fq $'\t'"$target"$'\t' "$STAGING_STATE/files.manifest" 2>/dev/null; then
        continue
    fi
    if [[ "$legacy_install" = yes ]]; then
        printf 'created\t%s\t-\n' "$target" >> "$STAGING_STATE/files.manifest"
    elif [[ -e "$target" || -L "$target" ]]; then
        original="$STAGING_STATE/originals$target"
        mkdir -p "$(dirname "$original")"
        cp -a -- "$target" "$original"
        printf 'restore\t%s\toriginals%s\n' "$target" "$target" >> "$STAGING_STATE/files.manifest"
    else
        printf 'created\t%s\t-\n' "$target" >> "$STAGING_STATE/files.manifest"
    fi
done

: > "$STAGING_STATE/patches.manifest"
for index in "${!PATCH_NAMES[@]}"; do
    patch_name="${PATCH_NAMES[$index]}"
    install -m 0644 "$REPO_ROOT/patches/$patch_name" "$STAGING_STATE/patches/$patch_name"
    printf '%s\t%s\t%s\t%s\n' "$patch_name" "${PATCH_TARGETS[$index]}" "${PATCH_MARKERS[$index]}" "${PATCH_FUZZ[$index]}" >> "$STAGING_STATE/patches.manifest"
done
install -m 0755 "$REPO_ROOT/uninstall.sh" "$STAGING_STATE/tools/uninstall.sh"
printf '2\n' > "$STAGING_STATE/schema-version"
printf '%s\n' "$PROJECT_VERSION" > "$STAGING_STATE/release"

for index in "${!MANAGED_SOURCES[@]}"; do
    install -D -m "${MANAGED_MODES[$index]}" "${MANAGED_SOURCES[$index]}" "${MANAGED_TARGETS[$index]}"
done

[[ "${MYVESTA_DOMAIN_PHP_TEST_FAIL_AT:-}" != after-files ]] || die 'injected failure after managed files'

for index in "${!PATCH_NAMES[@]}"; do
    status="$(patch_status "$index")" || die "patch conflict during transaction: ${PATCH_NAMES[$index]}"
    if [[ "$status" = applicable ]]; then
        patch --batch --no-backup-if-mismatch --forward --fuzz="${PATCH_FUZZ[$index]}" -p3 -d "$VESTA_ROOT" < "$REPO_ROOT/patches/${PATCH_NAMES[$index]}"
    fi
done

[[ "${MYVESTA_DOMAIN_PHP_TEST_FAIL_AT:-}" != after-patches ]] || die 'injected failure after patches'

rm -rf -- "$INSTALL_STATE"
mv "$STAGING_STATE" "$INSTALL_STATE"
STAGING_STATE=''
rm -f -- "$LEGACY_MANIFEST"
printf '%s\n' "$BACKUP_ROOT" > "$STATE_ROOT/last_backup"

[[ "${MYVESTA_DOMAIN_PHP_TEST_FAIL_AT:-}" != before-check ]] || die 'injected failure before post-install check'

if ! env VESTA_ROOT="$VESTA_ROOT" \
    MYVESTA_DOMAIN_PHP_STATE="$STATE_ROOT" \
    MYVESTA_DOMAIN_PHP_ETC="$PHP_ETC_ROOT" \
    MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT="$ALLOW_CUSTOM_ROOT" \
    "$VESTA_ROOT/bin/v-check-domain-php-config-patch" > "$BACKUP_ROOT/post-install-check.log" 2>&1; then
    cat "$BACKUP_ROOT/post-install-check.log" >&2
    die 'post-install verification failed'
fi

committed=yes
echo "Installed myVesta domain PHP configuration $PROJECT_VERSION."
echo "Backup: $BACKUP_ROOT"
cat "$BACKUP_ROOT/post-install-check.log"
