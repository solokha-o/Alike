# Alike Legal Copy

Source of truth for Alike's public legal documents and the paywall subscription
disclosure.

```
Docs/legal/
├── README.md                     this file — the runbook
└── subscription-disclosure.md    paywall disclosure copy, all thirteen locales

alikeapp/alikeapp.github.io       the published pages themselves (separate repo)
├── privacy.md  terms.md  support.md  index.md        en, at the root
├── uk/ de/ fr/ es/ pt-br/ it/ nl/ pl/ tr/ zh-hant/ ar/  the same four per locale
└── scripts/check-site.sh                             the build gate
```

The site publishes twelve locales — `en`, `uk`, `de`, `fr`, `es`, `pt-BR`, `it`,
`nl`, `pl`, `tr`, `zh-Hant`, `ar` — against thirteen App Store listings. `es` is one page
serving both `es-ES` and `es-MX`: the legal copy does not need the regional
vocabulary split, so `/es/` carries the Spain wording and advertises
`hreflang="es-419"` for the Latin American storefront.

The legal pages *are* the landing page, so they live with it — in the
[`alikeapp/alikeapp.github.io`](https://github.com/alikeapp/alikeapp.github.io)
repository, which is where an organization Pages site has to be served from.
There is one copy of each document, not a source copy and a published copy that
can drift.

## Operator details

| Field | Value |
| --- | --- |
| Operator | Oleksandr Solokha, individual developer |
| Country | Ukraine |
| Governing law | Ukraine, without prejudice to mandatory local consumer rights |
| Contact | oleksandr.solokha@gmail.com |

## Published URLs

The privacy pages are published as part of the landing page on GitHub Pages.

All 44 are `https://alikeapp.github.io` + the path below.

| Locale | Landing | Privacy Policy | Terms of Use | Support |
| --- | --- | --- | --- | --- |
| `en` | `/` | `/privacy/` | `/terms/` | `/support/` |
| `uk` | `/uk/` | `/uk/privacy/` | `/uk/terms/` | `/uk/support/` |
| `de` | `/de/` | `/de/privacy/` | `/de/terms/` | `/de/support/` |
| `fr` | `/fr/` | `/fr/privacy/` | `/fr/terms/` | `/fr/support/` |
| `es` | `/es/` | `/es/privacy/` | `/es/terms/` | `/es/support/` |
| `pt-BR` | `/pt-br/` | `/pt-br/privacy/` | `/pt-br/terms/` | `/pt-br/support/` |
| `it` | `/it/` | `/it/privacy/` | `/it/terms/` | `/it/support/` |
| `nl` | `/nl/` | `/nl/privacy/` | `/nl/terms/` | `/nl/support/` |
| `pl` | `/pl/` | `/pl/privacy/` | `/pl/terms/` | `/pl/support/` |
| `tr` | `/tr/` | `/tr/privacy/` | `/tr/terms/` | `/tr/support/` |
| `zh-Hant` | `/zh-hant/` | `/zh-hant/privacy/` | `/zh-hant/terms/` | `/zh-hant/support/` |

URL paths are lowercase, so Brazilian Portuguese is `/pt-br/` while its language
tag stays `pt-BR`, and Traditional Chinese is `/zh-hant/` against `zh-Hant`. The
App Store `es-MX` listing points at the `es` row.

This is an **organization** Pages site served from the domain root. `alike.github.io`
was the first choice and is unavailable — `alike` is an existing GitHub account
(registered 2011, no public repos) — so the site is published from the `alikeapp`
organization instead, which gets the same root-level shape without a `/Alike/`
sub-path.

Each Markdown file carries Jekyll front matter with the `permalink` that produces
the URL above, so the files can be dropped into the Pages site as-is.

> **Organization sites take an empty `baseurl`.** Because the site is served from
> the domain root, `_config.yml` sets:
>
> ```yaml
> url: "https://alikeapp.github.io"
> baseurl: ""
> ```
>
> Every internal link goes through `relative_url`/`absolute_url`, so those two
> values are the only place the address is configured. A non-empty `baseurl`
> here would make every published link wrong by one path segment.
>
> The deploy workflow's third-party-host check also allow-lists
> `alikeapp.github.io`. That is not cosmetic: `sitemap.xml` and `robots.txt`
> emit absolute URLs, so a stale host there fails the build on the site's own
> links.

If you later move to a custom domain, update `privacyPolicyURL` in
`Alike/Alike/Configuration/SubscriptionConfiguration.swift`, the table above,
`ALIKE_PRIVACY_URL`, and the App Store Connect privacy URL. Those four are the
complete list.

## Where the app uses these

| Surface | What it links to |
| --- | --- |
| Paywall disclosure (Scanner, Details, Settings) | Privacy Policy + Terms of Use |
| Settings → Legal | Privacy Policy + Terms of Use |
| App Store Connect listing | Privacy Policy URL |
| Generated metadata bundle | Privacy + Terms appended to each localized description |

Both URLs are injected once in `RootView` through
`.subscriptionLegalLinks(SubscriptionConfiguration.legalLinks)` and read from the
SwiftUI environment everywhere else, so there is exactly one place to change them.

## Terms of Use and the Apple EULA

`termsOfUse` in the app points at the published Terms of Use page,
`https://alikeapp.github.io/terms/` — the same URL the App Store listing carries,
so the in-app link and the listing lead to the same place.

That page describes how Alike works, what Alike Pro includes, and the
subscription billing rules, and it names
[Apple's Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
as the licence that legally governs use of the app, deferring to it wherever the
two conflict. Apple accepts a custom Terms page on that basis, so the app does
not link to Apple's copy directly.

Keep the EULA reference and the auto-renewable subscription disclosures on that
page — **in every language**. Removing either is what would turn this into a
review problem, and a translation that quietly drops one looks like ordinary
prose in a diff.

That is now asserted rather than reviewed: `scripts/check-site.sh` in the site
repo greps each rendered Terms page for a per-locale sentinel proving Apple's
Standard EULA is still named, plus a fragment of each of the two disclosure
paragraphs, and fails the build if any is missing. Adding a locale means adding
its `check_terms` row.

## Publishing checklist

1. Review the copy for anything that has drifted from actual app behaviour. The
   privacy policy claims are derived from the shipped in-app guide strings and
   from the fact that the codebase contains no networking and no analytics SDKs —
   re-verify both before each release that touches those areas.
2. Update the "Last updated" date in every file you changed, in every language.
   The date belongs to the document, not to the translation: if the English
   Privacy Policy changes, all six copies change and all six dates move.
3. If the subscription disclosure changed, confirm all three copies agree — this
   document, the catalog, and the site's `_data/<locale>.yml`. Nothing propagates
   between the two repositories:

   ```sh
   tools/check_site_legal_parity.py --require
   ```

   `--require` is not optional here. Without it a missing site checkout is a
   skip that exits 0, so the step would report success having compared nothing
   — exactly the false green this check exists to prevent. Pass `--site-repo`
   if the checkout is not next to this repository.
4. Open a pull request against `main` in `alikeapp/alikeapp.github.io`. Its
   `scripts/check-site.sh` runs there and asserts the locale matrix, internal
   links, hreflang, the Terms guardrails below, and that no third-party host is
   referenced. Merging deploys it; no manual copying is involved, and this does
   not wait on the app's release merge.
5. Confirm all 48 URLs load publicly with no sign-in — the loop is in
   `Docs/release-checklist.md` step 6.
6. Confirm `SubscriptionConfiguration.privacyPolicyURL` matches the live URL.
   The in-app links stay English for every locale: they are the app's own
   fallback, and `localized_url()` is what routes each *listing* to its own
   language.
7. Set the same privacy URL in App Store Connect and in `ALIKE_PRIVACY_URL` for
   the metadata bundle, and set the per-locale overrides
   (`ALIKE_{PRIVACY,TERMS,SUPPORT}_URL_{UK,DE_DE,FR_FR,ES_ES,ES_MX,PT_BR,IT,NL_NL,PL,TR,ZH_HANT,AR_SA}`)
   so each listing points at its own pages. All thirty-six are required —
   strict generation fails on an unset override instead of falling back to
   English. The full list with values is in `Docs/release-checklist.md` step
   0.
8. Check that `copyright_year` in the site's `_config.yml` still equals the year
   in `COPYRIGHT` in `tools/prepare_app_store_upload_bundle.py`. Nothing enforces
   this across the two repositories, and it is a copyright line, not a current
   year — it should only ever change if the year of first publication was wrong.
9. Verify the links open from all three paywall entry points and from
   Settings → Legal in a Release build.

## Keeping copy honest

These documents make specific factual claims. If any of the following stops
being true, the copy must change in the same pull request:

- Alike makes no network requests of its own and bundles no analytics, crash
  reporting, advertising, or tracking SDKs.
- All photo analysis runs on device via the Vision framework; no photo or derived
  data leaves the device.
- Deletion always requires explicit user confirmation and routes through iOS,
  landing in Recently Deleted.
- Notification permission is requested only when the weekly cleanup reminder is
  enabled.
- Delete Alike Data erases local Alike data only and never touches photos, photo
  access, or the subscription.
- Alike Pro consists of exactly the yearly and monthly products in
  `Docs/Subscriptions.md`, with a 7-day trial on yearly only.
