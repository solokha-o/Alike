# Alike Pro subscriptions

This document is the release and QA reference for Alike Pro subscriptions. The
production identifiers are defined in `SubscriptionCatalog.production`; the
local StoreKit mirror is `Alike/Configuration/Alike.storekit`.

## Product catalog

All products belong to the single **Alike Pro** auto-renewable subscription
group.

| Presentation | Plan | Product ID | Duration | Intended US price | Introductory offer | Service level |
| --- | --- | --- | --- | ---: | --- | ---: |
| Primary | Yearly | `com.alike.app.pro.yearly` | 1 year | $39.99 | 7-day free trial | 1 |
| Secondary | Monthly | `com.alike.app.pro.monthly` | 1 month | $6.99 | None | 2 |

Product IDs are permanent. App Store Connect, application code, this document,
and the StoreKit configuration must match exactly. Never rename or reuse an ID
for a different product.

Customer-facing paywalls must use StoreKit's localized `displayName` and
`displayPrice`. The prices above describe the intended App Store Connect setup;
they are not a currency-formatting source for UI.

## Localizations

Localized product copy lives in `Alike/Configuration/Alike.storekit` and is the
source `tools/prepare_app_store_upload_bundle.py` reads to emit
`build/generated/store_upload/iap_metadata/app_store_connect_iap_metadata.json`.
App Store Connect limits the display name to 30 characters and the description
to 45.

Locales below are the App Store Connect codes the generated JSON carries; the
StoreKit file spells the same ones `en_US`, `uk`, `de_DE`, `fr_FR`, `es_ES`,
`es_MX`, `pt_BR`, `it_IT`, `nl_NL`, `pl_PL`, `tr_TR` and `zh_TW`. The two codes
that are not a plain underscore swap are `zh_TW`, which App Store Connect calls
`zh-Hant`, and `it_IT`/`pl_PL`/`tr_TR`, which it calls bare `it`, `pl` and
`tr`; `STOREKIT_TO_APP_STORE_LOCALE` in
`tools/prepare_app_store_upload_bundle.py` holds the mapping.

| Product | Locale | Display name | Description |
| --- | --- | --- | --- |
| Group | en-US | Alike Pro | — |
| Group | uk | Alike Pro | — |
| Group | de-DE | Alike Pro | — |
| Group | fr-FR | Alike Pro | — |
| Group | es-ES | Alike Pro | — |
| Group | es-MX | Alike Pro | — |
| Group | pt-BR | Alike Pro | — |
| Group | it | Alike Pro | — |
| Group | nl-NL | Alike Pro | — |
| Group | pl | Alike Pro | — |
| Group | tr | Alike Pro | — |
| Group | zh-Hant | Alike Pro | — |
| Yearly | en-US | Alike Pro Yearly | Unlock every Pro tool. First 7 days free. |
| Yearly | uk | Alike Pro на рік | Усі функції Alike Pro. 7 днів безкоштовно. |
| Yearly | de-DE | Alike Pro Jahresplan | Alle Pro-Funktionen. 7 Tage gratis. |
| Yearly | fr-FR | Alike Pro annuel | Tous les outils Pro. 7 jours offerts. |
| Yearly | es-ES | Alike Pro anual | Todas las funciones Pro. 7 días gratis. |
| Yearly | es-MX | Alike Pro anual | Todas las funciones Pro. 7 días gratis. |
| Yearly | pt-BR | Alike Pro anual | Todos os recursos Pro. 7 dias grátis. |
| Yearly | it | Alike Pro annuale | Tutti gli strumenti Pro. 7 giorni gratis. |
| Yearly | nl-NL | Alike Pro jaarlijks | Alle Pro-functies. Eerste 7 dagen gratis. |
| Yearly | pl | Alike Pro rocznie | Wszystkie funkcje Pro. 7 dni za darmo. |
| Yearly | tr | Alike Pro yıllık | Tüm Pro araçları. İlk 7 gün ücretsiz. |
| Yearly | zh-Hant | Alike Pro 年繳 | 解鎖所有 Pro 功能，前 7 天免費。 |
| Monthly | en-US | Alike Pro Monthly | Unlock all Alike Pro photo cleanup features. |
| Monthly | uk | Alike Pro на місяць | Усі функції очищення фото Alike Pro. |
| Monthly | de-DE | Alike Pro Monatsplan | Alle Aufräumfunktionen von Alike Pro. |
| Monthly | fr-FR | Alike Pro mensuel | Tout le nettoyage photo d’Alike Pro. |
| Monthly | es-ES | Alike Pro mensual | Toda la limpieza de fotos de Alike Pro. |
| Monthly | es-MX | Alike Pro mensual | Toda la limpieza de fotos de Alike Pro. |
| Monthly | pt-BR | Alike Pro mensal | Toda a limpeza de fotos do Alike Pro. |
| Monthly | it | Alike Pro mensile | Tutta la pulizia foto di Alike Pro. |
| Monthly | nl-NL | Alike Pro maandelijks | Al het opruimwerk van Alike Pro. |
| Monthly | pl | Alike Pro miesięcznie | Wszystkie porządki w zdjęciach Alike Pro. |
| Monthly | tr | Alike Pro aylık | Alike Pro'nun tüm fotoğraf temizliği. |
| Monthly | zh-Hant | Alike Pro 月繳 | Alike Pro 的完整照片清理功能。 |

The paywall shows StoreKit's localized `displayName`, so a missing locale means
that storefront falls back to English plan names in the paywall and in
Settings, then Subscriptions.

`fastlane deliver` does not touch in-app purchases. Subscription and group
localizations reach App Store Connect only through
`bundle exec ruby tools/app_store_iap_metadata.rb upload-localizations`, which
is not wired into any lane. That script upserts localizations onto products
that already exist; it never creates the group or the products. It also
tolerates HTTP 400/409/422 for any locale other than `en-US` by counting it as
skipped rather than failing, so a run that skipped every localization still
exits successfully. Read the `skipped` line in its output before assuming the
eleven non-English locales — `uk`, `de-DE`, `fr-FR`, `es-ES`, `es-MX`, `pt-BR`,
`it`, `nl-NL`, `pl`, `tr`, `zh-Hant` — landed, then confirm with `status`: it
prints `localizations=11/12 missing=zh-Hant` rather than a bare count, with the
expectation taken from the payload, so a locale added to the StoreKit file
moves the check with it. Re-run or add by hand anything it names.

The same script has `status` (read-only, safe to run first),
`upload-introductory-offers` and `upload-review-screenshots`. The screenshot
comes from `--screenshot PATH`, or from `ALIKE_IAP_REVIEW_SCREENSHOT_PATH` in
`.env` when the flag is omitted:

```sh
bundle exec ruby tools/app_store_iap_metadata.rb status
bundle exec ruby tools/app_store_iap_metadata.rb upload-introductory-offers
bundle exec ruby tools/app_store_iap_metadata.rb upload-review-screenshots \
  --screenshot Docs/images/review/11-paywall-disclosure.png
```

## Introductory offer

The yearly free trial is configured in `Alike.storekit` as an
`introductoryOffer` and exported to the generated metadata as
`FREE_TRIAL` / `ONE_WEEK` / `numberOfPeriods 1`. App Store Connect has no
"7 days" duration — `ONE_WEEK` is the value that matches `P1W` in StoreKit and
the "7-day free trial" wording on the paywall. Changing one without the other
makes the paywall disclosure false, which is a review rejection.

App Store Connect requires every introductory offer to name a **territory**;
there is no "all storefronts" form. `upload-introductory-offers` therefore
creates one offer per territory, using the subscription's own price
territories as the scope (175 for Alike Pro Yearly). Re-running it is safe:
territories that already carry a matching offer are reported as unchanged. If a
territory has an offer that does *not* match the local configuration, the
command fails and names those territories rather than stacking a second offer
or deleting the existing one — resolve those in App Store Connect by hand.

Eligibility is not a field. An introductory offer is only ever granted to a
customer who has never subscribed in the group, which is why the paywall says
"for eligible new subscribers".

## App Store Connect setup

1. Create one auto-renewable subscription group named **Alike Pro**.
2. Create the yearly and monthly products with the exact identifiers above.
3. Set yearly above monthly in the subscription level order.
4. Configure the intended US prices and localize each storefront in App Store
   Connect as release markets are added. Add all twelve product localizations
   from the table above — en-US, uk, de-DE, fr-FR, es-ES, es-MX, pt-BR, it,
   nl-NL, pl, tr and zh-Hant — either by hand or with
   `tools/app_store_iap_metadata.rb upload-localizations` once the products
   exist, then confirm with `status`, which reports `localizations=N/12` and
   names any missing locale, because skipped locales do not fail the upload
   run.
5. Add a seven-day free-trial introductory offer to yearly only. Eligibility is
   determined by StoreKit per subscription group.
6. Supply review information and submit the products with the app version that
   first exposes the paywall.

App Store Connect is authoritative for sandbox and production commerce. The
checked-in StoreKit configuration is authoritative for deterministic local
development and simulator QA.

## Local QA

The `Alike-VerboseLogs` and `Alike-DebugVerboseLogs` launch schemes use
`Alike/Configuration/Alike.storekit`; use one of them for subscription QA. The
`Alike` scheme runs Release with no StoreKit configuration attached, so its
purchases go to the real StoreKit sandbox. Xcode's StoreKit transaction
manager can reset transactions and simulate interrupted purchases, Ask to Buy,
billing retry, renewals, expiration, revocation, and refunds. Change those
controls only for the scenario under test and restore their defaults afterward.

| Scenario | Setup and expected result |
| --- | --- |
| Yearly purchase | Eligible account sees a seven-day trial; verified purchase grants premium and records the yearly product ID. |
| Monthly purchase | Purchase has no trial; verified purchase grants premium and records the monthly product ID. |
| Cancellation | Cancel the purchase sheet; outcome is cancelled and premium state does not change. |
| Pending purchase | Enable Ask to Buy or interrupted purchasing; outcome remains pending and access is not granted before verification. |
| Restore | Reset app state without deleting StoreKit transactions, restore purchases, and verify premium returns. |
| Renewal | Advance StoreKit time and confirm a verified renewal keeps premium active. |
| Expiration | Disable renewal or expire the transaction and confirm entitlement refresh removes premium. |
| Revocation/refund | Revoke or refund the transaction and confirm entitlement refresh removes premium. |
| Upgrade | Buy monthly, then yearly; yearly becomes the active higher-level entitlement. |
| Trial eligibility | Use a clean transaction history to test the trial, then repurchase in the same group and verify the trial is no longer offered. |

Before release, repeat purchase and restore checks with sandbox products from
App Store Connect; a local StoreKit pass does not validate server-side product
availability or review configuration.
