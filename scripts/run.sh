#!/bin/bash
# Builds and (re)launches PasteBack.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PasteBack"

"$ROOT/scripts/build.sh" "${1:-debug}"

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3
open "$ROOT/$APP_NAME.app"
echo "==> Launched $APP_NAME.app"
