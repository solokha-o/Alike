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
COPYRIGHT = "2026 Oleksandr Solokha"
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
# The description footer is the only place the legal links appear as prose, so
# the labels follow the locale of the copy around them. en-US keeps the values
# above; validation still looks for the en-US TERMS_LABEL, so this table has to
# stay in step with it.
LOCALE_LEGAL_LABELS = {
    "en-US": (PRIVACY_LABEL, TERMS_LABEL),
    "uk": ("Політика конфіденційності", "Умови використання"),
    "de-DE": ("Datenschutzrichtlinie", "Nutzungsbedingungen"),
    "fr-FR": ("Politique de confidentialité", "Conditions d’utilisation"),
    "es-ES": ("Política de privacidad", "Términos de uso"),
    "es-MX": ("Política de privacidad", "Términos de uso"),
    "pt-BR": ("Política de Privacidade", "Termos de Uso"),
    "it": ("Informativa sulla privacy", "Condizioni d’uso"),
    "nl-NL": ("Privacybeleid", "Gebruiksvoorwaarden"),
    "pl": ("Polityka prywatności", "Warunki korzystania"),
    "tr": ("Gizlilik Politikası", "Kullanım Koşulları"),
    "zh-Hant": ("隱私權政策", "使用條款"),
    "ar-SA": ("سياسة الخصوصية", "شروط الاستخدام"),
}
TODO_MARKER = "TODO:"
APP_SUBTITLE_MAX_LENGTH = 30
# App Store Connect counts keywords in characters, commas included — not bytes.
# Counting bytes made the limit roughly twice as strict for Cyrillic: the uk
# keyword list has 51 characters of real headroom but only 7 bytes of it.
APP_KEYWORDS_MAX_LENGTH = 100
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


# The listing ships the same thirteen languages the app itself is translated into.
# `source` is the app's own language code, which is also the directory name
# under Docs/images/; `apple` is the App Store Connect locale, which is not the
# same string. es-419 is the app's Latin American Spanish and maps onto App
# Store Connect's es-MX slot, the only Latin American Spanish the store offers.
# zh-Hant is the one code that is identical on both sides. it, pl and tr are
# bare codes rather than region-qualified ones: Fastlane `deliver`
# (`Deliver::Loader.language_folders`, checked as of 2.230.0) rejects the
# region-qualified it-IT, pl-PL and tr-TR as unsupported directory names, while
# nl-NL and zh-Hant are accepted as-is.
#
# Adding a locale means five things, and a missing one is a validation error
# rather than a silent gap: a mapping here, an entry in METADATA, a row in
# LOCALE_LEGAL_LABELS, a deck in Docs/images/<source>/, and a localization in
# Alike.storekit for the subscription group and every product in it. Arabic
# arrived with the first four and without the fifth, which is what
# validate_storekit_locale_coverage() now refuses to let happen again.
UPLOAD_SAFE_LOCALES = (
    LocaleMapping(source="en-US", apple="en-US"),
    LocaleMapping(source="uk", apple="uk"),
    LocaleMapping(source="de", apple="de-DE"),
    LocaleMapping(source="fr", apple="fr-FR"),
    LocaleMapping(source="es", apple="es-ES"),
    LocaleMapping(source="es-419", apple="es-MX"),
    LocaleMapping(source="pt-BR", apple="pt-BR"),
    LocaleMapping(source="it", apple="it"),
    LocaleMapping(source="nl", apple="nl-NL"),
    LocaleMapping(source="pl", apple="pl"),
    LocaleMapping(source="tr", apple="tr"),
    LocaleMapping(source="zh-Hant", apple="zh-Hant"),
    LocaleMapping(source="ar", apple="ar-SA"),
)

# DELIVER_ACCEPTED_LOCALES guards UPLOAD_SAFE_LOCALES against a regression of
# the it-IT/pl-PL/tr-TR mistake: Fastlane `deliver` accepts a fixed set of
# locale folder names (see `Deliver::Loader.language_folders`), and a locale
# spelled outside that set fails at upload time with "Unsupported directory
# name(s)" instead of at generation time where it is cheap to catch. This
# project ships only the subset of that set the app is translated into, and
# validate_locale_folder_names() checks every generated metadata/screenshot
# folder against it.
DELIVER_ACCEPTED_LOCALES = frozenset(
    {
        "en-US",
        "uk",
        "de-DE",
        "fr-FR",
        "es-ES",
        "es-MX",
        "pt-BR",
        "it",
        "nl-NL",
        "pl",
        "tr",
        "zh-Hant",
        "ar-SA",
    }
)

# StoreKit writes its own locale spelling into Alike.storekit. Traditional
# Chinese is the one that does not simply underscore the App Store code: Xcode
# writes zh_TW, which App Store Connect calls zh-Hant. it_IT, pl_PL and tr_TR
# map onto the bare it/pl/tr Deliver folder names for the same reason as
# UPLOAD_SAFE_LOCALES above — Deliver rejects the region-qualified spelling.
STOREKIT_TO_APP_STORE_LOCALE = {
    "en_US": "en-US",
    "uk": "uk",
    "de_DE": "de-DE",
    "fr_FR": "fr-FR",
    "es_ES": "es-ES",
    "es_MX": "es-MX",
    "pt_BR": "pt-BR",
    "it_IT": "it",
    "nl_NL": "nl-NL",
    "pl_PL": "pl",
    "tr_TR": "tr",
    "zh_TW": "zh-Hant",
    "ar_SA": "ar-SA",
}

APP_STORE_TO_STOREKIT_LOCALE = {apple: storekit for storekit, apple in STOREKIT_TO_APP_STORE_LOCALE.items()}

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
# published privacy policy, terms of use and landing page in the
# alikeapp/alikeapp.github.io repository, and
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
- No ads anywhere in the app.
- Scanning and cleanup need no connection at all — Alike works in Airplane Mode.
- Nothing is deleted without your explicit confirmation.

BUILT FOR REAL LIBRARIES
- Three sensitivity levels, from near-identical shots to a wider net.
- Best Shot detection, so every group has a sensible default to keep.
- Review badges: New, In Review, Reviewed, and Needs Review after a rescan.
- Add or delete photos and Alike notices, then resurfaces only the groups that changed — no full rescan to stay current.
- Progress, Selected and Estimated Savings while you work.
- Cleanup history grouped by month, so you can see what you have already reclaimed.
- A roomy one-column layout or a denser grid, switchable any time and remembered.
- A searchable guide inside the app, one tap from the Scanner.
- Optional cleanup reminders, delivered as local notifications on your own schedule.
- Thirteen languages: English, Ukrainian, German, French, Spanish, Latin American Spanish, Brazilian Portuguese, Italian, Dutch, Polish, Turkish, Traditional Chinese and Arabic. Full Dark Mode support.

YOU STAY IN CONTROL
- Photos you clear go to Recently Deleted, recoverable for about 30 days.
- Settings, then Data & Privacy, then Delete Alike Data erases every scan result, cleanup record and preference the app has stored — and never touches your photo library.
- Grant Full Access or Limited Access; Alike works with whatever you choose to share.

ALIKE FREE
- 3 scans per month
- Guided review with Best Shot
- Sorting and cleanup history
- Clean up one photo at a time

ALIKE PRO
- 7 days free on the yearly plan, for eligible new subscribers
- Unlimited scans
- Clean up whole selections at once
- Screenshot cleanup
- Blurred photo cleanup
- Advanced filters
- Custom cleanup reminders

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
- Без реклами в застосунку.
- Сканування та прибирання не потребують інтернету — Alike працює в режимі польоту.
- Нічого не видаляється без вашого явного підтвердження.

СТВОРЕНО ДЛЯ СПРАВЖНІХ МЕДІАТЕК
- Три рівні чутливості — від майже ідентичних знімків до ширшого пошуку.
- Вибір найкращого знімка, тож у кожній групі є розумний варіант залишити.
- Позначки: «Нове», «У перегляді», «Переглянуто», «Потребує перегляду».
- Додали чи видалили фото — Alike це помічає й повертає до перегляду лише ті групи, що змінилися, без повного пересканування.
- Прогрес, «Обрано» й «Орієнтовна економія» просто під час роботи.
- Історія прибирання за місяцями — видно, скільки місця вже повернуто.
- Просторий один стовпець або щільніша сітка — перемикайте будь-коли, вибір запам’ятовується.
- Довідка з пошуком просто в застосунку, за один дотик зі «Сканера».
- Необовʼязкові нагадування про прибирання — локальні сповіщення за вашим розкладом.
- Тринадцять мов: англійська, українська, німецька, французька, іспанська, латиноамериканська іспанська, бразильська португальська, італійська, нідерландська, польська, турецька, традиційна китайська та арабська. Повна темна тема.

ВИ КЕРУЄТЕ ВСІМ
- Прибрані фото потрапляють до «Нещодавно видалених» і залишаються доступними близько 30 днів.
- «Дані та приватність» → «Видалити дані Alike» стирає всі результати сканувань, записи прибирання та налаштування застосунку — і не торкається вашої медіатеки.
- Надайте повний або обмежений доступ: Alike працює з тим, чим ви вирішили поділитися.

ALIKE FREE
- 3 сканування на місяць
- Покроковий перегляд із найкращим знімком
- Сортування та історія прибирання
- Прибирання по одному фото за раз

ALIKE PRO
- 7 днів безкоштовно на річному плані, для нових підписників, які мають на це право
- Необмежені сканування
- Прибирання цілих виділень одразу
- Прибирання знімків екрана
- Прибирання розмитих фото
- Розширені фільтри
- Власні нагадування про прибирання

Alike Pro — це підписка з автоматичним поновленням, річний і місячний плани, ціни у вашій валюті. Річний план містить 7 днів безкоштовно для нових підписників, які мають на це право; оплата починається після завершення пробного періоду. Підписка поновлюється автоматично, якщо її не скасувати щонайменше за 24 години до завершення поточного періоду, а оплата стягується з вашого облікового запису Apple. Керувати підпискою або скасувати її можна будь-коли в Налаштуваннях iOS."""

# The five Tier 1 descriptions below are adapted, not translated. Structure and
# claims match en-US exactly — the auto-renew paragraph in particular is a legal
# requirement and appears in full everywhere — but the wording follows the
# register and vocabulary the app itself already uses in that language: informal
# in de, es, es-419 and pt-BR, vouvoiement in fr, and feature names taken from
# the .xcstrings catalogs so the listing and the UI say the same words.
DE_DE_DESCRIPTION = """\
Alike findet die Beinahe-Dubletten in deiner Mediathek, gruppiert sie, wählt in jeder Gruppe die beste Aufnahme und hilft dir, den Rest aufzuräumen — und kein einziges Foto verlässt dabei dein Gerät.

SO FUNKTIONIERT ES
Scannen. Alike vergleicht deine Mediathek mit Apples Vision-Framework, vollständig auf deinem iPhone. Verglichen werden Fotos, die zeitlich und örtlich nah beieinander entstanden sind. Bildschirmfotos bleiben außen vor, solange du sie nicht ausdrücklich anforderst.
Prüfen. Jede Gruppe öffnet sich mit einer bereits ausgewählten besten Aufnahme, sodass du in Sekunden entscheidest. Nur die beste behalten, alle außer der besten auswählen oder von Hand wählen.
Aufräumen. Bestätige, und die gewählten Fotos wandern zu „Zuletzt gelöscht“, wo iOS sie rund 30 Tage aufbewahrt.

DATENSCHUTZ IST DER GANZE PUNKT
- Die gesamte Analyse läuft auf dem Gerät mit Apples Vision-Framework.
- Kein Foto, keine Miniatur und kein Merkmalsabdruck wird jemals hochgeladen.
- Kein Konto, keine Anmeldung, kein Alike-Server.
- Keine Nutzungsanalyse, kein Tracking, keine Werbe-IDs.
- Keine Werbung, nirgendwo in der App.
- Scannen und Aufräumen brauchen überhaupt keine Verbindung — Alike arbeitet im Flugmodus.
- Nichts wird ohne deine ausdrückliche Bestätigung gelöscht.

FÜR ECHTE MEDIATHEKEN GEBAUT
- Drei Empfindlichkeitsstufen, von fast identischen Aufnahmen bis zu einem weiteren Netz.
- Erkennung der besten Aufnahme, damit jede Gruppe eine sinnvolle Vorauswahl hat.
- Prüfstatus: Neu, In Prüfung, Geprüft und Erneut prüfen nach einem weiteren Scan.
- Kommen Fotos dazu oder fallen weg, merkt Alike das und zeigt nur die geänderten Gruppen erneut — kein vollständiger Scan, um aktuell zu bleiben.
- Fortschritt, Ausgewählt und geschätzte Ersparnis, während du arbeitest.
- Verlauf nach Monaten gruppiert, damit du siehst, wie viel Platz du schon zurückgeholt hast.
- Ein großzügiges einspaltiges Layout oder ein dichteres Raster, jederzeit umschaltbar und gemerkt.
- Eine durchsuchbare Anleitung in der App, einen Tipp vom Scanner entfernt.
- Optionale Aufräum-Erinnerungen als lokale Mitteilungen, nach deinem eigenen Zeitplan.
- Dreizehn Sprachen: Englisch, Ukrainisch, Deutsch, Französisch, Spanisch, Lateinamerikanisches Spanisch, Brasilianisches Portugiesisch, Italienisch, Niederländisch, Polnisch, Türkisch, Traditionelles Chinesisch und Arabisch. Voller Dark Mode.

DU BEHÄLTST DIE KONTROLLE
- Aufgeräumte Fotos landen bei „Zuletzt gelöscht“ und bleiben rund 30 Tage wiederherstellbar.
- Einstellungen, dann Daten & Datenschutz, dann Alike-Daten löschen entfernt jedes Scan-Ergebnis, jeden Aufräum-Eintrag und jede Einstellung, die die App gespeichert hat — und rührt deine Mediathek nicht an.
- Erteile vollen oder eingeschränkten Zugriff: Alike arbeitet mit dem, was du teilen möchtest.

ALIKE FREE
- 3 Scans pro Monat
- Geführte Prüfung mit bester Aufnahme
- Sortierung und Aufräum-Verlauf
- Ein Foto nach dem anderen aufräumen

ALIKE PRO
- 7 Tage gratis im Jahresplan, für berechtigte neue Abonnenten
- Unbegrenzte Scans
- Ganze Auswahlen auf einmal aufräumen
- Bildschirmfotos aufräumen
- Unscharfe Fotos aufräumen
- Erweiterte Filter
- Eigene Aufräum-Erinnerungen

Alike Pro ist ein Abonnement mit automatischer Verlängerung, im Jahres- und im Monatsplan, berechnet in deiner Landeswährung. Der Jahresplan enthält 7 Tage gratis für berechtigte neue Abonnenten, und die Abrechnung beginnt nach Ablauf des Testzeitraums. Abonnements verlängern sich automatisch, sofern sie nicht mindestens 24 Stunden vor Ende des laufenden Zeitraums gekündigt werden, und die Zahlung erfolgt über deinen Apple Account. Verwalten oder kündigen kannst du jederzeit in den iOS-Einstellungen."""

FR_FR_DESCRIPTION = """\
Alike retrouve les quasi-doublons cachés dans votre photothèque, les regroupe, choisit la meilleure photo de chaque groupe et vous aide à nettoyer le reste — sans qu'une seule photo quitte votre appareil.

COMMENT ÇA MARCHE
Analyser. Alike compare votre photothèque avec le framework Vision d'Apple, entièrement sur votre iPhone. Les photos prises à des dates et des lieux proches sont comparées, et les captures d'écran restent hors des résultats tant que vous ne les demandez pas.
Examiner. Chaque groupe s'ouvre avec une meilleure photo déjà sélectionnée : vous décidez en quelques secondes. Ne garder que la meilleure, tout sélectionner sauf la meilleure, ou choisir à la main.
Nettoyer. Confirmez, et les photos choisies rejoignent « Supprimés récemment », où iOS les conserve environ 30 jours.

LA CONFIDENTIALITÉ EST TOUT L'INTÉRÊT
- Toute l'analyse se fait sur l'appareil avec le framework Vision d'Apple.
- Aucune photo, aucune miniature, aucune empreinte n'est jamais envoyée en ligne.
- Aucun compte, aucune connexion, aucun serveur Alike.
- Aucune mesure d'audience, aucun suivi, aucun identifiant publicitaire.
- Aucune publicité, nulle part dans l'app.
- L'analyse et le nettoyage ne demandent aucune connexion — Alike fonctionne en mode Avion.
- Rien n'est supprimé sans votre confirmation explicite.

CONÇU POUR DE VRAIES PHOTOTHÈQUES
- Trois niveaux de sensibilité, des photos presque identiques à un filet plus large.
- Détection de la meilleure photo : chaque groupe s'ouvre sur un choix raisonnable à garder.
- Badges d'examen : Nouveau, En cours, Examiné, et À revoir après une nouvelle analyse.
- Vous ajoutez ou supprimez des photos, Alike le remarque et ne remet en avant que les groupes modifiés — aucune analyse complète pour rester à jour.
- Progression, Sélectionnées et Économie estimée pendant que vous travaillez.
- Historique de nettoyage par mois, pour voir l'espace déjà récupéré.
- Une mise en page aérée sur une colonne ou une grille plus dense, permutables à tout moment et mémorisées.
- Un mode d'emploi consultable dans l'app, à un geste du Scanner.
- Rappels de nettoyage facultatifs, en notifications locales, à votre rythme.
- Treize langues : anglais, ukrainien, allemand, français, espagnol, espagnol d'Amérique latine, portugais brésilien, italien, néerlandais, polonais, turc, chinois traditionnel et arabe. Mode sombre complet.

VOUS GARDEZ LA MAIN
- Les photos nettoyées rejoignent « Supprimés récemment » et restent récupérables environ 30 jours.
- Réglages, puis Données et confidentialité, puis Supprimer les données Alike efface tous les résultats d'analyse, l'historique de nettoyage et les préférences enregistrés par l'app — et ne touche jamais à votre photothèque.
- Accordez un accès complet ou limité : Alike travaille avec ce que vous choisissez de partager.

ALIKE FREE
- 3 analyses par mois
- Examen guidé avec la meilleure photo
- Tri et historique de nettoyage
- Nettoyage photo par photo

ALIKE PRO
- 7 jours offerts sur la formule annuelle, pour les nouveaux abonnés éligibles
- Analyses illimitées
- Nettoyage groupé d'une sélection entière
- Nettoyage des captures d'écran
- Nettoyage des photos floues
- Filtres avancés
- Rappels de nettoyage personnalisés

Alike Pro est un abonnement à renouvellement automatique, en formule annuelle ou mensuelle, facturé dans votre devise locale. La formule annuelle comprend 7 jours d'essai gratuit pour les nouveaux abonnés éligibles, et la facturation commence à la fin de l'essai. L'abonnement se renouvelle automatiquement sauf résiliation au moins 24 heures avant la fin de la période en cours, et le paiement est prélevé sur votre compte Apple. Vous pouvez le gérer ou le résilier à tout moment dans les Réglages iOS."""

ES_ES_DESCRIPTION = """\
Alike encuentra los casi duplicados escondidos en tu fototeca, los agrupa, elige la mejor toma de cada grupo y te ayuda a limpiar el resto, sin que ninguna foto salga de tu dispositivo.

CÓMO FUNCIONA
Analizar. Alike compara tu fototeca con el framework Vision de Apple, íntegramente en tu iPhone. Se comparan las fotos tomadas en momentos y lugares cercanos, y las capturas de pantalla se quedan fuera de los resultados salvo que las pidas.
Revisar. Cada grupo se abre con una mejor toma ya seleccionada, así que decides en segundos. Quedarte solo con la mejor, seleccionar todas menos la mejor o elegir a mano.
Limpiar. Confirma y las fotos elegidas pasan a «Eliminados recientemente», donde iOS las guarda unos 30 días.

LA PRIVACIDAD ES TODO EL SENTIDO
- Todo el análisis se ejecuta en el dispositivo con el framework Vision de Apple.
- Ninguna foto, miniatura ni huella de características se sube nunca.
- Sin cuenta, sin inicio de sesión, sin servidor de Alike.
- Sin analíticas, sin seguimiento, sin identificadores publicitarios.
- Sin anuncios en ninguna parte de la app.
- Analizar y limpiar no necesitan conexión: Alike funciona en modo avión.
- No se elimina nada sin tu confirmación explícita.

HECHO PARA FOTOTECAS REALES
- Tres niveles de sensibilidad, desde tomas casi idénticas hasta una red más amplia.
- Detección de la mejor toma, para que cada grupo tenga una opción razonable que conservar.
- Indicadores de revisión: Nueva, En revisión, Revisada y Requiere revisión tras un nuevo análisis.
- Añades o eliminas fotos y Alike lo nota, y vuelve a mostrar solo los grupos que han cambiado, sin repetir el análisis completo.
- Progreso, Seleccionadas y Ahorro estimado mientras trabajas.
- Historial de limpieza agrupado por meses, para ver cuánto espacio has recuperado ya.
- Una disposición amplia de una columna o una cuadrícula más densa, intercambiables cuando quieras y recordadas.
- Instrucciones de uso con búsqueda dentro de la app, a un toque del Analizador.
- Recordatorios de limpieza opcionales, como notificaciones locales, con tu propio horario.
- Trece idiomas: inglés, ucraniano, alemán, francés, español, español de Latinoamérica, portugués de Brasil, italiano, neerlandés, polaco, turco, chino tradicional y árabe. Modo oscuro completo.

TÚ TIENES EL CONTROL
- Las fotos limpiadas pasan a «Eliminados recientemente» y se pueden recuperar durante unos 30 días.
- Ajustes, luego Datos y privacidad, luego Eliminar datos de Alike borra todos los resultados de análisis, el historial de limpieza y las preferencias que la app haya guardado, y nunca toca tu fototeca.
- Concede acceso completo o limitado: Alike trabaja con lo que decidas compartir.

ALIKE FREE
- 3 análisis al mes
- Revisión guiada con la mejor toma
- Ordenación e historial de limpieza
- Limpieza de una foto cada vez

ALIKE PRO
- 7 días gratis en el plan anual, para nuevos suscriptores que cumplan los requisitos
- Análisis ilimitados
- Limpieza por lotes de selecciones enteras
- Limpieza de capturas de pantalla
- Limpieza de fotos borrosas
- Filtros avanzados
- Recordatorios de limpieza personalizados

Alike Pro es una suscripción de renovación automática con planes anual y mensual, con precios en tu moneda local. El plan anual incluye 7 días de prueba gratuita para nuevos suscriptores que cumplan los requisitos, y el cobro empieza al terminar la prueba. Las suscripciones se renuevan automáticamente salvo que se cancelen al menos 24 horas antes del final del periodo en curso, y el pago se carga a tu cuenta de Apple. Puedes gestionarla o cancelarla cuando quieras en los Ajustes de iOS."""

ES_MX_DESCRIPTION = """\
Alike encuentra los casi duplicados escondidos en tu fototeca, los agrupa, elige la mejor toma de cada grupo y te ayuda a limpiar el resto, sin que ninguna foto salga de tu dispositivo.

CÓMO FUNCIONA
Analizar. Alike compara tu fototeca con el framework Vision de Apple, totalmente en tu iPhone. Se comparan las fotos tomadas en momentos y lugares cercanos, y las capturas de pantalla se quedan fuera de los resultados a menos que las pidas.
Revisar. Cada grupo se abre con una mejor toma ya seleccionada, así que decides en segundos. Quedarte solo con la mejor, seleccionar todas menos la mejor o elegir a mano.
Limpiar. Confirma y las fotos elegidas pasan a «Eliminados recientemente», donde iOS las guarda unos 30 días.

LA PRIVACIDAD ES TODO EL SENTIDO
- Todo el análisis se ejecuta en el dispositivo con el framework Vision de Apple.
- Ninguna foto, miniatura ni huella de características se sube nunca.
- Sin cuenta, sin inicio de sesión, sin servidor de Alike.
- Sin analíticas, sin rastreo, sin identificadores publicitarios.
- Sin anuncios en ninguna parte de la app.
- Analizar y limpiar no necesitan conexión: Alike funciona en modo avión.
- No se elimina nada sin tu confirmación explícita.

HECHO PARA FOTOTECAS REALES
- Tres niveles de sensibilidad, desde tomas casi idénticas hasta una red más amplia.
- Detección de la mejor toma, para que cada grupo tenga una opción razonable que conservar.
- Indicadores de revisión: Nueva, En revisión, Revisada y Requiere revisión después de un nuevo análisis.
- Agregas o eliminas fotos y Alike lo nota, y vuelve a mostrar solo los grupos que cambiaron, sin repetir el análisis completo.
- Progreso, Seleccionadas y Ahorro estimado mientras trabajas.
- Historial de limpieza agrupado por meses, para ver cuánto espacio ya recuperaste.
- Un diseño amplio de una columna o una cuadrícula más densa, intercambiables cuando quieras y recordados.
- Instrucciones de uso con búsqueda dentro de la app, a un toque del Analizador.
- Recordatorios de limpieza opcionales, como notificaciones locales, con tu propio horario.
- Trece idiomas: inglés, ucraniano, alemán, francés, español, español de Latinoamérica, portugués de Brasil, italiano, neerlandés, polaco, turco, chino tradicional y árabe. Modo oscuro completo.

TÚ TIENES EL CONTROL
- Las fotos limpiadas pasan a «Eliminados recientemente» y se pueden recuperar durante unos 30 días.
- Configuración, luego Datos y privacidad, luego Eliminar datos de Alike borra todos los resultados de análisis, el historial de limpieza y las preferencias que la app haya guardado, y nunca toca tu fototeca.
- Otorga acceso completo o limitado: Alike trabaja con lo que decidas compartir.

ALIKE FREE
- 3 análisis al mes
- Revisión guiada con la mejor toma
- Ordenamiento e historial de limpieza
- Limpieza de una foto a la vez

ALIKE PRO
- 7 días gratis en el plan anual, para nuevos suscriptores que cumplan los requisitos
- Análisis ilimitados
- Limpieza por lotes de selecciones enteras
- Limpieza de capturas de pantalla
- Limpieza de fotos borrosas
- Filtros avanzados
- Recordatorios de limpieza personalizados

Alike Pro es una suscripción de renovación automática con planes anual y mensual, con precios en tu moneda local. El plan anual incluye 7 días de prueba gratis para nuevos suscriptores que cumplan los requisitos, y el cobro empieza al terminar la prueba. Las suscripciones se renuevan automáticamente a menos que se cancelen al menos 24 horas antes del final del periodo en curso, y el pago se carga a tu cuenta de Apple. Puedes administrarla o cancelarla cuando quieras en la Configuración de iOS."""

PT_BR_DESCRIPTION = """\
O Alike encontra as quase duplicadas escondidas na sua fototeca, agrupa todas, escolhe a melhor foto de cada grupo e ajuda você a limpar o resto — sem que uma única foto saia do seu dispositivo.

COMO FUNCIONA
Analisar. O Alike compara sua fototeca com o framework Vision da Apple, inteiramente no seu iPhone. São comparadas as fotos feitas em horários e lugares próximos, e as capturas de tela ficam fora dos resultados a menos que você peça.
Revisar. Cada grupo abre com uma melhor foto já selecionada, então você decide em segundos. Manter só a melhor, selecionar todas menos a melhor ou escolher na mão.
Limpar. Confirme, e as fotos escolhidas vão para «Apagados recentemente», onde o iOS as guarda por cerca de 30 dias.

PRIVACIDADE É O PONTO PRINCIPAL
- Toda a análise roda no dispositivo, com o framework Vision da Apple.
- Nenhuma foto, miniatura ou impressão de características é enviada para lugar nenhum.
- Sem conta, sem login, sem servidor do Alike.
- Sem analytics, sem rastreamento, sem identificadores de publicidade.
- Sem anúncios em nenhuma parte do app.
- Analisar e limpar não precisam de conexão alguma — o Alike funciona em modo avião.
- Nada é apagado sem a sua confirmação explícita.

FEITO PARA FOTOTECAS DE VERDADE
- Três níveis de sensibilidade, das fotos quase idênticas até uma rede mais ampla.
- Detecção da melhor foto, para que cada grupo já tenha uma escolha sensata para manter.
- Selos de revisão: Nova, Em revisão, Revisada e Revisar de novo depois de uma nova análise.
- Você adiciona ou apaga fotos e o Alike percebe, trazendo de volta só os grupos que mudaram — sem repetir a análise inteira.
- Progresso, Selecionadas e Economia estimada enquanto você trabalha.
- Histórico de limpeza agrupado por mês, para ver quanto espaço você já recuperou.
- Um layout espaçoso de uma coluna ou uma grade mais densa, alternáveis a qualquer momento e memorizados.
- Instruções de uso com busca dentro do app, a um toque do Analisador.
- Lembretes de limpeza opcionais, como notificações locais, no seu próprio horário.
- Treze idiomas: inglês, ucraniano, alemão, francês, espanhol, espanhol da América Latina, português do Brasil, italiano, neerlandês, polonês, turco, chinês tradicional e árabe. Modo escuro completo.

VOCÊ NO CONTROLE
- As fotos limpas vão para «Apagados recentemente» e continuam recuperáveis por cerca de 30 dias.
- Ajustes, depois Dados e privacidade, depois Apagar dados do Alike remove todos os resultados de análise, o histórico de limpeza e as preferências que o app guardou — e nunca encosta na sua fototeca.
- Conceda acesso total ou limitado: o Alike trabalha com o que você escolher compartilhar.

ALIKE FREE
- 3 análises por mês
- Revisão guiada com a melhor foto
- Ordenação e histórico de limpeza
- Limpeza de uma foto por vez

ALIKE PRO
- 7 dias grátis no plano anual, para novos assinantes elegíveis
- Análises ilimitadas
- Limpeza em lote de seleções inteiras
- Limpeza de capturas de tela
- Limpeza de fotos desfocadas
- Filtros avançados
- Lembretes de limpeza personalizados

O Alike Pro é uma assinatura de renovação automática com planos anual e mensal, com preços na sua moeda local. O plano anual inclui 7 dias de teste grátis para novos assinantes elegíveis, e a cobrança começa quando o teste termina. As assinaturas são renovadas automaticamente, a menos que sejam canceladas pelo menos 24 horas antes do fim do período atual, e o pagamento é debitado da sua Conta Apple. Você pode gerenciar ou cancelar quando quiser nos Ajustes do iOS."""

# The five Tier 3 descriptions follow the same rule as Tier 1 above: same
# structure, same claims, the auto-renew paragraph in full, and feature names
# lifted from the .xcstrings catalogs so the listing and the UI say the same
# words. Register follows the catalogs too, which is informal in all five —
# including Turkish, where the app says "Fotoğrafların", not "Fotoğraflarınız".
IT_DESCRIPTION = """\
Alike trova i quasi-doppioni nascosti nella tua libreria, li raggruppa, sceglie lo scatto migliore di ogni gruppo e ti aiuta a eliminare il resto — senza che una sola foto lasci il tuo dispositivo.

COME FUNZIONA
Scansiona. Alike confronta la tua libreria con il framework Vision di Apple, interamente sul tuo iPhone. Vengono confrontate le foto scattate vicine nel tempo e nel luogo, e gli screenshot restano fuori dai risultati se non li richiedi.
Controlla. Ogni gruppo si apre con lo scatto migliore già selezionato, così decidi in pochi secondi. Tieni solo la migliore, seleziona tutte tranne la migliore oppure scegli a mano.
Pulisci. Conferma e le foto che hai scelto finiscono in «Eliminati di recente», dove iOS le conserva per circa 30 giorni.

LA PRIVACY È TUTTO IL PUNTO
- Tutta l'analisi avviene sul dispositivo con il framework Vision di Apple.
- Nessuna foto, miniatura o impronta caratteristica viene mai caricata online.
- Nessun account, nessun accesso, nessun server Alike.
- Nessuna analisi statistica, nessun tracciamento, nessun identificativo pubblicitario.
- Nessuna pubblicità in nessuna parte dell'app.
- La scansione e la pulizia non richiedono alcuna connessione: Alike funziona in modalità aereo.
- Niente viene eliminato senza la tua conferma esplicita.

PENSATA PER LIBRERIE VERE
- Tre livelli di sensibilità, dagli scatti quasi identici a una rete più ampia.
- Riconoscimento dello scatto migliore, così ogni gruppo ha già una scelta sensata da tenere.
- Indicatori di controllo: Nuovo, In controllo, Controllato e Da controllare dopo una nuova scansione.
- Aggiungi o elimini foto e Alike se ne accorge, riproponendo solo i gruppi cambiati — senza rifare tutta la scansione.
- Avanzamento, Selezionate e Risparmio stimato mentre lavori.
- Cronologia pulizia raggruppata per mese, per vedere quanto spazio hai già recuperato.
- Un layout ampio a una colonna o una griglia più fitta, alternabili quando vuoi e ricordati.
- Istruzioni consultabili dentro l'app, a un tocco dallo Scanner.
- Promemoria di pulizia facoltativi, come notifiche locali, secondo i tuoi orari.
- Tredici lingue: inglese, ucraino, tedesco, francese, spagnolo, spagnolo latinoamericano, portoghese brasiliano, italiano, olandese, polacco, turco, cinese tradizionale e arabo. Modalità scura completa.

SEI TU A DECIDERE
- Le foto che elimini vanno in «Eliminati di recente» e restano recuperabili per circa 30 giorni.
- Impostazioni, poi Dati e privacy, poi Elimina i dati di Alike cancella ogni risultato di scansione, registro di pulizia e preferenza salvati dall'app — e non tocca mai la tua libreria.
- Concedi accesso completo o limitato: Alike lavora con quello che scegli di condividere.

ALIKE FREE
- 3 scansioni al mese
- Controllo guidato con lo scatto migliore
- Ordinamento e cronologia pulizia
- Pulizia di una foto alla volta

ALIKE PRO
- 7 giorni gratis sul piano annuale, per i nuovi abbonati idonei
- Scansioni illimitate
- Pulizia di intere selezioni in una volta
- Pulizia screenshot
- Pulizia foto sfocate
- Filtri avanzati
- Promemoria di pulizia personalizzati

Alike Pro è un abbonamento a rinnovo automatico con piani annuale e mensile, con prezzi nella tua valuta locale. Il piano annuale include una prova gratuita di 7 giorni per i nuovi abbonati idonei, e la fatturazione inizia al termine della prova. Gli abbonamenti si rinnovano automaticamente se non vengono annullati almeno 24 ore prima della fine del periodo in corso, e il pagamento viene addebitato sul tuo account Apple. Puoi gestire o annullare l'abbonamento in qualsiasi momento in Impostazioni di iOS."""

NL_NL_DESCRIPTION = """\
Alike vindt de bijna-dubbele foto's die zich in je bibliotheek verstoppen, groepeert ze, kiest de beste opname van elke groep en helpt je de rest op te ruimen — zonder dat één foto je apparaat verlaat.

ZO WERKT HET
Scannen. Alike vergelijkt je bibliotheek met Apples Vision-framework, volledig op je iPhone. Foto's die qua tijd en plaats dicht bij elkaar liggen worden vergeleken, en schermafbeeldingen blijven buiten de resultaten tenzij je erom vraagt.
Bekijken. Elke groep opent met een beste opname die al geselecteerd is, dus je beslist in seconden. Alleen de beste bewaren, alles behalve de beste selecteren of met de hand kiezen.
Opruimen. Bevestig, en de foto's die je koos gaan naar 'Recent verwijderd', waar iOS ze ongeveer 30 dagen bewaart.

PRIVACY IS DE HELE BEDOELING
- Alle analyse draait op het apparaat met Apples Vision-framework.
- Geen foto, miniatuur of kenmerkafdruk wordt ooit geüpload.
- Geen account, geen inloggen, geen Alike-server.
- Geen analytics, geen tracking, geen advertentie-id's.
- Nergens in de app advertenties.
- Scannen en opruimen hebben helemaal geen verbinding nodig — Alike werkt in vliegtuigmodus.
- Er wordt niets verwijderd zonder je uitdrukkelijke bevestiging.

GEMAAKT VOOR ECHTE BIBLIOTHEKEN
- Drie niveaus van gevoeligheid, van bijna identieke opnamen tot een breder net.
- Herkenning van de beste opname, zodat elke groep een verstandige keuze klaar heeft staan.
- Statuslabels: Nieuw, Wordt bekeken, Bekeken en Moet worden bekeken na een nieuwe scan.
- Voeg foto's toe of verwijder ze en Alike merkt het, en toont alleen de groepen die veranderd zijn — geen volledige nieuwe scan nodig.
- Voortgang, Geselecteerd en Geschatte besparing terwijl je werkt.
- Opruimgeschiedenis per maand, zodat je ziet hoeveel je al hebt teruggewonnen.
- Een ruime indeling met één kolom of een dichter raster, altijd om te wisselen en onthouden.
- Een doorzoekbare handleiding in de app, één tik vanaf de Scanner.
- Optionele opruimherinneringen als lokale berichtgevingen, op je eigen schema.
- Dertien talen: Engels, Oekraïens, Duits, Frans, Spaans, Latijns-Amerikaans Spaans, Braziliaans Portugees, Italiaans, Nederlands, Pools, Turks, traditioneel Chinees en Arabisch. Volledige donkere modus.

JIJ HOUDT DE CONTROLE
- Opgeruimde foto's gaan naar 'Recent verwijderd' en blijven ongeveer 30 dagen terug te halen.
- Instellingen, dan Gegevens en privacy, dan Verwijder Alike-gegevens wist elk scanresultaat, opruimrecord en elke voorkeur die de app heeft bewaard — en raakt je fotobibliotheek nooit aan.
- Geef volledige of beperkte toegang: Alike werkt met wat jij besluit te delen.

ALIKE FREE
- 3 scans per maand
- Begeleid bekijken met de beste opname
- Sorteren en opruimgeschiedenis
- Eén foto tegelijk opruimen

ALIKE PRO
- 7 dagen gratis op het jaarabonnement, voor nieuwe abonnees die daarvoor in aanmerking komen
- Onbeperkt scannen
- Hele selecties in één keer opruimen
- Schermafbeeldingen opruimen
- Wazige foto's opruimen
- Geavanceerde filters
- Eigen opruimherinneringen

Alike Pro is een abonnement met automatische verlenging, met een jaar- en een maandplan, geprijsd in je eigen valuta. Het jaarabonnement bevat een gratis proefperiode van 7 dagen voor nieuwe abonnees die daarvoor in aanmerking komen, en de facturering begint zodra de proefperiode afloopt. Abonnementen worden automatisch verlengd, tenzij ze minstens 24 uur voor het einde van de huidige periode worden opgezegd. Het bedrag wordt afgeschreven van je Apple Account. Je kunt je abonnement altijd beheren of opzeggen in de iOS-instellingen."""

PL_DESCRIPTION = """\
Alike znajduje prawie identyczne zdjęcia ukryte w Twojej bibliotece, grupuje je, wybiera najlepsze ujęcie w każdej grupie i pomaga uporządkować resztę — a żadne zdjęcie nie opuszcza Twojego urządzenia.

JAK TO DZIAŁA
Skanuj. Alike porównuje bibliotekę za pomocą frameworka Vision od Apple, w całości na Twoim iPhonie. Porównywane są zdjęcia zrobione blisko siebie w czasie i miejscu, a zrzuty ekranu nie trafiają do wyników, dopóki o nie nie poprosisz.
Przejrzyj. Każda grupa otwiera się z już wybranym najlepszym ujęciem, więc decyzja zajmuje sekundy. Zostaw tylko najlepsze, zaznacz wszystkie oprócz najlepszego albo wybierz ręcznie.
Uporządkuj. Potwierdź, a wybrane zdjęcia trafią do albumu „Ostatnio usunięte”, gdzie iOS trzyma je około 30 dni.

PRYWATNOŚĆ TO CAŁY SENS
- Cała analiza działa na urządzeniu, na frameworku Vision od Apple.
- Żadne zdjęcie, miniatura ani odcisk cech nigdy nie jest wysyłany do sieci.
- Bez konta, bez logowania, bez serwera Alike.
- Bez analityki, bez śledzenia, bez identyfikatorów reklamowych.
- Bez reklam w jakiejkolwiek części aplikacji.
- Skanowanie i porządki nie potrzebują żadnego połączenia — Alike działa w trybie samolotowym.
- Nic nie zostaje usunięte bez Twojego wyraźnego potwierdzenia.

ZROBIONE DLA PRAWDZIWYCH BIBLIOTEK
- Trzy poziomy czułości, od niemal identycznych ujęć po szersze sito.
- Wykrywanie najlepszego ujęcia, więc każda grupa ma sensowny domyślny wybór do zachowania.
- Znaczniki przeglądu: Nowe, W trakcie przeglądu, Przejrzane i Wymaga przeglądu po ponownym skanowaniu.
- Dodajesz albo usuwasz zdjęcia, a Alike to zauważa i przywraca tylko zmienione grupy — bez pełnego skanowania od nowa.
- Postęp, Wybrane i Szacowana oszczędność w trakcie pracy.
- Historia porządków pogrupowana według miesięcy, żeby było widać, ile miejsca już odzyskałeś.
- Przestronny układ jednokolumnowy albo gęstsza siatka, przełączane w każdej chwili i zapamiętywane.
- Przeszukiwalna instrukcja w aplikacji, jedno dotknięcie od Skanera.
- Opcjonalne przypomnienia o porządkach jako powiadomienia lokalne, według Twojego harmonogramu.
- Trzynaście języków: angielski, ukraiński, niemiecki, francuski, hiszpański, hiszpański latynoamerykański, portugalski brazylijski, włoski, niderlandzki, polski, turecki, chiński tradycyjny i arabski. Pełny tryb ciemny.

TO TY DECYDUJESZ
- Uporządkowane zdjęcia trafiają do albumu „Ostatnio usunięte” i można je odzyskać przez około 30 dni.
- Ustawienia, potem Dane i prywatność, potem Usuń dane Alike kasuje każdy wynik skanowania, zapis porządków i ustawienie zapisane przez aplikację — i nigdy nie rusza Twojej biblioteki zdjęć.
- Przyznaj pełny albo ograniczony dostęp: Alike pracuje z tym, czym zdecydujesz się podzielić.

ALIKE FREE
- 3 skanowania miesięcznie
- Prowadzony przegląd z najlepszym ujęciem
- Sortowanie i historia porządków
- Porządki po jednym zdjęciu

ALIKE PRO
- 7 dni za darmo w planie rocznym, dla uprawnionych nowych subskrybentów
- Nieograniczone skanowania
- Porządki w całych zaznaczeniach naraz
- Porządki w zrzutach ekranu
- Porządki w rozmytych zdjęciach
- Zaawansowane filtry
- Własne przypomnienia o porządkach

Alike Pro to subskrypcja odnawiana automatycznie, w planie rocznym i miesięcznym, w cenach w Twojej walucie. Plan roczny obejmuje 7-dniowy bezpłatny okres próbny dla uprawnionych nowych subskrybentów, a naliczanie opłat zaczyna się po zakończeniu okresu próbnego. Subskrypcje odnawiają się automatycznie, o ile nie zostaną anulowane co najmniej 24 godziny przed końcem bieżącego okresu, a płatność jest pobierana z Twojego konta Apple. Subskrypcją możesz zarządzać lub anulować ją w dowolnym momencie w Ustawieniach iOS."""

TR_DESCRIPTION = """\
Alike, kitaplığında saklanan neredeyse aynı fotoğrafları bulur, gruplar, her grubun en iyi karesini seçer ve geri kalanını temizlemene yardım eder — üstelik tek bir fotoğraf bile cihazından çıkmaz.

NASIL ÇALIŞIR
Tara. Alike, kitaplığını Apple'ın Vision çerçevesiyle tamamen iPhone'unda karşılaştırır. Zaman ve yer olarak birbirine yakın çekilen fotoğraflar karşılaştırılır, ekran görüntüleri ise sen istemedikçe sonuçlara girmez.
Gözden geçir. Her grup, en iyi karesi seçili olarak açılır; kararın saniyeler sürer. Yalnızca en iyisini tut, en iyisi hariç tümünü seç ya da elle seç.
Temizle. Onayla; seçtiğin fotoğraflar Son Silinenler'e taşınır, iOS onları yaklaşık 30 gün orada tutar.

MESELENİN TAMAMI GİZLİLİK
- Tüm analiz, Apple'ın Vision çerçevesiyle cihazın üzerinde çalışır.
- Hiçbir fotoğraf, küçük resim ya da öznitelik izi hiçbir zaman yüklenmez.
- Hesap yok, oturum açma yok, Alike sunucusu yok.
- Analitik yok, izleme yok, reklam tanımlayıcısı yok.
- Uygulamanın hiçbir yerinde reklam yok.
- Tarama ve temizlik hiçbir bağlantı gerektirmez — Alike uçak modunda da çalışır.
- Açık onayın olmadan hiçbir şey silinmez.

GERÇEK KİTAPLIKLAR İÇİN
- Üç duyarlılık düzeyi: neredeyse aynı karelerden daha geniş bir ağa.
- En İyi Kare algılama, böylece her grupta saklanacak makul bir seçenek hazır bekler.
- Gözden geçirme rozetleri: Yeni, Gözden geçiriliyor, Gözden geçirildi ve yeni taramadan sonra Gözden geçirilmeli.
- Fotoğraf ekler ya da silersin, Alike bunu fark eder ve yalnızca değişen grupları yeniden getirir — baştan tam tarama gerekmez.
- Çalışırken İlerleme, Seçildi ve Tahmini Kazanç.
- Aya göre gruplanmış Temizlik Geçmişi, ne kadar yer kazandığını görebilesin diye.
- Ferah tek sütunlu düzen ya da daha sık ızgara; istediğin zaman değiştirilir ve hatırlanır.
- Uygulamanın içinde aranabilir bir kullanım kılavuzu, Tarayıcı'dan bir dokunuş uzakta.
- İsteğe bağlı temizlik anımsatıcıları, kendi programına göre yerel bildirim olarak gelir.
- On üç dil: İngilizce, Ukraynaca, Almanca, Fransızca, İspanyolca, Latin Amerika İspanyolcası, Brezilya Portekizcesi, İtalyanca, Felemenkçe, Lehçe, Türkçe, Geleneksel Çince ve Arapça. Tam Koyu Mod desteği.

KONTROL SENDE
- Temizlediğin fotoğraflar Son Silinenler'e gider ve yaklaşık 30 gün geri alınabilir.
- Ayarlar, sonra Veriler ve Gizlilik, sonra Alike Verilerini Sil; uygulamanın sakladığı her tarama sonucunu, temizlik kaydını ve tercihi siler — fotoğraf kitaplığına ise hiç dokunmaz.
- Tam erişim ya da sınırlı erişim ver: Alike paylaşmayı seçtiğin neyse onunla çalışır.

ALIKE FREE
- Ayda 3 tarama
- En İyi Kare ile yönlendirilmiş gözden geçirme
- Sıralama ve temizlik geçmişi
- Fotoğrafları teker teker temizleme

ALIKE PRO
- Yıllık planda 7 gün ücretsiz, uygun yeni aboneler için
- Sınırsız tarama
- Seçimlerin tamamını tek seferde temizleme
- Ekran görüntüsü temizliği
- Bulanık fotoğraf temizliği
- Gelişmiş filtreler
- Kendi temizlik anımsatıcıların

Alike Pro, yıllık ve aylık planları olan, kendi para biriminde fiyatlanan otomatik yenilenen bir aboneliktir. Yıllık plan, uygun yeni aboneler için 7 günlük ücretsiz deneme içerir ve faturalandırma deneme sona erdiğinde başlar. Abonelikler, mevcut dönemin bitiminden en az 24 saat önce iptal edilmediği sürece otomatik olarak yenilenir ve ödeme Apple Hesabından tahsil edilir. Aboneliğini istediğin zaman iOS Ayarları'ndan yönetebilir veya iptal edebilirsin."""

ZH_HANT_DESCRIPTION = """\
Alike 會找出照片圖庫裡藏著的近乎重複的照片，把它們分成一組組，在每一組中挑出最佳照片，並幫你清理其餘的——而且沒有任何一張照片會離開你的裝置。

運作方式
掃描。Alike 以 Apple 的 Vision 框架比對你的照片圖庫，全程在 iPhone 上完成。系統只比對拍攝時間與地點相近的照片，螢幕快照除非你特別要求，否則不會出現在結果中。
檢視。每一組打開時都已選好最佳照片，你只需幾秒就能決定。可以只保留最佳照片、選取除最佳照片外的全部，或自行手動挑選。
清理。確認之後，你選取的照片會移到「最近刪除」，iOS 會在那裡保留約 30 天。

隱私就是重點所在
- 所有分析都以 Apple 的 Vision 框架在裝置上執行。
- 任何照片、縮覽圖或特徵指紋都不會被上傳。
- 沒有帳戶、不需登入，也沒有 Alike 伺服器。
- 沒有分析追蹤，沒有行為追蹤，沒有廣告識別碼。
- App 裡任何地方都沒有廣告。
- 掃描與清理完全不需要連線——Alike 在飛航模式下照樣運作。
- 未經你明確確認，不會刪除任何東西。

為真實的照片圖庫而設計
- 三種敏感度：從幾乎完全相同的照片，到範圍更寬的比對。
- 最佳照片偵測，讓每一組都有一個合理的保留預設值。
- 檢視標記：新項目、檢視中、已檢視，以及重新掃描後的待檢視。
- 你新增或刪除照片後 Alike 會察覺，只把有變動的那幾組重新提出來——不必整個重掃一次。
- 工作過程中隨時可見進度、已選取與預估可省空間。
- 依月份分組的清理歷史記錄，讓你看見已經省回多少空間。
- 寬鬆的單欄版面或更緊湊的格狀版面，隨時切換並自動記住。
- App 內建可搜尋的使用說明，從掃描畫面點一下就能開啟。
- 選用的清理提醒，以本地通知依你自己的時間送達。
- 十三種語言：英文、烏克蘭文、德文、法文、西班牙文、拉丁美洲西班牙文、巴西葡萄牙文、義大利文、荷蘭文、波蘭文、土耳其文、繁體中文與阿拉伯文。完整支援深色模式。

一切由你決定
- 清理掉的照片會進入「最近刪除」，約 30 天內都還能還原。
- 「設定」→「資料與隱私權」→「刪除 Alike 資料」會清除 App 儲存的所有掃描結果、清理記錄與偏好設定——完全不會動到你的照片圖庫。
- 你可以授予完整取用權或有限取用權：無論你選擇分享什麼，Alike 都能運作。

ALIKE FREE
- 每月 3 次掃描
- 有最佳照片引導的檢視流程
- 排序與清理歷史記錄
- 一次清理一張照片

ALIKE PRO
- 年繳方案 7 天免費，適用於符合資格的新訂閱者
- 無限次掃描
- 一次清理整批選取的照片
- 螢幕快照清理
- 模糊照片清理
- 進階篩選
- 自訂清理提醒

Alike Pro 是自動續訂的訂閱項目，提供年繳與月繳方案，並以你的當地貨幣定價。年繳方案為符合資格的新訂閱者提供 7 天免費試用，試用結束時即開始計費。除非在目前週期結束前至少 24 小時取消，訂閱項目將自動續訂，款項將向你的 Apple 帳戶收取。你可以隨時在 iOS「設定」中管理或取消訂閱項目。"""


AR_DESCRIPTION = """\
يعثر Alike على الصور شبه المكررة المختبئة في مكتبتك، ويجمّعها، ويختار أفضل لقطة في كل مجموعة، ويساعدك على إزالة الباقي — دون أن تغادر صورة واحدة جهازك.

كيف يعمل
افحص. يقارن Alike مكتبتك باستخدام إطار عمل Vision من Apple، بالكامل على جهاز iPhone. تُقارن الصور المتقاربة في الزمان والمكان، وتبقى لقطات الشاشة خارج النتائج ما لم تطلبها.
راجع. تُفتح كل مجموعة وقد اختير فيها «أفضل لقطة» سلفًا، فتقرر في ثوانٍ. احتفظ بالأفضل فقط، أو حدد الكل ما عدا الأفضل، أو اختر يدويًا.
نظّف. أكّد، فتنتقل الصور التي اخترتها إلى «المحذوفة مؤخرًا»، حيث يحتفظ بها iOS نحو 30 يومًا.

الخصوصية هي الفكرة كلها
- يجري التحليل كله على الجهاز بإطار عمل Vision من Apple.
- لا تُرفع أي صورة أو صورة مصغّرة أو بصمة سمات إلى أي مكان.
- لا حساب، ولا تسجيل دخول، ولا خادم خاص بـ Alike.
- لا تحليلات، ولا تتبّع، ولا معرّفات إعلانية.
- لا إعلانات في أي مكان داخل التطبيق.
- لا يحتاج الفحص والتنظيف إلى اتصال إطلاقًا — يعمل Alike في وضع الطيران.
- لا يُحذف أي شيء دون تأكيدك الصريح.

مصمَّم لمكتبات حقيقية
- ثلاثة مستويات حساسية، من اللقطات شبه المتطابقة إلى نطاق أوسع.
- كشف أفضل لقطة، فلكل مجموعة خيار افتراضي معقول للاحتفاظ به.
- شارات المراجعة: جديدة، قيد المراجعة، تمت مراجعتها، وبحاجة إلى مراجعة بعد إعادة الفحص.
- أضف صورًا أو احذفها فيلاحظ Alike ذلك، ثم يعيد إظهار المجموعات التي تغيّرت وحدها — دون إعادة فحص كاملة لتبقى محدَّثًا.
- التقدّم والمحدد والتوفير التقديري أمام عينيك أثناء العمل.
- سجل تنظيف مجمَّع حسب الشهر، لترى ما استرجعته حتى الآن.
- تخطيط فسيح بعمود واحد أو شبكة أكثر كثافة، يمكن تبديله في أي وقت ويُحفظ اختيارك.
- دليل قابل للبحث داخل التطبيق، على بُعد نقرة واحدة من شاشة الفحص.
- تذكيرات تنظيف اختيارية، تصل كإشعارات محلية وفق جدولك أنت.
- ثلاث عشرة لغة: الإنجليزية والأوكرانية والألمانية والفرنسية والإسبانية وإسبانية أمريكا اللاتينية والبرتغالية البرازيلية والإيطالية والهولندية والبولندية والتركية والصينية التقليدية والعربية. ودعم كامل للوضع الداكن.

تبقى أنت المتحكم
- تنتقل الصور التي تنظّفها إلى «المحذوفة مؤخرًا»، ويمكن استعادتها نحو 30 يومًا.
- الإعدادات، ثم البيانات والخصوصية، ثم حذف بيانات Alike يمحو كل نتيجة فحص وسجل تنظيف وتفضيل خزّنه التطبيق — ولا يمس مكتبة صورك أبدًا.
- امنح وصولًا كاملًا أو وصولًا محدودًا؛ يعمل Alike مع ما تختار مشاركته.

‏ALIKE المجاني
- 3 فحوصات شهريًا
- مراجعة موجَّهة مع أفضل لقطة
- الترتيب وسجل التنظيف
- تنظيف صورة واحدة في كل مرة

‏ALIKE PRO
- 7 أيام مجانًا في الخطة السنوية، للمشتركين الجدد المؤهلين
- فحوصات غير محدودة
- تنظيف تحديدات كاملة دفعة واحدة
- تنظيف لقطات الشاشة
- تنظيف الصور الضبابية
- مرشّحات متقدمة
- تذكيرات تنظيف مخصصة

‏Alike Pro اشتراك يتجدد تلقائيًا بخطتين سنوية وشهرية، بسعر بعملتك المحلية. تشمل الخطة السنوية تجربة مجانية مدتها 7 أيام للمشتركين الجدد المؤهلين، وتبدأ الفوترة عند انتهاء التجربة. تتجدد الاشتراكات تلقائيًا ما لم تُلغَ قبل 24 ساعة على الأقل من نهاية الفترة الحالية، وتُخصم قيمة الدفع من حساب Apple الخاص بك. يمكنك الإدارة أو الإلغاء في أي وقت من إعدادات iOS."""


METADATA = {
    "en-US": {
        "subtitle": "Find and clear similar photos",
        "description": EN_US_DESCRIPTION,
        # App Store Connect indexes the app name and subtitle on top of this
        # field, so "similar", "photo" and "cleaner" are deliberately absent —
        # repeating them here would spend characters on terms already covered.
        "keywords": "duplicate,cleanup,camera roll,storage,space,declutter,gallery,screenshot,blurry,album,delete",
        # Promotional text is the one field App Store Connect accepts without a
        # new build, so the trial lives here as well as in the description.
        "promotional_text": "Alike groups the photos that look alike, picks the best shot in each group, and helps you clear the rest. All on your iPhone. Alike Pro: 7 days free on the yearly plan.",
        "release_notes": "Alike now looks at the photos themselves when it picks the best shot — and it can enhance that one photo for you, reversibly.\n\n- The best shot is chosen from sharpness, exposure, faces and noise, so a blurred favourite no longer beats a sharp frame.\n- A short note says why it won: sharper, better exposure, face in focus.\n- When nothing clearly stands out, Alike says so and asks you to choose, instead of guessing.\n- Enhance the best shot with one tap, touch and hold to compare it with the original, and go back to the original whenever you want — Live Photos included.\n- The original is kept by the system, no copy is created, and the change shows up in Photos like any other edit.\n\nEverything still runs on your device: no account, no uploads, and what you clear goes to Recently Deleted, where iOS keeps it for about 30 days.\n\nFeedback and bug reports are genuinely welcome — the support link on the App Store page reaches me directly.",
    },
    "uk": {
        "subtitle": "Знайти й прибрати схожі фото",
        "description": UK_DESCRIPTION,
        # Same rule as en-US: the uk subtitle already covers "схожі" and "фото".
        "keywords": "дублікати,очищення,галерея,сховище,місце,скріншоти,розмиті,копії,знімки,видалити",
        "promotional_text": "Alike групує схожі фотографії, обирає найкращий знімок і допомагає прибрати решту — усе на вашому iPhone. Alike Pro: 7 днів безкоштовно на річному плані.",
        "release_notes": "Alike тепер дивиться на самі фотографії, коли обирає найкращий кадр, — і може покращити цей кадр так, що це завжди можна скасувати.\n\n- Найкращий кадр обирається за різкістю, експозицією, обличчями й шумом, тож розмите улюблене фото більше не виграє в різкого.\n- Короткий підпис пояснює, чому переміг саме цей кадр: різкіше, краща експозиція, обличчя у фокусі.\n- Коли жоден кадр не виділяється, Alike так і каже й просить обрати самому, замість вгадувати.\n- Покращення застосовується одним дотиком, утримування показує оригінал для порівняння, а повернути оригінал можна будь-коли — включно з Live Photos.\n- Оригінал зберігає сама система, копія не створюється, а зміна видно у «Фото», як будь-яке інше редагування.\n\nУсе так само виконується на вашому пристрої: без облікового запису й без вивантаження, а прибране потрапляє до «Нещодавно видалених», де iOS зберігає його близько 30 днів.\n\nВідгуки та повідомлення про помилки дуже вітаються — посилання на підтримку на сторінці App Store веде безпосередньо до розробника.",
    },
    # Keywords below are researched per market rather than translated. Each set
    # skips whatever the localized subtitle already indexes — "ähnliche Fotos",
    # "photos similaires", "duplicados", "duplicadas" — because App Store
    # Connect indexes the name and subtitle on top of this field, and repeating
    # them spends a 100-character budget on terms already covered.
    "de-DE": {
        "subtitle": "Ähnliche Fotos aufräumen",
        "description": DE_DE_DESCRIPTION,
        "keywords": "doppelte,duplikate,bilder,speicherplatz,galerie,bildschirmfoto,unscharf,löschen,kamera",
        "promotional_text": "Alike gruppiert ähnliche Fotos, wählt die beste Aufnahme und hilft dir, den Rest aufzuräumen — alles auf deinem iPhone. Alike Pro: 7 Tage gratis im Jahresplan.",
        "release_notes": "Alike schaut jetzt in die Fotos selbst, wenn es die beste Aufnahme wählt — und kann genau dieses Foto verbessern, jederzeit umkehrbar.\n\n- Die beste Aufnahme ergibt sich aus Schärfe, Belichtung, Gesichtern und Rauschen: Ein unscharfer Favorit gewinnt nicht mehr gegen ein scharfes Bild.\n- Eine kurze Notiz sagt, warum sie gewonnen hat: schärfer, bessere Belichtung, Gesicht im Fokus.\n- Wenn nichts klar heraussticht, sagt Alike das und bittet dich zu wählen, statt zu raten.\n- Verbessere die beste Aufnahme mit einem Tippen, halte gedrückt für den Vergleich mit dem Original, und kehre jederzeit zum Original zurück — auch bei Live Photos.\n- Das Original behält das System, es entsteht keine Kopie, und die Änderung ist in Fotos wie jede andere Bearbeitung sichtbar.\n\nAlles läuft weiterhin auf deinem Gerät: kein Konto, keine Uploads, und was du aufräumst, geht nach „Zuletzt gelöscht“, wo iOS es rund 30 Tage aufbewahrt.\n\nRückmeldungen und Fehlerberichte sind ausdrücklich willkommen — der Support-Link auf der App-Store-Seite erreicht mich direkt.",
    },
    "fr-FR": {
        "subtitle": "Nettoyer les photos similaires",
        "description": FR_FR_DESCRIPTION,
        "keywords": "doublons,double,images,stockage,espace,galerie,capture,flou,supprimer,pellicule,ranger",
        "promotional_text": "Alike regroupe les photos qui se ressemblent, choisit la meilleure et vous aide à nettoyer le reste, sur votre iPhone. Alike Pro : 7 jours offerts en formule annuelle.",
        "release_notes": "Alike regarde désormais les photos elles-mêmes pour choisir la meilleure prise — et peut améliorer cette photo, de façon réversible.\n\n- La meilleure prise est choisie selon la netteté, l'exposition, les visages et le bruit : une favorite floue ne l'emporte plus sur une image nette.\n- Une courte note indique pourquoi elle a gagné : plus nette, meilleure exposition, visage net.\n- Quand rien ne se détache clairement, Alike le dit et vous laisse choisir au lieu de deviner.\n- Améliorez la meilleure prise d'une seule touche, touchez et maintenez pour la comparer à l'originale, et revenez à l'originale quand vous voulez — Live Photos comprises.\n- L'originale est conservée par le système, aucune copie n'est créée, et la modification apparaît dans Photos comme toute autre retouche.\n\nTout se passe toujours sur votre appareil : aucun compte, aucun envoi, et ce que vous nettoyez part dans « Supprimés récemment », où iOS le conserve environ 30 jours.\n\nVos retours et vos rapports de bugs sont sincèrement bienvenus — le lien d'assistance sur la page App Store me parvient directement.",
    },
    "es-ES": {
        "subtitle": "Encuentra y limpia duplicados",
        "description": ES_ES_DESCRIPTION,
        "keywords": "fotos,repetidas,similares,almacenamiento,espacio,galería,captura,borrosas,borrar,carrete",
        "promotional_text": "Alike agrupa las fotos que se parecen, elige la mejor toma de cada grupo y te ayuda a limpiar el resto, en tu iPhone. Alike Pro: 7 días gratis en el plan anual.",
        "release_notes": "Alike ahora mira las fotos en sí para elegir la mejor toma, y puede mejorar esa foto de forma reversible.\n\n- La mejor toma se elige por nitidez, exposición, rostros y ruido: una favorita movida ya no gana a una imagen nítida.\n- Una nota breve dice por qué ha ganado: más nítida, mejor exposición, rostro enfocado.\n- Cuando ninguna destaca con claridad, Alike lo dice y te pide elegir, en lugar de adivinar.\n- Mejora la mejor toma con un toque, mantén pulsado para compararla con el original y vuelve al original cuando quieras, también en Live Photos.\n- El original lo guarda el sistema, no se crea ninguna copia y el cambio se ve en Fotos como cualquier otra edición.\n\nTodo sigue ejecutándose en tu dispositivo: sin cuenta, sin subidas, y lo que limpias va a «Eliminados recientemente», donde iOS lo guarda unos 30 días.\n\nLos comentarios y los informes de errores son muy bienvenidos: el enlace de soporte de la página de App Store llega directamente a mí.",
    },
    "es-MX": {
        "subtitle": "Encuentra y limpia duplicados",
        "description": ES_MX_DESCRIPTION,
        "keywords": "fotos,iguales,liberar espacio,almacenamiento,celular,galería,capturas,borrosas,eliminar",
        "promotional_text": "Alike agrupa las fotos que se parecen, elige la mejor toma de cada grupo y te ayuda a limpiar el resto, en tu iPhone. Alike Pro: 7 días gratis en el plan anual.",
        "release_notes": "Alike ahora mira las fotos en sí para elegir la mejor toma, y puede mejorar esa foto de forma reversible.\n\n- La mejor toma se elige por nitidez, exposición, rostros y ruido: una favorita movida ya no le gana a una imagen nítida.\n- Una nota breve dice por qué ganó: más nítida, mejor exposición, rostro enfocado.\n- Cuando ninguna destaca con claridad, Alike lo dice y te pide elegir, en lugar de adivinar.\n- Mejora la mejor toma con un toque, mantén presionado para compararla con el original y vuelve al original cuando quieras, también en Live Photos.\n- El original lo guarda el sistema, no se crea ninguna copia y el cambio se ve en Fotos como cualquier otra edición.\n\nTodo sigue ejecutándose en tu dispositivo: sin cuenta, sin subidas, y lo que limpias va a «Eliminados recientemente», donde iOS lo guarda unos 30 días.\n\nLos comentarios y los reportes de errores son muy bienvenidos: el enlace de soporte de la página de App Store llega directamente a mí.",
    },
    "pt-BR": {
        "subtitle": "Encontre e limpe duplicadas",
        "description": PT_BR_DESCRIPTION,
        "keywords": "fotos,repetidas,iguais,armazenamento,liberar espaço,galeria,captura,desfocadas,apagar",
        "promotional_text": "O Alike agrupa as fotos parecidas, escolhe a melhor de cada grupo e ajuda você a limpar o resto, no seu iPhone. Alike Pro: 7 dias grátis no plano anual.",
        "release_notes": "O Alike agora olha para as próprias fotos ao escolher a melhor — e pode aprimorar essa foto de forma reversível.\n\n- A melhor foto é escolhida por nitidez, exposição, rostos e ruído: uma favorita tremida não vence mais uma imagem nítida.\n- Uma nota curta diz por que ela venceu: mais nítida, melhor exposição, rosto em foco.\n- Quando nada se destaca com clareza, o Alike diz isso e pede que você escolha, em vez de adivinhar.\n- Aprimore a melhor foto com um toque, mantenha pressionado para comparar com o original e volte ao original quando quiser — inclusive em Live Photos.\n- O original fica guardado pelo sistema, nenhuma cópia é criada, e a mudança aparece em Fotos como qualquer outra edição.\n\nTudo continua rodando no seu dispositivo: sem conta, sem envios, e o que você limpa vai para «Apagados recentemente», onde o iOS guarda por cerca de 30 dias.\n\nComentários e relatos de erros são muito bem-vindos — o link de suporte na página da App Store chega direto a mim.",
    },
    # Tier 3 keywords follow the same market-research rule as Tier 1: they skip
    # whatever the localized subtitle already indexes — "doppioni", "dubbels",
    # "podobne zdjęcia", "benzer fotoğrafları", 相似照片 — because App Store
    # Connect indexes the name and subtitle on top of this field.
    #
    # The limits are characters, not bytes, which is what makes zh-Hant the
    # roomiest listing here rather than the tightest: a 100-character keyword
    # field holds far more Chinese terms than Latin ones, and a subtitle says in
    # sixteen characters what English needs twenty-nine for. Brevity is still
    # the rule, but the earlier eleven-character subtitle left the single
    # heaviest indexed field after the name two-thirds empty, so it now also
    # carries 相片 — the spelling Traditional Chinese searches use at least as
    # often as 照片, which no field held before — and 一鍵.
    "it": {
        "subtitle": "Trova e pulisci i doppioni",
        "description": IT_DESCRIPTION,
        "keywords": "foto,simili,duplicate,spazio,archiviazione,galleria,screenshot,sfocate,eliminare,rullino",
        "promotional_text": "Alike raggruppa le foto simili, sceglie lo scatto migliore di ogni gruppo e ti aiuta a eliminare il resto, sul tuo iPhone. Alike Pro: 7 giorni gratis sul piano annuale.",
        "release_notes": "Alike ora guarda le foto stesse quando sceglie lo scatto migliore — e può migliorare quella foto, in modo reversibile.\n\n- Lo scatto migliore viene scelto in base a nitidezza, esposizione, volti e rumore: una preferita mossa non batte più un'immagine nitida.\n- Una breve nota dice perché ha vinto: più nitida, esposizione migliore, volto a fuoco.\n- Quando non emerge nulla di chiaro, Alike lo dice e ti chiede di scegliere, invece di tirare a indovinare.\n- Migliora lo scatto migliore con un tocco, tieni premuto per confrontarlo con l'originale e torna all'originale quando vuoi — Live Photos comprese.\n- L'originale lo conserva il sistema, non viene creata alcuna copia e la modifica compare in Foto come qualsiasi altra.\n\nTutto avviene ancora sul tuo dispositivo: nessun account, nessun caricamento, e ciò che elimini finisce in «Eliminati di recente», dove iOS lo conserva per circa 30 giorni.\n\nCommenti e segnalazioni sono davvero benvenuti: il link di assistenza sulla pagina App Store arriva direttamente a me.",
    },
    "nl-NL": {
        "subtitle": "Vind en ruim dubbels op",
        "description": NL_NL_DESCRIPTION,
        "keywords": "foto,dubbele,opruimen,opslag,ruimte,galerij,schermafbeelding,wazig,verwijderen,album",
        "promotional_text": "Alike groepeert de foto's die op elkaar lijken, kiest de beste opname van elke groep en helpt je de rest op te ruimen. Alike Pro: 7 dagen gratis op het jaarplan.",
        "release_notes": "Alike kijkt nu naar de foto's zelf bij het kiezen van de beste foto — en kan die ene foto verbeteren, altijd terug te draaien.\n\n- De beste foto wordt gekozen op scherpte, belichting, gezichten en ruis: een onscherpe favoriet wint niet meer van een scherpe opname.\n- Een korte notitie zegt waarom die won: scherper, betere belichting, gezicht scherp.\n- Als er niets duidelijk uitspringt, zegt Alike dat en laat het jou kiezen in plaats van te gokken.\n- Verbeter de beste foto met één tik, houd vast om te vergelijken met het origineel en ga wanneer je wilt terug naar het origineel — ook bij Live Photos.\n- Het origineel bewaart het systeem, er komt geen kopie bij, en de wijziging is in Foto's te zien als elke andere bewerking.\n\nAlles draait nog steeds op je apparaat: geen account, geen uploads, en wat je opruimt gaat naar 'Recent verwijderd', waar iOS het ongeveer 30 dagen bewaart.\n\nReacties en foutmeldingen zijn oprecht welkom — de ondersteuningslink op de App Store-pagina komt rechtstreeks bij mij terecht.",
    },
    "pl": {
        "subtitle": "Znajdź i usuń podobne zdjęcia",
        "description": PL_DESCRIPTION,
        "keywords": "duplikaty,kopie,porządki,pamięć,miejsce,galeria,zrzut ekranu,rozmyte,usuwanie,album",
        "promotional_text": "Alike grupuje podobnie wyglądające zdjęcia, wybiera najlepsze ujęcie w każdej grupie i pomaga uporządkować resztę. Alike Pro: 7 dni za darmo w planie rocznym.",
        "release_notes": "Alike patrzy teraz na same zdjęcia, gdy wybiera najlepsze ujęcie — i potrafi je poprawić w sposób odwracalny.\n\n- Najlepsze ujęcie wybierane jest na podstawie ostrości, ekspozycji, twarzy i szumu: poruszone zdjęcie z ulubionych nie wygrywa już z ostrym.\n- Krótka notka mówi, dlaczego wygrało: ostrzejsze, lepsza ekspozycja, twarz w ostrości.\n- Gdy nic wyraźnie się nie wyróżnia, Alike to mówi i prosi o wybór, zamiast zgadywać.\n- Popraw najlepsze ujęcie jednym dotknięciem, przytrzymaj, aby porównać je z oryginałem, i wróć do oryginału, kiedy zechcesz — także w Live Photos.\n- Oryginał przechowuje system, nie powstaje żadna kopia, a zmianę widać w Zdjęciach jak każdą inną edycję.\n\nWszystko nadal działa na Twoim urządzeniu: bez konta, bez wysyłania czegokolwiek, a to, co uporządkujesz, trafia do „Ostatnio usuniętych”, gdzie iOS trzyma je około 30 dni.\n\nUwagi i zgłoszenia błędów są naprawdę mile widziane — link do pomocy na stronie App Store trafia bezpośrednio do mnie.",
    },
    "tr": {
        "subtitle": "Benzer fotoğrafları temizle",
        "description": TR_DESCRIPTION,
        "keywords": "kopya,yinelenen,depolama,alan,galeri,ekran görüntüsü,bulanık,silme,albüm,yer açma",
        "promotional_text": "Alike benzeyen fotoğrafları gruplar, her grubun en iyi karesini seçer ve geri kalanını temizlemene yardım eder. Alike Pro: yıllık planda 7 gün ücretsiz.",
        "release_notes": "Alike artık en iyi kareyi seçerken fotoğrafların kendisine bakıyor — ve o fotoğrafı geri alınabilir şekilde iyileştirebiliyor.\n\n- En iyi kare netlik, pozlama, yüzler ve gürültüye göre seçiliyor: bulanık bir favori artık net bir kareyi geçemiyor.\n- Kısa bir not neden kazandığını söylüyor: daha net, daha iyi pozlama, yüz net.\n- Hiçbiri açıkça öne çıkmıyorsa Alike bunu söylüyor ve tahmin etmek yerine seçmeni istiyor.\n- En iyi kareyi tek dokunuşla iyileştir, orijinaliyle karşılaştırmak için basılı tut ve istediğin an orijinaline dön — Live Photos dahil.\n- Orijinali sistem saklıyor, kopya oluşmuyor ve değişiklik Fotoğraflar'da diğer düzenlemeler gibi görünüyor.\n\nHer şey yine cihazında çalışıyor: hesap yok, yükleme yok; temizlediklerin Son Silinenler'e gider, iOS onları yaklaşık 30 gün orada tutar.\n\nGeri bildirimler ve hata bildirimleri gerçekten memnuniyetle karşılanır — App Store sayfasındaki destek bağlantısı doğrudan bana ulaşır.",
    },
    "zh-Hant": {
        "subtitle": "找出相似與重複相片，一鍵清出空間",
        "description": ZH_HANT_DESCRIPTION,
        "keywords": "重覆,清理,相簿,圖庫,儲存,釋放,螢幕快照,截圖,模糊,刪除,整理,近似,連拍,空間不足,照片管理,記憶體,瘦身,掃描,批次,手機,離線,隱私,一模一樣,圖片,檔案,免費,智慧,清空,選片",
        "promotional_text": "Alike 會把看起來相像的照片分成一組組，挑出每一組的最佳照片，並幫你清理其餘的，全程在 iPhone 上完成。Alike Pro：年繳方案 7 天免費。",
        "release_notes": "Alike 現在會看照片本身來挑選最佳照片，而且可以優化那張照片，隨時都能還原。\n\n- 最佳照片依清晰度、曝光、人臉與雜訊挑選：模糊的最愛照片不再勝過清晰的一張。\n- 一行簡短說明會告訴你它為何勝出：更清晰、曝光更佳、人臉清晰。\n- 若沒有明顯勝出的一張，Alike 會直說並請你自行挑選，而不是亂猜。\n- 輕點一下就能優化最佳照片，按住可與原始照片比較，隨時都能還原為原始照片，Live Photo 也適用。\n- 原始照片由系統保留，不會產生副本，變更會像其他編輯一樣顯示在「照片」中。\n\n一切仍在你的裝置上執行：沒有帳戶、不上傳任何東西，清理掉的照片會移到「最近刪除」，iOS 會在那裡保留約 30 天。\n\n歡迎提供意見與回報問題——App Store 頁面上的支援連結會直接寄到我這裡。",
    },
    "ar-SA": {
        "subtitle": "اعثر على الصور المتشابهة",
        "description": AR_DESCRIPTION,
        # Same rule as every other locale: the name and subtitle already carry
        # "صور" and "متشابهة", so the keyword field spends its characters elsewhere.
        "keywords": "مكرر,تنظيف,معرض,مساحة,تخزين,ترتيب,ألبوم,لقطة شاشة,ضبابي,حذف,نسخ,صور مكررة,تفريغ,أرشيف",
        "promotional_text": "يجمّع Alike الصور المتشابهة، ويختار أفضل لقطة في كل مجموعة، ويساعدك على إزالة الباقي. كل ذلك على جهاز iPhone. ‏Alike Pro: 7 أيام مجانًا في الخطة السنوية.",
        "release_notes": "يفحص Alike الآن الصور نفسها عند اختيار أفضل لقطة، ويمكنه تحسين تلك الصورة مع إمكانية التراجع في أي وقت.\n\n- تُختار أفضل لقطة حسب الحدة والإضاءة والوجوه والضوضاء، فلم تعد الصورة المفضّلة الضبابية تتفوّق على لقطة حادة.\n- ملاحظة قصيرة تشرح سبب فوزها: أكثر حدة، إضاءة أفضل، الوجه واضح.\n- وعندما لا تبرز أي لقطة بوضوح، يقول Alike ذلك ويطلب منك الاختيار بدلًا من التخمين.\n- حسّن أفضل لقطة بلمسة واحدة، والمس مع الاستمرار لمقارنتها بالأصل، وعُد إلى الأصل متى شئت — بما في ذلك صور Live Photos.\n- يحتفظ النظام بالأصل، ولا تُنشأ أي نسخة، ويظهر التعديل في «الصور» مثل أي تعديل آخر.\n\nكل شيء ما زال يجري على جهازك: لا حساب ولا رفع، وما تنظّفه ينتقل إلى «المحذوفة مؤخرًا» حيث يحتفظ به iOS نحو 30 يومًا.\n\nملاحظاتكم وبلاغاتكم مرحَّب بها فعلًا — رابط الدعم في صفحة App Store يصلني مباشرة.",
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
        "--allow-shared-urls",
        action="store_true",
        help=(
            "Allow non-English listings to fall back to the shared ALIKE_*_URL values. "
            "Without it, strict generation requires every locale's own overrides."
        ),
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


def description_with_links(
    description: str, privacy_url: str, terms_url: str, locale: str = "en-US"
) -> str:
    privacy_label, terms_label = LOCALE_LEGAL_LABELS.get(locale, (PRIVACY_LABEL, TERMS_LABEL))
    footer = f"{privacy_label}: {privacy_url}\n{terms_label}: {terms_url}"
    return f"{description.rstrip()}\n\n{footer}"


def locale_url_env_var(kind: str, apple_locale: str) -> str:
    """Name of the per-locale override for one URL kind, e.g. ALIKE_PRIVACY_URL_ZH_HANT."""
    return f"ALIKE_{kind}_URL_{apple_locale.upper().replace('-', '_')}"


def localized_url(base_url: str, kind: str, apple_locale: str) -> str:
    """Return the locale's own legal/support URL, falling back to the shared one.

    The fallback in the last line is not a supported configuration. It survives
    because `--allow-shared-urls` and `--allow-placeholder-urls` need it, and
    because this function has no way to tell which run it is in; on every other
    run `validate_localized_urls` fails before the bundle is used, naming the
    unset variable. An unconfigured `.env` therefore does not quietly produce
    English URLs for twelve listings any more — it produces a hard failure.

    The site publishes each locale's own pages — /uk/, /de/, /fr/, /es/,
    /pt-br/, /it/, /nl/, /pl/, /tr/, /zh-hant/, /ar/ — and all twelve non-English
    listings must point at them through their own
    ALIKE_{PRIVACY,TERMS,SUPPORT}_URL_<LOCALE> overrides, thirty-six in all.
    _ES_MX points at the same /es/ pages as _ES_ES on purpose: one Spanish page
    serves both listings, said explicitly rather than by falling through to
    English.
    """
    override = os.environ.get(locale_url_env_var(kind, apple_locale), "").strip()
    return override if override else base_url


def generate_metadata(privacy_url: str, support_url: str, terms_url: str, marketing_url: str) -> None:
    write_text(METADATA_ROOT / "copyright.txt", COPYRIGHT)
    write_text(METADATA_ROOT / "primary_category.txt", PRIMARY_CATEGORY)
    write_text(METADATA_ROOT / "secondary_category.txt", SECONDARY_CATEGORY)

    for mapping in UPLOAD_SAFE_LOCALES:
        values = METADATA[mapping.apple]
        locale_root = METADATA_ROOT / mapping.apple
        locale_privacy_url = localized_url(privacy_url, "PRIVACY", mapping.apple)
        locale_terms_url = localized_url(terms_url, "TERMS", mapping.apple)
        locale_support_url = localized_url(support_url, "SUPPORT", mapping.apple)
        write_text(locale_root / "name.txt", APP_NAME)
        write_text(locale_root / "subtitle.txt", values["subtitle"])
        write_text(
            locale_root / "description.txt",
            description_with_links(
                values["description"],
                locale_privacy_url,
                locale_terms_url,
                locale=mapping.apple,
            ),
        )
        write_text(locale_root / "keywords.txt", values["keywords"])
        write_text(locale_root / "promotional_text.txt", values["promotional_text"])
        write_text(locale_root / "release_notes.txt", values["release_notes"])
        write_text(locale_root / "privacy_url.txt", locale_privacy_url)
        write_text(locale_root / "support_url.txt", locale_support_url)
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

- Localized copy for all thirteen listing locales is defined in `tools/prepare_app_store_upload_bundle.py`: `en-US`, `uk`, `de-DE`, `fr-FR`, `es-ES`, `es-MX`, `pt-BR`, `it`, `nl-NL`, `pl`, `tr`, `zh-Hant`, `ar-SA`. They match the languages the app itself is translated into; the app's `es-419` maps onto App Store Connect's `es-MX`. Validation fails if `METADATA` and `UPLOAD_SAFE_LOCALES` ever disagree, and strict generation refuses to run if any `TODO:` marker is reintroduced.
- App Review contact and reviewer notes are generated into `metadata/review_information/*.txt` and uploaded automatically by Fastlane `deliver`.
- Edit tracked reviewer notes in `Docs/app-store-review-notes.txt`.
- Alike has no account and no sign-in, so `demo_user.txt` and `demo_password.txt` are intentionally empty.
- `marketing_url.txt` is written only when `ALIKE_MARKETING_URL` is set. The marketing URL is optional for Apple, and `deliver` leaves the App Store Connect value untouched when the file is absent.
- Every locale gets `ALIKE_PRIVACY_URL` / `ALIKE_TERMS_URL` / `ALIKE_SUPPORT_URL` unless it has its own override, suffixed with the App Store locale uppercased and `-` to `_`: `_UK`, `_DE_DE`, `_FR_FR`, `_ES_ES`, `_ES_MX`, `_PT_BR`, `_IT`, `_NL_NL`, `_PL`, `_TR`, `_ZH_HANT`, `_AR_SA`. The site publishes all twelve of those locales, so all thirty-six are required: strict generation fails on an unset override rather than falling back to the shared English URL, which would send a reader who was just reading localized App Store copy to an English privacy policy. `--allow-shared-urls` opts out deliberately. `_ES_MX` points at the same `/es/` pages as `_ES_ES`: one Spanish page serves both listings. Values are listed in `Docs/release-checklist.md` step 0. The description footer labels follow the locale on their own.
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
            _, locale_terms_label = LOCALE_LEGAL_LABELS.get(
                mapping.apple, (PRIVACY_LABEL, TERMS_LABEL)
            )
            if f"{locale_terms_label}:" not in description:
                errors.append(f"{description_path} is missing a {locale_terms_label} link")
            if TERMS_URL_PLACEHOLDER in description and not allow_placeholder_urls:
                errors.append(f"{description_path} still contains placeholder Terms of Use URL")
    return errors


def validate_localized_urls(allow_placeholder_urls: bool, allow_shared_urls: bool) -> list[str]:
    """Fail strict generation when a non-English listing would carry English legal URLs.

    The failure this exists to prevent, in the past tense because it can no
    longer happen: `localized_url` falls back to the shared ALIKE_*_URL when a
    locale has no override, and until this check that fallback was silent. With
    only the three base URLs set, generation and validation both passed while
    ten listings pointed German, Polish or Traditional Chinese readers at the
    English privacy policy, terms and support pages. Nothing in the bundle
    looked wrong, because a shared URL is indistinguishable from a deliberate
    one — and since the working `.env` is untracked by design, a clean release
    machine reproduced exactly that bundle. Release 1.1.0 was generated that way
    until the overrides were filled in by hand.

    Now every locale except en-US must set its own three overrides, and the
    emitted files have to match them. `--allow-shared-urls` opts out for a
    deliberate shared-URL run, and `--allow-placeholder-urls` (structural
    generation, no real URLs at all) skips the check the same way it skips the
    other URL rules. Neither flag reaches an upload path: `tools/text` and the
    Fastlane lanes do not accept them.

    es-MX is not an exception: it points at the same /es/ pages as es-ES, but it
    says so through its own overrides rather than by falling through to English.
    """
    if allow_placeholder_urls or allow_shared_urls:
        return []

    errors: list[str] = []
    base_urls = {
        "PRIVACY": os.environ.get("ALIKE_PRIVACY_URL", "").strip(),
        "TERMS": os.environ.get("ALIKE_TERMS_URL", "").strip(),
        "SUPPORT": os.environ.get("ALIKE_SUPPORT_URL", "").strip(),
    }
    emitted_files = {"PRIVACY": "privacy_url.txt", "SUPPORT": "support_url.txt"}

    for mapping in UPLOAD_SAFE_LOCALES:
        if mapping.apple == "en-US":
            continue
        for kind in ("PRIVACY", "TERMS", "SUPPORT"):
            variable = locale_url_env_var(kind, mapping.apple)
            override = os.environ.get(variable, "").strip()
            if not override:
                errors.append(
                    f"{variable} is unset, so the {mapping.apple} listing would reuse the shared "
                    f"{kind.title()} URL; set it (values in Docs/release-checklist.md step 0) or pass "
                    f"--allow-shared-urls"
                )
                continue
            if not override.startswith("https://"):
                errors.append(f"{variable} must use an https:// URL")
                continue

            # The override existing is not the same as the bundle carrying it —
            # a stale bundle validated with --validate-only would otherwise pass
            # on the strength of the environment alone.
            filename = emitted_files.get(kind)
            if filename is None:
                continue
            path = METADATA_ROOT / mapping.apple / filename
            emitted = path.read_text(encoding="utf-8").strip() if path.exists() else ""
            if emitted and emitted != override:
                errors.append(f"{path} is {emitted}, not the {variable} value {override}")
            elif emitted and emitted == base_urls[kind] and base_urls[kind]:
                errors.append(f"{path} still carries the shared {kind.title()} URL")

        # The Terms URL never gets a file of its own; it reaches the listing
        # through the footer appended to every description.
        terms_override = os.environ.get(locale_url_env_var("TERMS", mapping.apple), "").strip()
        description_path = METADATA_ROOT / mapping.apple / "description.txt"
        if terms_override and description_path.exists():
            description = description_path.read_text(encoding="utf-8")
            if terms_override not in description:
                errors.append(f"{description_path} does not link {terms_override}")
    return errors


def validate_locale_folder_names() -> list[str]:
    # Fastlane `deliver` (`Deliver::Loader.language_folders`) accepts only a
    # fixed set of locale folder names and raises "Unsupported directory
    # name(s)" for anything outside it — it-IT, pl-PL and tr-TR are the ones
    # this project has actually hit. Checking UPLOAD_SAFE_LOCALES against
    # DELIVER_ACCEPTED_LOCALES here catches a region-qualified locale at
    # generation time instead of at upload time, with no fastlane invocation
    # needed to do it.
    errors: list[str] = []
    for mapping in UPLOAD_SAFE_LOCALES:
        if mapping.apple not in DELIVER_ACCEPTED_LOCALES:
            errors.append(
                f"{mapping.apple} (source {mapping.source}) is not a locale folder name Fastlane deliver "
                f"accepts; see DELIVER_ACCEPTED_LOCALES"
            )
    # review_information/ sits alongside the locale folders under
    # METADATA_ROOT but is not one itself, so it is excluded here rather than
    # flagged as an unsupported locale.
    for locale_root in (METADATA_ROOT, SCREENSHOTS_ROOT):
        if not locale_root.exists():
            continue
        for path in sorted(locale_root.iterdir()):
            if not path.is_dir() or path.name == "review_information":
                continue
            if path.name not in DELIVER_ACCEPTED_LOCALES:
                errors.append(
                    f"{path} is not a locale folder name Fastlane deliver accepts; see DELIVER_ACCEPTED_LOCALES"
                )
    return errors


def validate_metadata() -> list[str]:
    errors: list[str] = []
    # METADATA and UPLOAD_SAFE_LOCALES have to describe the same set of
    # localizations. A locale in one and not the other is either copy that
    # silently never ships or a KeyError deep inside generation.
    mapped_locales = {mapping.apple for mapping in UPLOAD_SAFE_LOCALES}
    for locale in sorted(mapped_locales - METADATA.keys()):
        errors.append(f"{locale} is in UPLOAD_SAFE_LOCALES but has no METADATA entry")
    for locale in sorted(METADATA.keys() - mapped_locales):
        errors.append(f"{locale} has METADATA copy but is not in UPLOAD_SAFE_LOCALES, so it never ships")

    # LOCALE_LEGAL_LABELS needs the same treatment, and for a subtler reason.
    # description_with_links() falls back to the English labels for an unlisted
    # locale, and validate_urls() looks up that same fallback, so a missing row
    # produces a listing that reads "Privacy Policy" in the middle of Polish
    # prose and passes every other check. Only this comparison catches it.
    for locale in sorted(mapped_locales - LOCALE_LEGAL_LABELS.keys()):
        errors.append(f"{locale} is in UPLOAD_SAFE_LOCALES but has no LOCALE_LEGAL_LABELS row, so its legal links would read in English")
    for locale in sorted(LOCALE_LEGAL_LABELS.keys() - mapped_locales):
        errors.append(f"{locale} has LOCALE_LEGAL_LABELS but is not in UPLOAD_SAFE_LOCALES, so the labels are never used")

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
        if keywords_path.exists() and len(keywords_path.read_text(encoding="utf-8").strip()) > APP_KEYWORDS_MAX_LENGTH:
            errors.append(f"{keywords_path} exceeds {APP_KEYWORDS_MAX_LENGTH} characters")
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


def storekit_expected_locales() -> list[str]:
    """The Alike.storekit spellings of every locale the listing ships.

    The IAP payload is derived from Alike.storekit, so a listing locale missing
    there is a locale whose subscription name and description never reach App
    Store Connect. Nothing said so: the payload carried whatever the file held,
    and validate_iap_localizations() checked the shape of the localizations
    present rather than which ones were.
    """
    missing_mapping = [
        mapping.apple for mapping in UPLOAD_SAFE_LOCALES if mapping.apple not in APP_STORE_TO_STOREKIT_LOCALE
    ]
    if missing_mapping:
        raise SystemExit(
            f"STOREKIT_TO_APP_STORE_LOCALE has no StoreKit spelling for {', '.join(missing_mapping)}"
        )
    return [APP_STORE_TO_STOREKIT_LOCALE[mapping.apple] for mapping in UPLOAD_SAFE_LOCALES]


def validate_storekit_locale_coverage(label: str, localizations: list[dict]) -> list[str]:
    """Every listing locale is localized here, and nothing else is."""
    expected = storekit_expected_locales()
    present = [localization.get("locale", "") for localization in localizations]
    errors: list[str] = []

    missing = [locale for locale in expected if locale not in present]
    if missing:
        errors.append(
            f"{label} is missing localizations for {', '.join(missing)}; the listing ships "
            f"{len(expected)} locales, {STOREKIT_PATH.name} carries {len(present)}"
        )

    unexpected = sorted({locale for locale in present if locale not in expected})
    if unexpected:
        errors.append(
            f"{label} localizes {', '.join(unexpected)}, which the listing does not ship; "
            "add the locale to UPLOAD_SAFE_LOCALES or remove it here"
        )

    duplicates = sorted({locale for locale in present if present.count(locale) > 1})
    if duplicates:
        errors.append(f"{label} localizes {', '.join(duplicates)} more than once")

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
        errors.extend(
            validate_storekit_locale_coverage(
                label=f"Subscription group {group.get('name')}",
                localizations=localizations,
            )
        )
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


# A static IAP description cannot know whether the customer in front of it is
# eligible for the trial. StoreKit decides that per subscription group, a
# customer who already used the Alike Pro trial never gets another one, and
# Docs/legal/subscription-disclosure.md calls the "for eligible new subscribers"
# hedge load-bearing for exactly that reason. The hedge does not fit: App Store
# Connect caps the description at 45 characters, and "Unlock every Pro tool.
# First 7 days free." already spends 41 of them. So the trial is promised only
# where eligibility is known — the paywall — and these descriptions must not
# claim it. The tokens below are the trial vocabulary of the thirteen shipped
# locales; the copy that replaced the claims avoids all of them. The Arabic pair
# are stems rather than words: مجاني/مجانية and تجربة/تجريبية all start there,
# and casefold() leaves Arabic unchanged, so the stem is the whole match.
IAP_TRIAL_CLAIM_TOKENS = (
    "free", "trial",
    "gratis", "gratuit", "gratuita", "gratuito", "grátis", "offert",
    "darmo", "bezpłat", "ücretsiz", "deneme",
    "безкоштов", "безплат",
    "免費", "試用",
    "مجان", "تجرب",
)


def trial_claim_tokens(text: str) -> list[str]:
    lowered = text.casefold()
    return [token for token in IAP_TRIAL_CLAIM_TOKENS if token in lowered]


def validate_iap_product_localizations(product_id: str, localizations: list[dict]) -> list[str]:
    errors: list[str] = []
    if not localizations:
        return [f"{product_id} has no localizations"]

    errors.extend(validate_storekit_locale_coverage(label=product_id, localizations=localizations))

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
        claims = trial_claim_tokens(description)
        if claims:
            errors.append(
                f"{product_id} {locale} description promises a free trial ({', '.join(claims)}); "
                f"eligibility is decided by StoreKit and cannot be hedged inside "
                f"{IAP_DESCRIPTION_MAX_LENGTH} characters, so the trial belongs on the paywall only "
                f"(Docs/legal/subscription-disclosure.md)"
            )
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


def validate_bundle(allow_placeholder_urls: bool, allow_shared_urls: bool = False) -> None:
    errors = []
    errors.extend(validate_locale_folder_names())
    errors.extend(validate_metadata())
    errors.extend(validate_urls(allow_placeholder_urls))
    errors.extend(validate_localized_urls(allow_placeholder_urls, allow_shared_urls))
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

    validate_bundle(
        allow_placeholder_urls=args.allow_placeholder_urls,
        allow_shared_urls=args.allow_shared_urls,
    )
    print(f"Prepared App Store upload bundle at {STORE_UPLOAD_ROOT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
