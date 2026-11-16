#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BASE_URL="${BASE_URL:-$(terraform -chdir=terraform output -raw alb_url)}"
echo "Target: $BASE_URL"
exec k6 run -e BASE_URL="$BASE_URL" "$@" loadtest/script.js
