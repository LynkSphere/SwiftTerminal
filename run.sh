#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

PROJECT=$(ls -d "$ROOT_DIR"/*.xcodeproj 2>/dev/null | head -1)
if [[ -z "${PROJECT:-}" ]]; then
  echo "error: no .xcodeproj found in $ROOT_DIR" >&2
  exit 1
fi
APP_NAME=$(basename "$PROJECT" .xcodeproj)
BUNDLE_ID=$(grep -m1 PRODUCT_BUNDLE_IDENTIFIER "$PROJECT/project.pbxproj" \
  | sed 's/.*= //;s/;.*//;s/"//g' | tr -d '[:space:]')

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -destination "platform=macOS" \
  -quiet \
  build

APP_BUNDLE=$(echo "$DERIVED_DATA"/$APP_NAME-*/Build/Products/Debug/$APP_NAME.app)
APP_BIN="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

run_app() {
  "$APP_BIN" &
  APP_PID=$!
  trap "kill $APP_PID 2>/dev/null" EXIT
  wait $APP_PID
}

case "$MODE" in
  run)
    run_app
    ;;
  --logs|logs)
    run_app &
    /usr/bin/log stream --info --style compact \
      --predicate "process == \"$APP_NAME\" OR subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    echo "usage: $0 [run|--logs]" >&2
    exit 2
    ;;
esac
