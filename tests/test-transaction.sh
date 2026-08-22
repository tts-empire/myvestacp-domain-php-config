#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/myvesta-domain-php-test.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

export VESTA_ROOT="$TEST_ROOT/vesta"
export MYVESTA_DOMAIN_PHP_STATE="$TEST_ROOT/state"
export MYVESTA_DOMAIN_PHP_ETC="$TEST_ROOT/etc/php"
export MYVESTA_DOMAIN_PHP_SERVICE_ROOT="$TEST_ROOT/services"
export TEST_RESTART_LOG="$TEST_ROOT/restarts.log"
export TEST_FPM_INVALID="$TEST_ROOT/fpm-invalid"
export TEST_RESTART_FAIL_ONCE="$TEST_ROOT/restart-fail-once"
export PATH="$TEST_ROOT/mock-bin:$PATH"

mkdir -p "$VESTA_ROOT/bin" "$MYVESTA_DOMAIN_PHP_STATE/domains" "$MYVESTA_DOMAIN_PHP_ETC/8.2/fpm/pool.d" "$MYVESTA_DOMAIN_PHP_SERVICE_ROOT" "$TEST_ROOT/mock-bin"
touch "$MYVESTA_DOMAIN_PHP_SERVICE_ROOT/php8.2-fpm" "$TEST_RESTART_LOG"

printf '#!/bin/bash\necho test-user\n' > "$VESTA_ROOT/bin/v-search-domain-owner"
printf '#!/bin/bash\necho 8.2\n' > "$VESTA_ROOT/bin/v-get-php-version-of-domain"
printf '%s\n' \
    '#!/bin/bash' \
    'if [[ "$1" = "-i" ]]; then' \
    '  printf "%s\\n" "memory_limit => 128M => 128M" "max_execution_time => 30 => 30" "max_input_time => 60 => 60" "post_max_size => 32M => 32M" "upload_max_filesize => 32M => 32M" "max_input_vars => 1000 => 1000" "max_file_uploads => 20 => 20"' \
    '  exit 0' \
    'fi' \
    'if [[ "$1" = "-t" && -e "$TEST_FPM_INVALID" ]]; then echo invalid >&2; exit 1; fi' \
    'exit 0' > "$TEST_ROOT/mock-bin/php-fpm8.2"
printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s\\n" "$*" >> "$TEST_RESTART_LOG"' \
    'if [[ "$1" = "restart" && -e "$TEST_RESTART_FAIL_ONCE" ]]; then rm -f "$TEST_RESTART_FAIL_ONCE"; exit 1; fi' \
    'exit 0' > "$TEST_ROOT/mock-bin/systemctl"
chmod +x "$VESTA_ROOT/bin/v-search-domain-owner" "$VESTA_ROOT/bin/v-get-php-version-of-domain" "$TEST_ROOT/mock-bin/php-fpm8.2" "$TEST_ROOT/mock-bin/systemctl"

POOL="$MYVESTA_DOMAIN_PHP_ETC/8.2/fpm/pool.d/example.test.conf"
printf '%s\n' \
    '[example.test]' \
    'user = test-user' \
    'group = test-user' \
    'listen = /run/php/example.test.sock' \
    'pm = ondemand' \
    'pm.max_children = 4' \
    'pm.max_requests = 1000' \
    'php_admin_value[memory_limit] = 256M' \
    'php_admin_value[max_execution_time] = 45' > "$POOL"

"$ROOT/bin/v-update-domain-php-config" example.test yes set memory_limit 384M set pm.max_children 7 >/tmp/myvesta-domain-php-test-output
grep -qx 'memory_limit=384M' "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf"
grep -qx 'pm.max_children=7' "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf"
grep -q '^php_admin_value\[memory_limit\] = 384M$' "$POOL"
grep -q '^pm.max_children = 7$' "$POOL"
[[ "$(wc -l < "$TEST_RESTART_LOG")" -eq 1 ]]

config_json="$("$ROOT/bin/v-list-domain-php-config" example.test json)"
php -r '
$data = json_decode($argv[1], true);
if (!is_array($data)) exit(1);
if ($data["ACTUAL"]["memory_limit"]["VALUE"] !== "384M") exit(2);
if ($data["ACTUAL"]["memory_limit"]["SOURCE"] !== "managed") exit(3);
if ($data["ACTUAL"]["memory_limit"]["BASE_VALUE"] !== "256M") exit(4);
if ($data["ACTUAL"]["max_input_time"]["VALUE"] !== "60") exit(5);
if ($data["ACTUAL"]["max_input_time"]["SOURCE"] !== "php_ini") exit(6);
' "$config_json"

"$ROOT/bin/v-update-domain-php-config" example.test no reset memory_limit >/tmp/myvesta-domain-php-test-output
! grep -q '^memory_limit=' "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf"
[[ "$(grep -c '^php_admin_value\[memory_limit\] = 256M$' "$POOL")" -eq 1 ]]
! grep -q '^php_admin_value\[memory_limit\] = 384M$' "$POOL"

"$ROOT/bin/v-change-domain-php-config" example.test pm.max_requests 2000 no >/tmp/myvesta-domain-php-test-output
grep -qx 'pm.max_requests=2000' "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf"

cp -a "$POOL" "$TEST_ROOT/pool.before-failure"
cp -a "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf" "$TEST_ROOT/state.before-failure"
touch "$TEST_FPM_INVALID"
if "$ROOT/bin/v-update-domain-php-config" example.test no set post_max_size 128M >/tmp/myvesta-domain-php-test-output 2>&1; then
    echo 'transaction unexpectedly succeeded with invalid FPM configuration' >&2
    exit 1
fi
cmp "$POOL" "$TEST_ROOT/pool.before-failure"
cmp "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf" "$TEST_ROOT/state.before-failure"

rm -f "$TEST_FPM_INVALID"
cp -a "$POOL" "$TEST_ROOT/pool.before-restart-failure"
cp -a "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf" "$TEST_ROOT/state.before-restart-failure"
touch "$TEST_RESTART_FAIL_ONCE"
if "$ROOT/bin/v-update-domain-php-config" example.test yes set upload_max_filesize 64M >/tmp/myvesta-domain-php-test-output 2>&1; then
    echo 'transaction unexpectedly succeeded with failed PHP-FPM restart' >&2
    exit 1
fi
cmp "$POOL" "$TEST_ROOT/pool.before-restart-failure"
cmp "$MYVESTA_DOMAIN_PHP_STATE/domains/example.test.conf" "$TEST_ROOT/state.before-restart-failure"
grep -q '^reset-failed php8.2-fpm$' "$TEST_RESTART_LOG"

echo "Transaction tests passed."
