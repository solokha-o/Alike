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

| Product | Locale | Display name | Description |
| --- | --- | --- | --- |
| Group | en-US | Alike Pro | — |
| Group | uk | Alike Pro | — |
| Yearly | en-US | Alike Pro Yearly | Unlock all Alike Pro photo cleanup features. |
| Yearly | uk | Alike Pro на рік | Усі функції очищення фото Alike Pro. |
| Monthly | en-US | Alike Pro Monthly | Unlock all Alike Pro photo cleanup features. |
| Monthly | uk | Alike Pro на місяць | Усі функції очищення фото Alike Pro. |

The paywall shows StoreKit's localized `displayName`, so a missing locale means
that storefront falls back to English plan names in the paywall and in
Settings, then Subscriptions.

`fastlane deliver` does not touch in-app purchases. Subscription and group
localizations reach App Store Connect only through
`bundle exec ruby tools/app_store_iap_metadata.rb upload-localizations`, which
is not wired into any lane. That script upserts localizations onto products
that already exist; it never creates the group or the products. It also
tolerates HTTP 400/409/422 for any locale other than `en-US` by counting it as
skipped rather than failing, so read the `skipped` line in its output before
assuming `uk` landed.

The same script has `status` (read-only, safe to run first) and
`upload-review-screenshots`. The screenshot comes from `--screenshot PATH`, or
from `ALIKE_IAP_REVIEW_SCREENSHOT_PATH` in `.env` when the flag is omitted:

```sh
bundle exec ruby tools/app_store_iap_metadata.rb status
bundle exec ruby tools/app_store_iap_metadata.rb upload-review-screenshots \
  --screenshot Docs/images/review/11-paywall-disclosure.png
```

## App Store Connect setup

1. Create one auto-renewable subscription group named **Alike Pro**.
2. Create the yearly and monthly products with the exact identifiers above.
3. Set yearly above monthly in the subscription level order.
4. Configure the intended US prices and localize each storefront in App Store
   Connect as release markets are added. Add the en-US and uk product
   localizations from the table above, either by hand or with
   `tools/app_store_iap_metadata.rb upload-localizations` once the products
   exist.
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
