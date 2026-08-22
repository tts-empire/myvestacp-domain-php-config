#!/bin/bash

# Shared implementation for the MyVesta domain PHP configuration commands.
# This file is installed outside the MyVesta source tree.

set -u

VESTA_ROOT="${VESTA_ROOT:-/usr/local/vesta}"
STATE_ROOT="${MYVESTA_DOMAIN_PHP_STATE:-/var/lib/myvesta-domain-php-config}"
DOMAIN_STATE_ROOT="$STATE_ROOT/domains"
PHP_ETC_ROOT="${MYVESTA_DOMAIN_PHP_ETC:-/etc/php}"
SERVICE_MARKER_ROOT="${MYVESTA_DOMAIN_PHP_SERVICE_ROOT:-}"
MANAGED_BEGIN='; BEGIN MYVESTA-DOMAIN-PHP-CONFIG'
MANAGED_END='; END MYVESTA-DOMAIN-PHP-CONFIG'

PHP_PARAMETERS="memory_limit max_execution_time max_input_time post_max_size upload_max_filesize max_input_vars max_file_uploads pm.max_children pm pm.max_requests"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}

valid_parameter() {
    local parameter="$1"
    local candidate
    for candidate in $PHP_PARAMETERS; do
        [[ "$candidate" = "$parameter" ]] && return 0
    done
    return 1
}

valid_value() {
    local parameter="$1"
    local value="$2"
    case "$parameter" in
        memory_limit|post_max_size|upload_max_filesize)
            [[ "$value" =~ ^[0-9]+([KMG]B?|B)?$ ]]
            ;;
        max_execution_time|max_input_time|max_input_vars|max_file_uploads|pm.max_children|pm.max_requests)
            [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 0 ))
            ;;
        pm)
            [[ "$value" = ondemand || "$value" = dynamic || "$value" = static ]] 
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_state() {
    install -d -m 0750 "$DOMAIN_STATE_ROOT"
}

owner_of() {
    local domain="$1"
    "$VESTA_ROOT/bin/v-search-domain-owner" "$domain" 2>&1 | awk 'NF { print $1; exit }'
}

php_version_of() {
    "$VESTA_ROOT/bin/v-get-php-version-of-domain" "$1" 2>&1 | awk 'NF { print $1; exit }'
}

config_file_of() {
    local domain="$1"
    local version="$2"
    printf '%s/%s/fpm/pool.d/%s.conf\n' "$PHP_ETC_ROOT" "$version" "$domain"
}

service_exists() {
    local version="$1"
    if [[ -n "$SERVICE_MARKER_ROOT" ]]; then
        [[ -e "$SERVICE_MARKER_ROOT/php${version}-fpm" ]]
        return $?
    fi
    [[ -e "/etc/init.d/php${version}-fpm" || -e "/lib/systemd/system/php${version}-fpm.service" || -e "/etc/systemd/system/php${version}-fpm.service" ]]
}

php_fpm_binary() {
    local version="$1"
    local binary
    for binary in "php-fpm${version}" "/usr/sbin/php-fpm${version}" "/usr/sbin/php-fpm"; do
        if command -v "$binary" >/tmp/myvesta-domain-php-command-check 2>&1 || [[ -x "$binary" ]]; then
            command -v "$binary" 2>/tmp/myvesta-domain-php-command-path || printf '%s\n' "$binary"
            return 0
        fi
    done
    return 1
}

resolve_domain() {
    local domain="$1"
    valid_domain "$domain" || die "invalid domain: $domain"
    local owner
    owner="$(owner_of "$domain")"
    [[ -n "$owner" ]] || die "domain not found: $domain"
    printf '%s\n' "$owner"
}

state_file_of() {
    printf '%s/%s.conf\n' "$DOMAIN_STATE_ROOT" "$1"
}

get_state_value() {
    local domain="$1"
    local parameter="$2"
    local file
    file="$(state_file_of "$domain")"
    [[ -f "$file" ]] || return 0
    awk -F= -v key="$parameter" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

has_state_value() {
    [[ -n "$(get_state_value "$1" "$2")" ]]
}

set_state_value() {
    local domain="$1"
    local parameter="$2"
    local value="$3"
    local file tmp
    ensure_state
    file="$(state_file_of "$domain")"
    tmp="$(mktemp "$STATE_ROOT/.domain-config.XXXXXX")" || die "cannot create temporary state file"
    if [[ -f "$file" ]]; then
        awk -F= -v key="$parameter" -v val="$value" '
            BEGIN { found=0 }
            $1 == key { if (!found) { print key "=" val; found=1 }; next }
            { print }
            END { if (!found) print key "=" val }
        ' "$file" > "$tmp"
    else
        printf '%s=%s\n' "$parameter" "$value" > "$tmp"
    fi
    chmod 0640 "$tmp"
    mv -f "$tmp" "$file"
}

remove_state_value() {
    local domain="$1"
    local parameter="$2"
    local file tmp
    file="$(state_file_of "$domain")"
    [[ -f "$file" ]] || return 0
    tmp="$(mktemp "$STATE_ROOT/.domain-config.XXXXXX")" || die "cannot create temporary state file"
    awk -F= -v key="$parameter" '$1 != key { print }' "$file" > "$tmp"
    if [[ -s "$tmp" ]]; then
        chmod 0640 "$tmp"
        mv -f "$tmp" "$file"
    else
        rm -f -- "$tmp" "$file"
    fi
}

is_pool_manager_parameter() {
    case "$1" in
        pm|pm.max_children|pm.max_requests) return 0 ;;
        *) return 1 ;;
    esac
}

# Print VALUE<TAB>SOURCE for the last active matching directive in a pool file.
# SOURCE is managed when the winning directive is inside our managed block,
# otherwise it is pool. With scope=base, the managed block is ignored.
pool_setting_of() {
    local config="$1"
    local parameter="$2"
    local scope="${3:-all}"
    awk -v key="$parameter" -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" -v scope="$scope" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        $0 == begin { managed=1; next }
        $0 == end { managed=0; next }
        {
            if (scope == "base" && managed) next
            line=trim($0)
            if (line == "" || line ~ /^[;#]/) next
            separator=index(line, "=")
            if (separator == 0) next
            name=trim(substr(line, 1, separator - 1))
            value=trim(substr(line, separator + 1))
            if (name == key || name == "php_admin_value[" key "]" || name == "php_value[" key "]") {
                if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") || (substr(value, 1, 1) == "\047" && substr(value, length(value), 1) == "\047")) {
                    value=substr(value, 2, length(value) - 2)
                }
                found=value
                source=(managed ? "managed" : "pool")
            }
        }
        END {
            if (found != "") printf "%s\t%s\n", found, source
        }
    ' "$config"
}

write_fpm_ini_dump() {
    local version="$1"
    local destination="$2"
    local binary
    binary="$(php_fpm_binary "$version")" || return 1
    "$binary" -i > "$destination" 2>/tmp/myvesta-domain-php-ini-dump
}

ini_setting_of() {
    local dump="$1"
    local parameter="$2"
    awk -F'=>' -v key="$parameter" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        trim($1) == key { print trim($2); exit }
    ' "$dump"
}

copy_without_managed_block() {
    local source="$1"
    local destination="$2"
    awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
        $0 == begin { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' "$source" > "$destination"
}

render_managed_block() {
    local domain="$1"
    local parameter value
    printf '\n%s\n' "$MANAGED_BEGIN"
    printf '; Managed by myvestacp-domain-php-config for %s\n' "$domain"
    for parameter in $PHP_PARAMETERS; do
        value="$(get_state_value "$domain" "$parameter")"
        [[ -n "$value" ]] || continue
        case "$parameter" in
            pm) printf 'pm = %s\n' "$value" ;;
            pm.max_children|pm.max_requests) printf '%s = %s\n' "$parameter" "$value" ;;
            *) printf 'php_admin_value[%s] = %s\n' "$parameter" "$value" ;;
        esac
    done
    printf '%s\n' "$MANAGED_END"
}

apply_domain_config() {
    local domain="$1"
    local version="$2"
    local config tmp backup
    config="$(config_file_of "$domain" "$version")"
    [[ -f "$config" ]] || die "FPM pool does not exist: $config"
    tmp="$(mktemp "$STATE_ROOT/.pool.XXXXXX")" || die "cannot create temporary pool file"
    backup="${config}.myvesta-domain-php.back"
    copy_without_managed_block "$config" "$tmp"
    if [[ -s "$(state_file_of "$domain")" ]]; then
        render_managed_block "$domain" >> "$tmp"
    fi
    cp -a "$config" "$backup"
    chmod --reference="$config" "$tmp" 2>/tmp/myvesta-domain-php-chmod || chmod 0644 "$tmp"
    chown --reference="$config" "$tmp" 2>/tmp/myvesta-domain-php-chown || true
    mv -f "$tmp" "$config"
}

validate_domain_config() {
    local version="$1"
    local binary
    binary="$(php_fpm_binary "$version")" || die "PHP-FPM binary not found for PHP $version"
    "$binary" -t 2>&1
}

restart_php_service() {
    local version="$1"
    local service="php${version}-fpm"
    if command -v systemctl >/tmp/myvesta-domain-php-command-check 2>&1; then
        systemctl restart "$service" >/tmp/myvesta-domain-php-restart 2>&1
        return $?
    fi
    if command -v service >/tmp/myvesta-domain-php-command-check 2>&1; then
        service "$service" restart >/tmp/myvesta-domain-php-restart 2>&1
        return $?
    fi
    return 1
}

recover_php_service() {
    local version="$1"
    local service="php${version}-fpm"
    if command -v systemctl >/tmp/myvesta-domain-php-command-check 2>&1; then
        systemctl reset-failed "$service" >/tmp/myvesta-domain-php-recover 2>&1 || true
        systemctl restart "$service" >>/tmp/myvesta-domain-php-recover 2>&1
        return $?
    fi
    restart_php_service "$version"
}

rollback_domain_config() {
    local domain="$1"
    local version="$2"
    local config
    config="$(config_file_of "$domain" "$version")"
    [[ -f "${config}.myvesta-domain-php.back" ]] && cp -a "${config}.myvesta-domain-php.back" "$config"
}

emit_json_string() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
