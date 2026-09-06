#!/bin/bash
set -euo pipefail
python api_main.py &
API_PID=$!
python main.py &
BOT_PID=$!

term() {
  kill "$API_PID" "$BOT_PID" 2>/dev/null || true
  wait || true
}
trap term SIGTERM SIGINT

wait -n
term
exit 1
