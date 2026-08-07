#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_SCREENSHOTS_ROOT = ROOT / "Docs" / "images"
generated_store_upload_root_value = os.environ.get("ALIKE_GENERATED_STORE_UPLOAD_ROOT", "").strip()
# An empty override must fall back to the default: Path("") is the current
# directory, and reset_output_dirs() would then rmtree ./metadata,
# ./screenshots and ./iap_metadata in whatever directory the tool runs from.
GENERATED_STORE_UPLOAD_ROOT = (
    Path(generated_store_upload_root_value)
    if generated_store_upload_root_value
    else ROOT / "build" / "generated" / "store_upload"
)
STORE_UPLOAD_ROOT = GENERATED_STORE_UPLOAD_ROOT
METADATA_ROOT = GENERATED_STORE_UPLOAD_ROOT / "metadata"
SCREENSHOTS_ROOT = GENERATED_STORE_UPLOAD_ROOT / "screenshots"
IAP_METADATA_ROOT = GENERATED_STORE_UPLOAD_ROOT / "iap_metadata"
IAP_METADATA_FILE = IAP_METADATA_ROOT / "app_store_connect_iap_metadata.json"
iap_review_screenshot_value = os.environ.get("ALIKE_IAP_REVIEW_SCREENSHOT_PATH", "").strip()
IAP_REVIEW_SCREENSHOT_PATH = Path(iap_review_screenshot_value) if iap_review_screenshot_value else None
REVIEW_NOTES_FILE = ROOT / "Docs" / "app-store-review-notes.txt"
STOREKIT_PATH = ROOT / "Alike" / "Configuration" / "Alike.storekit"
EXPECTED_SCREENSHOT_SIZE = (1320, 2868)
APP_IDENTIFIER = "com.alike.app"
APP_NAME = "Alike: Similar Photo Cleaner"
COPYRIGHT = "2026 Oleksandr Solokha. Alike"
PRIMARY_CATEGORY = "PHOTO_AND_VIDEO"
SECONDARY_CATEGORY = "UTILITIES"
PRIVACY_URL_PLACEHOLDER = "__ALIKE_PRIVACY_URL__"
SUPPORT_URL_PLACEHOLDER = "__ALIKE_SUPPORT_URL__"
# Apple treats the marketing URL as optional, and deliver leaves the App Store
# Connect value untouched when the file is absent. So this one has no
# placeholder: either ALIKE_MARKETING_URL is set and the file is written, or
# nothing is written at all.
MARKETING_URL_ENV = "ALIKE_MARKETING_URL"
TERMS_URL_PLACEHOLDER = "__ALIKE_TERMS_URL__"
TERMS_URL_DEFAULT = TERMS_URL_PLACEHOLDER
PRIVACY_LABEL = "Privacy Policy"
TERMS_LABEL = "Terms of Use"
TODO_MARKER = "TODO:"
APP_SUBTITLE_MAX_LENGTH = 30
APP_KEYWORDS_MAX_BYTES = 100
APP_PROMOTIONAL_TEXT_MAX_LENGTH = 170
APP_DESCRIPTION_MAX_LENGTH = 4000
APP_RELEASE_NOTES_MAX_LENGTH = 4000
APP_REVIEW_NOTES_MAX_LENGTH = 4000
IAP_DISPLAY_NAME_MIN_LENGTH = 2
IAP_DISPLAY_NAME_MAX_LENGTH = 30
IAP_DESCRIPTION_MAX_LENGTH = 45

# App Review contact and notes are uploaded by Fastlane `deliver` from
# metadata/review_information/*.txt so they do not need manual entry in
# App Store Connect. Real uploads require ALIKE_REVIEW_* environment variables.
# Public structural validation uses explicit non-personal placeholders.
REVIEW_FIRST_NAME = os.environ.get("ALIKE_REVIEW_FIRST_NAME", "").strip() or "__ALIKE_REVIEW_FIRST_NAME__"
REVIEW_LAST_NAME = os.environ.get("ALIKE_REVIEW_LAST_NAME", "").strip() or "__ALIKE_REVIEW_LAST_NAME__"
REVIEW_EMAIL = os.environ.get("ALIKE_REVIEW_EMAIL", "").strip() or "review@example.com"
REVIEW_PHONE = os.environ.get("ALIKE_REVIEW_PHONE", "").strip() or "+10000000000"

# Alike has no account and no sign-in. Empty demo credentials make Deliver set
# `demo_account_required = false`, which matches the real App Review flow.
REVIEW_SIGNIN_USER = ""
REVIEW_SIGNIN_SECRET = ""


@dataclass(frozen=True)
class LocaleMapping:
    source: str
    apple: str


# en-GB is deliberately not uploaded. Its copy stays in METADATA so the
# localization can be switched back on by adding a mapping here; an en-GB
# localization that already exists in App Store Connect has to be removed there
# by hand, because deliver never deletes localizations.
UPLOAD_SAFE_LOCALES = (
    LocaleMapping(source="en-US", apple="en-US"),
    LocaleMapping(source="uk", apple="uk"),
)

STOREKIT_TO_APP_STORE_LOCALE = {
    "en_US": "en-US",
    "uk": "uk",
}

REQUIRED_LOCALIZED_FILES = (
    "name.txt",
    "subtitle.txt",
    "description.txt",
    "keywords.txt",
    "promotional_text.txt",
    "release_notes.txt",
    "privacy_url.txt",
    "support_url.txt",
)


# Localized App Store copy. Every claim here must stay consistent with the
# published privacy policy, terms of use and landing page under `site/`, and
# with the free/Pro split defined by PremiumFeature and PremiumAccessPolicy.
# Prices are never stated: StoreKit supplies localized pricing.
EN_US_DESCRIPTION = """\
Alike finds the near-duplicates hiding in your camera roll, groups them, picks the best shot in each group, and helps you clear the rest — without a single photo leaving your device.

HOW IT WORKS
Scan. Alike compares your library with Apple's Vision framework, entirely on your iPhone. Photos taken close together in time and place are compared, and screenshots stay out of the results unless you ask for them.
Review. Every group opens with a Best Shot already selected, so you can decide in seconds. Keep Best Only, Select All Except Best, or pick by hand.
Clear. Confirm, and the photos you chose move to Recently Deleted, where iOS keeps them for about 30 days.

PRIVACY IS THE WHOLE POINT
- All analysis runs on device with Apple's Vision framework.
- No photo, thumbnail or feature print is ever uploaded.
- No account, no sign-in, no Alike server.
- No analytics, no tracking, no advertising identifiers.
- Nothing is deleted without your explicit confirmation.

FEATURES
- Three sensitivity levels, from near-identical shots to a wider net.
- Best Shot detection, so every group has a sensible default to keep.
- Review badges: New, In Review, Reviewed, and Needs Review after a rescan.
- Progress, Selected and Estimated Savings, plus cleanup history by month.
- A roomy one-column layout or a denser grid, switchable any time and remembered.
- Full English and Ukrainian, and complete Dark Mode support.

ALIKE FREE
- 3 scans per month
- Guided review with Best Shot
- Sorting and cleanup history
- Clean up one photo at a time

ALIKE PRO
- Unlimited scans
- Clean up whole selections at once
- Screenshot cleanup
- Blurred photo cleanup
- Advanced filters
- Custom cleanup reminders

Alike Pro is an auto-renewable subscription with yearly and monthly plans, priced in your local currency. The yearly plan includes a 7-day free trial for eligible new subscribers, and billing starts when the trial ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and payment is charged to your Apple Account. Manage or cancel anytime in iOS Settings."""

EN_GB_DESCRIPTION = """\
Alike finds the near-duplicates hiding in your camera roll, groups them, picks the best shot in each group, and helps you clear the rest — without a single photo leaving your device.

HOW IT WORKS
Scan. Alike compares your library with Apple's Vision framework, entirely on your iPhone. Photos taken close together in time and place are compared, and screenshots stay out of the results unless you ask for them.
Review. Every group opens with a Best Shot already selected, so you can decide in seconds. Keep Best Only, Select All Except Best, or pick by hand.
Clear. Confirm, and the photos you chose move to Recently Deleted, where iOS keeps them for about 30 days.

PRIVACY IS THE WHOLE POINT
- All analysis runs on device with Apple's Vision framework.
- No photo, thumbnail or feature print is ever uploaded.
- No account, no sign-in, no Alike server.
- No analytics, no tracking, no advertising identifiers.
- Nothing is deleted without your explicit confirmation.

FEATURES
- Three sensitivity levels, from near-identical shots to a wider net.
- Best Shot detection, so every group has a sensible default to keep.
- Review badges: New, In Review, Reviewed, and Needs Review after a rescan.
- Progress, Selected and Estimated Savings, plus cleanup history by month.
- A roomy one-column layout or a denser grid, switchable any time and remembered.
- Full English and Ukrainian, and complete Dark Mode support.

ALIKE FREE
- 3 scans per month
- Guided review with Best Shot
- Sorting and cleanup history
- Organise one photo at a time

ALIKE PRO
- Unlimited scans
- Organise whole selections at once
- Screenshot cleanup
- Blurred photo cleanup
- Advanced filters
- Customised cleanup reminders

Alike Pro is an auto-renewable subscription with yearly and monthly plans, priced in your local currency. The yearly plan includes a 7-day free trial for eligible new subscribers, and billing starts when the trial ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and payment is charged to your Apple Account. Manage or cancel anytime in iOS Settings."""

UK_DESCRIPTION = """\
Alike знаходить майже однакові знімки у вашій медіатеці, групує їх, обирає найкращий у кожній групі й допомагає прибрати решту — і жодне фото не залишає ваш пристрій.

ЯК ЦЕ ПРАЦЮЄ
Сканування. Alike порівнює медіатеку за допомогою фреймворку Apple Vision повністю на вашому iPhone. Порівнюються знімки, близькі за часом і місцем зйомки, а знімки екрана не потрапляють у результати, якщо ви не попросите.
Перегляд. Кожна група відкривається з уже обраним найкращим знімком, тож рішення займає секунди. «Залишити лише найкраще», «Обрати все крім найкращого» або вибір вручну.
Прибирання. Підтвердьте — і обрані фотографії потраплять до «Нещодавно видалених», де iOS зберігає їх близько 30 днів.

КОНФІДЕНЦІЙНІСТЬ — ЦЕ СУТЬ
- Увесь аналіз виконується на пристрої фреймворком Apple Vision.
- Жодне фото, ескіз чи відбиток ознак не завантажується в інтернет.
- Без облікового запису, без входу, без сервера Alike.
- Без аналітики, відстеження та рекламних ідентифікаторів.
- Нічого не видаляється без вашого явного підтвердження.

МОЖЛИВОСТІ
- Три рівні чутливості — від майже ідентичних знімків до ширшого пошуку.
- Вибір найкращого знімка, тож у кожній групі є розумний варіант залишити.
- Позначки: «Нове», «У перегляді», «Переглянуто», «Потребує перегляду».
- Прогрес, «Обрано» й «Орієнтовна економія», а також історія за місяцями.
- Просторий один стовпець або щільніша сітка — перемикайте будь-коли, вибір запам’ятовується.
- Повна підтримка англійської та української й темна тема.

ALIKE FREE
- 3 сканування на місяць
- Покроковий перегляд із найкращим знімком
- Сортування та історія прибирання
- Прибирання по одному фото за раз

ALIKE PRO
- Необмежені сканування
- Прибирання цілих виділень одразу
- Прибирання знімків екрана
- Прибирання розмитих фото
- Розширені фільтри
- Власні нагадування про прибирання

Alike Pro — це підписка з автоматичним поновленням, річний і місячний плани, ціни у вашій валюті. Річний план містить 7 днів безкоштовно для нових підписників, які мають на це право; оплата починається після завершення пробного періоду. Підписка поновлюється автоматично, якщо її не скасувати щонайменше за 24 години до завершення поточного періоду, а оплата стягується з вашого облікового запису Apple. Керувати підпискою або скасувати її можна будь-коли в Налаштуваннях iOS."""

METADATA = {
    "en-US": {
        "subtitle": "Find and clear similar photos",
        "description": EN_US_DESCRIPTION,
        "keywords": "duplicate,similar,photo cleaner,cleanup,camera roll,storage,space,declutter,gallery",
        "promotional_text": "Alike groups the photos that look alike, picks the best shot in each group, and helps you clear the rest. Everything runs on your device.",
        "release_notes": "First release of Alike.\n\nScan your library for visually similar photos, review each group with a Best Shot already picked, and clear the rest. Every scan runs on your device — no account, no uploads, and deletion always goes to Recently Deleted.\n\nAlike Pro adds unlimited scans, batch cleanup, screenshot and blurred-photo cleanup, advanced filters, and custom cleanup reminders.",
    },
    "en-GB": {
        "subtitle": "Find and clear similar photos",
        "description": EN_GB_DESCRIPTION,
        "keywords": "duplicate,similar,photo cleaner,cleanup,camera roll,storage,space,declutter,gallery",
        "promotional_text": "Alike groups the photos that look alike, picks the best shot in each group, and helps you organise the rest. Everything runs on your device.",
        "release_notes": "First release of Alike.\n\nScan your library for visually similar photos, review each group with a Best Shot already picked, and organise the rest. Every scan runs on your device — no account, no uploads, and deletion always goes to Recently Deleted.\n\nAlike Pro adds unlimited scans, batch cleanup, screenshot and blurred-photo cleanup, advanced filters, and custom cleanup reminders.",
    },
    "uk": {
        "subtitle": "Знайти й прибрати схожі фото",
        "description": UK_DESCRIPTION,
        "keywords": "фото,схожі,дублікати,прибирання,памʼять,медіатека",
        "promotional_text": "Alike групує схожі фотографії, обирає найкращий знімок у кожній групі й допомагає прибрати решту. Усе працює на вашому пристрої.",
        "release_notes": "Перший випуск Alike.\n\nСкануйте медіатеку на візуально схожі фото, переглядайте кожну групу з уже обраним найкращим знімком і прибирайте решту. Кожне сканування виконується на пристрої — без облікового запису й без вивантаження, а видалені фото завжди потрапляють до «Нещодавно видалених».\n\nAlike Pro додає необмежені сканування, пакетне прибирання, прибирання знімків екрана та розмитих фото, розширені фільтри й власні нагадування.",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare Alike App Store metadata and screenshots for fastlane deliver.")
    parser.add_argument(
        "--allow-placeholder-urls",
        action="store_true",
        help="Allow placeholder URLs and placeholder copy for local structural generation.",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate the existing generated bundle under build/generated/store_upload without rewriting it.",
    )
    return parser.parse_args()


def env_or_placeholder(key: str, placeholder: str) -> str:
    value = os.environ.get(key, "").strip()
    return value if value else placeholder


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.rstrip() + "\n", encoding="utf-8")


def review_notes_text() -> str:
    if not REVIEW_NOTES_FILE.exists():
        raise FileNotFoundError(f"Missing App Review notes: {REVIEW_NOTES_FILE}")
    return REVIEW_NOTES_FILE.read_text(encoding="utf-8").strip()


def numbered_pngs(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(path for path in root.glob("*.png") if path.name[:2].isdigit())


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a valid PNG")
    return struct.unpack(">II", header[16:24])


def jpeg_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        data = handle.read()
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        raise ValueError(f"{path} is not a valid JPEG")

    index = 2
    while index < len(data):
        while index < len(data) and data[index] != 0xFF:
            index += 1
        while index < len(data) and data[index] == 0xFF:
            index += 1
        if index >= len(data):
            break

        marker = data[index]
        index += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if index + 2 > len(data):
            break

        segment_length = struct.unpack(">H", data[index:index + 2])[0]
        segment_start = index + 2
        segment_end = index + segment_length
        if marker in range(0xC0, 0xC4) or marker in range(0xC5, 0xC8) or marker in range(0xC9, 0xCC) or marker in range(0xCD, 0xD0):
            if segment_start + 5 > len(data):
                break
            height, width = struct.unpack(">HH", data[segment_start + 1:segment_start + 5])
            return width, height
        index = segment_end

    raise ValueError(f"{path} does not include a readable JPEG size")


def image_size(path: Path) -> tuple[int, int]:
    if path.suffix.lower() in {".jpg", ".jpeg"}:
        return jpeg_size(path)
    return png_size(path)


def reset_output_dirs() -> None:
    for path in (METADATA_ROOT, SCREENSHOTS_ROOT, IAP_METADATA_ROOT):
        if path.exists():
            shutil.rmtree(path)
        path.mkdir(parents=True, exist_ok=True)


def description_with_links(description: str, privacy_url: str, terms_url: str) -> str:
    footer = f"{PRIVACY_LABEL}: {privacy_url}\n{TERMS_LABEL}: {terms_url}"
    return f"{description.rstrip()}\n\n{footer}"


def generate_metadata(privacy_url: str, support_url: str, terms_url: str, marketing_url: str) -> None:
    write_text(METADATA_ROOT / "copyright.txt", COPYRIGHT)
    write_text(METADATA_ROOT / "primary_category.txt", PRIMARY_CATEGORY)
    write_text(METADATA_ROOT / "secondary_category.txt", SECONDARY_CATEGORY)

    for mapping in UPLOAD_SAFE_LOCALES:
        values = METADATA[mapping.apple]
        locale_root = METADATA_ROOT / mapping.apple
        write_text(locale_root / "name.txt", APP_NAME)
        write_text(locale_root / "subtitle.txt", values["subtitle"])
        write_text(
            locale_root / "description.txt",
            description_with_links(values["description"], privacy_url, terms_url),
        )
        write_text(locale_root / "keywords.txt", values["keywords"])
        write_text(locale_root / "promotional_text.txt", values["promotional_text"])
        write_text(locale_root / "release_notes.txt", values["release_notes"])
        write_text(locale_root / "privacy_url.txt", privacy_url)
        write_text(locale_root / "support_url.txt", support_url)
        if marketing_url:
            write_text(locale_root / "marketing_url.txt", marketing_url)


def generate_review_information() -> None:
    root = METADATA_ROOT / "review_information"
    write_text(root / "first_name.txt", REVIEW_FIRST_NAME)
    write_text(root / "last_name.txt", REVIEW_LAST_NAME)
    write_text(root / "email_address.txt", REVIEW_EMAIL)
    write_text(root / "phone_number.txt", REVIEW_PHONE)
    # Alike needs no reviewer account; empty files keep Deliver's
    # demo_account_required flag false.
    write_text(root / "demo_user.txt", REVIEW_SIGNIN_USER)
    write_text(root / "demo_password.txt", REVIEW_SIGNIN_SECRET)
    write_text(root / "notes.txt", review_notes_text())


def copy_screenshots() -> None:
    # Screenshots are rendered per language, so each source locale has its own
    # folder under Docs/images/.
    for mapping in UPLOAD_SAFE_LOCALES:
        destination_root = SCREENSHOTS_ROOT / mapping.apple
        destination_root.mkdir(parents=True, exist_ok=True)
        for source in numbered_pngs(SOURCE_SCREENSHOTS_ROOT / mapping.source):
            shutil.copy2(source, destination_root / source.name)


def load_storekit() -> dict:
    if not STOREKIT_PATH.exists():
        raise FileNotFoundError(f"Missing StoreKit configuration: {STOREKIT_PATH}")
    return json.loads(STOREKIT_PATH.read_text(encoding="utf-8"))


def app_store_locale(storekit_locale: str) -> str:
    return STOREKIT_TO_APP_STORE_LOCALE.get(storekit_locale, storekit_locale.replace("_", "-"))


def exported_localizations(localizations: list[dict]) -> list[dict]:
    exported = []
    for localization in localizations:
        storekit_locale = localization.get("locale", "")
        exported.append(
            {
                "locale": app_store_locale(storekit_locale),
                "storekitLocale": storekit_locale,
                "displayName": localization.get("displayName", ""),
                "description": localization.get("description", ""),
            }
        )
    return exported


# StoreKit describes the offer with an ISO 8601 period and a payment mode;
# App Store Connect wants its own enums. Only the durations Apple actually
# offers for an introductory offer are mapped, so an unsupported period fails
# loudly here instead of being rejected mid-upload.
STOREKIT_TO_APP_STORE_OFFER_DURATION = {
    "P3D": "THREE_DAYS",
    "P1W": "ONE_WEEK",
    "P2W": "TWO_WEEKS",
    "P1M": "ONE_MONTH",
    "P2M": "TWO_MONTHS",
    "P3M": "THREE_MONTHS",
    "P6M": "SIX_MONTHS",
    "P1Y": "ONE_YEAR",
}

STOREKIT_TO_APP_STORE_OFFER_MODE = {
    "free": "FREE_TRIAL",
    "payAsYouGo": "PAY_AS_YOU_GO",
    "payUpFront": "PAY_UP_FRONT",
}


def exported_introductory_offer(subscription: dict) -> dict | None:
    offer = subscription.get("introductoryOffer")
    if not offer:
        return None

    period = offer.get("subscriptionPeriod", "")
    payment_mode = offer.get("paymentMode", "")
    product_id = subscription.get("productID", "<unknown>")

    duration = STOREKIT_TO_APP_STORE_OFFER_DURATION.get(period)
    if duration is None:
        raise SystemExit(
            f"{product_id}: introductory offer period {period!r} has no App Store Connect duration"
        )

    mode = STOREKIT_TO_APP_STORE_OFFER_MODE.get(payment_mode)
    if mode is None:
        raise SystemExit(
            f"{product_id}: introductory offer payment mode {payment_mode!r} is not supported"
        )

    return {
        "offerMode": mode,
        "duration": duration,
        "numberOfPeriods": offer.get("numberOfPeriods", 1),
        "storekitSubscriptionPeriod": period,
        "storekitPaymentMode": payment_mode,
    }


def iap_payload_from_storekit(storekit: dict) -> dict:
    subscription_groups = []
    subscriptions = []
    consumables = []

    for group in storekit.get("subscriptionGroups", []):
        subscription_groups.append(
            {
                "id": group.get("id"),
                "referenceName": group.get("name"),
                "localizations": exported_localizations(group.get("localizations", [])),
            }
        )
        for subscription in group.get("subscriptions", []):
            subscriptions.append(
                {
                    "productID": subscription.get("productID"),
                    "referenceName": subscription.get("referenceName"),
                    "type": subscription.get("type"),
                    "subscriptionGroupID": subscription.get("subscriptionGroupID"),
                    "level": subscription.get("groupNumber"),
                    "recurringSubscriptionPeriod": subscription.get("recurringSubscriptionPeriod"),
                    "displayPrice": subscription.get("displayPrice"),
                    "introductoryOffer": exported_introductory_offer(subscription),
                    "localizations": exported_localizations(subscription.get("localizations", [])),
                }
            )

    for product in storekit.get("products", []):
        consumables.append(
            {
                "productID": product.get("productID"),
                "referenceName": product.get("referenceName"),
                "type": product.get("type"),
                "displayPrice": product.get("displayPrice"),
                "localizations": exported_localizations(product.get("localizations", [])),
            }
        )

    return {
        "appIdentifier": APP_IDENTIFIER,
        "source": str(STOREKIT_PATH.relative_to(ROOT)),
        "notes": [
            "Fastlane deliver uploads app metadata and screenshots, not this IAP metadata.",
            "Use this file as the source for App Store Connect API automation for in-app purchase localizations.",
            "locale is normalized for App Store Connect-style locale IDs; storekitLocale preserves the Xcode StoreKit source locale.",
            "IAP displayName must be 2-30 characters; IAP description must be no more than 45 characters.",
        ],
        "subscriptionGroups": subscription_groups,
        "subscriptions": subscriptions,
        "consumables": consumables,
    }


def write_iap_metadata() -> None:
    storekit = load_storekit()
    payload = iap_payload_from_storekit(storekit)
    IAP_METADATA_ROOT.mkdir(parents=True, exist_ok=True)
    IAP_METADATA_FILE.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n",
        encoding="utf-8",
    )


def write_docs() -> None:
    upload_locales = "\n".join(f"- `{mapping.source}` -> `{mapping.apple}`" for mapping in UPLOAD_SAFE_LOCALES)
    write_text(
        STORE_UPLOAD_ROOT / "README.md",
        f"""# Alike Generated App Store Upload Bundle

This folder is generated by `tools/prepare_app_store_upload_bundle.py` for Fastlane `deliver`.

Public screenshot sources live under `Docs/images/`, and App Review notes come from `Docs/app-store-review-notes.txt`. Localized release metadata is defined directly in this script.

## Upload-safe locale mapping

{upload_locales}

## Local validation

Preferred shortcut:

```bash
tools/meta
```

Use real public URLs when validating the generated upload bundle:

```bash
ALIKE_PRIVACY_URL="https://example.com/privacy" \\
ALIKE_SUPPORT_URL="https://example.com/support" \\
bundle exec fastlane ios metadata_validate
```

For local structural generation before public URLs and marketing copy are ready:

```bash
python3 tools/prepare_app_store_upload_bundle.py --allow-placeholder-urls
```

## CI upload

Preferred shortcut:

```bash
tools/upload
```

`metadata_upload` regenerates this bundle, validates it, then uploads metadata and screenshots without uploading a binary or submitting for review:

```bash
ALIKE_PRIVACY_URL="$ALIKE_PRIVACY_URL" \\
ALIKE_SUPPORT_URL="$ALIKE_SUPPORT_URL" \\
APP_STORE_CONNECT_KEY_ID="$APP_STORE_CONNECT_KEY_ID" \\
APP_STORE_CONNECT_ISSUER_ID="$APP_STORE_CONNECT_ISSUER_ID" \\
APP_STORE_CONNECT_API_KEY_PATH="$APP_STORE_CONNECT_API_KEY_PATH" \\
bundle exec fastlane ios metadata_upload
```

Alternatively set `APP_STORE_CONNECT_API_KEY_CONTENT` and optional `APP_STORE_CONNECT_API_KEY_IS_BASE64=true`.

## Split uploads

To upload only text metadata (descriptions, keywords, App Review information) without touching screenshots:

```bash
tools/text
```

To upload only screenshots without touching text metadata:

```bash
tools/upload-screenshots
```

## Notes

- Localized copy for `en-US`, `en-GB` and `uk` is defined in `tools/prepare_app_store_upload_bundle.py`, but only `en-US` and `uk` are uploaded. Strict generation refuses to run if any `TODO:` marker is reintroduced.
- App Review contact and reviewer notes are generated into `metadata/review_information/*.txt` and uploaded automatically by Fastlane `deliver`.
- Edit tracked reviewer notes in `Docs/app-store-review-notes.txt`.
- Alike has no account and no sign-in, so `demo_user.txt` and `demo_password.txt` are intentionally empty.
- `marketing_url.txt` is written only when `ALIKE_MARKETING_URL` is set. The marketing URL is optional for Apple, and `deliver` leaves the App Store Connect value untouched when the file is absent.
- App privacy questionnaire data is not included; Fastlane `deliver` only uploads the privacy URL.
- Subscription metadata is exported to `iap_metadata/app_store_connect_iap_metadata.json`.
- Fastlane `deliver` does not upload the exported IAP metadata; use it as source data for a separate App Store Connect API automation step.
- Screenshots come from `Docs/images/<locale>/`, rendered by `tools/generate_app_store_product_screenshots.py`, and are copied into each upload-safe locale; generated copies remain under `build/`.
""",
    )


def validate_urls(allow_placeholder_urls: bool) -> list[str]:
    errors: list[str] = []
    for mapping in UPLOAD_SAFE_LOCALES:
        for filename in ("privacy_url.txt", "support_url.txt"):
            path = METADATA_ROOT / mapping.apple / filename
            value = path.read_text(encoding="utf-8").strip() if path.exists() else ""
            if not value:
                errors.append(f"{path} is empty")
            if value in {PRIVACY_URL_PLACEHOLDER, SUPPORT_URL_PLACEHOLDER} and not allow_placeholder_urls:
                errors.append(f"{path} still contains placeholder URL")
            if value and value not in {PRIVACY_URL_PLACEHOLDER, SUPPORT_URL_PLACEHOLDER} and not value.startswith("https://"):
                errors.append(f"{path} must use an https:// URL")
        # Optional: absent means "leave the App Store Connect value alone".
        marketing_path = METADATA_ROOT / mapping.apple / "marketing_url.txt"
        if marketing_path.exists():
            marketing_value = marketing_path.read_text(encoding="utf-8").strip()
            if not marketing_value:
                errors.append(f"{marketing_path} is empty; unset {MARKETING_URL_ENV} instead")
            elif not marketing_value.startswith("https://"):
                errors.append(f"{marketing_path} must use an https:// URL")
        description_path = METADATA_ROOT / mapping.apple / "description.txt"
        if description_path.exists():
            description = description_path.read_text(encoding="utf-8")
            if f"{TERMS_LABEL}:" not in description:
                errors.append(f"{description_path} is missing a {TERMS_LABEL} link")
            if TERMS_URL_PLACEHOLDER in description and not allow_placeholder_urls:
                errors.append(f"{description_path} still contains placeholder Terms of Use URL")
    return errors


def validate_metadata() -> list[str]:
    errors: list[str] = []
    for filename in ("copyright.txt", "primary_category.txt", "secondary_category.txt"):
        path = METADATA_ROOT / filename
        if not path.exists() or not path.read_text(encoding="utf-8").strip():
            errors.append(f"Missing non-localized metadata: {path}")

    for mapping in UPLOAD_SAFE_LOCALES:
        locale_root = METADATA_ROOT / mapping.apple
        for filename in REQUIRED_LOCALIZED_FILES:
            path = locale_root / filename
            if not path.exists():
                errors.append(f"Missing localized metadata file: {path}")
                continue
            value = path.read_text(encoding="utf-8").strip()
            if not value:
                errors.append(f"Empty localized metadata file: {path}")
        subtitle_path = locale_root / "subtitle.txt"
        keywords_path = locale_root / "keywords.txt"
        promotional_path = locale_root / "promotional_text.txt"
        description_path = locale_root / "description.txt"
        if subtitle_path.exists() and len(subtitle_path.read_text(encoding="utf-8").strip()) > APP_SUBTITLE_MAX_LENGTH:
            errors.append(f"{subtitle_path} exceeds {APP_SUBTITLE_MAX_LENGTH} characters")
        if keywords_path.exists() and len(keywords_path.read_text(encoding="utf-8").strip().encode("utf-8")) > APP_KEYWORDS_MAX_BYTES:
            errors.append(f"{keywords_path} exceeds {APP_KEYWORDS_MAX_BYTES} UTF-8 bytes")
        if promotional_path.exists() and len(promotional_path.read_text(encoding="utf-8").strip()) > APP_PROMOTIONAL_TEXT_MAX_LENGTH:
            errors.append(f"{promotional_path} exceeds {APP_PROMOTIONAL_TEXT_MAX_LENGTH} characters")
        if description_path.exists() and len(description_path.read_text(encoding="utf-8").strip()) > APP_DESCRIPTION_MAX_LENGTH:
            errors.append(f"{description_path} exceeds {APP_DESCRIPTION_MAX_LENGTH} characters")
        release_notes_path = locale_root / "release_notes.txt"
        if release_notes_path.exists() and len(release_notes_path.read_text(encoding="utf-8").strip()) > APP_RELEASE_NOTES_MAX_LENGTH:
            errors.append(f"{release_notes_path} exceeds {APP_RELEASE_NOTES_MAX_LENGTH} characters")
    return errors


def validate_placeholder_copy(allow_placeholders: bool) -> list[str]:
    if allow_placeholders:
        return []

    errors: list[str] = []
    for mapping in UPLOAD_SAFE_LOCALES:
        locale_root = METADATA_ROOT / mapping.apple
        for filename in REQUIRED_LOCALIZED_FILES:
            path = locale_root / filename
            if path.exists() and TODO_MARKER in path.read_text(encoding="utf-8"):
                errors.append(f"{path} still contains {TODO_MARKER} placeholder copy")
    return errors


def validate_iap_localizations() -> list[str]:
    errors: list[str] = []
    storekit = load_storekit()
    groups = storekit.get("subscriptionGroups", [])
    if not groups:
        errors.append(f"{STOREKIT_PATH} has no subscription groups")

    for group in groups:
        localizations = group.get("localizations", [])
        if not localizations:
            errors.append(f"Subscription group {group.get('name')} has no localizations")
        for localization in localizations:
            display_name = localization.get("displayName", "")
            locale = localization.get("locale", "<unknown>")
            if not (IAP_DISPLAY_NAME_MIN_LENGTH <= len(display_name) <= IAP_DISPLAY_NAME_MAX_LENGTH):
                errors.append(
                    f"Subscription group {group.get('name')} {locale} displayName must be "
                    f"{IAP_DISPLAY_NAME_MIN_LENGTH}-{IAP_DISPLAY_NAME_MAX_LENGTH} characters"
                )

        for subscription in group.get("subscriptions", []):
            errors.extend(
                validate_iap_product_localizations(
                    product_id=subscription.get("productID", "<unknown>"),
                    localizations=subscription.get("localizations", []),
                )
            )

    for product in storekit.get("products", []):
        errors.extend(
            validate_iap_product_localizations(
                product_id=product.get("productID", "<unknown>"),
                localizations=product.get("localizations", []),
            )
        )

    if IAP_METADATA_FILE.exists():
        payload = json.loads(IAP_METADATA_FILE.read_text(encoding="utf-8"))
        if payload.get("appIdentifier") != APP_IDENTIFIER:
            errors.append(f"{IAP_METADATA_FILE} appIdentifier does not match {APP_IDENTIFIER}")
        if not payload.get("subscriptions"):
            errors.append(f"{IAP_METADATA_FILE} has no subscription metadata")
    else:
        errors.append(f"Missing generated IAP metadata export: {IAP_METADATA_FILE}")

    return errors


def validate_iap_product_localizations(product_id: str, localizations: list[dict]) -> list[str]:
    errors: list[str] = []
    if not localizations:
        return [f"{product_id} has no localizations"]

    for localization in localizations:
        locale = localization.get("locale", "<unknown>")
        display_name = localization.get("displayName", "")
        description = localization.get("description", "")
        if not (IAP_DISPLAY_NAME_MIN_LENGTH <= len(display_name) <= IAP_DISPLAY_NAME_MAX_LENGTH):
            errors.append(
                f"{product_id} {locale} displayName must be "
                f"{IAP_DISPLAY_NAME_MIN_LENGTH}-{IAP_DISPLAY_NAME_MAX_LENGTH} characters"
            )
        if len(description) > IAP_DESCRIPTION_MAX_LENGTH:
            errors.append(f"{product_id} {locale} description exceeds {IAP_DESCRIPTION_MAX_LENGTH} characters")
        if not description:
            errors.append(f"{product_id} {locale} description is empty")
    return errors


def validate_screenshots(allow_placeholders: bool) -> list[str]:
    errors: list[str] = []
    for mapping in UPLOAD_SAFE_LOCALES:
        locale_root = SCREENSHOTS_ROOT / mapping.apple
        files = numbered_pngs(locale_root)
        if not files:
            if not allow_placeholders:
                errors.append(f"No numbered screenshots found in {locale_root}")
            continue
        for path in files:
            try:
                size = png_size(path)
            except ValueError as error:
                errors.append(str(error))
                continue
            if size != EXPECTED_SCREENSHOT_SIZE:
                errors.append(f"{path} has size {size}, expected {EXPECTED_SCREENSHOT_SIZE}")
        contact_sheets = sorted(locale_root.glob("*contact-sheet*.png"))
        if contact_sheets:
            errors.extend(f"Contact sheet must not be uploaded: {path}" for path in contact_sheets)
    return errors


def validate_iap_review_screenshot(allow_placeholders: bool) -> list[str]:
    if IAP_REVIEW_SCREENSHOT_PATH is None:
        return [] if allow_placeholders else ["ALIKE_IAP_REVIEW_SCREENSHOT_PATH is required"]
    if not IAP_REVIEW_SCREENSHOT_PATH.exists():
        return [f"Missing IAP review screenshot: {IAP_REVIEW_SCREENSHOT_PATH}"]
    try:
        size = image_size(IAP_REVIEW_SCREENSHOT_PATH)
    except ValueError as error:
        return [str(error)]
    if size != EXPECTED_SCREENSHOT_SIZE:
        return [f"{IAP_REVIEW_SCREENSHOT_PATH} has size {size}, expected {EXPECTED_SCREENSHOT_SIZE}"]
    return []


def validate_review_information(allow_placeholders: bool) -> list[str]:
    errors: list[str] = []
    root = METADATA_ROOT / "review_information"
    for filename in ("first_name.txt", "last_name.txt", "email_address.txt", "phone_number.txt", "notes.txt"):
        path = root / filename
        if not path.exists():
            errors.append(f"Missing review information file: {path}")
            continue
        if not path.read_text(encoding="utf-8").strip():
            errors.append(f"Empty review information file: {path}")
    for filename in ("demo_user.txt", "demo_password.txt"):
        if not (root / filename).exists():
            errors.append(f"Missing review information file: {root / filename}")
    notes_path = root / "notes.txt"
    if notes_path.exists():
        notes = notes_path.read_text(encoding="utf-8").strip()
        if len(notes) > APP_REVIEW_NOTES_MAX_LENGTH:
            errors.append(f"{notes_path} exceeds {APP_REVIEW_NOTES_MAX_LENGTH} characters")
    if not allow_placeholders:
        placeholder_values = {REVIEW_FIRST_NAME, REVIEW_LAST_NAME, REVIEW_EMAIL, REVIEW_PHONE}
        if any(value.startswith("__ALIKE_") for value in placeholder_values):
            errors.append("Real App Review contact values are required")
        if REVIEW_EMAIL == "review@example.com" or REVIEW_PHONE == "+10000000000":
            errors.append("Real App Review email and phone values are required")
    return errors


def validate_bundle(allow_placeholder_urls: bool) -> None:
    errors = []
    errors.extend(validate_metadata())
    errors.extend(validate_urls(allow_placeholder_urls))
    errors.extend(validate_placeholder_copy(allow_placeholder_urls))
    errors.extend(validate_review_information(allow_placeholder_urls))
    errors.extend(validate_iap_localizations())
    errors.extend(validate_screenshots(allow_placeholder_urls))
    errors.extend(validate_iap_review_screenshot(allow_placeholder_urls))
    if errors:
        formatted = "\n".join(f"- {error}" for error in errors)
        raise SystemExit(f"App Store upload bundle validation failed:\n{formatted}")


def main() -> None:
    args = parse_args()
    if not args.validate_only:
        reset_output_dirs()
        generate_metadata(
            privacy_url=env_or_placeholder("ALIKE_PRIVACY_URL", PRIVACY_URL_PLACEHOLDER),
            support_url=env_or_placeholder("ALIKE_SUPPORT_URL", SUPPORT_URL_PLACEHOLDER),
            terms_url=env_or_placeholder("ALIKE_TERMS_URL", TERMS_URL_DEFAULT),
            marketing_url=os.environ.get(MARKETING_URL_ENV, "").strip(),
        )
        generate_review_information()
        copy_screenshots()
        write_iap_metadata()
        write_docs()

    validate_bundle(allow_placeholder_urls=args.allow_placeholder_urls)
    print(f"Prepared App Store upload bundle at {STORE_UPLOAD_ROOT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
