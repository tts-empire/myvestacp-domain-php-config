#!/bin/bash
set -Eeuo pipefail
exec "$(dirname "$0")/install.sh" "$@"
