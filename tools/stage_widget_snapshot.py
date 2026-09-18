#!/usr/bin/env python3
"""Put one widget state on a simulator, so the Lock Screen slots can be looked at.

The simulator cannot form clusters and never sets `photoScreenshot`, so no state
past "never scanned" can be reached by using the app there. What can be reached is
the file the extension reads: `widget-snapshot.json` in the App Group container.

The sequence matters and is not obvious:

  terminate -> write the file -> `simctl install` -> **never launch**

A launch makes `WidgetSnapshotPublisher` republish from the simulator's real
(empty) library and the hand-written file is gone. The reinstall is what reloads
the timelines; the extension then reads whatever is on disk. Accessory widgets
take about 25 seconds to redraw after that — the home-screen ones are quicker —
so `--screenshot` waits before it captures.

The widget gallery is not a preview of any of this: `getSnapshot` returns
`WidgetSnapshot.placeholder()` whenever `context.isPreview`, so a state is only
visible once the widget is placed on a screen.

Usage:
    python3 tools/stage_widget_snapshot.py hasSuggestions
    python3 tools/stage_widget_snapshot.py legacy141 --appearance dark --screenshot out.png
    python3 tools/stage_widget_snapshot.py --list
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

BUNDLE_ID = "com.alike.app"
APP_GROUP = "group.com.alike.ios.widgets"
SNAPSHOT_FILE = "widget-snapshot.json"
ACCESSORY_REDRAW_SECONDS = 30

GENERATED_AT = datetime.now(timezone.utc).replace(microsecond=0)
SCANNED_AT = GENERATED_AT - timedelta(hours=3)
BYTES = 1_932_735_283          # ≈1.8 GB reclaimable
LIBRARY_BYTES = 27_917_287_424  # ≈27.9 GB library, so the ring sits near 7%


def iso(moment: datetime) -> str:
    return moment.isoformat().replace("+00:00", "Z")


def base(**overrides) -> dict:
    """A scanned, authorized, premium-free snapshot. Overrides shape the state."""
    snapshot = {
        "schemaVersion": 1,
        "generatedAt": iso(GENERATED_AT),
        "photoAuthorization": "authorized",
        "hasCompletedScan": True,
        "lastScanDate": iso(SCANNED_AT),
        "libraryChangedSinceScan": False,
        "estimatedSavingsBytes": BYTES,
        "libraryTotalBytes": LIBRARY_BYTES,
        "clusterCount": 24,
        "screenshotAssetCount": 86,
        "blurredPhotoAssetCount": 12,
        "isPremium": False,
    }
    snapshot.update(overrides)
    return {key: value for key, value in snapshot.items() if value is not None}


def session(reviewed: int, total: int) -> dict:
    return {
        "reviewedClusters": reviewed,
        "inReviewClusters": 0,
        "totalClusters": total,
        "updatedAt": iso(SCANNED_AT),
    }


# One fixture per row of the Lock Screen QA matrix. `unavailable` is the absence
# of a file rather than a payload, so it carries None.
STATES: dict[str, dict | None] = {
    "hasSuggestions": base(),
    # A day older than the staleness threshold, so the rectangular slot dates itself.
    "hasSuggestionsStale": base(generatedAt=iso(GENERATED_AT - timedelta(hours=30))),
    "resumeReview": base(sessionProgress=session(18, 30)),
    "libraryChanged": base(libraryChangedSinceScan=True),
    "allCaughtUp": base(estimatedSavingsBytes=0, clusterCount=0,
                        screenshotAssetCount=0, blurredPhotoAssetCount=0),
    "neverScanned": base(hasCompletedScan=False, lastScanDate=None,
                         estimatedSavingsBytes=None, libraryTotalBytes=None,
                         clusterCount=None),
    "noAccessLimited": base(photoAuthorization="limited"),
    "noAccessDenied": base(photoAuthorization="denied", hasCompletedScan=False,
                           lastScanDate=None, estimatedSavingsBytes=None,
                           libraryTotalBytes=None, clusterCount=None),
    "unavailable": None,
    # What every 1.4.1 install has on disk: no `libraryTotalBytes` key at all, so
    # the circular slot must draw no ring rather than a ring at zero.
    "legacy141": base(libraryTotalBytes=None),
}


def run(*arguments: str) -> str:
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"{' '.join(arguments)} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def container(udid: str) -> Path:
    path = run("xcrun", "simctl", "get_app_container", udid, BUNDLE_ID, "groups")
    for line in path.splitlines():
        identifier, _, location = line.partition("\t")
        if identifier.strip() == APP_GROUP:
            return Path(location.strip())
        # A single-group container prints just the path.
        if not location and line.startswith("/"):
            return Path(line.strip())
    sys.exit(f"{APP_GROUP} is not among the app's groups on {udid}. Install the app first.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("state", nargs="?", choices=sorted(STATES), help="which display state to stage")
    parser.add_argument("--udid", default="booted", help="simulator UDID (default: booted)")
    parser.add_argument("--app", type=Path, help="Alike.app to reinstall; omit to reuse the installed build")
    parser.add_argument("--appearance", choices=["light", "dark"], help="simctl ui appearance")
    parser.add_argument("--content-size", help="simctl ui content_size, e.g. accessibility-medium")
    parser.add_argument("--screenshot", type=Path, help="capture here once the widgets have redrawn")
    parser.add_argument("--wait", type=int, default=ACCESSORY_REDRAW_SECONDS,
                        help=f"seconds to wait before the screenshot (default: {ACCESSORY_REDRAW_SECONDS})")
    parser.add_argument("--list", action="store_true", help="print the states and exit")
    arguments = parser.parse_args()

    if arguments.list or not arguments.state:
        print("\n".join(sorted(STATES)))
        return 0

    payload = STATES[arguments.state]
    target = container(arguments.udid) / SNAPSHOT_FILE

    # The app may not be running; terminating one that is not is not an error here.
    subprocess.run(["xcrun", "simctl", "terminate", arguments.udid, BUNDLE_ID],
                   capture_output=True, text=True)

    if payload is None:
        target.unlink(missing_ok=True)
    else:
        target.write_text(json.dumps(payload, indent=2) + "\n")

    if arguments.app:
        run("xcrun", "simctl", "install", arguments.udid, str(arguments.app))
    else:
        print("no --app given: reload the timelines yourself (reinstall or re-place the widget)",
              file=sys.stderr)

    if arguments.appearance:
        run("xcrun", "simctl", "ui", arguments.udid, "appearance", arguments.appearance)
    if arguments.content_size:
        run("xcrun", "simctl", "ui", arguments.udid, "content_size", arguments.content_size)

    print(f"staged {arguments.state} at {target}")

    if arguments.screenshot:
        time.sleep(arguments.wait)
        run("xcrun", "simctl", "io", arguments.udid, "screenshot", str(arguments.screenshot))
        print(f"captured {arguments.screenshot}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
