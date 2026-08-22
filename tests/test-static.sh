#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/myvesta-domain-php-static.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
for file in "$ROOT"/*.sh "$ROOT"/bin/* "$ROOT"/lib/*.sh; do
    bash -n "$file"
done
for file in "$ROOT"/web/edit/domain-php-config/*.php; do
    php -l "$file" >/dev/null
done
php -l "$ROOT/web/templates/admin/edit_domain_php_config.html" >/dev/null

grep -q "v-update-domain-php-config" "$ROOT/web/edit/domain-php-config/index.php"
grep -q "actual_value" "$ROOT/web/edit/domain-php-config/index.php"
grep -q "2>&1" "$ROOT/web/edit/domain-php-config/index.php"
grep -q 'class="data mode-add"' "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q 'class="data-col2" width="600px"' "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q 'class="button cancel"' "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q "Actual setting" "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q "Suggested setting" "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q "useDomainPhpSuggestion" "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q "resetDomainPhpSetting" "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q "specific to this server; they are not standard PHP defaults" "$ROOT/web/edit/domain-php-config/index.php"
test -x "$ROOT/bin/v-update-domain-php-config"
test -x "$ROOT/bin/v-uninstall-domain-php-config"
grep -q "0.2.0-beta" "$ROOT/install.sh"
grep -q "installation-state schema 2" "$ROOT/bin/v-check-domain-php-config-patch"

check_patch() {
    local patch_file="$1"
    patch --batch --no-backup-if-mismatch --dry-run --fuzz=0 --forward -p0 -d / < "$patch_file" >/dev/null 2>&1 || \
        patch --batch --no-backup-if-mismatch --dry-run --fuzz=0 --forward --reverse -p0 -d / < "$patch_file" >/dev/null 2>&1
}

if [[ -d /usr/local/vesta && -f /usr/local/vesta/web/templates/admin/edit_web.html ]]; then
    check_patch "$ROOT/patches/edit_web.html.add-link.patch"
    check_patch "$ROOT/patches/edit_web_user.html.add-link.patch"
    check_patch "$ROOT/patches/v-rebuild-web-domains.add-hook.patch"
    check_patch "$ROOT/patches/list_web_admin.add-php-link.patch"
    check_patch "$ROOT/patches/list_web_user.add-php-link.patch"
fi

if [[ -n "${MYVESTA_TEST_DOMAIN:-}" ]]; then
    "$ROOT/bin/v-suggest-domain-php-config" "$MYVESTA_TEST_DOMAIN" json > "$TEST_TMP/advisor.json"
    grep -q '"SUGGESTED"' "$TEST_TMP/advisor.json"
fi

"$ROOT/tests/test-transaction.sh"
"$ROOT/tests/test-lifecycle.sh"

echo "Static tests passed."
