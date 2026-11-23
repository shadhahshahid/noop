#!/usr/bin/env bash
#
# Personal fork only (not upstream): make a copy of the official AltServer 1.8.4 for macOS (Intel)
# that can sign in to Apple again, as a stopgap until the AltStore project ships its own fix.
#
# The fault: AltServer describes the Mac to Apple's sign-in server with the word "macOS" on macOS 11
# and later, and since about 19 Nov 2026 that server answers HTTP 503 to it. "Mac OS X" is accepted
# (altstoreio/AltStore issues 1871 and 1877; the source fix is pull request 1875):
#
#     let osName = (osVersion.majorVersion < 11) ? "Mac OS X" : "macOS"
#
# What this does, and all it does:
#   1. Refuses to run unless the installed app is exactly the official 1.8.4 build this was written
#      against (checked by the SHA-256 of its program file).
#   2. Copies the app to a folder of your choice. The installed app is never modified.
#   3. In the copy, keeps only the Intel half of the program and changes 7 bytes in it, so the
#      choice above always yields "Mac OS X". Every byte around them is checked first.
#   4. Re-signs the copy ad hoc, because changing a program invalidates the developer's signature.
#
# The copy is therefore NOT signed by the AltStore developer. Apart from those 7 bytes, the dropped
# Apple-silicon half and the signature, it is the official app.
#
# Usage:
#   Tools/custom-altserver-503fix.sh <destination-folder>
# Result: <destination-folder>/AltServer.app

set -euo pipefail

SRC="/Applications/AltServer.app"
DEST_DIR="${1:?usage: $0 <destination-folder>}"
DEST="$DEST_DIR/AltServer.app"

WANT_VERSION="1.8.4"
WANT_BUILD="101"
# SHA-256 of Contents/MacOS/AltServer in the official AltServer 1.8.4 (101), universal.
WANT_SHA="f572afc38e3a42937717fced36b1b12cdab54a5af9d431d6335a5d139793d50e"

[ "$(uname -m)" = "x86_64" ] || { echo "FAIL: this fix is written for an Intel Mac only"; exit 1; }
[ -d "$SRC" ] || { echo "FAIL: $SRC not found"; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$SRC/Contents/Info.plist"; }
[ "$(plist CFBundleShortVersionString)" = "$WANT_VERSION" ] && [ "$(plist CFBundleVersion)" = "$WANT_BUILD" ] \
  || { echo "FAIL: installed AltServer is $(plist CFBundleShortVersionString) ($(plist CFBundleVersion)), expected $WANT_VERSION ($WANT_BUILD)"; exit 1; }
GOT_SHA=$(shasum -a 256 "$SRC/Contents/MacOS/AltServer" | cut -d' ' -f1)
[ "$GOT_SHA" = "$WANT_SHA" ] || { echo "FAIL: installed AltServer is not the official 1.8.4 build this fix was written for"; exit 1; }
codesign --verify --deep --strict "$SRC" || { echo "FAIL: the installed AltServer's own signature does not verify"; exit 1; }
echo "ok:   installed AltServer is the official $WANT_VERSION ($WANT_BUILD), signature intact"

[ ! -e "$DEST" ] || { echo "FAIL: $DEST already exists; move it away first"; exit 1; }
mkdir -p "$DEST_DIR"
ditto "$SRC" "$DEST"
BIN="$DEST/Contents/MacOS/AltServer"
lipo "$BIN" -thin x86_64 -output "$BIN.intel"
mv "$BIN.intel" "$BIN"
chmod 755 "$BIN"

python3 -I - "$BIN" <<'EOF'
import sys

path = sys.argv[1]
data = bytearray(open(path, "rb").read())

# The compiled form of the line quoted at the top of this script, at its known place in the Intel
# program: compare the macOS major version with 11, then pick one of two short strings and its length.
OFFSET = 0x8A2FC
BEFORE = bytes.fromhex(
    "4883f90b"                # cmp    rcx, 11
    "48b94d6163204f532058"    # movabs rcx, "Mac OS X"
    "48ba6d61634f53000000"    # movabs rdx, "macOS"            <- changed
    "480f4cd1"                # cmovl  rdx, rcx
    "48899518ffffff"          # mov    [rbp-0xe8], rdx
    "49be00000000000000e5"    # movabs r14, length 5 marker     <- changed
    "4c0f4cf0"                # cmovl  r14, rax
)
AFTER = bytes.fromhex(
    "4883f90b"
    "48b94d6163204f532058"
    "48ba4d6163204f532058"    # movabs rdx, "Mac OS X"
    "480f4cd1"
    "48899518ffffff"
    "49be00000000000000e8"    # movabs r14, length 8 marker
    "4c0f4cf0"
)
assert len(BEFORE) == len(AFTER)
if bytes(data[OFFSET:OFFSET + len(BEFORE)]) != BEFORE:
    sys.exit("FAIL: the program does not contain the expected code at the expected place")
if data.count(BEFORE) != 1:
    sys.exit("FAIL: the expected code appears more than once")
original = bytes(data)
data[OFFSET:OFFSET + len(AFTER)] = AFTER
# Proof over the WHOLE program, before it is re-signed: same length, and exactly 7 bytes differ.
differing = [i for i in range(len(original)) if original[i] != data[i]]
if len(data) != len(original) or len(differing) != 7:
    sys.exit(f"FAIL: expected exactly 7 changed bytes, got {len(differing)}")
if not all(OFFSET <= i < OFFSET + len(AFTER) for i in differing):
    sys.exit("FAIL: a byte outside the expected code changed")
open(path, "wb").write(data)
print("ok:   changed exactly 7 bytes of the Intel program, all inside that one choice;")
print("      the OS name sent to Apple is now always \"Mac OS X\"")
EOF

# The developer's signature no longer matches a changed program, so replace it with an ad-hoc one.
# No hardened runtime: without the developer's identity the app could not load its own frameworks.
codesign --force --deep --sign - "$DEST" 2>/dev/null
codesign --verify --deep --strict "$DEST" || { echo "FAIL: the copy's new signature does not verify"; exit 1; }
echo "ok:   copy re-signed ad hoc and its seal verifies"

echo "PASS: fixed copy is at $DEST"
