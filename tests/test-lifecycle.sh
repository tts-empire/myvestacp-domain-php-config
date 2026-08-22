#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/myvesta-domain-php-lifecycle.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

CASE_ROOT=''
VESTA_ROOT=''
STATE_ROOT=''
PHP_ETC_ROOT=''
CASE_PATH=''
BASE_PATH="$PATH"

fail() {
    echo "Lifecycle test failed: $*" >&2
    exit 1
}

create_fixture() {
    local name="$1" dialect="$2"
    CASE_ROOT="$TEST_ROOT/$name"
    VESTA_ROOT="$CASE_ROOT/vesta"
    STATE_ROOT="$CASE_ROOT/state"
    PHP_ETC_ROOT="$CASE_ROOT/etc/php"
    mkdir -p "$VESTA_ROOT" "$VESTA_ROOT/bin" "$PHP_ETC_ROOT/8.2/fpm/pool.d" "$CASE_ROOT/mock-bin"
    cp -a "$ROOT/tests/fixtures/$dialect/." "$VESTA_ROOT/"
    chmod 0755 "$VESTA_ROOT/bin/v-rebuild-web-domains"
    printf '#!/bin/bash\necho test-user\n' > "$VESTA_ROOT/bin/v-search-domain-owner"
    printf '#!/bin/bash\necho 8.2\n' > "$VESTA_ROOT/bin/v-get-php-version-of-domain"
    chmod 0755 "$VESTA_ROOT/bin/v-search-domain-owner" "$VESTA_ROOT/bin/v-get-php-version-of-domain"
    printf '#!/bin/bash\nexit 0\n' > "$CASE_ROOT/mock-bin/php-fpm8.2"
    chmod 0755 "$CASE_ROOT/mock-bin/php-fpm8.2"
    CASE_PATH="$CASE_ROOT/mock-bin:$BASE_PATH"
    printf '[example.test]\npm = ondemand\npm.max_children = 4\n' > "$PHP_ETC_ROOT/8.2/fpm/pool.d/example.test.conf"
}

installer() {
    env \
        VESTA_ROOT="$VESTA_ROOT" \
        MYVESTA_DOMAIN_PHP_STATE="$STATE_ROOT" \
        MYVESTA_DOMAIN_PHP_ETC="$PHP_ETC_ROOT" \
        MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT=yes \
        PATH="$CASE_PATH" \
        "$ROOT/install.sh" "$@"
}

installed_uninstaller() {
    env \
        VESTA_ROOT="$VESTA_ROOT" \
        MYVESTA_DOMAIN_PHP_STATE="$STATE_ROOT" \
        MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT=yes \
        PATH="$CASE_PATH" \
        "$VESTA_ROOT/bin/v-uninstall-domain-php-config" "$@"
}

snapshot_vesta() {
    find "$VESTA_ROOT" -type f -print0 | sort -z | xargs -0 sha256sum
}

assert_markers() {
    grep -Fq 'PHP Domain Configuration' "$VESTA_ROOT/web/templates/admin/edit_web.html"
    grep -Fq 'PHP Domain Configuration' "$VESTA_ROOT/web/templates/user/edit_web.html"
    grep -Fq '/edit/domain-php-config/' "$VESTA_ROOT/web/templates/admin/list_web.html"
    grep -Fq '/edit/domain-php-config/' "$VESTA_ROOT/web/templates/user/list_web.html"
    grep -Fq 'v-reapply-domain-php-config' "$VESTA_ROOT/bin/v-rebuild-web-domains"
}

assert_no_markers() {
    ! grep -Fq 'PHP Domain Configuration' "$VESTA_ROOT/web/templates/admin/edit_web.html"
    ! grep -Fq 'PHP Domain Configuration' "$VESTA_ROOT/web/templates/user/edit_web.html"
    ! grep -Fq '/edit/domain-php-config/' "$VESTA_ROOT/web/templates/admin/list_web.html"
    ! grep -Fq '/edit/domain-php-config/' "$VESTA_ROOT/web/templates/user/list_web.html"
    ! grep -Fq 'v-reapply-domain-php-config' "$VESTA_ROOT/bin/v-rebuild-web-domains"
}

apply_fixture_patches() {
    local patch_file fuzz
    for patch_file in \
        edit_web.html.add-link.patch \
        edit_web_user.html.add-link.patch \
        v-rebuild-web-domains.add-hook.patch \
        list_web_admin.add-php-link.patch \
        list_web_user.add-php-link.patch; do
        fuzz=0
        patch --batch --no-backup-if-mismatch --forward --fuzz="$fuzz" -p3 -d "$VESTA_ROOT" < "$ROOT/patches/$patch_file" >/dev/null
    done
}

install_legacy_files() {
    install -m 0755 "$ROOT/lib/domain-php-common.sh" "$VESTA_ROOT/bin/myvesta-domain-php-common.sh"
    for command_name in v-list-domain-php-config v-change-domain-php-config v-update-domain-php-config v-reapply-domain-php-config v-suggest-domain-php-config v-check-domain-php-config-patch; do
        install -m 0755 "$ROOT/bin/$command_name" "$VESTA_ROOT/bin/$command_name"
    done
    install -d "$VESTA_ROOT/web/edit/domain-php-config" "$VESTA_ROOT/web/templates/admin"
    install -m 0644 "$ROOT/web/edit/domain-php-config/index.php" "$VESTA_ROOT/web/edit/domain-php-config/index.php"
    install -m 0644 "$ROOT/web/templates/admin/edit_domain_php_config.html" "$VESTA_ROOT/web/templates/admin/edit_domain_php_config.html"
    mkdir -p "$STATE_ROOT/domains"
    printf 'memory_limit=384M\n' > "$STATE_ROOT/domains/example.test.conf"
    {
        printf '%s\n' "$VESTA_ROOT/bin/myvesta-domain-php-common.sh"
        printf '%s\n' "$VESTA_ROOT/bin/v-list-domain-php-config"
        printf 'PATCH:%s\n' "$ROOT/patches/edit_web.html.add-link.patch"
    } > "$STATE_ROOT/installed.manifest"
}

echo 'Lifecycle: fixture patch compatibility'
for dialect in upstream-current legacy-debian10; do
    create_fixture "patch-$dialect" "$dialect"
    installer --dry-run >/dev/null
done

echo 'Lifecycle: clean install, idempotency and checkout-independent uninstall'
create_fixture clean upstream-current
mkdir -p "$STATE_ROOT/domains"
printf 'memory_limit=256M\n' > "$STATE_ROOT/domains/example.test.conf"
before="$(snapshot_vesta)"
installer --dry-run >/dev/null
[[ "$(snapshot_vesta)" = "$before" ]] || fail 'dry-run changed the myVesta fixture'
installer >/dev/null
assert_markers
grep -qx 2 "$STATE_ROOT/install/schema-version"
grep -qx '0.2.0-beta' "$STATE_ROOT/install/release"
[[ -x "$VESTA_ROOT/bin/v-uninstall-domain-php-config" ]]
installer >/dev/null
[[ "$(grep -Fc 'PHP Domain Configuration' "$VESTA_ROOT/web/templates/admin/edit_web.html")" -eq 1 ]]
installed_uninstaller --dry-run >/dev/null
installed_uninstaller >/dev/null
assert_no_markers
[[ -f "$STATE_ROOT/domains/example.test.conf" ]]
[[ ! -e "$VESTA_ROOT/bin/v-update-domain-php-config" ]]
[[ ! -e "$STATE_ROOT/install" ]]

echo 'Lifecycle: pre-existing managed file restoration'
create_fixture original-file upstream-current
printf '#!/bin/bash\necho original-command\n' > "$VESTA_ROOT/bin/v-list-domain-php-config"
chmod 0755 "$VESTA_ROOT/bin/v-list-domain-php-config"
installer >/dev/null
installed_uninstaller >/dev/null
grep -Fq 'original-command' "$VESTA_ROOT/bin/v-list-domain-php-config"

echo 'Lifecycle: legacy 0.1.0 migration'
create_fixture legacy-upgrade legacy-debian10
apply_fixture_patches
install_legacy_files
installer >/dev/null
assert_markers
grep -qx 2 "$STATE_ROOT/install/schema-version"
[[ -f "$STATE_ROOT/install/legacy-installed.manifest" ]]
[[ ! -e "$STATE_ROOT/installed.manifest" ]]
grep -qx 'memory_limit=384M' "$STATE_ROOT/domains/example.test.conf"
installed_uninstaller >/dev/null
assert_no_markers
grep -qx 'memory_limit=384M' "$STATE_ROOT/domains/example.test.conf"

echo 'Lifecycle: install rollback at every mutation boundary'
for failure_point in after-files after-patches before-check; do
    create_fixture "failure-$failure_point" upstream-current
    before="$(snapshot_vesta)"
    if MYVESTA_DOMAIN_PHP_TEST_FAIL_AT="$failure_point" installer >/dev/null 2>&1; then
        fail "installer unexpectedly succeeded at $failure_point"
    fi
    after="$(snapshot_vesta)"
    if [[ "$after" != "$before" ]]; then
        diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
        fail "rollback mismatch at $failure_point"
    fi
    [[ ! -e "$STATE_ROOT/install" ]] || fail "install state remained at $failure_point"
done

echo 'Lifecycle: uninstall rollback'
create_fixture uninstall-failure upstream-current
installer >/dev/null
before="$(snapshot_vesta)"
if MYVESTA_DOMAIN_PHP_TEST_FAIL_AT=uninstall-after-patches installed_uninstaller >/dev/null 2>&1; then
    fail 'uninstaller unexpectedly succeeded after patch removal'
fi
[[ "$(snapshot_vesta)" = "$before" ]] || fail 'uninstall rollback did not restore myVesta files'
assert_markers
grep -qx 2 "$STATE_ROOT/install/schema-version"
installed_uninstaller >/dev/null

echo 'Lifecycle: conflicts and unsupported environments'
create_fixture conflict upstream-current
sed -i 's/WordPress/CustomPress/' "$VESTA_ROOT/web/templates/admin/list_web.html"
before="$(snapshot_vesta)"
if installer --dry-run >/dev/null 2>&1; then
    fail 'conflicting fixture passed preflight'
fi
[[ "$(snapshot_vesta)" = "$before" ]] || fail 'conflict preflight changed files'

create_fixture mixed upstream-current
printf '\n<!-- PHP Domain Configuration -->\n' >> "$VESTA_ROOT/web/templates/admin/edit_web.html"
if installer --dry-run >/dev/null 2>&1; then
    fail 'partial marker passed preflight'
fi

create_fixture partial-state upstream-current
mkdir -p "$STATE_ROOT/install"
if installer --dry-run >/dev/null 2>&1; then
    fail 'partial schema-2 state passed preflight'
fi

create_fixture unsupported-root upstream-current
if env VESTA_ROOT="$VESTA_ROOT" MYVESTA_DOMAIN_PHP_STATE="$STATE_ROOT" MYVESTA_DOMAIN_PHP_ETC="$PHP_ETC_ROOT" "$ROOT/install.sh" --dry-run >/dev/null 2>&1; then
    fail 'unsupported root was accepted without the test-only override'
fi

create_fixture unsupported-os upstream-current
printf 'ID=debian\nVERSION_ID=13\n' > "$CASE_ROOT/os-release"
if env VESTA_ROOT="$VESTA_ROOT" MYVESTA_DOMAIN_PHP_STATE="$STATE_ROOT" MYVESTA_DOMAIN_PHP_ETC="$PHP_ETC_ROOT" MYVESTA_DOMAIN_PHP_OS_RELEASE="$CASE_ROOT/os-release" MYVESTA_DOMAIN_PHP_TEST_ALLOW_CUSTOM_ROOT=yes PATH="$CASE_PATH" "$ROOT/install.sh" --dry-run >/dev/null 2>&1; then
    fail 'Debian 13 fixture was accepted'
fi

echo 'Lifecycle tests passed.'
