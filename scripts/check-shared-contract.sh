#!/bin/bash
#
# The widget reads its notes out of an App Group container the main app writes to,
# and the two targets share no code — so the group identifier, the UserDefaults
# keys and the payload's shape are each spelled out twice. A mismatch is invisible
# at build time: the widget's `try?` decode just returns nil and it renders
# "No notes" forever, on every home screen, until someone notices.
#
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

APP=notes/AppGroup.swift
WIDGET=NotesWidget/NotesWidget.swift

# Value of a `static let <name> = "..."` declaration.
literal_for() {
    grep -oE "static let $2 = \"[^\"]+\"" "$1" \
        | head -1 \
        | sed -E 's/.*"([^"]+)"/\1/'
}

compare_literal() {
    local name=$1 app_value widget_value

    app_value=$(literal_for "$APP" "$name")
    widget_value=$(literal_for "$WIDGET" "$name")

    if [ -z "$app_value" ] || [ -z "$widget_value" ]; then
        echo "FAIL  $name: not declared in both $APP and $WIDGET"
        status=1
    elif [ "$app_value" != "$widget_value" ]; then
        echo "FAIL  $name: \"$app_value\" in the app, \"$widget_value\" in the widget"
        status=1
    else
        echo "ok    $name: \"$app_value\" in both targets"
    fi
}

compare_literal identifier
compare_literal widgetDataKey
compare_literal widgetTotalKey

# The widget's deep link is built in the widget and taken apart in the app, so
# the scheme and the host are spelled twice as well. A mismatch compiles, and the
# tap still opens the app — just on the list rather than on the note that was
# pressed, which is indistinguishable from the widget having no link at all.
compare_literal scheme
compare_literal noteHost

# And the scheme has to be declared, or iOS routes the URL nowhere. It lives in
# notes/Info.plist because CFBundleURLTypes is an array of dictionaries, which the
# INFOPLIST_KEY_* build settings that generate the rest of that plist cannot
# express. Asserted from the source plist rather than the built one so this stays
# a checkout-only check — the built plist is covered in CI alongside the usage
# descriptions.
APP_PLIST=notes/Info.plist
declared_schemes=$(
    /usr/libexec/PlistBuddy -c Print "$APP_PLIST" 2>/dev/null \
        | grep -A5 'CFBundleURLSchemes' \
        | sed -nE 's/^[[:space:]]+([a-zA-Z][a-zA-Z0-9.+-]*)$/\1/p'
)

if grep -qxF "$(literal_for "$APP" scheme)" <<<"$declared_schemes"; then
    echo "ok    $APP_PLIST declares the $(literal_for "$APP" scheme): URL scheme"
else
    echo "FAIL  $APP_PLIST does not declare the $(literal_for "$APP" scheme): URL scheme"
    status=1
fi

# Without the entitlement the suite silently resolves to nil at runtime and the
# app's writes go nowhere, so the identifier has to be granted to both targets.
group=$(literal_for "$APP" identifier)

for entitlements in notes/notes.entitlements NotesWidgetExtension.entitlements; do
    if grep -q "<string>$group</string>" "$entitlements"; then
        echo "ok    $entitlements grants $group"
    else
        echo "FAIL  $entitlements does not grant $group"
        status=1
    fi
done

# Stored properties of a struct, as "name type" lines. The payload is keyed
# JSON, so declaration order does not matter to the decoder — but a renamed or
# retyped field breaks it, and that is what this compares.
fields_in() {
    awk -v name="$2" '
        $0 ~ "^struct " name "[:{ ]" { inside = 1; next }
        inside && /^}/ { exit }
        inside && $1 == "let" { sub(":", "", $2); print $2, $3 }
    ' "$1" | sort
}

if ! diff_output=$(diff \
    <(fields_in "$APP" WidgetNoteEntry) \
    <(fields_in "$WIDGET" WidgetNote)); then
    echo "FAIL  payload shape differs between WidgetNoteEntry and WidgetNote"
    echo "$diff_output" | sed 's/^/        /'
    status=1
else
    echo "ok    payload shape: $(fields_in "$APP" WidgetNoteEntry | wc -l | tr -d ' ') fields match"
fi

# An untitled note has no title of its own, so `displayTitle` falls back to its
# content — which means a view that also prints `content` underneath renders the
# same text twice, headline and caption both, on every home screen. `bodyPreview`
# is the property that decides when there is a second line to show at all, and
# reaching past it for `.content` is exactly how that regressed. The widget target
# has no unit tests of its own to catch it — it shares no code with the app, which
# is why this file exists — so the rule is asserted structurally: only `WidgetNote`
# itself may read the field.
#
# Matches member access (`note.content`), not the initialiser label (`content:`)
# the placeholder and preview entries are built from.
body_leak=0

while IFS= read -r offender; do
    echo "FAIL  widget reads a note's .content outside WidgetNote: $offender"
    body_leak=1
    status=1
done < <(
    awk '
        /^struct WidgetNote[:{ ]/ { inside = 1; next }
        inside && /^}/ { inside = 0; next }
        inside { next }
        /[A-Za-z_][A-Za-z0-9_]*\.content([^A-Za-z0-9_:]|$)/ {
            gsub(/^[[:space:]]+/, "")
            print FILENAME ":" FNR ": " $0
        }
    ' "$WIDGET"
)

if [ "$body_leak" -eq 0 ]; then
    echo "ok    the widget reads a note's body only through bodyPreview"
fi

# What stands in for a protected note's body is spelled out twice as well. The app
# has it as `NoteModel.redactedBody` — a constant precisely because it had drifted
# between call sites, redacting the same note to a different width depending on
# which list it appeared in — and the widget, sharing no code, repeats the literal
# in `WidgetNote.displayTitle`. The same drift, one target further out, and the one
# place it shows is the home screen. Compared by the bullets themselves rather than
# by a declaration, since the widget's is a bare literal.
MODEL=notes/Models/NoteModel.swift

app_redaction=$(grep -oE 'redactedBody = "[^"]+"' "$MODEL" | head -1 | sed -E 's/.*"([^"]+)"/\1/')
widget_redactions=$(grep -oE '"•+"' "$WIDGET" | tr -d '"' | sort -u)

if [ -z "$app_redaction" ]; then
    echo "FAIL  redactedBody: not declared in $MODEL"
    status=1
elif [ -z "$widget_redactions" ]; then
    echo "FAIL  redactedBody: the widget renders no redacted body at all"
    status=1
elif [ "$widget_redactions" != "$app_redaction" ]; then
    echo "FAIL  redactedBody: ${#app_redaction} bullets in the app, the widget uses:"
    printf '%s\n' "$widget_redactions" | sed 's/^/        /'
    status=1
else
    echo "ok    redactedBody: ${#app_redaction} bullets in both targets"
fi

# The widget has its own asset catalog, so the accent colour is declared twice as
# well — and `Color.accentColor` in the widget resolves against the widget's copy.
# The template leaves that colorset defined but *empty*, which compiles, ships no
# `Assets.car` at all, and silently renders as the system blue next to an orange
# app. Both are colour references (`systemOrangeColor`) rather than components, so
# comparing them is a string compare.
accent_reference_in() {
    /usr/bin/python3 -c '
import json, sys
colors = json.load(open(sys.argv[1]))["colors"]
for entry in colors:
    color = entry.get("color")
    if color:
        print(color.get("reference") or json.dumps(color.get("components"), sort_keys=True))
        break
' "$1"
}

app_accent=$(accent_reference_in notes/Assets.xcassets/AccentColor.colorset/Contents.json)
widget_accent=$(accent_reference_in NotesWidget/Assets.xcassets/AccentColor.colorset/Contents.json)

if [ -z "$app_accent" ] || [ -z "$widget_accent" ]; then
    echo "FAIL  AccentColor: defined but carries no colour in one of the two catalogs"
    status=1
elif [ "$app_accent" != "$widget_accent" ]; then
    echo "FAIL  AccentColor: $app_accent in the app, $widget_accent in the widget"
    status=1
else
    echo "ok    AccentColor: $app_accent in both catalogs"
fi

exit "$status"
