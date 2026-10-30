---
name: localized-copy-review
description: >-
  Review and edit Alike translations for semantic accuracy, natural phrasing,
  legal claim parity, and marketing clarity. Use for native-style review of
  privacy, terms, landing copy, subscription copy, or app strings. Do not use
  for catalog plumbing, adding locales, or certifying legal compliance.
---

# Localized Copy Review

Preserve the source claim before improving its phrasing. Never claim that an AI
review is a native-speaker or legal sign-off.

## Workflow

1. Read `Docs/Localization/native-review.md` and the English text for the assigned
   surface. For legal or subscription copy, also read `Docs/legal/README.md` and
   `Docs/legal/subscription-disclosure.md`.
2. Resolve repository, base revision, locale, file, and validation boundaries from
   the request. Do not expand a site-only request into app changes.
3. Read the relevant references below. Apply the locale register and glossary.
4. Review every assigned source-target pair in context. Separate semantic review
   from fluency review; then check legal claims and marketing where applicable.
5. Edit wording directly when authorized. Make small, locale-specific changes.
   Preserve syntax, links, keys, placeholders, plural forms, and protected copy.
6. Re-read each changed paragraph against English. Review the final diff for
   omissions, stronger promises, incorrect suffixes, and cross-file drift.
7. Follow the requested delivery and validation rules. Distinguish text review,
   automated checks, native-speaker review, and legal review in the handoff.

## Decision rules

- English is the semantic baseline. If it conflicts with current product facts,
  inspect authoritative app sources and record the conflict. Do not silently
  choose an older skill list or invent a compromise count.
- A language and a regional locale are different units. Derive advertised counts
  from current catalogs and project configuration, and name the unit accurately.
- For subscription disclosures, treat the legal document, PurchasesUI catalog,
  and site data as one coordinated change. A site-only task must leave protected
  disclosure values unchanged and record the exact mismatch for its owner.
- If a term remains uncertain, retain the narrowest supported meaning and identify
  the file and phrase. Do not replace uncertainty with a confidence percentage.
- Keep temporary comparison notes outside the repository unless requested.
- Do not run tests or builds when the user assigns validation to another agent.
  Do not describe unrun checks as passed.
- Reuse `spm-localization` for catalog mechanics, `ios-git-flow` for commits, and
  `pr-agent-flow` for PRs only when the requested work needs them.
- This skill does not authorize installing plugins, creating PRs, changing Notion
  status, adding locales, or changing app behavior beyond the user's task.

## Routing map

- Every translation review: [Language review](references/language-review.md).
- Locale register, terminology, and paths: [Locale rules](references/locale-rules.md).
- Privacy, terms, or subscriptions: [Legal parity](references/legal-parity.md).
- Landing pages, App Store text, or promotional prose:
  [Marketing review](references/marketing-review.md).
- Reference inventory and optional external methods:
  [Reference index](references/_index.md).
