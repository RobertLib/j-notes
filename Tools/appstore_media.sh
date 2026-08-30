#!/bin/bash
#
# appstore_media.sh — regenerates every screenshot and App Preview in AppStore/.
#
#     Tools/appstore_media.sh                 # screenshots + previews
#     Tools/appstore_media.sh screenshots     # screenshots only
#     Tools/appstore_media.sh video           # previews only
#
# Needs Xcode, the simulators named below and ImageMagick (`brew install
# imagemagick`) for the lossless PNG squeeze. Everything is driven by the `-shot`
# launch argument handled in notes/Support/ScreenshotScenes.swift, which is
# `#if DEBUG` only — so this builds Debug, and none of it exists in the build
# that goes to the App Store.
#
# Output goes to AppStore/screenshots/<locale>/<device>/ and
# AppStore/preview/<locale>/<device>.mp4, where <device> is iphone-6.5 or
# ipad-13. Override the root with OUT_ROOT=… to try things out without touching
# the set you are about to upload.
#
# The plain screenshots are the app on its own. Tools/appstore_compose.sh turns
# them into the coloured, captioned, device-framed set that actually goes up —
# run it after this one.
#
set -euo pipefail

MODE="${1:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore}"
WORK="${WORK:-$(mktemp -d -t jnotes-appstore)}"
BID=cz.rob.notes

# Both devices record their App Store slot size natively, so nothing here is
# scaled or cropped:
#   iPhone 11 Pro Max → 1242 × 2688, one of the two sizes Connect takes for 6.5"
#   iPad Pro 13" (M5) → 2064 × 2752, one of the two it takes for iPad 13"
#
# **6.5" is the iPhone slot this listing uses**, and it is not interchangeable
# with 6.9": Apple derives every smaller size from the file you upload, but only
# within a slot, and a listing sitting on one refuses the other's file outright.
# The screenshots on the live listing are 6.9"; replacing them means moving the
# listing to the 6.5" slot in Connect, not mixing the two. If 6.9" is ever wanted
# as well, add "iPhone 17 Pro Max" at 1320 × 2868 alongside this one — `shoot`
# already takes the device and its expected size as arguments.
IPHONE_NAME="iPhone 11 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M5)"
IPHONE_SHOT_SIZE=(1242 2688)
IPAD_SHOT_SIZE=(2064 2752)

# Xcode ships the iPhone 11 Pro Max device *type* but does not always leave a
# ready-made device for it, so the 6.5" one is created on demand (see
# ensure_device). iOS 26 still runs on that hardware, which is why the current
# runtime pairs with it at all.
IPHONE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max
IPAD_TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB

# App Preview render sizes — the only two App Store Connect takes for these
# devices, and *not* the devices' own resolutions. See AppStore/screenshots.md
# before changing either.
IPHONE_VIDEO_SIZE=(886 1920)
IPAD_VIDEO_SIZE=(1200 1600)

# Prague. The map has to be somewhere, and the notes the pose seeds carry
# coordinates a few streets apart in Vinohrady, Letná and Smíchov — so the
# device is put there too, and the map's locate button has something honest to
# find. Matches Shots.Place in notes/Support/ScreenshotScenes.swift.
DEVICE_LOCATION="${DEVICE_LOCATION:-50.0810,14.4230}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

udid_for() {
    # Device lines are indented four spaces and read "<name> (<udid>) (<state>)".
    # Matched as a fixed string, because names like "iPad Pro 13-inch (M5)" carry
    # brackets of their own; the trailing " (" keeps "iPhone 11" from matching
    # "iPhone 11 Pro Max".
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' \
        | head -n 1 || true
}

ensure_device() { # ensure_device <name> <device-type-id> -> udid on stdout
    local udid; udid="$(udid_for "$1")"
    if [ -z "$udid" ]; then
        # Newest installed runtime. simctl refuses a pairing the runtime does
        # not support, so a device type that has aged out fails here rather than
        # producing something that never boots. Messages go to stderr, because
        # the caller reads this function's stdout.
        local rt
        rt="$(xcrun simctl list runtimes available \
              | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' \
              | tail -n 1)"
        [ -n "$rt" ] || { echo "no iOS simulator runtime installed" >&2; return 1; }
        echo "  creating simulator '$1' on ${rt##*.}" >&2
        xcrun simctl create "$1" "$2" "$rt" >/dev/null || return 1
        udid="$(udid_for "$1")"
    fi
    printf '%s' "$udid"
}

boot_and_install() {
    local udid="$1"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    # A pose seeds the notes file, and the app writes to it from then on like any
    # other run would, so each shot starts from a clean install rather than from
    # whatever the last one left behind.
    xcrun simctl uninstall "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    # 9:41 and a full battery, unplugged. `--batteryState charged` is the
    # plugged-in glyph — a green cell with a bolt through it — which reads as a
    # phone on charge rather than as a phone. Apple's own marketing shots do not
    # have one.
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --batteryState discharging --batteryLevel 100 \
        --cellularMode active --cellularBars 4 \
        --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true
    # The map frames the notes' own coordinates, but the locate button and the
    # blue dot need the device to be somewhere.
    xcrun simctl location "$udid" set "$DEVICE_LOCATION" >/dev/null 2>&1 || true
    # And the permission has to be granted ahead of the pose rather than asked
    # for during it. Without this the map shot photographs the system's location
    # prompt sitting over the map — which is a real screen the app shows, and not
    # one anybody wants on the store page. The prompt is also modal enough to
    # survive into the next pose, so it takes the shot after it down too.
    xcrun simctl privacy "$udid" grant location "$BID" >/dev/null 2>&1 || true
    # Face ID enrolled, so a protected note opens onto its unlock gate instead of
    # straight onto the text. Without an enrolled device `NoteLock` correctly
    # decides there is no way in and shows the note unlocked — which is the right
    # behaviour and the wrong screenshot. There is no simctl verb for this; the
    # notification is the one the daemon listens on.
    xcrun simctl spawn "$udid" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1 \
        >/dev/null 2>&1 || true
    xcrun simctl spawn "$udid" notifyutil -p com.apple.BiometricKit.enrollmentChanged \
        >/dev/null 2>&1 || true
}

locale_args() {
    case "$1" in
        cs)    printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(cs)" -AppleLocale cs_CZ ;;
        en-US) printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(en-US)" -AppleLocale en_US ;;
    esac
}

launch() { # launch <udid> <locale> <args...>
    local udid="$1" loc="$2"; shift 2
    local largs=()
    while IFS= read -r -d '' a; do largs+=("$a"); done < <(locale_args "$loc")
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BID" "${largs[@]}" "$@" >/dev/null
}

# A pose seeds its notes before the store reads them, but what happens after the
# first frame is not instant: a push animation, the map's tiles arriving, a
# drawing being rendered. The app drops a marker file once its own settle time
# has elapsed (Shots.markReady), so nothing here has to sleep for a guess — and
# the map's four seconds are not paid on the other seven shots.
container_for() { xcrun simctl get_app_container "$1" "$BID" data; }

clear_ready() { rm -f "$(container_for "$1")/Documents/shot-ready" 2>/dev/null || true; }

wait_ready() { # wait_ready <udid> <timeout-seconds>
    local marker="$(container_for "$1")/Documents/shot-ready"
    local waited=0
    while [ ! -f "$marker" ] && [ "$waited" -lt "$2" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    # stderr, because the caller reads this function's stdout.
    [ -f "$marker" ] || { echo "  !! pose never became ready (${2}s)" >&2; return 1; }
    printf '%s' "$waited"
}

# ---------------------------------------------------------------- build

say "Building Debug for the simulator"
xcodebuild -project "$ROOT/notes.xcodeproj" -scheme notes \
    -configuration Debug -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$WORK/dd" build >/dev/null
APP="$WORK/dd/Build/Products/Debug-iphonesimulator/J-Notes.app"

IPHONE_UDID="$(ensure_device "$IPHONE_NAME" "$IPHONE_TYPE" || true)"
IPAD_UDID="$(ensure_device "$IPAD_NAME" "$IPAD_TYPE" || true)"
[ -n "$IPHONE_UDID" ] \
    || { echo "no simulator named '$IPHONE_NAME', and creating one failed"; exit 1; }
[ -n "$IPAD_UDID" ] \
    || { echo "no simulator named '$IPAD_NAME', and creating one failed"; exit 1; }

# ---------------------------------------------------------------- screenshots

# The pose names, in upload order. Which notes each one seeds and what it opens
# is in Shots — this list only says which of them to photograph and in what
# order. Order matters more than count: most people never scroll past the second
# shot, so the first two carry the app on their own.
SHOTS=(
    01-list
    02-locked
    03-drawing
    04-checklist
    05-calendar
    06-map
    07-detail
)

shoot() { # shoot <udid> <locale> <device-dir> <W> <H>
    local udid="$1" loc="$2" dev="$3" w="$4" h="$5"
    local dir="$OUT_ROOT/screenshots/$loc/$dev"
    mkdir -p "$dir"
    for name in "${SHOTS[@]}"; do
        clear_ready "$udid"
        launch "$udid" "$loc" -shot "$name"
        local waited
        waited="$(wait_ready "$udid" 60)" || exit 1
        xcrun simctl io "$udid" screenshot "$dir/$name.png" >/dev/null 2>&1
        local size
        size="$(magick identify -format '%wx%h' "$dir/$name.png")"
        printf '  %-14s %-10s ready in %2ss\n' "$name" "$size" "$waited"
        # Both devices record their slot size, so a mismatch means the simulator
        # is not the one this script expects rather than something to paper over.
        if [ "$size" != "${w}x${h}" ]; then
            echo "     !! expected ${w}x${h} — wrong simulator or a changed runtime"
            exit 1
        fi
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

if [ "$MODE" = all ] || [ "$MODE" = screenshots ]; then
    command -v magick >/dev/null \
        || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    for loc in en-US cs; do
        say "Screenshots — iPhone 6.5\" / $loc"
        shoot "$IPHONE_UDID" "$loc" iphone-6.5 "${IPHONE_SHOT_SIZE[@]}"
        say "Screenshots — iPad 13\" / $loc"
        shoot "$IPAD_UDID" "$loc" ipad-13 "${IPAD_SHOT_SIZE[@]}"
    done

    # The simulator writes RGBA even though every pixel is opaque, and App Store
    # Connect wants screenshots without transparency. Dropping the channel leaves
    # the picture untouched and saves about a third of the size — verified rather
    # than assumed, and anything that is not identical is left alone.
    say "Squeezing PNGs (lossless)"
    while IFS= read -r f; do
        magick "$f" -alpha off -depth 8 -strip \
                    -define png:compression-level=9 \
                    -define png:compression-filter=5 "$f.opt"
        if [ "$(magick compare -metric AE "$f" "$f.opt" null: 2>&1 | awk '{print $1}')" = "0" ]; then
            mv "$f.opt" "$f"
        else
            rm -f "$f.opt"
            echo "  left as-is (not identical): $f"
        fi
    done < <(find "$OUT_ROOT/screenshots" -name '*.png')
    du -sh "$OUT_ROOT/screenshots"
fi

# ---------------------------------------------------------------- previews

# One recording, of the app walking itself through its own navigation.
#
# `simctl io recordVideo` writes a frame when the screen *changes* and not
# otherwise, so a recording of a notes app sitting still is a recording of
# nothing: the app is up about a second after launch and then emits no further
# frames at all. Measured, on the list pose: content at 1.0 s, and the last frame
# in a twelve-second recording is at 1.92 s. The first preview built here was
# three such recordings cut together, and it held three still pictures for
# eighteen seconds — each opening on the splash screen, because the splash was
# the only thing in shot that moved.
#
# So there is one clip rather than three, and the app moves itself through it:
# list, calendar, map, back to the list, a note, a drawing. The schedule is
# `Shots.tour` in notes/Support/ScreenshotScenes.swift, next to the notes it
# opens; the seconds below only have to be long enough to contain it.
CLIPS=(
    "tour|22|-shot preview-tour"
)

# One window, and it is the whole tour: from just after the app has replaced the
# splash to just after the last step has settled. There is nothing to cut between
# when the take is continuous — which is also what removes the sister project's
# hazard of a window drifting off the action, since the only two edges here are
# the start and the end.
#
# The start is measured, not guessed: launch at 0, splash from about 0.4, the
# list from 1.0. 1.2 opens on the list with the splash gone. The iPad reaches
# each state a little sooner than the iPhone, which is why the two have their
# own points.
#
# The end is bounded by the recording rather than by the number here. A file
# written by recordVideo ends at its last frame, and its last frame is the last
# thing that moved — so a window reaching past the tour's final step is silently
# clamped to it, and the preview comes out shorter than asked for. The total has
# to land inside Connect's 15-30 s, and appstore_conform.swift refuses the file
# if it does not, which is how this was found.
#
# Which is also why the tour has one more step than the preview shows. 18.6 lands
# between the tour's fifth step and its sixth, so the preview ends holding the
# locked note; the sixth is underneath it, keeping frames coming so that the hold
# is a hold rather than a clamp. Moving this number means moving that step.
IPHONE_CUTS=(tour:1.2:18.6)
IPAD_CUTS=(tour:1.1:18.5)

record() { # record <udid> <locale> <clipdir>
    local udid="$1" loc="$2" dir="$3"
    mkdir -p "$dir"
    for entry in "${CLIPS[@]}"; do
        IFS='|' read -r name secs args <<<"$entry"
        clear_ready "$udid"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" $args
        xcrun simctl io "$udid" recordVideo --codec h264 --force "$dir/$name.mp4" >/dev/null 2>&1 &
        local pid=$!
        sleep "$secs"
        kill -INT $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        sleep 1
        printf '  %-10s %s\n' "$name" "$(avmediainfo "$dir/$name.mp4" | awk '/^Duration:/{print $2 "s"}')"
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

assemble() { # assemble <clipdir> <out.mp4> <W> <H> <cut...>
    local dir="$1" out="$2" w="$3" h="$4"; shift 4
    mkdir -p "$(dirname "$out")"
    local specs=()
    for cut in "$@"; do specs+=("$dir/${cut%%:*}.mp4:${cut#*:}"); done
    swift "$ROOT/Tools/appstore_video.swift" "$out" "$w" "$h" "${specs[@]}"
    # What comes out of the cut is the right size and the wrong everything else
    # for App Store Connect — too high a profile, too fast a bit rate and no
    # audio at all. This pins the lot to Apple's table. There is deliberately no
    # music: see the header of appstore_conform.swift for what goes on the audio
    # track instead, and why it cannot simply be empty.
    swift "$ROOT/Tools/appstore_conform.swift" "$out" "$w" "$h"
}

if [ "$MODE" = all ] || [ "$MODE" = video ]; then
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    for loc in en-US cs; do
        say "Preview — iPhone 6.5\" / $loc"
        record "$IPHONE_UDID" "$loc" "$WORK/clips/iphone-$loc"
        assemble "$WORK/clips/iphone-$loc" "$OUT_ROOT/preview/$loc/iphone-6.5.mp4" \
            "${IPHONE_VIDEO_SIZE[@]}" "${IPHONE_CUTS[@]}"

        say "Preview — iPad 13\" / $loc"
        record "$IPAD_UDID" "$loc" "$WORK/clips/ipad-$loc"
        assemble "$WORK/clips/ipad-$loc" "$OUT_ROOT/preview/$loc/ipad-13.mp4" \
            "${IPAD_VIDEO_SIZE[@]}" "${IPAD_CUTS[@]}"
    done
fi

say "Done. Working files in $WORK"
