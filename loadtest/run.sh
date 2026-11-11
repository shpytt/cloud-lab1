#!/usr/bin/env bash
# Запуск навантажувального тесту однією командою: ./loadtest/run.sh
# Адресу сервісу бере з terraform output (або зі змінної BASE_URL).
# Додаткові параметри передаються в k6, наприклад: ./loadtest/run.sh -e VUS=60
set -euo pipefail
cd "$(dirname "$0")/.."
BASE_URL="${BASE_URL:-$(terraform -chdir=terraform output -raw alb_url)}"
echo "Target: $BASE_URL"
exec k6 run -e BASE_URL="$BASE_URL" "$@" loadtest/script.js
