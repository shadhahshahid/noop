#!/usr/bin/env python3
"""Personal fork only (not upstream): write and check the fork's own AltStore source.

The source lets AltStore install and update the fork's builds with one tap. AltStore refuses a
source build unless three things hold, so this tool derives all of them from the packaged .ipa
itself rather than from hand-kept lists:

  * the listed version and build number equal the app's (CFBundleShortVersionString / CFBundleVersion);
  * every privacy permission the app or its extensions request (NS…UsageDescription) is declared;
  * every entitlement the app or its extensions carry is declared.

Usage:
  custom-altstore-source.py build <ipa> --download-url URL --out source.json
                                  [--previous old-source.json] [--notes TEXT] [--label TEXT] [--date YYYY-MM-DD]
      Writes the source with this build as its newest version. Older versions listed in
      --previous are kept (newest first, at most KEEP_VERSIONS).

  custom-altstore-source.py check <source.json> <ipa>
      Applies AltStore's install checks to the newest listed version. Exit status 0 when every
      check passes, 1 otherwise; each failed check is printed.

`codesign` is needed to read entitlements, so this runs on macOS only.
"""

import argparse
import datetime
import hashlib
import json
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO = "shadhahshahid/noop"
SOURCE_URL = f"https://raw.githubusercontent.com/{REPO}/altstore/source.json"
# Must differ from upstream's "com.noopapp.noop.altstore": AltStore refuses a second source with an
# identifier it already has.
SOURCE_ID = "io.github.shadhahshahid.noop.altstore"
UPSTREAM_SOURCE_ID = "com.noopapp.noop.altstore"
BUNDLE_ID = "com.noopapp.noop"
ICON_URL = ("https://github.com/ryanbr/noop/raw/main/Strand/Resources/Assets.xcassets/"
            "AppIcon.appiconset/icon_512x512.png")
TINT = "3DDC97"
MIN_OS = "17.0"
KEEP_VERSIONS = 5

PRIVACY_KEY = re.compile(r"^NS[A-Za-z]+UsageDescription$")
# Added by the sideloader when it signs the app; never part of what a source declares.
IGNORED_ENTITLEMENTS = {
    "application-identifier",
    "com.apple.developer.team-identifier",
    "keychain-access-groups",
}


class Problem(Exception):
    """A fault in the inputs, reported as one line."""


def read_app(ipa: Path) -> dict:
    """Version, build, privacy strings and entitlements of the app inside the archive."""
    if not ipa.is_file():
        raise Problem(f"no such file: {ipa}")
    try:
        archive = zipfile.ZipFile(ipa)
    except zipfile.BadZipFile:
        raise Problem(f"not a readable zip: {ipa}")
    with archive, tempfile.TemporaryDirectory(prefix="noop-source-") as work:
        archive.extractall(work)
        apps = [p for p in (Path(work) / "Payload").glob("*.app") if p.is_dir()]
        if len(apps) != 1:
            raise Problem(f"expected exactly one .app in Payload, found {len(apps)}")
        app = apps[0]
        bundles = [app] + sorted(p for p in (app / "PlugIns").glob("*.appex") if p.is_dir())

        info = plistlib.loads((app / "Info.plist").read_bytes())
        privacy: dict = {}
        entitlements: set = set()
        for bundle in bundles:
            bundle_info = plistlib.loads((bundle / "Info.plist").read_bytes())
            for key, value in bundle_info.items():
                if PRIVACY_KEY.match(key):
                    privacy.setdefault(key, str(value))
            signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)],
                                    capture_output=True)
            if signed.returncode != 0:
                raise Problem(f"could not read the code signature of {bundle.name}")
            if signed.stdout.strip():
                entitlements.update(plistlib.loads(signed.stdout).keys())

        return {
            "bundle_id": info.get("CFBundleIdentifier", ""),
            "version": info.get("CFBundleShortVersionString", ""),
            "build": info.get("CFBundleVersion", ""),
            "privacy": dict(sorted(privacy.items())),
            "entitlements": sorted(entitlements - IGNORED_ENTITLEMENTS),
        }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def build(args) -> int:
    ipa = Path(args.ipa)
    app = read_app(ipa)
    if app["bundle_id"] != BUNDLE_ID:
        raise Problem(f"bundle id is '{app['bundle_id']}', expected '{BUNDLE_ID}'")
    if not app["version"] or not app["build"]:
        raise Problem("the app has no version or build number")
    if not args.download_url.startswith(f"https://github.com/{REPO}/releases/download/"):
        raise Problem("the download URL must be a release asset of the fork")

    date = args.date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    notes = args.notes or f"Personal fork build {app['version']} ({app['build']})."
    entry = {
        "version": app["version"],
        "buildVersion": app["build"],
        "date": date,
        "localizedDescription": notes,
        "downloadURL": args.download_url,
        "size": ipa.stat().st_size,
        "sha256": sha256(ipa),
        "minOSVersion": MIN_OS,
    }
    if args.label:
        entry["marketingVersion"] = args.label

    older = []
    if args.previous:
        try:
            previous = json.loads(Path(args.previous).read_text(encoding="utf-8"))
            older = previous["apps"][0]["versions"]
        except (OSError, ValueError, KeyError, IndexError, TypeError):
            raise Problem(f"could not read the versions in {args.previous}")
    same = lambda v: (v.get("version"), v.get("buildVersion")) == (entry["version"], entry["buildVersion"])
    versions = ([entry] + [v for v in older if not same(v)])[:KEEP_VERSIONS]

    source = {
        "name": "NOOP (personal fork)",
        "identifier": SOURCE_ID,
        "sourceURL": SOURCE_URL,
        "subtitle": "One person's redesigned build of NOOP. Not the official source.",
        "description": ("Builds of a personal fork of NOOP, the independent open-source WHOOP companion "
                        "(https://github.com/ryanbr/noop). Compiled by GitHub Actions from "
                        f"https://github.com/{REPO}. Unofficial and unsupported; the official source "
                        "is the one to use unless this fork is yours."),
        "iconURL": ICON_URL,
        "website": f"https://github.com/{REPO}",
        "tintColor": TINT,
        "apps": [{
            "name": "NOOP",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Personal fork of NoopApp",
            "subtitle": "Read your own WHOOP strap, fully offline.",
            "localizedDescription": ("A personal fork of NOOP with a redesigned interface. It reads a WHOOP "
                                     "strap you own directly over Bluetooth, with no account and no cloud; "
                                     "everything stays on your iPhone. Not affiliated with WHOOP or with "
                                     "the NOOP project."),
            "iconURL": ICON_URL,
            "tintColor": TINT,
            "category": "healthcare-fitness",
            "screenshotURLs": [],
            "versions": versions,
            "appPermissions": {
                "entitlements": app["entitlements"],
                "privacy": app["privacy"],
            },
            # Legacy top-level fields, mirrored from the newest version for older clients.
            "version": entry["version"],
            "buildVersion": entry["buildVersion"],
            "versionDate": entry["date"],
            "versionDescription": entry["localizedDescription"],
            "downloadURL": entry["downloadURL"],
            "size": entry["size"],
            "minOSVersion": MIN_OS,
        }],
        "news": [],
    }
    Path(args.out).write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {args.out}: {entry['version']} ({entry['buildVersion']}), {entry['size']} bytes, "
          f"{len(app['privacy'])} privacy permissions, {len(app['entitlements'])} entitlements, "
          f"{len(versions)} version(s) listed")
    return 0


def check(args) -> int:
    ipa = Path(args.ipa)
    app = read_app(ipa)
    try:
        source = json.loads(Path(args.source).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise Problem(f"could not read {args.source} as JSON")

    fails = 0

    def verdict(ok: bool, passed: str, failed: str) -> None:
        nonlocal fails
        if ok:
            print(f"ok:   {passed}")
        else:
            print(f"FAIL: {failed}")
            fails += 1

    identifier = source.get("identifier", "") if isinstance(source, dict) else ""
    verdict(bool(identifier) and identifier != UPSTREAM_SOURCE_ID,
            f"source identifier is its own ({identifier})",
            f"source identifier '{identifier}' is missing or is the official source's")

    listings = [a for a in source.get("apps", []) if isinstance(a, dict)] if isinstance(source, dict) else []
    listing = next((a for a in listings if a.get("bundleIdentifier") == app["bundle_id"]), None)
    if listing is None or not listing.get("versions"):
        print(f"FAIL: the source lists no version of {app['bundle_id']}")
        print(f"FAILED: {fails + 1} check(s) on {Path(args.source).name}")
        return 1
    newest = listing["versions"][0]

    verdict(newest.get("version") == app["version"],
            f"version matches the app ({app['version']})",
            f"source lists version '{newest.get('version')}', the app is '{app['version']}'")
    verdict(newest.get("buildVersion") == app["build"],
            f"build number matches the app ({app['build']})",
            f"source lists build '{newest.get('buildVersion')}', the app is '{app['build']}'")
    verdict(newest.get("size") == ipa.stat().st_size,
            "size matches the file",
            f"source lists size {newest.get('size')}, the file is {ipa.stat().st_size}")
    verdict(newest.get("sha256") == sha256(ipa),
            "sha256 matches the file",
            "sha256 in the source does not match the file")
    url = str(newest.get("downloadURL", ""))
    verdict(url.startswith(f"https://github.com/{REPO}/releases/download/") and url.endswith(ipa.name),
            "download URL is this file on the fork's releases",
            f"download URL '{url}' is not this file on the fork's releases")

    declared = listing.get("appPermissions") or {}
    declared_privacy = set((declared.get("privacy") or {}).keys())
    declared_entitlements = set(declared.get("entitlements") or [])
    missing_privacy = sorted(set(app["privacy"]) - declared_privacy)
    missing_entitlements = sorted(set(app["entitlements"]) - declared_entitlements)
    verdict(not missing_privacy,
            f"all {len(app['privacy'])} privacy permissions are declared",
            "privacy permissions not declared by the source: " + ", ".join(missing_privacy))
    verdict(not missing_entitlements,
            f"all {len(app['entitlements'])} entitlements are declared",
            "entitlements not declared by the source: " + ", ".join(missing_entitlements))

    builds = [(v.get("version"), v.get("buildVersion")) for v in listing["versions"]]
    verdict(len(builds) == len(set(builds)),
            f"every listed version is distinct ({len(builds)} listed)",
            "the same version and build number is listed twice")

    if fails == 0:
        print(f"PASS: {Path(args.source).name} will install {ipa.name}")
        return 0
    print(f"FAILED: {fails} check(s) on {Path(args.source).name}")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Write and check the fork's AltStore source.")
    commands = parser.add_subparsers(dest="command", required=True)

    build_cmd = commands.add_parser("build")
    build_cmd.add_argument("ipa")
    build_cmd.add_argument("--download-url", required=True)
    build_cmd.add_argument("--out", required=True)
    build_cmd.add_argument("--previous")
    build_cmd.add_argument("--notes")
    build_cmd.add_argument("--label")
    build_cmd.add_argument("--date")
    build_cmd.set_defaults(run=build)

    check_cmd = commands.add_parser("check")
    check_cmd.add_argument("source")
    check_cmd.add_argument("ipa")
    check_cmd.set_defaults(run=check)

    args = parser.parse_args()
    try:
        return args.run(args)
    except Problem as problem:
        print(f"FAIL: {problem}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
