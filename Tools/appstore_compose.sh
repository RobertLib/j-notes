#!/bin/bash
#
# appstore_compose.sh — turns the plain screenshots into the ones that go up.
#
#     Tools/appstore_compose.sh
#
# Reads AppStore/screenshots/<locale>/<device>/*.png and writes
# AppStore/screenshots-composed/<locale>/<device>/*.png with the same names, so
# either set can be uploaded and the order is unchanged. Needs only ImageMagick
# — no simulator and no build.
#
# The layout is the one already on the live listing: a flat saturated colour, a
# heading in white across the top, and the screenshot in a device frame below it,
# running off the bottom edge. Every proportion below was measured off the shots
# currently on the store rather than invented, so a new set drops in beside the
# old one without the listing changing character halfway down.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN_ROOT="${IN_ROOT:-$ROOT/AppStore/screenshots}"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore/screenshots-composed}"

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
[ -d "$IN_ROOT" ] || { echo "no screenshots in $IN_ROOT — run Tools/appstore_media.sh first"; exit 1; }

# SF Pro Rounded, which is what the headings on the live listing are set in, and
# the only rounded face on a stock macOS with complete Czech diacritics — Arial
# Rounded Bold has neither ť nor ě, and would drop them silently. Given as a
# path, not as a name: the Homebrew build has no fontconfig type map, so
# `-font SFNSRounded` fails and takes the heading with it while still exiting 0.
#
# ImageMagick instantiates a variable font at its default weight, so this comes
# out Regular however it is asked for. The weight is put back with a stroke of
# the fill colour, which is what STROKE below is for: 4% of the point size is
# about a Bold, measured against the live shots letter by letter.
FONT="${FONT:-/System/Library/Fonts/SFNSRounded.ttf}"
[ -f "$FONT" ] || { echo "no font at $FONT — set FONT=/path/to/font.ttf"; exit 1; }

TEXT='#FFFFFF'
BEZEL='#0B0B0D'   # the phone's body
RIM='#5C5C61'     # the hairline the titanium edge catches

# One colour per shot, in upload order, from the family already on the listing:
# the app's own accent orange, the yellow the splash gradient fades to, and the
# purple and blue the note colours use. Each shot gets its own so the row of
# thumbnails in search results reads as a set rather than as one long block.
colour_for() {
    case "$1" in
        01-list)      printf '#FEC800' ;;
        02-locked)    printf '#8E67E8' ;;
        03-drawing)   printf '#1BB0F7' ;;
        04-checklist) printf '#28BF6A' ;;
        05-calendar)  printf '#F2607A' ;;
        06-map)       printf '#FF9600' ;;
        07-detail)    printf '#5B6BE1' ;;
        *)            printf '#FF9600' ;;
    esac
}

# The captions. Two or three lines each, broken by hand: leaving one word alone
# on the last line looks like an accident. Order matches the shot order, and the
# second one carries the promise the whole listing rests on — most people never
# scroll past it.
en_caption() {
    case "$1" in
        01-list)      printf 'Your notes.\nOn your phone.\nNowhere else.' ;;
        02-locked)    printf 'Lock a note\nbehind Face ID' ;;
        03-drawing)   printf 'Sketch it\nwhen writing it\nwould take longer' ;;
        04-checklist) printf 'Tick things off\ninside the note' ;;
        05-calendar)  printf 'Reminders that\nactually arrive' ;;
        06-map)       printf 'Every note remembers\nwhere you wrote it' ;;
        07-detail)    printf 'No ads. No account.\nNo subscription.' ;;
    esac
}

cs_caption() {
    case "$1" in
        01-list)      printf 'Vaše poznámky.\nVe vašem telefonu.\nNikde jinde.' ;;
        02-locked)    printf 'Zamkněte poznámku\npod Face ID' ;;
        03-drawing)   printf 'Nakreslete to,\nco by se psalo\ndéle' ;;
        04-checklist) printf 'Odškrtávejte\npřímo v poznámce' ;;
        05-calendar)  printf 'Připomínky,\nkteré opravdu dorazí' ;;
        06-map)       printf 'Každá poznámka ví,\nkde vznikla' ;;
        07-detail)    printf 'Bez reklam. Bez účtu.\nBez předplatného.' ;;
    esac
}

caption_for() { # caption_for <locale> <name>
    case "$1" in
        cs) cs_caption "$2" ;;
        *)  en_caption "$2" ;;
    esac
}

# Proportions, measured off the shots on the live listing and expressed against
# the canvas so an iPhone and an iPad shot are laid out the same way rather than
# the iPad getting a device a third of the size. The numbers are per mille,
# because bash has no fractions.
DEVICE_W_PM=793      # device body, as a fraction of the canvas width
DEVICE_TOP_PM=282    # top of the device, as a fraction of the canvas height
BEZEL_PM=30          # body around the screen, as a fraction of the canvas width
POINT_PM=113         # heading size, as a fraction of the canvas width
TEXT_WIDTH_PM=790    # the widest a heading line may be before it is shrunk
TEXT_HEIGHT_PM=780   # the tallest a heading block may be, against the band

compose() { # compose <in.png> <out.png> <locale> <name> <notch|plain>
    local src="$1" dst="$2" loc="$3" name="$4" style="$5"
    local W H
    # The newline matters: `read` returns non-zero at EOF without one, and under
    # `set -e` that ends the run with no output at all.
    read -r W H < <(magick identify -format '%w %h\n' "$src")

    local bg;   bg="$(colour_for "$name")"
    local text; text="$(caption_for "$loc" "$name")"

    local dev_w=$((W * DEVICE_W_PM / 1000))
    local bezel=$((W * BEZEL_PM / 1000))
    local dev_x=$(((W - dev_w) / 2))
    local dev_y=$((H * DEVICE_TOP_PM / 1000))
    local screen_w=$((dev_w - 2 * bezel))
    # The device runs off the bottom of the canvas on purpose — it is what makes
    # the shot read as a phone in the hand rather than as a product photo — so
    # the body is drawn taller than the space left for it and simply ends.
    local dev_h=$((H - dev_y + bezel))

    # Screen corners follow the hardware: about 8.8% of the screen's width on
    # every iPhone since the X, and a much softer proportion on an iPad. The body
    # is the screen's radius plus the bezel, which is what keeps the two curves
    # concentric — a body radius chosen on its own is the single thing that makes
    # a drawn frame look drawn.
    local screen_r body_r
    if [ "$style" = notch ]; then
        screen_r=$((screen_w * 88 / 1000))
    else
        screen_r=$((screen_w * 45 / 1000))
    fi
    body_r=$((screen_r + bezel))

    # The screenshot, scaled to the screen width and with its corners rounded.
    # Scaled, never cropped sideways: the status bar at the top and the tab bar
    # at the bottom both have to survive at their own proportions. What is cut is
    # only what falls past the bottom edge of the canvas, which is the same thing
    # the device body does.
    local screen_h=$((dev_h - 2 * bezel))
    local scaled_h=$((H * screen_w / W))
    # `-compose Over` is put back before the `-extent`, and it is not optional:
    # `-extent` composites the picture onto its new canvas using whatever compose
    # operator is current, so the CopyOpacity left over from the line above turns
    # the finished screen back into its own mask. Silently — a grey rounded
    # rectangle is a perfectly valid image, and the only symptom is a device with
    # nothing in it.
    magick "$src" -resize "${screen_w}x${scaled_h}!" \
        \( -size "${screen_w}x${scaled_h}" xc:black -fill white \
           -draw "roundrectangle 0,0 $((screen_w-1)),$((scaled_h-1)) $screen_r,$screen_r" \) \
        -alpha off -compose CopyOpacity -composite +repage \
        -compose Over -background none -extent "${screen_w}x${screen_h}" \
        "$WORK/screen.png"

    # The body: a rounded black rectangle with a hairline rim, the screen laid
    # into it, and — on the iPhone — the notch painted back on. The simulator's
    # framebuffer has no notch in it; the status bar simply leaves a gap where
    # one would be, so without this the shot reads as a phone that does not exist.
    local notch_w=$((screen_w * 500 / 1000))
    local notch_h=$((screen_w * 72 / 1000))
    local notch_x=$(((screen_w - notch_w) / 2))
    local notch_r=$((notch_h * 45 / 100))

    magick -size "${dev_w}x${dev_h}" xc:none \
        -fill "$BEZEL" -stroke "$RIM" -strokewidth "$((bezel / 6 + 1))" \
        -draw "roundrectangle 0,0 $((dev_w-1)),$((dev_h-1)) $body_r,$body_r" \
        "$WORK/screen.png" -geometry "+${bezel}+${bezel}" -composite \
        "$WORK/body.png"

    if [ "$style" = notch ]; then
        magick "$WORK/body.png" -fill "$BEZEL" -stroke none \
            -draw "roundrectangle $((bezel + notch_x)),$((bezel - notch_r)) $((bezel + notch_x + notch_w)),$((bezel + notch_h)) $notch_r,$notch_r" \
            "$WORK/body.png"
    fi

    # The heading is centred in the space above the device, not pinned to the
    # top: a two-line caption and a three-line one then sit on the same optical
    # line instead of one of them clinging to the top edge.
    local point=$((W * POINT_PM / 1000))

    # Then shrunk until the widest line fits inside the margins. Measured rather
    # than guessed, and it is the Czech set that needs it — "Vaše poznámky." is
    # three characters longer than "Your notes." and the captions are broken by
    # hand, so a size chosen to suit English quietly runs a Czech line off both
    # edges. A line that fits is left at full size.
    local widest=0 line_w
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        line_w="$(magick -font "$FONT" -pointsize "$point" \
                         -strokewidth "$((point * 4 / 100))" \
                         label:"$line" -format '%w' info:)"
        [ "$line_w" -gt "$widest" ] && widest=$line_w
    done < <(printf '%s\n' "$text")

    local max_w=$((W * TEXT_WIDTH_PM / 1000))
    if [ "$widest" -gt "$max_w" ] && [ "$widest" -gt 0 ]; then
        point=$((point * max_w / widest))
    fi

    # And again against the height of the band, which is what an iPad needs. Its
    # canvas is 3:4 where the iPhone's is closer to 1:2, so the same fraction of
    # the width is a far larger fraction of the space above the device: a
    # three-line heading sized for the phone came down over the top of the iPad's
    # own frame. A line of this face occupies about 1.25 x its point size, and
    # `-interline-spacing` adds a fifth of one between lines.
    local lines; lines="$(printf '%s\n' "$text" | awk 'END { print NR }')"
    local band=$dev_y
    local max_h=$((band * TEXT_HEIGHT_PM / 1000))
    local block=$((lines * point * 125 / 100 + (lines - 1) * point / 5))
    if [ "$block" -gt "$max_h" ] && [ "$block" -gt 0 ]; then
        point=$((point * max_h / block))
        block=$((lines * point * 125 / 100 + (lines - 1) * point / 5))
    fi

    local stroke=$((point * 4 / 100))
    local offset=$(((band - block) / 2))
    [ "$offset" -lt 0 ] && offset=0

    magick -size "${W}x${H}" "xc:$bg" \
        \( "$WORK/body.png" \
           \( +clone -background black -shadow "40x$((W / 70))+0+$((W / 200))" \) \
           +swap -background none -layers merge +repage \) \
        -gravity northwest -geometry "+$((dev_x - W / 70))+$((dev_y - W / 70))" -composite \
        -font "$FONT" -pointsize "$point" \
        -fill "$TEXT" -stroke "$TEXT" -strokewidth "$stroke" \
        -interline-spacing "$((point / 5))" \
        -gravity north -annotate "+0+${offset}" "$text" \
        -crop "${W}x${H}+0+0" +repage \
        -alpha off -depth 8 -strip \
        -define png:compression-level=9 "$dst"
}

WORK="$(mktemp -d -t jnotes-compose)"
trap 'rm -rf "$WORK"' EXIT

for loc_dir in "$IN_ROOT"/*; do
    [ -d "$loc_dir" ] || continue
    loc="$(basename "$loc_dir")"
    for dev_dir in "$loc_dir"/*; do
        [ -d "$dev_dir" ] || continue
        dev="$(basename "$dev_dir")"
        case "$dev" in
            iphone-*) style=notch ;;
            *)        style=plain ;;
        esac
        out="$OUT_ROOT/$loc/$dev"
        mkdir -p "$out"
        printf '\n\033[1m%s / %s\033[0m\n' "$loc" "$dev"
        for src in "$dev_dir"/*.png; do
            name="$(basename "$src" .png)"
            compose "$src" "$out/$name.png" "$loc" "$name" "$style"
            printf '  %-14s %s\n' "$name" "$(magick identify -format '%wx%h' "$out/$name.png")"
        done
    done
done

du -sh "$OUT_ROOT"
