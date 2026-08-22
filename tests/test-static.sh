#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for file in "$ROOT"/*.sh "$ROOT"/bin/* "$ROOT"/lib/*.sh; do
    bash -n "$file"
done
for file in "$ROOT"/web/edit/domain-php-config/*.php; do
    php -l "$file" >/tmp/myvesta-domain-php-lint
done

grep -q 'class="data mode-add"' "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q 'class="data-col2" width="600px"' "$ROOT/web/templates/admin/edit_domain_php_config.html"
grep -q 'class="button cancel"' "$ROOT/web/templates/admin/edit_domain_php_config.html"

check_patch() {
    local patch_file="$1"
    local patch_fuzz="$2"
    patch --dry-run --fuzz="$patch_fuzz" --forward -p0 -d / < "$patch_file" >/tmp/myvesta-domain-php-patch 2>&1 || \
        patch --dry-run --fuzz="$patch_fuzz" --reverse -p0 -d / < "$patch_file" >/tmp/myvesta-domain-php-patch 2>&1
}

if [[ -d /usr/local/vesta && -f /usr/local/vesta/web/templates/admin/edit_web.html ]]; then
    check_patch "$ROOT/patches/edit_web.html.add-link.patch" 3
    check_patch "$ROOT/patches/v-rebuild-web-domains.add-hook.patch" 3
    check_patch "$ROOT/patches/list_web_admin.add-php-link.patch" 0
    check_patch "$ROOT/patches/list_web_user.add-php-link.patch" 0
fi

if [[ -n "${MYVESTA_TEST_DOMAIN:-}" ]]; then
    "$ROOT/bin/v-suggest-domain-php-config" "$MYVESTA_TEST_DOMAIN" json >/tmp/myvesta-domain-php-advisor.json
    grep -q '"SUGGESTED"' /tmp/myvesta-domain-php-advisor.json
fi

echo "Static tests passed."
