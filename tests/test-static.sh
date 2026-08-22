#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for file in "$ROOT"/*.sh "$ROOT"/bin/* "$ROOT"/lib/*.sh; do
    bash -n "$file"
done
for file in "$ROOT"/web/edit/domain-php-config/*.php; do
    php -l "$file" >/tmp/myvesta-domain-php-lint
done

if [[ -d /usr/local/vesta && -f /usr/local/vesta/web/templates/admin/edit_web.html ]]; then
    patch --dry-run --fuzz=3 --forward -p0 -d / < "$ROOT/patches/edit_web.html.add-link.patch" >/tmp/myvesta-domain-php-patch 2>&1 || patch --dry-run --fuzz=3 --reverse -p0 -d / < "$ROOT/patches/edit_web.html.add-link.patch" >/tmp/myvesta-domain-php-patch 2>&1
    patch --dry-run --fuzz=3 --forward -p0 -d / < "$ROOT/patches/v-rebuild-web-domains.add-hook.patch" >/tmp/myvesta-domain-php-patch 2>&1 || patch --dry-run --fuzz=3 --reverse -p0 -d / < "$ROOT/patches/v-rebuild-web-domains.add-hook.patch" >/tmp/myvesta-domain-php-patch 2>&1
    patch --dry-run --fuzz=3 --forward -p0 -d / < "$ROOT/patches/edit_web_user.html.add-link.patch" >/tmp/myvesta-domain-php-patch 2>&1 || patch --dry-run --fuzz=3 --reverse -p0 -d / < "$ROOT/patches/edit_web_user.html.add-link.patch" >/tmp/myvesta-domain-php-patch 2>&1
fi

if [[ -n "${MYVESTA_TEST_DOMAIN:-}" ]]; then
    "$ROOT/bin/v-suggest-domain-php-config" "$MYVESTA_TEST_DOMAIN" json >/tmp/myvesta-domain-php-advisor.json
    grep -q '"SUGGESTED"' /tmp/myvesta-domain-php-advisor.json
fi

echo "Static tests passed."
