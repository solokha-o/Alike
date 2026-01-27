#!/bin/bash

# Скрипт для запуску всіх тестів Swift пакетів

set -e

echo "🧪 Запуск тестів Alike..."
echo ""

cd "$(dirname "$0")"

IOS_TEST_DESTINATION="${IOS_TEST_DESTINATION:-}"
IOS_TEST_DESTINATION_FILE="${IOS_TEST_DESTINATION_FILE:-}"
if [ -z "$IOS_TEST_DESTINATION" ] && command -v python3 >/dev/null 2>&1 && command -v xcrun >/dev/null 2>&1; then
    IOS_TEST_DESTINATION="$(python3 - <<'PY'
import json, subprocess, sys
try:
    out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
    data = json.loads(out)
    devices = []
    for runtime, items in data.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for d in items:
            if d.get("isAvailable") and d.get("name", "").startswith("iPhone"):
                devices.append((runtime, d["name"]))
    if devices:
        runtime, name = devices[0]
        # runtime example: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
        os_version = runtime.split("iOS-")[-1].replace("-", ".")
        print(f"platform=iOS Simulator,name={name},OS={os_version}")
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY
)"
fi

if [ -z "$IOS_TEST_DESTINATION" ]; then
    IOS_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 15,OS=latest"
fi

IOS_DESTINATION_FILE=""
if [ -n "$IOS_TEST_DESTINATION_FILE" ]; then
    IOS_DESTINATION_FILE="$IOS_TEST_DESTINATION_FILE"
else
    platform="${IOS_TEST_DESTINATION#platform=}"
    platform="${platform%%,*}"
    name="${IOS_TEST_DESTINATION#*name=}"
    name="${name%%,*}"
    os="${IOS_TEST_DESTINATION##*OS=}"
    IOS_DESTINATION_FILE="$(mktemp /tmp/alike-destination.XXXXXX.json)"
    cat > "$IOS_DESTINATION_FILE" <<EOF
{
  "version": 1,
  "sdk": "iphonesimulator",
  "platform": "${platform}",
  "name": "${name}",
  "os": "${os}"
}
EOF
fi

echo "📱 iOS destination: $IOS_TEST_DESTINATION"
echo "📄 Destination file: $IOS_DESTINATION_FILE"
echo ""

PACKAGES=(
    "Core"
    "DesignSystem"
    "Details"
    "Launch"
    "PhotoAnalysis"
    "Scanner"
    "Settings"
    "Storage"
    "Welcome"
)

FAILED=0
PASSED=0

for pkg in "${PACKAGES[@]}"; do
    echo "📦 Тестую $pkg..."
    if (cd "Packages/$pkg" && swift test --quiet --destination "$IOS_DESTINATION_FILE" 2>/dev/null); then
        echo "✅ $pkg - OK"
        ((PASSED++))
    else
        echo "❌ $pkg - FAILED"
        ((FAILED++))
    fi
    echo ""
done

echo "========================================="
echo "📊 Результати: $PASSED passed, $FAILED failed"
echo "========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "✅ Всі тести пройшли!"
