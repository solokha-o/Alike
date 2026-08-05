# Alike Legal Copy

Source of truth for Alike's public legal documents and the paywall subscription
disclosure.

```
Docs/legal/
├── README.md                     this file — the runbook
└── subscription-disclosure.md    paywall disclosure copy, EN + UK

site/                             the published pages themselves
├── privacy.md   uk/privacy.md    Privacy Policy, EN + UK
└── terms.md     uk/terms.md      Terms of Use, EN + UK
```

The legal pages live in `site/` because they *are* the landing page — they are
built and deployed with it by `.github/workflows/pages.yml`. There is one copy
of each document, not a source copy and a published copy that can drift.

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
| Privacy Policy (EN) | `https://solokha-o.github.io/Alike/privacy/` |
| Privacy Policy (UK) | `https://solokha-o.github.io/Alike/uk/privacy/` |
| Terms of Use (EN) | `https://solokha-o.github.io/Alike/terms/` |
| Terms of Use (UK) | `https://solokha-o.github.io/Alike/uk/terms/` |

This is a **project** Pages site under the `/Alike/` path, not a user site.
`alike.github.io` was considered and is unavailable — `alike` is an existing
GitHub account (registered 2011, no public repos), so that hostname cannot be
claimed.

Each Markdown file carries Jekyll front matter with the `permalink` that produces
the URL above, so the files can be dropped into the Pages site as-is.

> **Project sites need a `baseurl`.** Because the site is served from `/Alike/`
> rather than the domain root, `_config.yml` must set:
>
> ```yaml
> baseurl: "/Alike"
> ```
>
> Without it Jekyll emits `/privacy/` and every published link is wrong by one
> path segment. The relative cross-links between the privacy and terms pages
> resolve correctly either way.

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

`termsOfUse` in the app points at
[Apple's Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/),
which is the licence that legally governs use of the app. The Terms of Use pages
in this folder describe how Alike works, what Alike Pro includes, and the
subscription billing rules, and explicitly defer to Apple's Standard EULA on
licence terms. Publish them alongside the privacy pages; they are referenced from
the landing page rather than from the app's Terms link.

## Publishing checklist

1. Review the copy for anything that has drifted from actual app behaviour. The
   privacy policy claims are derived from the shipped in-app guide strings and
   from the fact that the codebase contains no networking and no analytics SDKs —
   re-verify both before each release that touches those areas.
2. Update the "Last updated" date in every file you changed, in both languages.
3. Merge to `main`. The Pages workflow builds `site/` and deploys it; no manual
   copying is involved.
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
