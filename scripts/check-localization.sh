#!/bin/bash
#
# Verifies that every localization carries the same set of keys, and that no key
# referenced from Swift is missing. A missing key is invisible at build time —
# the app just renders the raw key to the user — so it is checked here instead.
#
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

# Keys defined in a .strings file, one per line, sorted.
keys_in() {
    grep -oE '^[[:space:]]*"[^"]+"' "$1" | tr -d ' "' | sort
}

compare_bundle() {
    local label=$1 base=$2 translation=$3

    if ! diff_output=$(diff <(keys_in "$base") <(keys_in "$translation")); then
        echo "FAIL  $label: key sets differ between $(basename "$(dirname "$base")") and $(basename "$(dirname "$translation")")"
        echo "$diff_output" | sed 's/^/        /'
        status=1
    else
        echo "ok    $label: $(keys_in "$base" | wc -l | tr -d ' ') keys in parity"
    fi
}

compare_bundle "app" notes/en.lproj/Localizable.strings notes/cs.lproj/Localizable.strings
compare_bundle "widget" NotesWidget/en.lproj/Localizable.strings NotesWidget/cs.lproj/Localizable.strings
compare_bundle "shortcuts" notes/en.lproj/AppShortcuts.strings notes/cs.lproj/AppShortcuts.strings
compare_bundle "infoplist" notes/en.lproj/InfoPlist.strings notes/cs.lproj/InfoPlist.strings

# The usage descriptions are localized by a file of their own, and it was the one
# localized file nothing here looked at — so a key translated in `en` and missing
# from `cs` shipped the English sentence to a Czech user, in the one dialog the
# system puts in front of them before handing over the camera or Face ID. Exactly
# the silent failure the parity checks above exist to catch, one file further out.
#
# Checked against the build settings as well, because `InfoPlist.strings` only
# localizes keys that already exist: the generated plist is built from the
# `INFOPLIST_KEY_*` settings in the project, so a fourth usage description added
# there and left out of these files is untranslated everywhere, and an entry left
# in these files whose setting has gone localizes nothing at all. Neither is
# visible at build time, and CI's assertion on the built plist only covers the
# three keys it names.
usage_description_settings() {
    grep -oE 'INFOPLIST_KEY_NS[A-Za-z]+UsageDescription' notes.xcodeproj/project.pbxproj \
        | sed -E 's/^INFOPLIST_KEY_//' \
        | sort -u
}

usage_description_keys() {
    keys_in notes/en.lproj/InfoPlist.strings | grep -E 'UsageDescription$' || true
}

if ! diff_output=$(diff <(usage_description_settings) <(usage_description_keys)); then
    echo "FAIL  infoplist: usage descriptions in the project and in InfoPlist.strings disagree"
    echo "        < declared as an INFOPLIST_KEY_* build setting but not localized"
    echo "        > localized but declared by no build setting"
    echo "$diff_output" | sed 's/^/        /'
    status=1
else
    echo "ok    infoplist: $(usage_description_settings | wc -l | tr -d ' ') usage descriptions declared and localized"
fi

# App Intents rejects a spoken phrase that does not name the app, and it does so
# at build time — but only for the phrases it can see. A translation that drops
# the token would fail the same way, so it is checked before it reaches a build.
while IFS= read -r file; do
    while IFS= read -r phrase; do
        if [[ "$phrase" != *'${applicationName}'* ]]; then
            echo "FAIL  shortcuts: phrase in $file is missing \${applicationName}: $phrase"
            status=1
        fi
    done < <(grep -oE '= *"[^"]+"' "$file" | sed -E 's/^= *"//; s/"$//')
done < <(printf '%s\n' notes/en.lproj/AppShortcuts.strings notes/cs.lproj/AppShortcuts.strings)

# The plural dictionaries deliberately differ — Czech needs `few` and `many`
# where English does not — so only the top-level key names are compared.
plural_keys_in() {
    /usr/libexec/PlistBuddy -c Print "$1" 2>/dev/null \
        | grep -E '^    [A-Za-z]+ = Dict' \
        | awk '{print $1}' \
        | sort
}

if ! diff_output=$(diff \
    <(plural_keys_in notes/en.lproj/Localizable.stringsdict) \
    <(plural_keys_in notes/cs.lproj/Localizable.stringsdict)); then
    echo "FAIL  stringsdict: plural keys differ between en and cs"
    echo "$diff_output" | sed 's/^/        /'
    status=1
else
    echo "ok    stringsdict: plural keys in parity"
fi

# Every key used from Swift must exist. Covers the explicit lookups
# (String(localized:), NSLocalizedString, LocalizedStringKey,
# LocalizedStringResource), accessibility labels, and App Intents strings —
# rather than every bare Text("...") literal, which cannot be told apart from
# display text.
missing=0
plural_keys=$(plural_keys_in notes/en.lproj/Localizable.stringsdict)

while IFS= read -r key; do
    # Format-argument keys are stored with their placeholder, e.g. "errorFileRead %@".
    if grep -qE "^[[:space:]]*\"${key}( %@)?\"" notes/en.lproj/Localizable.strings; then
        continue
    fi

    # Plurals live in the stringsdict instead.
    if grep -qxF "$key" <<<"$plural_keys"; then
        continue
    fi

    echo "FAIL  key referenced from Swift but not defined: $key"
    missing=1
    status=1
done < <(
    {
        grep -rhoE '(String\(localized: "|NSLocalizedString\("|LocalizedStringKey\("|LocalizedStringResource\(")[a-zA-Z][a-zA-Z0-9]*' notes/ \
            | sed -E 's/.*"//'

        # Accessibility labels are bare LocalizedStringKey literals, and some are
        # picked with a ternary, so every quoted word on the call counts.
        grep -rhoE '\.accessibility(Label|Value)\([^)]*\)' notes/ \
            | grep -oE '"[a-zA-Z][a-zA-Z0-9]*"' \
            | tr -d '"'

        # App Intents takes LocalizedStringResource in assignment and argument
        # position, where no call syntax marks it. The project spells those keys
        # with an `intent` prefix precisely so they can be found here.
        grep -rhoE '"intent[A-Za-z0-9]*' notes/ | sed -E 's/^"//'

        # The SwiftUI views take `LocalizedStringKey` in their leading argument, so
        # a key written there carries nothing to mark it as one — `Text("noNotes")`,
        # `Button("cancel")`, `.navigationTitle("notes")`. None of the scans above
        # can see those, and they are the bulk of what the app actually renders.
        #
        # Restricted to identifier-shaped literals, which is what tells a key from
        # the display text the same initialiser equally takes: anything carrying a
        # space or a full stop is prose, `Text(verbatim:)` does not match, and an
        # interpolated literal starts with a backslash. That leaves a bare English
        # word used as display text as the one thing this would report wrongly —
        # and the fix for that is to make it a key, which is what it should have
        # been.
        #
        # Deliberately the leading argument only, rather than every quoted word in
        # the call the way the accessibility scan above can afford to be. `Label`
        # takes an SF Symbol name in its second argument, and those are
        # identifier-shaped too — `Label("marker", systemImage: "highlighter")`
        # would report `highlighter` as a missing key.
        grep -rhoE '(Text|Section|Button|Toggle|Picker|TextField|Label|ContentUnavailableView)\("[a-zA-Z][a-zA-Z0-9]*"|\.(navigationTitle|alert|confirmationDialog)\("[a-zA-Z][a-zA-Z0-9]*"' notes/ \
            | sed -E 's/.*"([^"]+)"/\1/'

        # The leading argument is not always a bare literal: it can be a ternary
        # picking between two of them, which is how the list's empty state chooses
        # between "you have no notes" and "nothing matched your search". Matched
        # only in that exact shape — the condition, then two identifier-shaped
        # literals — so the symbol name in a `Label`'s second argument still cannot
        # be mistaken for a key, and a ternary between two non-literals
        # (`note.isProtected ? NoteModel.redactedBody : note.content`) matches
        # nothing.
        grep -rhoE '(Text|Section|Button|Toggle|Picker|TextField|Label|ContentUnavailableView)\([^",)]*\?[[:space:]]*"[a-zA-Z][a-zA-Z0-9]*"[[:space:]]*:[[:space:]]*"[a-zA-Z][a-zA-Z0-9]*"' notes/ \
            | grep -oE '"[a-zA-Z][a-zA-Z0-9]*"' \
            | tr -d '"'

        # An enum that renders itself through `LocalizedStringKey(rawValue)` makes a
        # key of every one of its cases, and the rawValue is a variable — so the
        # literal scans above see none of them. `NoteSortOption` and
        # `NoteDisplayStyle` reach the sort and display menus with seven keys this
        # way, and a renamed case would have shipped the raw name to the menu.
        while IFS= read -r file; do
            awk '
                /^enum [A-Za-z_][A-Za-z0-9_]*[^{]*:[^{]*String/ {
                    inside = 1; count = 0; renders = 0; next
                }
                # Only a brace in the first column closes the enum; the ones
                # belonging to its properties are indented.
                inside && /^}/ {
                    if (renders) for (i = 0; i < count; i++) print cases[i]
                    inside = 0
                    next
                }
                inside && /LocalizedStringKey\(rawValue\)/ { renders = 1 }
                # An explicit raw value, and the implicit one a bare case carries.
                # `case .foo:` inside a switch matches neither, since a dot is not
                # the start of an identifier.
                inside && /^[[:space:]]*case [A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*"[^"]+"/ {
                    value = $0
                    sub(/^[^"]*"/, "", value)
                    sub(/".*$/, "", value)
                    cases[count++] = value
                }
                inside && /^[[:space:]]*case [A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/ {
                    cases[count++] = $2
                }
            ' "$file"
        done < <(grep -rl 'LocalizedStringKey(rawValue)' notes/ --include='*.swift')
    } | sort -u
)

if [ "$missing" -eq 0 ]; then
    echo "ok    every key referenced from Swift is defined"
fi

# The Shortcuts action's parameter summary is localized by its entire format
# string — App Intents records no key of its own for it — and the placeholders
# in that string are `${parameter}`, not the `\(\.$parameter)` written in Swift.
# So the scan above can neither see it nor compare it literally: the key is
# rebuilt here the way the system will look it up. Missing it leaves the action
# summary in English in every other language, which is what happened for the
# intent's title and description before they became keys.
summary_missing=0

while IFS= read -r summary; do
    [ -n "$summary" ] || continue

    key=$(printf '%s' "$summary" | perl -pe 's/\\\(\\\.\$(\w+)\)/\${$1}/g')

    if ! grep -qF "\"$key\"" notes/en.lproj/Localizable.strings; then
        echo "FAIL  parameter summary referenced from Swift but not defined: $key"
        summary_missing=1
        status=1
    fi
done < <(grep -rhoE 'Summary\("[^"]*"\)' notes/ | sed -E 's/^Summary\("//; s/"\)$//')

if [ "$summary_missing" -eq 0 ]; then
    echo "ok    every App Intents parameter summary is defined"
fi

# The widget is a separate target with its own Localizable.strings, and the scan
# above only looks at notes/ — so nothing used to check the widget's keys existed
# at all. Its strings render on the home screen, where a raw key is as visible as
# it gets.
widget_missing=0

# Key names exactly as written, spaces and all: the widget's keys are English
# sentences ("No notes"), which the parity check's whitespace-stripping form
# would mangle.
key_names_in() {
    sed -nE 's/^[[:space:]]*"([^"]+)".*/\1/p' "$1"
}

while IFS= read -r key; do
    if ! grep -qE "^[[:space:]]*\"${key}\"" NotesWidget/en.lproj/Localizable.strings; then
        echo "FAIL  widget key referenced from Swift but not defined: $key"
        widget_missing=1
        status=1
    fi
done < <(
    grep -rhoE '(String\(localized: "|NSLocalizedString\("|LocalizedStringKey\(")[^"]+' NotesWidget/ \
        | sed -E 's/.*"//' \
        | sort -u
)

# Checked from the other side as well, which is what catches a rename: the
# widget's remaining keys are bare `Text("...")` literals, indistinguishable from
# display text going forwards, but a key left defined and unused is decidable.
# A brand-new undefined literal still slips through — the same residual gap the
# app has, and the reason the parity check above exists too.
while IFS= read -r key; do
    if ! grep -rqF "\"$key\"" NotesWidget/*.swift; then
        echo "FAIL  widget key defined but referenced nowhere in Swift: $key"
        widget_missing=1
        status=1
    fi
done < <(key_names_in NotesWidget/en.lproj/Localizable.strings)

if [ "$widget_missing" -eq 0 ]; then
    echo "ok    widget keys and their Swift references agree in both directions"
fi

exit "$status"
