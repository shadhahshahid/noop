#!/usr/bin/env bash
#
# Personal fork only (not upstream): check a packaged sideload .ipa before anyone installs it.
#
# The checks cover what an install OVER an existing NOOP depends on: the app keeps the expected
# bundle identifier (otherwise iOS installs it as a separate, empty app), the widget extension is
# present and shares the app's App Group, and the capability template that AltStore / SideStore
# reads still requests HealthKit and the App Group. Nothing in the archive is executed.
#
# Usage:
#   Tools/custom-verify-ios-ipa.sh path/to/NOOP.ipa [expected-bundle-id] [expected-version]
#
# Exit status 0 when every check passes, 1 otherwise. Every failed check is printed.

set -uo pipefail

IPA="${1:?usage: $0 path/to/NOOP.ipa [expected-bundle-id] [expected-version]}"
WANT_ID="${2:-com.noopapp.noop}"
WANT_VERSION="${3:-}"

fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
pass() { echo "ok:   $*"; }
# Prints the value, or nothing when the key or the file is missing (PlistBuddy reports errors on stdout).
plist() { local v; v=$(/usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null) || v=""; printf '%s' "$v"; }

[ -f "$IPA" ] || { echo "FAIL: no such file: $IPA"; exit 1; }

WORK=$(mktemp -d /tmp/noop-verify-ipa.XXXXXX)
cleanup() { if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT

if unzip -tq "$IPA" >/dev/null 2>&1; then
  pass "archive is a readable zip"
else
  echo "FAIL: archive is not a readable zip"
  exit 1
fi
unzip -q "$IPA" -d "$WORK" || { echo "FAIL: could not unpack archive"; exit 1; }

APP_COUNT=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$APP_COUNT" != "1" ]; then
  echo "FAIL: expected exactly one .app in Payload, found $APP_COUNT"
  exit 1
fi
APP=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d | head -1)
WIDGET="$APP/PlugIns/NOOPWidgets.appex"

APP_ID=$(plist "$APP/Info.plist" CFBundleIdentifier)
VERSION=$(plist "$APP/Info.plist" CFBundleShortVersionString)
BUILD=$(plist "$APP/Info.plist" CFBundleVersion)
APP_GROUP=$(plist "$APP/Info.plist" AppGroupIdentifier)

if [ "$APP_ID" = "$WANT_ID" ]; then pass "bundle id is $APP_ID"; else fail "bundle id is '$APP_ID', expected '$WANT_ID'"; fi
if [ -n "$VERSION" ] && [ -n "$BUILD" ]; then pass "version $VERSION ($BUILD)"; else fail "version or build number is empty"; fi
if [ -n "$WANT_VERSION" ]; then
  if [ "$VERSION" = "$WANT_VERSION" ]; then pass "version matches $WANT_VERSION"; else fail "version is '$VERSION', expected '$WANT_VERSION'"; fi
fi
if [ -n "$APP_GROUP" ]; then pass "app group is $APP_GROUP"; else fail "AppGroupIdentifier is empty"; fi

if [ -d "$APP/Watch" ]; then fail "Watch folder is present (the sideload build must not carry it)"; else pass "no Watch folder"; fi

if [ -d "$WIDGET" ]; then
  WIDGET_ID=$(plist "$WIDGET/Info.plist" CFBundleIdentifier)
  WIDGET_GROUP=$(plist "$WIDGET/Info.plist" AppGroupIdentifier)
  if [ "$WIDGET_ID" = "$WANT_ID.widgets" ]; then pass "widget bundle id is $WIDGET_ID"; else fail "widget bundle id is '$WIDGET_ID', expected '$WANT_ID.widgets'"; fi
  if [ "$WIDGET_GROUP" = "$APP_GROUP" ]; then pass "widget shares the app group"; else fail "widget app group '$WIDGET_GROUP' differs from the app's '$APP_GROUP'"; fi
else
  fail "widget extension is missing: PlugIns/NOOPWidgets.appex"
fi

# The capability template: the ad-hoc signature's entitlements are what the sideloader provisions.
entitlement() { codesign -d --entitlements :- "$1" 2>/dev/null > "$WORK/ent.plist"; plist "$WORK/ent.plist" "$2"; }
SIGNED_GROUP=$(entitlement "$APP" 'com.apple.security.application-groups:0')
SIGNED_HEALTH=$(entitlement "$APP" 'com.apple.developer.healthkit')
if [ -n "$APP_GROUP" ] && [ "$SIGNED_GROUP" = "$APP_GROUP" ]; then pass "app requests its app group"; else fail "app does not request its app group (found '$SIGNED_GROUP')"; fi
if [ "$SIGNED_HEALTH" = "true" ]; then pass "app requests HealthKit"; else fail "app does not request HealthKit"; fi
if [ -d "$WIDGET" ]; then
  SIGNED_WIDGET_GROUP=$(entitlement "$WIDGET" 'com.apple.security.application-groups:0')
  if [ -n "$APP_GROUP" ] && [ "$SIGNED_WIDGET_GROUP" = "$APP_GROUP" ]; then pass "widget requests the app group"; else fail "widget does not request the app group (found '$SIGNED_WIDGET_GROUP')"; fi
fi

if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then pass "code seal is intact"; else fail "code seal does not verify (the bundle changed after signing)"; fi

if [ "$fails" -eq 0 ]; then
  echo "PASS: $(basename "$IPA") is safe to hand to a sideloader"
  exit 0
fi
echo "FAILED: $fails check(s) on $(basename "$IPA")"
exit 1
