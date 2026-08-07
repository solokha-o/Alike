# Alike Pro Subscription Disclosure Copy

This file is the source of truth for the subscription disclosure shown on the
paywall. The strings below must stay byte-identical to the corresponding entries
in `Alike/Alike/Localizable.xcstrings`. When you change one, change both.

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

### Paragraph 2 — trial and cancellation

**EN**

> The yearly plan includes a 7-day free trial for eligible new subscribers. Billing starts when the trial ends unless you cancel at least 24 hours before then. Manage or cancel anytime in iOS Settings.

**UK**

> Річний план містить 7 днів безкоштовно для нових підписників, які мають на це право. Оплата починається після завершення пробного періоду, якщо ви не скасуєте підписку щонайменше за 24 години до цього. Керувати підпискою або скасувати її можна будь-коли в Налаштуваннях iOS.

The phrase "for eligible new subscribers" is load-bearing. Trial eligibility is
decided by StoreKit per subscription group, and a customer who already used the
Alike Pro trial will not get another one. The copy must not promise a trial that
StoreKit will refuse.

### Link row

| Label (EN) | Label (UK) | Destination |
| --- | --- | --- |
| Privacy Policy | Політика конфіденційності | `SubscriptionConfiguration.legalLinks.privacyPolicy` |
| Terms of Use | Умови використання | `SubscriptionConfiguration.legalLinks.termsOfUse` |

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
