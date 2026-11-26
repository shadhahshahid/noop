#!/usr/bin/env bash
#
# Personal fork only (not upstream): capture screenshots of a DEBUG simulator build of NOOPiOS,
# populated by the app's own `--demo-seed` harness (120 days of synthetic data, no strap, no real
# health data). Used by .github/workflows/custom-ios-screenshots.yml so a change to a screen can be
# looked at before any build is installed on a phone.
#
# Usage:
#   Tools/custom-ios-screenshots.sh pick-sim
#       Prints "<udid> <name>" of an available iPhone simulator on the newest installed iOS runtime.
#   Tools/custom-ios-screenshots.sh capture <path/to/NOOP.app> <udid> <out-dir> [screen ...]
#       Installs the app on that simulator and writes one PNG per screen into <out-dir>.
#       "shell" is the full tab shell on its first tab and "tab1" … "tab4" open it on another tab;
#       every other name is passed to `--demo-screen <name>` (see DemoScreens in
#       StrandiOS/App/StrandiOSApp.swift). Add "-light" to any name to capture it in the light
#       theme. Add "+N" to also capture N further screenfuls below the first, for example
#       "shell+3" or "tab3-light+1"; those are written as <name>_p1.png … <name>_pN.png.
#       Capture stops early when a screenful is byte-identical to the one before it, which
#       happens on a screen that does not scroll; a screen with anything animating may repeat
#       its last screenful instead. With no screen names, a default set is captured.

set -euo pipefail

# First launch seeds the synthetic history before anything renders; later launches only draw.
SEED_WAIT="${SEED_WAIT:-45}"
DRAW_WAIT="${DRAW_WAIT:-10}"
# A full-size screenshot of a drawn screen is several hundred kilobytes; an all-black one is far smaller.
BLANK_BYTES="${BLANK_BYTES:-60000}"

pick_sim() {
  xcrun simctl list devices available --json | python3 -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "SimRuntime.iOS-" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.split("SimRuntime.iOS-")[1].split("-") if p.isdigit())
    for device in devices:
        name = device.get("name", "")
        if not device.get("isAvailable") or not name.startswith("iPhone"):
            continue
        # Prefer a standard-size phone over the small, large and budget variants.
        standard = not any(t in name for t in ("SE", "Plus", "Max", "Air", "mini", "16e", "17e"))
        key = (version, standard, "Pro" not in name)
        if best is None or key > best[0]:
            best = (key, device["udid"], name)
if best is None:
    sys.exit("no available iPhone simulator")
print(best[1], best[2])
'
}

capture() {
  local app="$1" udid="$2" out="$3"
  shift 3
  local screens=("$@")
  if [ "${#screens[@]}" -eq 0 ]; then
    screens=(shell tab1 tab2 tab3 tab4 forkmore forkstrap forkprofile forkscores live health
             shell-light forkmore-light)
  fi

  [ -d "$app" ] || { echo "no such app bundle: $app"; exit 1; }
  local bundle_id
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
  mkdir -p "$out"

  # Boots the device if needed and returns once it is ready.
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl ui "$udid" appearance dark
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 || echo "status bar override not available; continuing"
  xcrun simctl install "$udid" "$app"

  echo "seeding demo data (waiting ${SEED_WAIT}s)"
  xcrun simctl launch "$udid" "$bundle_id" --demo-seed
  sleep "$SEED_WAIT"

  local entry
  for entry in "${screens[@]}"; do
    # "name+N": N further screenfuls below the first one.
    local name="${entry%%+*}" pages=0
    case "$entry" in
      *+*) pages="${entry##*+}" ;;
    esac
    case "$pages" in
      ''|*[!0-9]*) echo "bad page count in '$entry'"; exit 2 ;;
    esac
    local base="$name"
    local args=(--demo-seed)
    case "$name" in
      *-light)
        base="${name%-light}"
        # An argument-domain default: forces the app's own Theme setting to Light for this launch.
        args+=(-theme.appearance light)
        ;;
    esac
    case "$base" in
      shell) ;;
      tab[0-4]) args+=(--demo-tab "${base#tab}") ;;
      *) args+=(--demo-screen "$base") ;;
    esac

    local page file previous=""
    for page in $(seq 0 "$pages"); do
      xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
      file="$out/$name.png"
      local page_args=("${args[@]}")
      if [ "$page" -gt 0 ]; then
        file="$out/${name}_p${page}.png"
        # DEBUG-only: scrolls the screen down by this many screenfuls (ForkDemoScroll).
        page_args+=(--demo-scroll-page "$page")
      fi
      xcrun simctl launch "$udid" "$bundle_id" "${page_args[@]}"
      sleep "$DRAW_WAIT"
      xcrun simctl io "$udid" screenshot "$file"
      # A picture this small is a blank frame: the app had not drawn yet. Wait and take it once more.
      if [ "$(wc -c < "$file")" -lt "$BLANK_BYTES" ]; then
        echo "blank frame for $(basename "$file"); retrying"
        sleep "$DRAW_WAIT"
        xcrun simctl io "$udid" screenshot "$file"
      fi
      # A screenful identical to the one before it means the bottom was already reached.
      if [ -n "$previous" ] && cmp -s "$previous" "$file"; then
        rm -f "$file"
        echo "bottom of $name reached before page $page"
        break
      fi
      previous="$file"
      echo "captured $(basename "$file")"
    done
  done
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true

  # Every requested screen must have produced a non-empty image.
  local missing=0
  for entry in "${screens[@]}"; do
    [ -s "$out/${entry%%+*}.png" ] || { echo "missing screenshot: ${entry%%+*}"; missing=1; }
  done
  [ "$missing" -eq 0 ] || exit 1
  ls -l "$out"
}

case "${1:-}" in
  pick-sim) pick_sim ;;
  capture)
    shift
    [ "$#" -ge 3 ] || { echo "usage: $0 capture <app> <udid> <out-dir> [screen ...]"; exit 2; }
    capture "$@"
    ;;
  *) echo "usage: $0 pick-sim | capture <app> <udid> <out-dir> [screen ...]"; exit 2 ;;
esac
