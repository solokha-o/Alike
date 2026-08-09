# Alike Legal Copy

Source of truth for Alike's public legal documents and the paywall subscription
disclosure.

```
Docs/legal/
├── README.md                     this file — the runbook
└── subscription-disclosure.md    paywall disclosure copy, EN + UK

alikeapp/alikeapp.github.io       the published pages themselves (separate repo)
├── privacy.md   uk/privacy.md    Privacy Policy, EN + UK
└── terms.md     uk/terms.md      Terms of Use, EN + UK
```

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

| Document | URL |
| --- | --- |
| Privacy Policy (EN) | `https://alikeapp.github.io/privacy/` |
| Privacy Policy (UK) | `https://alikeapp.github.io/uk/privacy/` |
| Terms of Use (EN) | `https://alikeapp.github.io/terms/` |
| Terms of Use (UK) | `https://alikeapp.github.io/uk/terms/` |

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
page. Removing either is what would turn this into a review problem.

## Publishing checklist

1. Review the copy for anything that has drifted from actual app behaviour. The
   privacy policy claims are derived from the shipped in-app guide strings and
   from the fact that the codebase contains no networking and no analytics SDKs —
   re-verify both before each release that touches those areas.
2. Update the "Last updated" date in every file you changed, in both languages.
3. Push to `main` in `alikeapp/alikeapp.github.io`. The Pages workflow there
   builds and deploys it; no manual copying is involved, and this does not wait
   on the app's release merge.
4. Confirm all four URLs load publicly with no sign-in.
5. Confirm `SubscriptionConfiguration.privacyPolicyURL` matches the live URL.
6. Set the same privacy URL in App Store Connect and in `ALIKE_PRIVACY_URL` for
   the metadata bundle.
7. Verify the links open from all three paywall entry points and from
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
