#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-IOS RunSmart app.xcodeproj}"
SCHEME="${SCHEME:-IOS RunSmart app}"
BUNDLE_ID="${BUNDLE_ID:-com.runsmart.lite}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/runsmart-screenshots-derived-data}"
OUTPUT_DIR="${OUTPUT_DIR:-fastlane/screenshots/en-US}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/IOS RunSmart app.app"
SETTLE_SECONDS="${SETTLE_SECONDS:-7}"

mkdir -p "$OUTPUT_DIR"

simulator_id() {
  local name="$1"
  xcrun simctl list devices available -j | ruby -rjson -e '
    name = ARGV.fetch(0)
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    matches = devices.select { |d| d["name"] == name && d["isAvailable"] }
    abort("No available simulator named #{name}") if matches.empty?
    puts matches.first.fetch("udid")
  ' "$name"
}

capture_device() {
  local device_name="$1"
  local prefix="$2"
  local expected_width="$3"
  local expected_height="$4"
  local udid
  udid="$(simulator_id "$device_name")"

  echo "==> Building for $device_name ($udid)"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build

  echo "==> Booting $device_name"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$APP_PATH"

  local tabs=("today" "plan" "run" "report" "profile")
  local labels=("today" "plan" "run" "report" "profile")

  for i in "${!tabs[@]}"; do
    local index
    index="$(printf "%02d" "$((i + 1))")"
    local tab="${tabs[$i]}"
    local label="${labels[$i]}"
    local output="$OUTPUT_DIR/${prefix}_${index}_${label}.png"

    echo "==> Capturing $device_name / $tab"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BUNDLE_ID" -RUNSMART_SCREENSHOT_MODE -INITIAL_TAB "$tab" >/dev/null
    sleep "$SETTLE_SECONDS"
    xcrun simctl io "$udid" screenshot "$output" >/dev/null

    local width height
    width="$(sips -g pixelWidth "$output" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$output" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
    if [[ "$width" != "$expected_width" || "$height" != "$expected_height" ]]; then
      echo "Screenshot dimension mismatch for $output: got ${width}x${height}, expected ${expected_width}x${expected_height}" >&2
      exit 1
    fi
  done
}

capture_device "iPhone 17 Pro Max" "iPhone_17_Pro_Max" "1320" "2868"
capture_device "iPhone 17e" "iPhone_17e" "1170" "2532"

echo "==> App Store screenshots captured in $OUTPUT_DIR"
