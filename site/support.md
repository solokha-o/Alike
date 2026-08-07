---
layout: page
title: Support
permalink: /support/
lang: en
alt_url: /uk/support/
description: "Support for Alike. No account and no ticket system — email us and you will get a reply."
---

{%- assign t = site.data[page.lang] %}

{{ t.support.subtitle }}

## {{ t.support.contact_title }}

{{ t.support.contact_body }}

[{{ site.contact_email }}](mailto:{{ site.contact_email }}?subject=Alike%20Support)

{{ t.support.response }}

## {{ t.support.before_title }}

{{ t.support.before_body }}

## {{ t.support.bug_title }}

{{ t.support.bug_body }}

Useful details to include:

- Your iPhone model and iOS version
- The Alike version, shown at the bottom of Settings
- What you did, what you expected, and what happened instead
- Whether the photo library permission is set to Full Access or Limited Access

## {{ t.support.privacy_title }}

{{ t.support.privacy_body }}

- [Privacy Policy]({{ t.privacy_url | relative_url }})
- [Terms of Use]({{ t.terms_url | relative_url }})

## Subscriptions and refunds

Alike Pro is sold by Apple. Subscriptions, cancellations, and refunds are handled
entirely through your Apple Account, and we cannot cancel or refund on your behalf.

- To manage or cancel: iOS Settings → your name → Subscriptions
- To request a refund: [Apple's refund process](https://support.apple.com/HT204084)
- To restore a purchase on a new device: Alike Settings → Restore Purchases
