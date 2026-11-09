#!/usr/bin/env python3
"""Report localization keys and asset catalog entries that look unused.

Report only: the script always exits 0 after a run, so it never blocks a gate.
tools/local_ci.sh full runs it and writes the report into the run's report folder.
Nothing is deleted. A finding is a candidate for a card, not a verdict.

What it reports:
- stale keys: `.xcstrings` keys whose `extractionState` is `stale`;
- unused keys: keys that no production source names as a string literal;
- missing translations: a key that has no translated value for a locale that the
  same catalog has for other keys;
- unused assets: `.xcassets` entries (image, color, symbol, data, app icon sets)
  that no source, project setting or plist names.

A key or an asset that can be in use without a literal reference is put under
"needs manual check" with the reason, not under "unused":
- a key in an `InfoPlist.xcstrings` catalog (the system reads it by its plist key);
- a key with a format specifier, such as `%@` or `%1$lld` (it can come from an
  interpolated `String(localized:)` or `Text` literal);
- a key or asset name that an interpolated or concatenated literal can build at
  run time, such as `"core.level.\\(level)"`;
- a key in a widget or App Intents catalog (the system can read it from metadata);
- a name that only a test names.

Usage:
  python3 tools/report_resource_hygiene.py [--output-dir DIR]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass, field

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT_NAME = "resource-hygiene"
ASSET_SET_SUFFIXES = (".imageset", ".colorset", ".symbolset", ".dataset", ".appiconset")
REFERENCE_SUFFIXES = (".swift", ".plist", ".pbxproj", ".entitlements", ".intentdefinition", ".storyboard", ".xib")
FORMAT_SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSaAp]")
SYSTEM_SCOPE = re.compile(r"Widget|Intent", re.IGNORECASE)
TRANSLATED_STATES = {"translated"}


@dataclass
class Corpus:
    """The text that can name a key or an asset, split into production and test sources."""

    production: str = ""
    tests: str = ""
    dynamic_patterns: list[re.Pattern] = field(default_factory=list)


def is_excluded(path: pathlib.PurePosixPath) -> bool:
    text = str(path)
    if text.startswith("Skills/") or text.startswith("build/"):
        return True
    return any(part in {".build", "DerivedData"} for part in path.parts)


def is_test_path(path: pathlib.PurePosixPath) -> bool:
    return any(part == "Tests" or part.endswith("Tests") for part in path.parts[:-1])


def tracked_files() -> list[pathlib.PurePosixPath]:
    output = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        check=True,
        cwd=REPOSITORY_ROOT,
        stdout=subprocess.PIPE,
    ).stdout
    paths = {pathlib.PurePosixPath(raw.decode("utf-8")) for raw in output.split(b"\0") if raw}
    return sorted(path for path in paths if not is_excluded(path))


# --- Swift string literals ---------------------------------------------------

STRING_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def interpolation_parts(literal: str) -> list[str] | None:
    """Split a literal body at `\\( ... )`. Return None when it has no interpolation."""
    parts, current, index, found = [], [], 0, False
    while index < len(literal):
        if literal.startswith("\\(", index):
            found = True
            depth, index = 1, index + 2
            while index < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[index], 0)
                index += 1
            parts.append("".join(current))
            current = []
            continue
        current.append(literal[index])
        index += 1
    parts.append("".join(current))
    return parts if found else None


MIN_PATTERN_LETTERS = 3


def is_specific(parts: list[str]) -> bool:
    """A pattern like `"\\(a).\\(b)"` would match every dotted key and hide real findings."""
    return sum(len(re.sub(r"\W", "", part)) for part in parts) >= MIN_PATTERN_LETTERS


def dynamic_patterns(source: str) -> list[re.Pattern]:
    """Return patterns for names that a literal builds at run time."""
    patterns = []
    for line in source.splitlines():
        # The interpolation can hold quotes, so take the line from the first quote.
        start = line.find('"')
        if start >= 0 and "\\(" in line:
            parts = interpolation_parts(line[start + 1 : line.rfind('"')] if line.rfind('"') > start else "")
            if parts and is_specific(parts):
                patterns.append(re.compile("^" + ".+".join(re.escape(part) for part in parts) + "$"))
        for match in STRING_LITERAL.finditer(line):
            rest = line[match.end() :].lstrip()
            # A literal prefix that code completes: "prefix." + value.
            if rest.startswith("+") and is_specific([match.group(1)]):
                patterns.append(re.compile("^" + re.escape(match.group(1)) + ".+$"))
    return patterns


def build_corpus(paths: list[pathlib.PurePosixPath], root: pathlib.Path = REPOSITORY_ROOT) -> Corpus:
    production, tests, patterns = [], [], []
    for path in paths:
        if not path.name.endswith(REFERENCE_SUFFIXES):
            continue
        file = root / path
        if not file.is_file():
            continue
        text = file.read_text(encoding="utf-8", errors="replace")
        (tests if is_test_path(path) else production).append(text)
        if path.suffix == ".swift" and not is_test_path(path):
            patterns += dynamic_patterns(text)
    return Corpus("\n".join(production), "\n".join(tests), patterns)


def names_literal(text: str, name: str) -> bool:
    return f'"{name}"' in text


def dynamic_match(corpus: Corpus, name: str) -> bool:
    return any(pattern.match(name) for pattern in corpus.dynamic_patterns)


# --- String catalogs ---------------------------------------------------------


def unit_states(localization: dict) -> list[str]:
    """Return every stringUnit state in a localization, variations included."""
    states = []
    stack = [localization]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            unit = node.get("stringUnit")
            if isinstance(unit, dict):
                states.append(unit.get("state", ""))
            stack += [value for key, value in node.items() if key != "stringUnit"]
    return states


def missing_locales(entry: dict, catalog_locales: set[str]) -> list[str]:
    if entry.get("shouldTranslate") is False:
        return []
    localizations = entry.get("localizations", {})
    missing = []
    for locale in sorted(catalog_locales):
        states = unit_states(localizations.get(locale, {}))
        if not states:
            missing.append(f"{locale} (absent)")
        else:
            untranslated = sorted({state for state in states if state not in TRANSLATED_STATES})
            if untranslated:
                missing.append(f"{locale} (state {', '.join(untranslated)})")
    return missing


def plist_key_used(corpus: Corpus, key: str) -> bool:
    return f"<key>{key}</key>" in corpus.production or f"INFOPLIST_KEY_{key} " in corpus.production


def classify_key(catalog: pathlib.PurePosixPath, key: str, entry: dict, corpus: Corpus) -> tuple[str, str]:
    """Return (category, reason). Category: stale, used, manual, unused."""
    if entry.get("extractionState") == "stale":
        return "stale", "extractionState is stale"
    if catalog.name == "InfoPlist.xcstrings":
        if plist_key_used(corpus, key):
            return "used", ""
        return "manual", "Info.plist catalog: the system reads the key"
    if names_literal(corpus.production, key):
        return "used", ""
    if dynamic_match(corpus, key):
        return "manual", "an interpolated or concatenated literal can build this key"
    if FORMAT_SPECIFIER.search(key):
        return "manual", "format key: an interpolated literal can produce it"
    if SYSTEM_SCOPE.search(str(catalog)):
        return "manual", "widget or App Intents catalog: system metadata can read it"
    if names_literal(corpus.tests, key):
        return "manual", "only a test names it"
    return "unused", "no literal reference in production code"


def catalog_findings(catalog: pathlib.PurePosixPath, data: dict, corpus: Corpus) -> dict:
    strings = data.get("strings", {})
    locales = {data.get("sourceLanguage", "en")}
    for entry in strings.values():
        locales |= set(entry.get("localizations", {}).keys())
    result = {"catalog": str(catalog), "keys": len(strings), "locales": sorted(locales)}
    for category in ("stale", "unused", "manual", "missingTranslations"):
        result[category] = []
    for key in sorted(strings):
        entry = strings[key]
        category, reason = classify_key(catalog, key, entry, corpus)
        if category != "used":
            result[category].append({"key": key, "reason": reason})
        missing = missing_locales(entry, locales)
        if missing:
            result["missingTranslations"].append({"key": key, "locales": missing})
    return result


# --- Asset catalogs ----------------------------------------------------------


def lower_camel(name: str) -> str:
    words = re.split(r"[^A-Za-z0-9]+", name)
    words = [word for word in words if word]
    if not words:
        return name
    first = words[0][0].lower() + words[0][1:]
    return first + "".join(word[0].upper() + word[1:] for word in words[1:])


def generated_symbols(name: str) -> set[str]:
    """Names that Xcode's generated asset symbols can use, such as `.widgetAccent`."""
    symbol = lower_camel(name)
    symbols = {symbol}
    for suffix in ("Color", "Image"):
        if symbol.endswith(suffix) and len(symbol) > len(suffix):
            symbols.add(symbol[: -len(suffix)])
    return symbols


def classify_asset(name: str, kind: str, corpus: Corpus) -> tuple[str, str]:
    if names_literal(corpus.production, name):
        return "used", ""
    if re.search(rf"=\s*\"?{re.escape(name)}\"?;", corpus.production):
        return "used", ""
    if re.search(rf"<string>{re.escape(name)}</string>", corpus.production):
        return "used", ""
    if any(re.search(rf"\.{re.escape(symbol)}\b", corpus.production) for symbol in generated_symbols(name)):
        return "used", ""
    if dynamic_match(corpus, name):
        return "manual", "an interpolated or concatenated literal can build this name"
    if kind == "appiconset":
        return "manual", "app icon: an alternate icon is named in code or Info.plist at run time"
    if names_literal(corpus.tests, name):
        return "manual", "only a test names it"
    return "unused", "no reference in code, project settings or plists"


def asset_findings(paths: list[pathlib.PurePosixPath], corpus: Corpus) -> list[dict]:
    sets = {}
    for path in paths:
        for index, part in enumerate(path.parts):
            if part.endswith(ASSET_SET_SUFFIXES) and any(p.endswith(".xcassets") for p in path.parts[:index]):
                set_path = pathlib.PurePosixPath(*path.parts[: index + 1])
                sets[set_path] = part.rsplit(".", 1)
                break
    findings = []
    for set_path, (name, kind) in sorted(sets.items()):
        category, reason = classify_asset(name, kind, corpus)
        if category != "used":
            findings.append({"asset": str(set_path), "name": name, "category": category, "reason": reason})
    return findings


# --- Report ------------------------------------------------------------------


def load_catalog(file: pathlib.Path) -> tuple[dict | None, str]:
    """Return (catalog, "") or (None, reason). A broken catalog must not stop the report."""
    try:
        data = json.loads(file.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError) as error:
        return None, f"{type(error).__name__}: {error}"
    if not isinstance(data, dict) or not isinstance(data.get("strings", {}), dict):
        return None, "not a string catalog: no `strings` object"
    if not all(isinstance(entry, dict) for entry in data.get("strings", {}).values()):
        return None, "not a string catalog: a key entry is not an object"
    return data, ""


def build_report(paths: list[pathlib.PurePosixPath], root: pathlib.Path = REPOSITORY_ROOT) -> dict:
    corpus = build_corpus(paths, root)
    catalogs, unparsed = [], []
    for path in paths:
        if path.suffix == ".xcstrings" and (root / path).is_file():
            data, reason = load_catalog(root / path)
            if data is None:
                unparsed.append({"catalog": str(path), "reason": reason})
            else:
                catalogs.append(catalog_findings(path, data, corpus))
    assets = asset_findings(paths, corpus)
    summary = {
        "catalogs": len(catalogs),
        "unparsedCatalogs": len(unparsed),
        "keys": sum(catalog["keys"] for catalog in catalogs),
        "staleKeys": sum(len(catalog["stale"]) for catalog in catalogs),
        "unusedKeys": sum(len(catalog["unused"]) for catalog in catalogs),
        "keysWithMissingTranslations": sum(len(catalog["missingTranslations"]) for catalog in catalogs),
        "unusedAssets": sum(1 for asset in assets if asset["category"] == "unused"),
        "needsManualCheck": sum(len(catalog["manual"]) for catalog in catalogs)
        + sum(1 for asset in assets if asset["category"] == "manual"),
    }
    return {"summary": summary, "catalogs": catalogs, "unparsedCatalogs": unparsed, "assets": assets}


def markdown(report: dict) -> str:
    summary = report["summary"]
    lines = [
        "# Resource hygiene report",
        "",
        "Report only. Nothing was deleted. File a card for each finding you confirm.",
        "",
        f"- Catalogs: {summary['catalogs']}, keys: {summary['keys']}",
        f"- Stale keys: {summary['staleKeys']}",
        f"- Unused keys: {summary['unusedKeys']}",
        f"- Keys with missing translations: {summary['keysWithMissingTranslations']}",
        f"- Unused assets: {summary['unusedAssets']}",
        f"- Needs manual check: {summary['needsManualCheck']}",
        f"- Catalogs that could not be parsed: {summary['unparsedCatalogs']}",
    ]
    if report["unparsedCatalogs"]:
        lines += ["", "## Could not parse", ""]
        for item in report["unparsedCatalogs"]:
            lines.append(f"- `{item['catalog']}` ({item['reason']})")
    for catalog in report["catalogs"]:
        if not any(catalog[category] for category in ("stale", "unused", "manual", "missingTranslations")):
            continue
        lines += ["", f"## {catalog['catalog']}", ""]
        for category, title in (("stale", "Stale"), ("unused", "Unused"), ("manual", "Needs manual check")):
            for item in catalog[category]:
                lines.append(f"- {title}: `{item['key']}` ({item['reason']})")
        for item in catalog["missingTranslations"]:
            lines.append(f"- Missing translation: `{item['key']}` ({', '.join(item['locales'])})")
    if report["assets"]:
        lines += ["", "## Assets", ""]
        for asset in report["assets"]:
            title = "Unused" if asset["category"] == "unused" else "Needs manual check"
            lines.append(f"- {title}: `{asset['asset']}` ({asset['reason']})")
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output-dir", type=pathlib.Path, help="write resource-hygiene.md and .json here")
    args = parser.parse_args(argv)
    try:
        return write_report(args.output_dir)
    except Exception as error:  # noqa: BLE001 - a report-only step must never fail the gate.
        print(f"Resource hygiene (report only): the report failed and was skipped: {type(error).__name__}: {error}")
        return 0


def write_report(output_dir: pathlib.Path | None) -> int:
    report = build_report(tracked_files())
    text = markdown(report)
    if output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / f"{REPORT_NAME}.md").write_text(text, encoding="utf-8")
        (output_dir / f"{REPORT_NAME}.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    else:
        print(text)
    summary = report["summary"]
    print(
        "Resource hygiene (report only): "
        f"{summary['staleKeys']} stale key(s), {summary['unusedKeys']} unused key(s), "
        f"{summary['keysWithMissingTranslations']} key(s) with missing translations, "
        f"{summary['unusedAssets']} unused asset(s), {summary['needsManualCheck']} need a manual check, "
        f"{summary['unparsedCatalogs']} catalog(s) could not be parsed."
    )
    if output_dir:
        print(f"Report: {output_dir / (REPORT_NAME + '.md')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
