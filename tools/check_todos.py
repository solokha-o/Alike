#!/usr/bin/env python3
"""Fail when a changed file has a work marker without a card link.

ADR-0001 written rule 13 and Skills/Workflow/todo-management/SKILL.md: a TODO,
FIXME or HACK comment needs a card link right after the marker.
XXX is never correct: replace it with the marker that matches the intent.
The link format is `TODO(#123): ...` or `TODO(https://...): ...`.

SwiftLint (`todo_without_link` in .swiftlint.yml, run by tools/lint) already
checks TODO, FIXME and HACK in Swift comments. This check covers the rest:
- XXX in Swift comments;
- TODO, FIXME, HACK and XXX in the comments of shell, Python and Ruby files
  (`.sh`, `.py`, `.rb`, the Fastlane files, and extensionless scripts with a
  shebang, such as `tools/lint`).

Markdown is not checked. The skills and docs show markers as instructional
examples, and the todo-management skill says not to report them as debt.

The changed-file set is the one that tools/lint uses: the files changed against
the merge-base with the base branch, plus staged, unstaged and untracked files.
`--all` checks every tracked file (an audit; it does not change the gate).

The check is line-based, so it has a known limit: a marker that follows a `#` or
`//` inside a string literal on the same line is also reported.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_BASE = "origin/develop"
# The same link format as the SwiftLint rule `todo_without_link`.
LINK = r"\((?:#\d+|https://[^\s)]+)\)"
LINKED_MARKER = re.compile(r"\b(TODO|FIXME|HACK)\b(?!" + LINK + ")")
ANY_XXX = re.compile(r"\bXXX\b")
SCRIPT_SUFFIXES = {".sh": "#", ".bash": "#", ".py": "#", ".rb": "#"}
RUBY_FILE_NAMES = {"Fastfile", "Appfile", "Deliverfile", "Gemfile", "Matchfile", "Pluginfile"}
# A `#` that starts a comment: not Ruby interpolation `#{`, and not shell `$#`
# or `${#name}`.
HASH_COMMENT = re.compile(r"(?<![${])#(?!\{)")
SHEBANG =re.compile(rb"^#!.*\b(?:bash|sh|zsh|python3?|ruby)\b")
EXCLUDED_PARTS = {".build", "build", "DerivedData", "vendor", "node_modules"}
EXCLUDED_PREFIXES = ("Skills/External/",)


def comment_style(path: pathlib.PurePosixPath, head: bytes) -> str | None:
    """Return "swift", "hash", or None when the file is not checked."""
    if path.suffix == ".swift":
        return "swift"
    if path.suffix in SCRIPT_SUFFIXES or path.name in RUBY_FILE_NAMES:
        return "hash"
    if path.suffix == "" and SHEBANG.match(head):
        return "hash"
    return None


def is_candidate_path(path: pathlib.PurePosixPath) -> bool:
    text = str(path)
    if any(text.startswith(prefix) for prefix in EXCLUDED_PREFIXES):
        return False
    return not any(part in EXCLUDED_PARTS for part in path.parts[:-1])


def comment_text(line: str, style: str, in_block: bool) -> tuple[str, bool]:
    """Return the comment part of a line, and whether a Swift block comment is still open."""
    if style == "hash":
        match = HASH_COMMENT.search(line)
        # A shebang is not a comment that can hold a marker.
        if match is None or line.startswith("#!"):
            return "", False
        return line[match.start() :], False
    parts = []
    index = 0
    while index < len(line):
        if in_block:
            end = line.find("*/", index)
            if end < 0:
                parts.append(line[index:])
                return " ".join(parts), True
            parts.append(line[index:end])
            index = end + 2
            in_block = False
            continue
        line_comment = line.find("//", index)
        block = line.find("/*", index)
        if line_comment >= 0 and (block < 0 or line_comment < block):
            parts.append(line[line_comment:])
            break
        if block < 0:
            break
        index = block + 2
        in_block = True
    return " ".join(parts), in_block


def line_findings(comment: str, style: str) -> list[str]:
    findings = []
    if style == "hash":
        findings += [f"{match.group(1)} without a card link" for match in LINKED_MARKER.finditer(comment)]
    findings += ["XXX marker" for _ in ANY_XXX.finditer(comment)]
    return findings


def file_findings(path: pathlib.PurePosixPath, data: bytes) -> list[tuple[int, str]]:
    style = comment_style(path, data[:128])
    if style is None:
        return []
    text = data.decode("utf-8", errors="replace")
    findings = []
    in_block = False
    for number, line in enumerate(text.splitlines(), start=1):
        comment, in_block = comment_text(line, style, in_block)
        findings += [(number, message) for message in line_findings(comment, style)]
    return findings


def git(*args: str) -> bytes:
    return subprocess.run(
        ["git", *args], check=True, cwd=REPOSITORY_ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    ).stdout


def split_paths(output: bytes) -> set[pathlib.PurePosixPath]:
    return {pathlib.PurePosixPath(raw.decode("utf-8")) for raw in output.split(b"\0") if raw}


def changed_paths(base_ref: str) -> tuple[set[pathlib.PurePosixPath], str | None]:
    """Return the changed paths and the merge-base, or None when there is no merge-base."""
    try:
        merge_base = git("merge-base", base_ref, "HEAD").decode().strip()
    except subprocess.CalledProcessError:
        merge_base = None
    paths = split_paths(git("diff", "--name-only", "-z", "--diff-filter=ACMR", merge_base or "HEAD"))
    paths |= split_paths(git("ls-files", "--others", "--exclude-standard", "-z"))
    return paths, merge_base


def all_paths() -> set[pathlib.PurePosixPath]:
    return split_paths(git("ls-files", "-z", "--cached", "--others", "--exclude-standard"))


def find_findings(paths) -> list[tuple[pathlib.PurePosixPath, int, str]]:
    results = []
    for path in sorted(paths):
        file = REPOSITORY_ROOT / path
        if not is_candidate_path(path) or not file.is_file():
            continue
        results += [(path, line, message) for line, message in file_findings(path, file.read_bytes())]
    return results


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--all", action="store_true", help="check every tracked and untracked file")
    args = parser.parse_args(argv)
    base_ref = os.environ.get("ALIKE_CI_BASE_REF") or DEFAULT_BASE

    if args.all:
        print("Checking all files.")
        paths = all_paths()
    else:
        paths, merge_base = changed_paths(base_ref)
        if merge_base is None:
            print(
                f"error: no merge-base with '{base_ref}' (missing ref or shallow clone). "
                "Fetch it (git fetch origin) or set ALIKE_CI_BASE_REF."
            )
            return 1
        print(f"Checking files changed against {base_ref} (merge-base {merge_base[:8]}).")

    findings = find_findings(paths)
    if not findings:
        print("No work markers without a card link.")
        return 0
    for path, line, message in findings:
        print(f"{path}:{line}: {message}.")
    print(
        f"\n{len(findings)} finding(s). Write TODO(#123): ... or TODO(https://...): ... "
        "(ADR-0001 written rule 13). Replace XXX with TODO, FIXME, HACK or WARNING. "
        "See Skills/Workflow/todo-management/SKILL.md."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
