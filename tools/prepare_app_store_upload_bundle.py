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


# The listing ships the same seven languages the app itself is translated into.
# `source` is the app's own language code, which is also the directory name
# under Docs/images/; `apple` is the App Store Connect locale, which is not the
# same string. es-419 is the app's Latin American Spanish and maps onto App
# Store Connect's es-MX slot, the only Latin American Spanish the store offers.
#
# Adding a locale means four things, and a missing one is a validation error
# rather than a silent gap: a mapping here, an entry in METADATA, a row in
# LOCALE_LEGAL_LABELS, and a deck in Docs/images/<source>/.
UPLOAD_SAFE_LOCALES = (
    LocaleMapping(source="en-US", apple="en-US"),
    LocaleMapping(source="uk", apple="uk"),
    LocaleMapping(source="de", apple="de-DE"),
    LocaleMapping(source="fr", apple="fr-FR"),
    LocaleMapping(source="es", apple="es-ES"),
    LocaleMapping(source="es-419", apple="es-MX"),
    LocaleMapping(source="pt-BR", apple="pt-BR"),
)

STOREKIT_TO_APP_STORE_LOCALE = {
    "en_US": "en-US",
    "uk": "uk",
    "de_DE": "de-DE",
    "fr_FR": "fr-FR",
    "es_ES": "es-ES",
    "es_MX": "es-MX",
    "pt_BR": "pt-BR",
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
- Seven languages: English, Ukrainian, German, French, Spanish, Latin American Spanish and Brazilian Portuguese. Full Dark Mode support.

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
- Сім мов: англійська, українська, німецька, французька, іспанська, латиноамериканська іспанська та бразильська португальська. Повна темна тема.

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
- Sieben Sprachen: Englisch, Ukrainisch, Deutsch, Französisch, Spanisch, Lateinamerikanisches Spanisch und Brasilianisches Portugiesisch. Voller Dark Mode.

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
- Sept langues : anglais, ukrainien, allemand, français, espagnol, espagnol d'Amérique latine et portugais brésilien. Mode sombre complet.

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
- Siete idiomas: inglés, ucraniano, alemán, francés, español, español de Latinoamérica y portugués de Brasil. Modo oscuro completo.

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
- Siete idiomas: inglés, ucraniano, alemán, francés, español, español de Latinoamérica y portugués de Brasil. Modo oscuro completo.

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
- Sete idiomas: inglês, ucraniano, alemão, francês, espanhol, espanhol da América Latina e português do Brasil. Modo escuro completo.

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
        "release_notes": "First release of Alike.\n\nScan your library for visually similar photos, review each group with a Best Shot already picked, and clear the rest. Every scan runs on your device — no account, no uploads, and deletion always goes to Recently Deleted, where iOS keeps your photos for about 30 days.\n\nIn this first version:\n- Three sensitivity levels, from near-identical shots to a wider net\n- Best Shot detection, so every group opens with a sensible keeper selected\n- Keep Best Only, Select All Except Best, or pick by hand\n- Review badges that track what is new, in review, reviewed, and what needs another look after your library changes\n- Progress, Selected and Estimated Savings while you work, plus cleanup history by month\n- A searchable guide inside the app, one tap from the Scanner\n- Optional cleanup reminders as local notifications\n- Seven languages: English, Ukrainian, German, French, Spanish, Latin American Spanish and Brazilian Portuguese, with full Dark Mode support\n\nAlike Pro adds unlimited scans, batch cleanup, screenshot and blurred-photo cleanup, advanced filters, and custom cleanup reminders. The yearly plan starts with 7 days free for eligible new subscribers.\n\nThank you for trying Alike. Feedback and bug reports are genuinely welcome — the support link on the App Store page reaches me directly.",
    },
    "uk": {
        "subtitle": "Знайти й прибрати схожі фото",
        "description": UK_DESCRIPTION,
        # Same rule as en-US: the uk subtitle already covers "схожі" and "фото".
        "keywords": "дублікати,очищення,галерея,сховище,місце,скріншоти,розмиті,копії,знімки,видалити",
        "promotional_text": "Alike групує схожі фотографії, обирає найкращий знімок і допомагає прибрати решту — усе на вашому iPhone. Alike Pro: 7 днів безкоштовно на річному плані.",
        "release_notes": "Перший випуск Alike.\n\nСкануйте медіатеку на візуально схожі фото, переглядайте кожну групу з уже обраним найкращим знімком і прибирайте решту. Кожне сканування виконується на пристрої — без облікового запису й без вивантаження, а прибрані фото завжди потрапляють до «Нещодавно видалених», де iOS зберігає їх близько 30 днів.\n\nУ цій першій версії:\n- Три рівні чутливості — від майже ідентичних знімків до ширшого пошуку\n- Вибір найкращого знімка: група відкривається з уже обраним варіантом залишити\n- «Залишити лише найкраще», «Обрати все крім найкращого» або вибір вручну\n- Позначки перегляду: що нове, що в роботі, що переглянуто і що варто передивитися після змін у медіатеці\n- Прогрес, «Обрано» й «Орієнтовна економія» під час роботи, а також історія прибирання за місяцями\n- Довідка з пошуком просто в застосунку, за один дотик зі «Сканера»\n- Необовʼязкові нагадування про прибирання як локальні сповіщення\n- Сім мов: англійська, українська, німецька, французька, іспанська, латиноамериканська іспанська та бразильська португальська, з повною підтримкою темної теми\n\nAlike Pro додає необмежені сканування, пакетне прибирання, прибирання знімків екрана та розмитих фото, розширені фільтри й власні нагадування. Річний план починається з 7 днів безкоштовно для нових підписників, які мають на це право.\n\nДякуємо, що спробували Alike. Відгуки та повідомлення про помилки дуже вітаються — посилання на підтримку на сторінці App Store веде безпосередньо до розробника.",
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
        "release_notes": "Erste Version von Alike.\n\nDurchsuche deine Mediathek nach visuell ähnlichen Fotos, prüfe jede Gruppe mit einer bereits gewählten besten Aufnahme und räume den Rest auf. Jeder Scan läuft auf deinem Gerät — kein Konto, keine Uploads, und Gelöschtes geht immer zu „Zuletzt gelöscht“, wo iOS deine Fotos rund 30 Tage aufbewahrt.\n\nIn dieser ersten Version:\n- Drei Empfindlichkeitsstufen, von fast identischen Aufnahmen bis zu einem weiteren Netz\n- Erkennung der besten Aufnahme, sodass jede Gruppe mit einer sinnvollen Vorauswahl öffnet\n- Nur die beste behalten, alle außer der besten auswählen oder von Hand wählen\n- Prüfstatus dafür, was neu ist, in Prüfung, geprüft und was nach Änderungen an deiner Mediathek noch einmal angesehen werden sollte\n- Fortschritt, Ausgewählt und geschätzte Ersparnis während der Arbeit, dazu ein Aufräum-Verlauf nach Monaten\n- Eine durchsuchbare Anleitung in der App, einen Tipp vom Scanner entfernt\n- Optionale Aufräum-Erinnerungen als lokale Mitteilungen\n- Sieben Sprachen: Englisch, Ukrainisch, Deutsch, Französisch, Spanisch, Lateinamerikanisches Spanisch und Brasilianisches Portugiesisch, mit vollem Dark Mode\n\nAlike Pro ergänzt unbegrenzte Scans, Stapel-Aufräumen, das Aufräumen von Bildschirmfotos und unscharfen Fotos, erweiterte Filter und eigene Aufräum-Erinnerungen. Der Jahresplan beginnt mit 7 Tagen gratis für berechtigte neue Abonnenten.\n\nDanke, dass du Alike ausprobierst. Rückmeldungen und Fehlerberichte sind ausdrücklich willkommen — der Support-Link auf der App-Store-Seite erreicht mich direkt.",
    },
    "fr-FR": {
        "subtitle": "Nettoyer les photos similaires",
        "description": FR_FR_DESCRIPTION,
        "keywords": "doublons,double,images,stockage,espace,galerie,capture,flou,supprimer,pellicule,ranger",
        "promotional_text": "Alike regroupe les photos qui se ressemblent, choisit la meilleure et vous aide à nettoyer le reste, sur votre iPhone. Alike Pro : 7 jours offerts en formule annuelle.",
        "release_notes": "Première version d'Alike.\n\nAnalysez votre photothèque à la recherche de photos visuellement similaires, examinez chaque groupe avec une meilleure photo déjà choisie, et nettoyez le reste. Chaque analyse se fait sur votre appareil — aucun compte, aucun envoi, et la suppression passe toujours par « Supprimés récemment », où iOS conserve vos photos environ 30 jours.\n\nDans cette première version :\n- Trois niveaux de sensibilité, des photos presque identiques à un filet plus large\n- Détection de la meilleure photo : chaque groupe s'ouvre sur un choix raisonnable à garder\n- Ne garder que la meilleure, tout sélectionner sauf la meilleure, ou choisir à la main\n- Des badges d'examen qui suivent ce qui est nouveau, en cours, examiné, et ce qui mérite un second regard après une modification de votre photothèque\n- Progression, Sélectionnées et Économie estimée pendant que vous travaillez, plus un historique de nettoyage par mois\n- Un mode d'emploi consultable dans l'app, à un geste du Scanner\n- Des rappels de nettoyage facultatifs, en notifications locales\n- Sept langues : anglais, ukrainien, allemand, français, espagnol, espagnol d'Amérique latine et portugais brésilien, avec un mode sombre complet\n\nAlike Pro ajoute les analyses illimitées, le nettoyage groupé, le nettoyage des captures d'écran et des photos floues, les filtres avancés et des rappels personnalisés. La formule annuelle commence par 7 jours offerts pour les nouveaux abonnés éligibles.\n\nMerci d'essayer Alike. Vos retours et vos rapports de bugs sont sincèrement bienvenus — le lien d'assistance sur la page App Store me parvient directement.",
    },
    "es-ES": {
        "subtitle": "Encuentra y limpia duplicados",
        "description": ES_ES_DESCRIPTION,
        "keywords": "fotos,repetidas,similares,almacenamiento,espacio,galería,captura,borrosas,borrar,carrete",
        "promotional_text": "Alike agrupa las fotos que se parecen, elige la mejor toma de cada grupo y te ayuda a limpiar el resto, en tu iPhone. Alike Pro: 7 días gratis en el plan anual.",
        "release_notes": "Primera versión de Alike.\n\nAnaliza tu fototeca en busca de fotos visualmente similares, revisa cada grupo con una mejor toma ya elegida y limpia el resto. Cada análisis se ejecuta en tu dispositivo: sin cuenta, sin subidas, y lo que se elimina pasa siempre a «Eliminados recientemente», donde iOS guarda tus fotos unos 30 días.\n\nEn esta primera versión:\n- Tres niveles de sensibilidad, desde tomas casi idénticas hasta una red más amplia\n- Detección de la mejor toma, para que cada grupo se abra con una opción razonable ya seleccionada\n- Quedarte solo con la mejor, seleccionar todas menos la mejor o elegir a mano\n- Indicadores de revisión que siguen lo nuevo, lo que está en revisión, lo revisado y lo que conviene mirar otra vez tras un cambio en tu fototeca\n- Progreso, Seleccionadas y Ahorro estimado mientras trabajas, además del historial de limpieza por meses\n- Instrucciones de uso con búsqueda dentro de la app, a un toque del Analizador\n- Recordatorios de limpieza opcionales, como notificaciones locales\n- Siete idiomas: inglés, ucraniano, alemán, francés, español, español de Latinoamérica y portugués de Brasil, con modo oscuro completo\n\nAlike Pro añade análisis ilimitados, limpieza por lotes, limpieza de capturas de pantalla y fotos borrosas, filtros avanzados y recordatorios personalizados. El plan anual empieza con 7 días gratis para nuevos suscriptores que cumplan los requisitos.\n\nGracias por probar Alike. Los comentarios y los informes de errores son muy bienvenidos: el enlace de soporte de la página de App Store llega directamente a mí.",
    },
    "es-MX": {
        "subtitle": "Encuentra y limpia duplicados",
        "description": ES_MX_DESCRIPTION,
        "keywords": "fotos,iguales,liberar espacio,almacenamiento,celular,galería,capturas,borrosas,eliminar",
        "promotional_text": "Alike agrupa las fotos que se parecen, elige la mejor toma de cada grupo y te ayuda a limpiar el resto, en tu iPhone. Alike Pro: 7 días gratis en el plan anual.",
        "release_notes": "Primera versión de Alike.\n\nAnaliza tu fototeca en busca de fotos visualmente similares, revisa cada grupo con una mejor toma ya elegida y limpia el resto. Cada análisis se ejecuta en tu dispositivo: sin cuenta, sin subidas, y lo que se elimina pasa siempre a «Eliminados recientemente», donde iOS guarda tus fotos unos 30 días.\n\nEn esta primera versión:\n- Tres niveles de sensibilidad, desde tomas casi idénticas hasta una red más amplia\n- Detección de la mejor toma, para que cada grupo se abra con una opción razonable ya seleccionada\n- Quedarte solo con la mejor, seleccionar todas menos la mejor o elegir a mano\n- Indicadores de revisión que siguen lo nuevo, lo que está en revisión, lo revisado y lo que conviene mirar otra vez después de un cambio en tu fototeca\n- Progreso, Seleccionadas y Ahorro estimado mientras trabajas, además del historial de limpieza por meses\n- Instrucciones de uso con búsqueda dentro de la app, a un toque del Analizador\n- Recordatorios de limpieza opcionales, como notificaciones locales\n- Siete idiomas: inglés, ucraniano, alemán, francés, español, español de Latinoamérica y portugués de Brasil, con modo oscuro completo\n\nAlike Pro agrega análisis ilimitados, limpieza por lotes, limpieza de capturas de pantalla y fotos borrosas, filtros avanzados y recordatorios personalizados. El plan anual empieza con 7 días gratis para nuevos suscriptores que cumplan los requisitos.\n\nGracias por probar Alike. Los comentarios y los reportes de errores son muy bienvenidos: el enlace de soporte de la página de App Store llega directamente a mí.",
    },
    "pt-BR": {
        "subtitle": "Encontre e limpe duplicadas",
        "description": PT_BR_DESCRIPTION,
        "keywords": "fotos,repetidas,iguais,armazenamento,liberar espaço,galeria,captura,desfocadas,apagar",
        "promotional_text": "O Alike agrupa as fotos parecidas, escolhe a melhor de cada grupo e ajuda você a limpar o resto, no seu iPhone. Alike Pro: 7 dias grátis no plano anual.",
        "release_notes": "Primeira versão do Alike.\n\nAnalise sua fototeca em busca de fotos visualmente parecidas, revise cada grupo com uma melhor foto já escolhida e limpe o resto. Cada análise roda no seu dispositivo — sem conta, sem envios, e o que sai vai sempre para «Apagados recentemente», onde o iOS guarda suas fotos por cerca de 30 dias.\n\nNesta primeira versão:\n- Três níveis de sensibilidade, das fotos quase idênticas até uma rede mais ampla\n- Detecção da melhor foto, para que cada grupo abra com uma escolha sensata já selecionada\n- Manter só a melhor, selecionar todas menos a melhor ou escolher na mão\n- Selos de revisão que acompanham o que é novo, o que está em revisão, o que foi revisado e o que merece um segundo olhar depois de uma mudança na sua fototeca\n- Progresso, Selecionadas e Economia estimada enquanto você trabalha, além do histórico de limpeza por mês\n- Instruções de uso com busca dentro do app, a um toque do Analisador\n- Lembretes de limpeza opcionais, como notificações locais\n- Sete idiomas: inglês, ucraniano, alemão, francês, espanhol, espanhol da América Latina e português do Brasil, com modo escuro completo\n\nO Alike Pro adiciona análises ilimitadas, limpeza em lote, limpeza de capturas de tela e de fotos desfocadas, filtros avançados e lembretes personalizados. O plano anual começa com 7 dias grátis para novos assinantes elegíveis.\n\nObrigado por experimentar o Alike. Comentários e relatos de erros são muito bem-vindos — o link de suporte na página da App Store chega direto a mim.",
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


def description_with_links(
    description: str, privacy_url: str, terms_url: str, locale: str = "en-US"
) -> str:
    privacy_label, terms_label = LOCALE_LEGAL_LABELS.get(locale, (PRIVACY_LABEL, TERMS_LABEL))
    footer = f"{privacy_label}: {privacy_url}\n{terms_label}: {terms_url}"
    return f"{description.rstrip()}\n\n{footer}"


def localized_url(base_url: str, kind: str, apple_locale: str) -> str:
    """Return the locale's own legal/support URL, falling back to the shared one.

    The site publishes Ukrainian pages at /uk/, so the uk listing should not send
    Ukrainian readers to English text. Set ALIKE_PRIVACY_URL_UK,
    ALIKE_TERMS_URL_UK or ALIKE_SUPPORT_URL_UK to point a locale somewhere else;
    with none of them set, every locale keeps the single shared URL it used
    before, so an unconfigured .env behaves exactly as it did.

    The same holds for the Tier 1 locales added alongside the app's own
    translations: ALIKE_*_URL_DE_DE, _FR_FR, _ES_ES, _ES_MX and _PT_BR. Until
    the site publishes those landing pages, leaving them unset is the intended
    state — all five fall back to the shared English URL rather than pointing at
    a page that does not exist.
    """
    suffix = apple_locale.upper().replace("-", "_")
    override = os.environ.get(f"ALIKE_{kind}_URL_{suffix}", "").strip()
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

- Localized copy for all seven listing locales is defined in `tools/prepare_app_store_upload_bundle.py`: `en-US`, `uk`, `de-DE`, `fr-FR`, `es-ES`, `es-MX`, `pt-BR`. They match the languages the app itself is translated into; the app's `es-419` maps onto App Store Connect's `es-MX`. Validation fails if `METADATA` and `UPLOAD_SAFE_LOCALES` ever disagree, and strict generation refuses to run if any `TODO:` marker is reintroduced.
- App Review contact and reviewer notes are generated into `metadata/review_information/*.txt` and uploaded automatically by Fastlane `deliver`.
- Edit tracked reviewer notes in `Docs/app-store-review-notes.txt`.
- Alike has no account and no sign-in, so `demo_user.txt` and `demo_password.txt` are intentionally empty.
- `marketing_url.txt` is written only when `ALIKE_MARKETING_URL` is set. The marketing URL is optional for Apple, and `deliver` leaves the App Store Connect value untouched when the file is absent.
- Every locale gets `ALIKE_PRIVACY_URL` / `ALIKE_TERMS_URL` / `ALIKE_SUPPORT_URL` unless it has its own override: `ALIKE_PRIVACY_URL_UK`, `ALIKE_TERMS_URL_UK`, `ALIKE_SUPPORT_URL_UK` (the suffix is the App Store locale, uppercased, `-` to `_`). The site publishes Ukrainian pages under `/uk/`, so set these three or the uk listing sends Ukrainian readers to English legal text. The Tier 1 locales use the same three variables suffixed `_DE_DE`, `_FR_FR`, `_ES_ES`, `_ES_MX` and `_PT_BR`; until the site publishes those pages, leaving them unset is correct and all five fall back to the shared English URL. The description footer labels follow the locale on their own.
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
