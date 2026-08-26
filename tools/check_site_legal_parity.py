#!/usr/bin/env python3
"""Assert the landing site's subscription disclosures still match this repo's copy.

`Docs/legal/subscription-disclosure.md` is the source of truth for the two
paragraphs App Review requires on an auto-renewable subscription paywall. Three
places carry them:

  1. this document;
  2. `Packages/Purchases/.../PurchasesUI/Resources/Localizable.xcstrings`, which
     `PurchasesUITests/SubscriptionDisclosureTests` already pins byte-for-byte;
  3. `_data/<locale>.yml` in the alikeapp/alikeapp.github.io repository, under
     `pricing.disclosure_renewal` and `pricing.disclosure_trial`.

Nothing pinned (3). It is a separate repository, so no test in either one can see
both sides, and the site's own `scripts/check-site.sh` deliberately greps only
short sentinel fragments — enough to catch a *dropped* disclosure, not a stale
one. That is the gap this closes: edit the wording here, and the published
pricing section keeps showing the old text with nothing failing.

Run it before publishing legal copy, per `Docs/legal/README.md`. It needs the
site checked out next to this repository, the same convention
`tools/import_device_screenshots.py` uses.

    tools/check_site_legal_parity.py --require     # release steps, gating
    tools/check_site_legal_parity.py               # incidental local run
    tools/check_site_legal_parity.py --site-repo ../alikeapp.github.io

**Pass --require anywhere the answer gates something.** Bare, a missing site
checkout is a skip that exits 0 — right for a machine that simply does not have
the sibling repository, and wrong for a checklist step, which would then report
success having compared nothing.

Exit codes: 0 parity holds (or the checkout is absent and --require was not
passed), 1 a locale differs, 2 the inputs could not be parsed.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DISCLOSURE_DOC = Path("Docs/legal/subscription-disclosure.md")

# Site locale -> the heading used in the disclosure document.
#
# `es-419` is in the document because the app ships it as its own catalog, but
# the site deliberately has no /es-419/ tree: one Spanish page serves both the
# es-ES and es-MX listings. It is absent here on purpose, and reported as such.
SITE_TO_DOC = {
    "en": "EN",
    "uk": "UK",
    "de": "DE",
    "fr": "FR",
    "es": "ES",
    "pt-BR": "PT-BR",
    "it": "IT",
    "nl": "NL",
    "pl": "PL",
    "tr": "TR",
    "zh-Hant": "ZH-HANT",
    "ar": "AR",
}
DOC_ONLY = {
    "ES-419": "/es/ serves both Spanish listings",
}

PARAGRAPHS = {
    "disclosure_renewal": "### Paragraph 1 — renewal and billing",
    "disclosure_trial": "### Paragraph 2 — trial and cancellation",
}


class ParseError(RuntimeError):
    pass


def doc_blocks(text: str, heading: str) -> dict[str, str]:
    """Pull the `**LOCALE**` / `> text` pairs out of one section."""
    if heading not in text:
        raise ParseError(f"heading not found in {DISCLOSURE_DOC}: {heading!r}")
    section = re.split(r"\n### |\n## ", text.split(heading, 1)[1], maxsplit=1)[0]
    blocks = dict(re.findall(r"\*\*([A-Z0-9\-]+)\*\*\s*\n\s*\n> (.+)", section))
    if not blocks:
        raise ParseError(f"no locale blocks under {heading!r} in {DISCLOSURE_DOC}")
    return blocks


def site_value(path: Path, key: str) -> str:
    """Read one `pricing.<key>` scalar without a YAML dependency.

    The keys are single-line double-quoted scalars two levels down. Anything
    else — a folded block, a repeated key — is a parse error rather than a
    guess, because guessing here would report false parity.
    """
    pattern = re.compile(rf'^\s{{2}}{re.escape(key)}:\s*"(.*)"\s*$')
    found = [m.group(1) for m in (pattern.match(line) for line in path.read_text(encoding="utf-8").splitlines()) if m]
    if len(found) != 1:
        raise ParseError(
            f"expected exactly one `{key}` line in {path}, found {len(found)}. "
            "If the value moved to a block scalar, this parser needs updating."
        )
    return found[0].replace('\\"', '"').replace("\\\\", "\\")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".", help="this repository's root")
    ap.add_argument(
        "--site-repo",
        default="../alikeapp.github.io",
        help="checkout of alikeapp/alikeapp.github.io (default: %(default)s)",
    )
    ap.add_argument(
        "--require",
        action="store_true",
        help="fail instead of skipping when the site checkout is missing; "
             "use this anywhere the result gates something",
    )
    args = ap.parse_args()

    repo = Path(args.repo).expanduser()
    site = Path(args.site_repo).expanduser()
    doc_path = repo / DISCLOSURE_DOC

    if not doc_path.is_file():
        print(f"error: {doc_path} not found", file=sys.stderr)
        return 2

    if not (site / "_data").is_dir():
        message = (
            f"Site checkout not found at {site}; pass --site-repo <path to alikeapp.github.io>."
        )
        if args.require:
            print(f"error: {message}", file=sys.stderr)
            return 2
        # Say plainly that nothing was compared. A "skip" line that reads like a
        # pass is how a checklist step ends up green having checked nothing.
        print(f"Skipped — {message}")
        print("Nothing was compared. Re-run with --require to make this a failure.")
        return 0

    try:
        text = doc_path.read_text(encoding="utf-8")
        expected = {key: doc_blocks(text, heading) for key, heading in PARAGRAPHS.items()}
    except ParseError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    failures = 0
    checked = 0
    for locale, doc_key in SITE_TO_DOC.items():
        data = site / "_data" / f"{locale}.yml"
        if not data.is_file():
            print(f"FAIL  {locale}: {data} does not exist")
            failures += 1
            continue
        for key in PARAGRAPHS:
            want = expected[key].get(doc_key)
            if want is None:
                print(f"error: {DISCLOSURE_DOC} has no **{doc_key}** block for {key}", file=sys.stderr)
                return 2
            try:
                got = site_value(data, key)
            except ParseError as exc:
                print(f"error: {exc}", file=sys.stderr)
                return 2
            checked += 1
            if got == want:
                print(f"ok    {locale} {key}")
            else:
                failures += 1
                print(f"FAIL  {locale} {key} differs")
                print(f"        doc : {want}")
                print(f"        site: {got}")

    for doc_key, why in sorted(DOC_ONLY.items()):
        print(f"note  {doc_key} has no site page — {why}")

    print()
    if failures:
        print(f"{failures} of {checked} disclosure strings differ between this repo and the site.", file=sys.stderr)
        print("Update both, or the published pricing section keeps showing the old wording.", file=sys.stderr)
        return 1
    print(f"All {checked} disclosure strings match {DISCLOSURE_DOC}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
