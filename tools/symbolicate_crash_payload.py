#!/usr/bin/env python3
"""Turn a MetricKit crash payload into a readable, symbolicated stack.

The app stores what `MXDiagnosticPayload.jsonRepresentation()` gives it and a user
emails that file as `alike-crash-N.json`. It carries binary UUIDs and offsets, not
function names; this script is the part a crash-reporting server would otherwise do.

For every binary in the payload it looks for a dSYM with the same UUID — Spotlight
first, then `dwarfdump --uuid` over:

  $ALIKE_XCODE_ARCHIVES_ROOT   (default ~/Library/Developer/Xcode/Archives; where
                               `tools/release-check` preserves each archive)
  build/fastlane/AlikeRelease.xcarchive
  build/fastlane/dsyms/        (`tools/dsyms X.Y.Z N` downloads; zips are unpacked)

and runs `atos` with the load address `address - offsetIntoBinaryTextSegment`.

System frames stay as offsets: their symbols are not in any archive of ours. A missing
dSYM for the app's own binary is an error, never a silently raw stack — that archive
has to be found, or the build was shipped without keeping one.

Usage:
    tools/symbolicate alike-crash-1.json
    tools/symbolicate payload.json --dsym-root ~/Downloads/dsyms
    tools/symbolicate payload.json --app-binary Alike --arch arm64e
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
UUID_LINE = re.compile(r"UUID: ([0-9A-Fa-f-]{36}) \((\S+)\) (.+)")


def fail(message: str, code: int = 1) -> "NoReturn":
    print(f"symbolicate: {message}", file=sys.stderr)
    sys.exit(code)


def run(*command: str) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    return result.stdout if result.returncode == 0 else ""


def load_payload(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        fail(f"cannot read {path}: {error}")
    except json.JSONDecodeError as error:
        fail(f"{path} is not JSON: {error}")
    if isinstance(payload, dict) and "schemaVersion" in payload and "reports" in payload:
        fail(
            f"{path.name} is the app's index, which holds no frames. "
            "Pass a payload instead: payloads/<id>.json, or the email attachment."
        )
    if not isinstance(payload, dict) or not payload.get("crashDiagnostics"):
        fail(f"{path.name} has no crashDiagnostics; is it a MetricKit diagnostic payload?")
    return payload


def walk_frames(frames: list, depth: int = 0):
    """Yields (depth, frame) in nesting order; a frame's callers are its subFrames."""
    for frame in frames or []:
        yield depth, frame
        yield from walk_frames(frame.get("subFrames"), depth + 1)


class DsymIndex:
    """UUID -> DWARF file, resolved lazily: Spotlight, then a scan of the roots."""

    def __init__(self, roots: list[Path]):
        self.roots = roots
        self.by_uuid: dict[str, Path] = {}
        self.scanned = False
        self.scratch = tempfile.TemporaryDirectory(prefix="alike-symbolicate-")

    def find(self, uuid: str) -> Path | None:
        uuid = uuid.upper()
        if uuid not in self.by_uuid:
            for hit in run("mdfind", f"com_apple_xcode_dsym_uuids == {uuid}").splitlines():
                self.index_bundle(Path(hit))
        if uuid not in self.by_uuid and not self.scanned:
            self.scan()
        return self.by_uuid.get(uuid)

    def index_bundle(self, bundle: Path) -> None:
        for line in run("xcrun", "dwarfdump", "--uuid", str(bundle)).splitlines():
            match = UUID_LINE.match(line.strip())
            if match:
                self.by_uuid.setdefault(match.group(1).upper(), Path(match.group(3)))

    def scan(self) -> None:
        self.scanned = True
        for root in self.roots:
            if not root.exists():
                continue
            for directory, names, files in os.walk(root):
                for name in list(names):
                    if name.endswith(".dSYM"):
                        self.index_bundle(Path(directory) / name)
                        names.remove(name)
                for name in files:
                    if name.endswith(".zip"):
                        self.index_zip(Path(directory) / name)

    def index_zip(self, archive: Path) -> None:
        target = Path(self.scratch.name) / archive.stem
        try:
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(target)
        except (OSError, zipfile.BadZipFile):
            return
        for directory, names, _ in os.walk(target):
            for name in list(names):
                if name.endswith(".dSYM"):
                    self.index_bundle(Path(directory) / name)
                    names.remove(name)


def symbolicate(dwarf: Path, arch: str, load_address: int, addresses: list[int]) -> dict[int, str]:
    output = run(
        "xcrun", "atos", "-o", str(dwarf), "-arch", arch, "-l", hex(load_address),
        *[hex(address) for address in addresses],
    ).splitlines()
    if len(output) != len(addresses):
        return {}
    return dict(zip(addresses, output))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("payload", type=Path, help="MetricKit diagnostic payload JSON")
    parser.add_argument("--dsym-root", type=Path, action="append", default=[],
                        help="extra directory to search for dSYMs (repeatable)")
    parser.add_argument("--app-binary", default="Alike",
                        help="binary whose dSYM must be found (default: Alike)")
    parser.add_argument("--arch", default="arm64")
    args = parser.parse_args()

    payload = load_payload(args.payload)
    archives = Path(os.environ.get("ALIKE_XCODE_ARCHIVES_ROOT")
                    or Path.home() / "Library/Developer/Xcode/Archives")
    roots = [*args.dsym_root, archives,
             ROOT_DIR / "build/fastlane/AlikeRelease.xcarchive",
             ROOT_DIR / "build/fastlane/dsyms"]
    index = DsymIndex(roots)

    for number, crash in enumerate(payload["crashDiagnostics"], start=1):
        meta = crash.get("diagnosticMetaData", {})
        print(f"Crash {number}: {meta.get('bundleIdentifier', '?')} "
              f"{meta.get('appVersion', '?')} ({meta.get('appBuildVersion', '?')}) — "
              f"{meta.get('osVersion', '?')} — {meta.get('deviceType', '?')}")
        print(f"  signal {meta.get('signal', '?')}, exception type {meta.get('exceptionType', '?')}, "
              f"code {meta.get('exceptionCode', '?')}")
        for key in ("terminationReason", "virtualMemoryRegionInfo", "objectiveCexceptionReason"):
            if meta.get(key):
                print(f"  {key}: {meta[key]}")

        stacks = crash.get("callStackTree", {}).get("callStacks", [])
        frames = [frame for stack in stacks
                  for _, frame in walk_frames(stack.get("callStackRootFrames"))]

        # One atos run per binary image.
        symbols: dict[tuple[str, int], str] = {}
        images: dict[tuple[str, int], list[int]] = {}
        for frame in frames:
            uuid, address, offset = (frame.get("binaryUUID"), frame.get("address"),
                                     frame.get("offsetIntoBinaryTextSegment"))
            if uuid and address is not None and offset is not None:
                images.setdefault((uuid.upper(), address - offset), []).append(address)
        missing_app_uuids = set()
        for (uuid, load_address), addresses in images.items():
            dwarf = index.find(uuid)
            if dwarf is None:
                continue
            for address, text in symbolicate(dwarf, args.arch, load_address, addresses).items():
                symbols[(uuid, address)] = text
        for frame in frames:
            uuid = (frame.get("binaryUUID") or "").upper()
            if frame.get("binaryName") == args.app_binary and index.find(uuid) is None:
                missing_app_uuids.add(uuid)
        if missing_app_uuids:
            searched = "\n    ".join(str(root) for root in roots)
            fail(
                f"no dSYM for {args.app_binary} with UUID {', '.join(sorted(missing_app_uuids))}.\n"
                f"  Searched Spotlight and:\n    {searched}\n"
                f"  Try: tools/dsyms {meta.get('appVersion', 'X.Y.Z')} {meta.get('appBuildVersion', 'N')}, "
                "or pass --dsym-root <dir>. Without the archive of that exact build "
                "this crash cannot be symbolicated.",
                code=2,
            )

        for position, stack in enumerate(stacks):
            attributed = " (crashed)" if stack.get("threadAttributed") else ""
            print(f"\nThread {position}{attributed}:")
            for depth, frame in walk_frames(stack.get("callStackRootFrames")):
                uuid = (frame.get("binaryUUID") or "").upper()
                address = frame.get("address")
                text = symbols.get((uuid, address)) or (
                    f"{frame.get('binaryName', '?')} + {frame.get('offsetIntoBinaryTextSegment', '?')}")
                shown = hex(address) if isinstance(address, int) else "?"
                print(f"  {depth:<3} {frame.get('binaryName', '?'):<28} {shown:<18} {text}")
        print()


if __name__ == "__main__":
    main()
