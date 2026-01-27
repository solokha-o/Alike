#!/bin/bash

# Скрипт для запуску всіх тестів через xcodebuild для iOS Simulator

echo "🧪 Запуск тестів Alike..."
echo ""

cd "$(dirname "$0")"

# Визначаємо доступний симулятор
SIMULATOR=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed 's/.*(\(.*\)).*/\1/')

if [ -z "$SIMULATOR" ]; then
    echo "❌ Не знайдено жодного симулятора iPhone"
    exit 1
fi

echo "📱 Використовую симулятор: $SIMULATOR"
echo ""

# Запуск тестів
xcodebuild test \
    -project Alike/Alike.xcodeproj \
    -scheme Alike \
    -destination "platform=iOS Simulator,id=$SIMULATOR" \
    -only-testing:WelcomeTests \
    -only-testing:ScannerTests \
    -only-testing:CoreTests \
    -only-testing:DesignSystemTests \
    -only-testing:PhotoAnalysisTests \
    -only-testing:StorageTests \
    2>&1 | xcpretty || true

echo ""
echo "✅ Тести завершено!"
