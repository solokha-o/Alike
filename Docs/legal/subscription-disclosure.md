# Alike Pro Subscription Disclosure Copy

This file is the source of truth for the subscription disclosure shown on the
paywall. The strings below must stay byte-identical to the corresponding entries
in `Packages/Purchases/Sources/PurchasesUI/Resources/Localizable.xcstrings` — the
task 39 split moved them out of the app catalog. When you change one, change both.

`PurchasesUITests/SubscriptionDisclosureTests` asserts that match, in every
shipped language, so a locale that drifts fails the suite rather than App Review.

Product facts come from `Docs/Subscriptions.md` and
`Alike/Configuration/Alike.storekit`.

## What App Review expects

App Store Review Guideline 3.1.2 requires an auto-renewable subscription paywall
to show, before purchase:

| Requirement | Where Alike shows it |
| --- | --- |
| Subscription title | Plan card, from StoreKit `displayName` |
| Duration of a period | Plan card, "Billed yearly" / "Billed monthly" |
| Price, and price per period | Plan card, from StoreKit `displayPrice` |
| Free trial duration and what follows | Disclosure block, second paragraph |
| Auto-renewal and how to cancel | Disclosure block, first and second paragraphs |
| Functional Privacy Policy link | Disclosure block link row |
| Functional Terms of Use link | Disclosure block link row |

Prices and plan names always come from StoreKit at runtime so they are correct
per storefront. Never hardcode a price in UI copy.

## Disclosure block

Rendered by `disclosure` in
`Packages/Purchases/Sources/PurchasesUI/SubscriptionPaywallView.swift`.

### Paragraph 1 — renewal and billing

**EN**

> Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple Account.

**UK**

> Підписка поновлюється автоматично, якщо її не скасувати щонайменше за 24 години до завершення поточного періоду. Оплата стягується з вашого облікового запису Apple.

**ES-419**

> Las suscripciones se renuevan automáticamente a menos que se cancelen al menos 24 horas antes de que finalice el periodo actual. El pago se carga a tu cuenta de Apple.

**ES**

> Las suscripciones se renuevan automáticamente a menos que se cancelen al menos 24 horas antes de que finalice el periodo actual. El pago se carga a tu cuenta de Apple.

**PT-BR**

> As assinaturas são renovadas automaticamente, a menos que sejam canceladas pelo menos 24 horas antes do fim do período atual. A cobrança é feita na sua conta Apple.

**DE**

> Abos verlängern sich automatisch, sofern sie nicht mindestens 24 Stunden vor Ende des aktuellen Zeitraums gekündigt werden. Die Zahlung wird über deinen Apple-Account abgerechnet.

**FR**

> Les abonnements sont renouvelés automatiquement, sauf résiliation au moins 24 heures avant la fin de la période en cours. Le paiement est débité de votre compte Apple.

### Paragraph 2 — trial and cancellation

**EN**

> The yearly plan includes a 7-day free trial for eligible new subscribers. Billing starts when the trial ends unless you cancel at least 24 hours before then. Manage or cancel anytime in iOS Settings.

**UK**

> Річний план містить 7 днів безкоштовно для нових підписників, які мають на це право. Оплата починається після завершення пробного періоду, якщо ви не скасуєте підписку щонайменше за 24 години до цього. Керувати підпискою або скасувати її можна будь-коли в Налаштуваннях iOS.

**ES-419**

> El plan anual incluye una prueba gratuita de 7 días para los nuevos suscriptores que cumplan los requisitos. El cobro empieza cuando termina la prueba, a menos que canceles al menos 24 horas antes. Puedes gestionar o cancelar la suscripción cuando quieras en Configuración de iOS.

**ES**

> El plan anual incluye una prueba gratuita de 7 días para los nuevos suscriptores que cumplan los requisitos. El cobro empieza cuando termina la prueba, a menos que canceles al menos 24 horas antes. Puedes gestionar o cancelar la suscripción cuando quieras en Ajustes de iOS.

**PT-BR**

> O plano anual inclui 7 dias de teste grátis para novos assinantes qualificados. A cobrança começa quando o teste termina, a menos que você cancele pelo menos 24 horas antes. Gerencie ou cancele quando quiser nos Ajustes do iOS.

**DE**

> Der Jahresplan enthält eine 7-tägige kostenlose Testphase für berechtigte neue Abonnentinnen und Abonnenten. Die Abrechnung beginnt mit dem Ende der Testphase, sofern du nicht mindestens 24 Stunden vorher kündigst. Du kannst dein Abo jederzeit in den iOS-Einstellungen verwalten oder kündigen.

**FR**

> La formule annuelle comprend un essai gratuit de 7 jours pour les nouveaux abonnés éligibles. La facturation commence à la fin de l’essai, sauf résiliation au moins 24 heures avant. Vous pouvez gérer ou résilier votre abonnement à tout moment dans les Réglages iOS.

The phrase "for eligible new subscribers" is load-bearing. Trial eligibility is
decided by StoreKit per subscription group, and a customer who already used the
Alike Pro trial will not get another one. The copy must not promise a trial that
StoreKit will refuse. Every locale above carries the same hedge — "que cumplan los
requisitos", "qualificados", "berechtigte", "éligibles" — and a translation pass
must not smooth it away.

### Link row

| Locale | Privacy Policy | Terms of Use |
| --- | --- | --- |
| `en` | Privacy Policy | Terms of Use |
| `uk` | Політика конфіденційності | Умови використання |
| `es-419` | Política de privacidad | Términos de uso |
| `es` | Política de privacidad | Términos de uso |
| `pt-BR` | Política de Privacidade | Termos de Uso |
| `de` | Datenschutzrichtlinie | Nutzungsbedingungen |
| `fr` | Politique de confidentialité | Conditions d’utilisation |

Destinations are `SubscriptionConfiguration.legalLinks.privacyPolicy` and
`.termsOfUse`. Both point at the same English URLs in every locale. The linked
pages are no longer English-only — the site publishes `en`, `uk`, `de`, `fr`,
`es` and `pt-BR` — but the *in-app* links are a single shared constant and stay
on the English pages, which Review accepts as long as the links work. What does
follow the reader's language is the App Store listing: `localized_url()` in
`tools/prepare_app_store_upload_bundle.py` sends each locale's `privacy_url.txt`
and `support_url.txt` to its own pages.

The two paragraphs above are also the source for the site's own pricing section.
`_data/<locale>.yml` in `alikeapp/alikeapp.github.io` carries them byte-for-byte
under `pricing.disclosure_renewal` and `pricing.disclosure_trial`, so a wording
change here is a three-place change: this file, the catalog, and the site.

`SubscriptionDisclosureTests` pins the catalog against this file. Nothing could
pin the site, because it is a separate repository and neither side's tests can
see both. `tools/check_site_legal_parity.py` closes that gap — it reads the site
checkout next to this one and fails on any locale that has drifted:

```sh
tools/check_site_legal_parity.py --require
```

Use `--require` whenever the answer is meant to gate something. Bare, the tool
skips and exits 0 when the site checkout is absent, which is right for an
incidental local run and wrong for a release step: it would report success
having compared nothing.

Both links are injected once in `RootView` via `.subscriptionLegalLinks(...)`
and read from the environment, so every paywall entry point — Scanner, Details,
and Settings — shows the same URLs. The same values back the Legal section in
Settings.

## Known gap

The plan cards do not show a per-plan trial badge, and
`SubscriptionPlan.configuredTrialDays` is not surfaced in the UI. The disclosure
paragraph covers the requirement in prose, which is compliant, but a badge on
the yearly card would be clearer. Doing it correctly requires plumbing StoreKit's
`isEligibleForIntroOffer` through `StoreKitClient` and `SubscriptionProduct` so
ineligible customers are never shown trial copy.
