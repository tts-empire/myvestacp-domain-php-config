#!/bin/bash
set -Eeuo pipefail

VESTA_ROOT="${VESTA_ROOT:-/usr/local/vesta}"
STATE_ROOT="${MYVESTA_DOMAIN_PHP_STATE:-/var/lib/myvesta-domain-php-config}"
ALLOW_CUSTOM_ROOT="${MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT:-no}"
INSTALL_STATE="$STATE_ROOT/install"
INSTALLED_UNINSTALLER="$INSTALL_STATE/tools/uninstall.sh"
DRY_RUN=no

if [[ "${MYVESTA_DOMAIN_PHP_UNINSTALL_INTERNAL:-no}" != yes && -x "$INSTALLED_UNINSTALLER" ]]; then
    exec env MYVESTA_DOMAIN_PHP_UNINSTALL_INTERNAL=yes \
        VESTA_ROOT="$VESTA_ROOT" \
        MYVESTA_DOMAIN_PHP_STATE="$STATE_ROOT" \
        MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT="$ALLOW_CUSTOM_ROOT" \
        "$INSTALLED_UNINSTALLER" "$@"
fi

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    echo 'Usage: uninstall.sh [--dry-run]'
}

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 64
fi
if [[ $# -eq 1 ]]; then
    [[ "$1" = --dry-run ]] || { usage >&2; exit 64; }
    DRY_RUN=yes
fi

[[ "$(id -u)" = 0 ]] || die 'run as root'
if [[ "$VESTA_ROOT" != /usr/local/vesta && "$ALLOW_CUSTOM_ROOT" != yes ]]; then
    die 'myVesta installations outside /usr/local/vesta are not supported'
fi
if [[ ! -f "$INSTALL_STATE/schema-version" ]]; then
    if [[ -f "$STATE_ROOT/installed.manifest" ]]; then
        die 'legacy 0.1.0 state detected; run the 0.2.0 upgrade before uninstalling'
    fi
    echo 'Patch is not installed.'
    exit 0
fi
[[ "$(cat "$INSTALL_STATE/schema-version")" = 2 ]] || die 'unsupported installation-state schema'
[[ -f "$INSTALL_STATE/files.manifest" ]] || die 'installed file manifest is missing'
[[ -f "$INSTALL_STATE/patches.manifest" ]] || die 'installed patch manifest is missing'

validate_target() {
    case "$1" in
        "$VESTA_ROOT"/*) return 0 ;;
        *) die "unsafe manifest target: $1" ;;
    esac
}

patch_preflight() {
    local patch_name target marker fuzz patch_file
    while IFS=$'\t' read -r patch_name target marker fuzz; do
        [[ -n "$patch_name" ]] || continue
        validate_target "$target"
        patch_file="$INSTALL_STATE/patches/$patch_name"
        [[ -f "$patch_file" && -f "$target" ]] || die "installed patch state is incomplete: $patch_name"
        if grep -Fq "$marker" "$target"; then
            patch --batch --forward --no-backup-if-mismatch --dry-run --reverse --fuzz="$fuzz" -p3 -d "$VESTA_ROOT" < "$patch_file" >/dev/null 2>&1 || die "cannot safely remove patch: $patch_name"
            printf 'Uninstall preflight OK: %-44s applied\n' "$patch_name"
        else
            printf 'Uninstall preflight OK: %-44s already absent\n' "$patch_name"
        fi
    done < "$INSTALL_STATE/patches.manifest"
}

while IFS=$'\t' read -r disposition target original; do
    [[ -n "$target" ]] || continue
    validate_target "$target"
    case "$disposition" in
        created) ;;
        restore)
            [[ "$original" = originals/* ]] || die "unsafe original path for $target"
            [[ -e "$INSTALL_STATE/$original" || -L "$INSTALL_STATE/$original" ]] || die "original file missing for $target"
            ;;
        *) die "invalid file disposition for $target" ;;
    esac
done < "$INSTALL_STATE/files.manifest"
patch_preflight

if [[ "$DRY_RUN" = yes ]]; then
    echo 'Uninstall preflight OK: no files changed'
    exit 0
fi

exec 9>"$STATE_ROOT/.lifecycle.lock"
flock -x 9 || die 'cannot acquire lifecycle lock'
patch_preflight

BACKUP_ROOT="$(mktemp -d "$STATE_ROOT/backups/$(date +%Y%m%d%H%M%S)-uninstall.XXXXXX")"
TRANSACTION_MANIFEST="$BACKUP_ROOT/transaction.manifest"
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
        echo 'Uninstall failed; restoring every changed target.' >&2
        restore_transaction || true
        echo "Rollback backup retained at: $BACKUP_ROOT" >&2
    fi
    exit "$status"
}
trap finish_transaction EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

declare -A backed_up=()
while IFS=$'\t' read -r disposition target original; do
    [[ -n "$target" ]] || continue
    if [[ -z "${backed_up[$target]:-}" ]]; then
        backup_target "$target"
        backed_up[$target]=yes
    fi
done < "$INSTALL_STATE/files.manifest"
while IFS=$'\t' read -r patch_name target marker fuzz; do
    [[ -n "$target" ]] || continue
    if [[ -z "${backed_up[$target]:-}" ]]; then
        backup_target "$target"
        backed_up[$target]=yes
    fi
done < "$INSTALL_STATE/patches.manifest"
backup_target "$INSTALL_STATE"
backup_target "$STATE_ROOT/last_backup"

mapfile -t patch_records < "$INSTALL_STATE/patches.manifest"
for (( index=${#patch_records[@]}-1; index>=0; index-- )); do
    IFS=$'\t' read -r patch_name target marker fuzz <<< "${patch_records[$index]}"
    [[ -n "$patch_name" ]] || continue
    if grep -Fq "$marker" "$target"; then
        patch --batch --forward --no-backup-if-mismatch --reverse --fuzz="$fuzz" -p3 -d "$VESTA_ROOT" < "$INSTALL_STATE/patches/$patch_name"
    fi
done

[[ "${MYVESTA_DOMAIN_PHP_TEST_FAIL_AT:-}" != uninstall-after-patches ]] || die 'injected uninstall failure after patches'

while IFS=$'\t' read -r disposition target original; do
    [[ -n "$target" ]] || continue
    if [[ "$disposition" = restore ]]; then
        rm -rf -- "$target"
        mkdir -p "$(dirname "$target")"
        cp -a -- "$INSTALL_STATE/$original" "$target"
    else
        rm -f -- "$target"
    fi
done < "$INSTALL_STATE/files.manifest"

[[ "${MYVESTA_DOMAIN_PHP_TEST_FAIL_AT:-}" != uninstall-after-files ]] || die 'injected uninstall failure after managed files'

rmdir "$VESTA_ROOT/web/edit/domain-php-config" 2>/dev/null || true
rm -rf -- "$INSTALL_STATE"
printf '%s\n' "$BACKUP_ROOT" > "$STATE_ROOT/last_backup"

for record in "${patch_records[@]}"; do
    IFS=$'\t' read -r patch_name target marker fuzz <<< "$record"
    [[ -n "$target" ]] || continue
    grep -Fq "$marker" "$target" && die "patch marker remains after uninstall: $patch_name"
done

committed=yes
echo 'Patch code removed. Domain state was retained.'
echo "Backup: $BACKUP_ROOT"
echo "Domain state: $STATE_ROOT/domains"
