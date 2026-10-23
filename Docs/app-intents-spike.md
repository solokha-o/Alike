# Спайк #5: App Intents + Spotlight entities (Siri)

Дата: 2026-10-23. Гілка `spike/app-intents` від `develop` (`b6d3768`, 1.7.0 build 16). Xcode 27.1, SDK iPhoneOS 27.1, симулятор iPhone 18 Pro Max, iOS 27.0, хост Mac M4 (macOS 27). Deployment target лишається iOS 17.0.

## Результат

**Go для частини A з обмеженнями. No-go до вимірювання для частини B.** Детальні таблиці нижче; розділи «Перевірено» і «Не перевірено» — наприкінці.

| Критерій go | Ціль | Стан |
|---|---|---|
| Мінімум 1 intent дає дію, яку не можна зробити швидше наявним способом | 1 | **Виконано.** `ShowReclaimableIntent` відповідає без відкриття застосунку і повертає число, яке Shortcuts може використати далі (автоматизація). Віджет показує цифру, але не віддає її в Shortcuts і не працює через Siri. |
| Spotlight-entity знаходиться за природним запитом і не розкриває нічого, крім метаданих | так | **Не виміряно.** Entity містить лише id, count, bytes, month (тест `PhotoClusterEntityTests`). Пошук у Spotlight див. «Перевірено»/«Не перевірено». |
| Delete All Data повністю очищає індекс | так | **Виконано в коді** (`deleteAllSearchableItems` у потоці Delete All Data, тести). Перевірка в Spotlight див. нижче. |
| 0 нових persisted-полів, без регресій у `tools/full` | 0 | Persisted-полів 0: Core Data, UserDefaults, `WidgetSnapshot` (schema 1) без змін. `tools/full` — див. «Перевірено». |

## Intent → користь

| Intent / entity | Що робить | Реальна користь чи маркетинг | Чому |
|---|---|---|---|
| `ShowReclaimableIntent` | Каже, скільки місця можна звільнити, не відкриваючи застосунок; повертає байти як значення | **Реальна користь** | Єдиний спосіб отримати цифру через Siri і в автоматизаціях Shortcuts (наприклад, «якщо > 1 ГБ — нагадай»). Джерело — той самий `WidgetSnapshot`, тож цифра збігається з віджетом і сканером. |
| `StartScanIntent` | Відкриває вкладку Scanner і запускає скан | **Маркетинг** | Головний екран робить це за 1 тап. Квота free-сканів і запит дозволу Photos лишаються в `ScannerView`, тож intent не швидший. Користь лише як крок автоматизації (наприклад, щонеділі). |
| `OpenClusterReviewIntent` | Відкриває категорію перегляду | **Дубль віджета** | Віджет відкриває ті самі 5 екранів. Для Pro-категорії без Pro повертає dialog «needs Pro» і той самий deep link; paywall показує `CleanupView.openCategory`, як і для віджета. |
| `PhotoClusterEntity` (Spotlight) | «12 similar photos · September 2026 · 48 MB» у Spotlight | **Не доведено** | Користь є лише з реальними кластерами і стабільним id. Зараз `PhotoCluster.id` регенерується кожен скан, тож індекс треба повністю перезаписувати після скану (так і зроблено). Для продакшну потрібен `contentKey`. |

## Рекомендація: A окремо від B

Так, випускати A окремо від B.

- A працює на iOS 17 без `#available`, не чіпає persisted data, має 1 intent із реальною користю. Ризик: R1 (додатковий кейс `WidgetDestination.scan`, не персистується).
- B потребує iOS 18 (`IndexedEntity`), стабільного id кластера (`contentKey` замість `id`) і ще не виміряна в Spotlight із реальними кластерами. Це окрема картка після заміру на пристрої.
- Реліз A — тільки після заміру ASO (вікно до 2026-10-29).

## API (SDK iPhoneOS 27.1, `AppIntents.swiftinterface`, `CoreSpotlight`)

| Символ | Доступний з | Потрібен для | Примітка |
|---|---|---|---|
| `AppIntent`, `AppShortcutsProvider`, `AppShortcut`, `AppEnum`, `AppEntity`, `EntityQuery`, `EntityStringQuery`, `IntentResult` (`ReturnsValue`, `ProvidesDialog`, `OpensIntent`), `AppDependencyManager`, `@Dependency` | iOS 16.0 | A | Працює на target 17 без `#available` |
| `AppIntentsPackage`, `EnumerableEntityQuery`, `WidgetConfigurationIntent`, `ProgressReportingIntent` | iOS 17.0 | A | `AppIntentsPackage` обов'язковий, щоб metadata processor побачив intents у SwiftPM-пакеті |
| `OpenURLIntent` | **iOS 18.0** | — | Картка не згадує; я планував його для deep link, але він недоступний на target 17. Замінено на `PendingWidgetDestination` |
| `IndexedEntity`, `CSSearchableIndex.indexAppEntities`, `deleteAppEntities(ofType:)`, `associateAppEntity` | **iOS 18.0** | B | B гейтиться `#available(iOS 18, *)`, а не 27 |
| `IndexedEntity.hideInSpotlight`, `appEntityIdentifier`, `appEntityUIElements`, `AppEntityUIElement` (View Annotations) | iOS 18.4 | дослідження | Картка пише «iOS 27» — хибно |
| `AppSchema` + макроси `AppEntity(schema:)`, `AppIntent(schema:)` (entity schemas); `AssistantSchema` deprecated | iOS 18.0 | — | Домени: messages, photos (системні Photos), files тощо. Домену «photo cleanup» немає, тож для Alike не підходить |
| `IntentModes`, `UndoableIntent`, `TargetContentProvidingIntent`, `onAppIntentExecution` | iOS 26.0 | — | Не потрібні |
| `IndexedEntityQuery` (`reindexAllEntities`), `LongRunningIntent`, `IntentExecutionTargets`, `EntityCollection`, `SyncableEntity`, `OwnershipProvidingEntity` | **iOS 27.0** | B опційно | Єдині релевантні новинки iOS 27. `IndexedEntityQuery` дає системі перевиклик реіндексації; у спайку не використано |
| `AppIntentsTesting` (`AppIntentDefinition`, `AnyAppEntity`, `IntentDefinitions`) | iOS 27.0, окремий test-framework у `Platforms/*/Developer/Library/Frameworks` | тести | Не використано: target 17; тести викликають `perform()` напряму |
| `CSSearchableIndex.deleteAllSearchableItems`, `isIndexingAvailable` | iOS 9.0 | Delete All Data | Без `#available` |
| `CSUserQuery` (semantic search), `CSSearchableIndex.protectionClass` | iOS 18.0 / 27.0 | — | Не потрібні |

## Розбіжності картки з кодом

- «13 локалей» — правильно: `ar, de, en, es, es-419, fr, it, nl, pl, pt-BR, tr, uk, zh-Hant`. Skill `Skills/Localization/spm-localization` пише «twelve» без `ar` — застарілий, у спайку не правив.
- «iOS 27 entity schemas» і «View Annotations iOS 27» — усе це iOS 18.0 / 18.4.
- «App Intents Testing framework (iOS 27)» існує як `AppIntentsTesting`, але вимагає iOS 27 у тестах; на target 17 тести викликають `perform()`.
- Локалізація intents «у пакеті» не працює: `appintentsmetadataprocessor` відхиляє `LocalizedStringResource` з будь-яким bundle, крім main (`AppIntents requires 'LocalizedStringResource' to use the main bundle`). Тому titles, descriptions, назви параметрів і властивостей живуть в `Alike/Alike/AppIntents/AppIntents.xcstrings` (таблиця `AppIntents`), фрази — в `AppShortcuts.xcstrings` app target. У пакеті лишилися тільки runtime-рядки dialog (`Localizable.xcstrings`, 6 ключів).
- `PhotoCluster.id` регенерується на кожному скані; стабільний — `contentKey`. У спайку entity id = `id.uuidString`, і індекс перезаписується повністю після кожного скану.
- Байтів і місяця в `PhotoCluster` немає: байти — `reclaimableCluster(keeping:)` з keeper із `reviewStates` (той самий розрахунок, що в `WidgetSnapshotPublisher.topClusters`), місяць — мінімальна `creationDate` з assets.
- Скан з intent напряму (`CleanupWorkspaceModel.scan`) обійшов би квоту free-сканів. Тому `StartScanIntent` лише відкриває Scanner через `WidgetDestination.scan` → `TabManager.navigateToScanner(andStartScan: true)`.
- Пакет `AppIntentsKit` залежить лише від `Core`. `Storage` не потрібен: дані intents читають з `WidgetSnapshotStore` (App Group JSON) і з live workspace через протоколи, зареєстровані в `AppDependencyManager`.

## Прототип

Коміти в `spike/app-intents` (суфікс `(spike #5)`):

- `Packages/AppIntentsKit` (Core-only): `StartScanIntent`, `ShowReclaimableIntent`, `OpenClusterReviewIntent`, `ClusterReviewCategory` (`AppEnum`), `AppIntentsEnvironmentProviding` + `IntentDestination`, `PhotoClusterEntity: IndexedEntity` + `PhotoClusterEntityQuery` (`@available(iOS 18)`), `ClusterSpotlightIndexer` (actor, батчі по 100, delete-then-index), `SpotlightIndexClearing`.
- App target `Alike/Alike/AppIntents/`: `AlikeAppIntents` (`AppIntentsPackage` + `AppShortcutsProvider`, 3 shortcuts × 3 фрази), `AppIntentsEnvironmentAdapter` (читає `WidgetSnapshotStore`, навігує через `PendingWidgetDestination`), `ClusterSpotlightPublisher` (публікує з того самого `task(id:)`, що й віджет; індексація в `Task.detached`), `AppIntents.xcstrings`, `AppShortcuts.xcstrings`.
- `WidgetDestination.scan` (R1, додатковий; не персистується) + гілка в `RootView.followPendingWidgetDestination`.
- `RootView.onDeleteAllData`: після `widgetSnapshotPublisher.clear()` — `try await clusterSpotlightPublisher.clear()` (`CSSearchableIndex.deleteAllSearchableItems`).
- `tools/local_ci.sh`: `AppIntentsKit` у `SWIFTPM_UNSUPPORTED_PACKAGES` (`.xcstrings` + metadata processor потребують `xcodebuild`).
- DEBUG: launch argument `--seed-spotlight-samples` підставляє 3 синтетичні записи, коли кластерів немає (симулятор не формує кластери).

### View Annotations (лише дослідження)

`appEntityIdentifier(_:)`, `appEntityUIElements(_:)` і `AppEntityUIElement` — iOS 18.4. Для сценарію «Siri, delete all except best here» на екрані Cluster review потрібно: (1) стабільний `PhotoClusterEntity.id` (`contentKey`), (2) `appEntityIdentifier` на контейнері екрана, (3) intent `DeleteNonKeepersIntent` з `requestConfirmation` і `UndoableIntent` (iOS 26) або власне підтвердження, бо `WidgetDestination`/intents зараз навмисно лише навігують. Це окрема картка з R3-ризиком (видалення фото), не частина A.

## Тести (XCTest)

- `AppIntentsKitTests`: `StartScanIntentTests` (2), `ShowReclaimableIntentTests` (4), `OpenClusterReviewIntentTests` (5), `PhotoClusterEntityTests` (5), `ClusterSpotlightIndexerTests` (4), `LocalizationCatalogTests` (6).
- `SettingsTests/DeleteAllDataSpotlightClearTests` (3): очищення індексу після локального wipe і перед callback; помилка очищення не ховається.
- `WidgetSupportTests/WidgetDestinationScanTests` (3).

## Як повторити

1. `git switch spike/app-intents`.
2. Збірка: `xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'generic/platform=iOS Simulator' build`.
3. Тести пакета: `xcodebuild -workspace Packages/AppIntentsKit -scheme AppIntentsKit -destination 'id=<iPhone 18 Pro Max>' -parallel-testing-enabled NO test`.
4. Shortcuts: встановити Debug-збірку на симулятор, відкрити Shortcuts → App Shortcuts → Alike.
5. Spotlight: `xcrun simctl launch <udid> com.alike.app --seed-spotlight-samples`, пройти onboarding і дозволити Photos, у Spotlight ввести «similar photos».
6. `ALIKE_BUILD_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro Max,OS=27.0' tools/full`.

## Перевірено

(заповнюється)

## Не перевірено

(заповнюється)

## Коли повертатися до ідеї

- Частина B — після того, як `PhotoCluster` отримає стабільний публічний id (`contentKey`) і буде перевірка Spotlight на iPhone з реальними кластерами.
- Configurable widgets через `AppIntentConfiguration` — коли A буде в релізі: `WidgetConfigurationIntent` (iOS 17) може перевикористати `ClusterReviewCategory`.
