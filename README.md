# J-Notes

A modern, feature-rich notes application for iOS and iPadOS built with SwiftUI.

## Features

### 📝 Core Functionality

- **Text and drawing notes** — type, or sketch with PencilKit
- **Checklists** with tappable checkboxes inside note text
- **Color-coded notes** for better organization
- **Tags** with quick filtering. Tags that differ only in case are one tag — the
  search field had always matched them that way, while the chip row showed two
  chips for one tag, each hiding the other's notes. A filter also cannot outlive
  the tag it names: deleting the last note carrying it used to take the chip away
  and leave the filter behind, and where it was the only tag the whole row went
  with it — an empty list, no explanation, and nothing left on screen to clear it
  with short of relaunching
- **Pin important notes** to keep them at the top
- **Search** across titles, content and tags
- **Sort and display styles** (compact / standard / detailed), remembered between launches
- **Trash** — deleted notes are recoverable and purged automatically after 30
  days, emptied in one go when you would rather not wait, and openable: a row
  showed a hundred characters and a drawing showed nothing at all, so deciding
  whether a note was worth keeping meant restoring it to find out. A note opened
  out of the trash offers Restore and Delete permanently in place of Edit and
  Delete — editing something already deleted writes to a note nobody can see, and
  Delete would have moved it into a trash it is already in
- **Adapts to the iPad**, where the list and the note it was picked from sit side
  by side rather than a column of text down the middle of a very wide screen. One
  list serves both: its rows carry a value, which a stack pushes and a split view
  selects. Rotating, or dragging the app in and out of Split View, carries
  whatever is open across rather than closing it
- A storage problem is reported wherever you are. The alert used to belong to the
  list, and an alert attached to a screen in an unselected tab is not presented —
  so a save that failed while the calendar or the map was in front turned up on
  the next trip back to the list instead: the right message at an arbitrary
  moment, long after whatever caused it

### 🎨 Drawing

- Pen, marker and pencil tools with adjustable width and color
- Photo library or camera image as a drawing background — a note whose only
  content is the photo saves too, since the photo is what it renders
- Pinch-to-zoom viewing of finished drawings
- Sharing a drawing hands over the picture itself, rendered as a PNG only if the
  share actually goes ahead

### 📅 Calendar Integration

- Calendar view listing notes by their **reminder** date

### 🗺️ Location-Based Notes

- The note's location is captured once, when it is created, from a recent fix
- View notes on an interactive map, grouped by location
- The map re-centres on you when you ask it to, not every time a fix arrives, so
  it stays where you panned it — including across a trip to another tab and back,
  which used to re-frame the camera and throw the pan away by the other door. The
  one exception is the very first look, where there is no stored fix to frame on —
  it asks for one and follows it, rather than parking on a default city and
  staying there
- Asking to be located moves the map with the fix already on hand and then follows
  whatever arrives next, rather than only reacting to a new one. `requestLocation`
  hands back a recent cached reading, so standing still delivers the identical
  coordinates twice — and a locate button whose only effect was to react to a
  *change* did nothing at all in exactly the case it is pressed in most
- If location access has been refused, the button says so and points at Settings
  instead of being inert. A permission that has not been asked for yet is left to
  the system prompt, which is the feedback
- A fix is asked for when the user does something that needs one, not on every
  launch. Core Location reports the current authorization once merely because a
  delegate was assigned, and reading that as a grant that had just landed meant an
  already-authorized app fetched the user's location at every start — status bar
  indicator and all — however little of the app they went on to use

### ⏰ Reminders

- Set reminders for your notes
- Local notifications to keep you on track
- A reminder that fires while the app is on screen still shows as a banner. iOS
  suppresses a foreground notification outright unless the app says otherwise,
  and the reminder defaults to five minutes out — so the one you set while
  finishing a note is exactly the one that used to go missing
- Tapping a reminder opens the note it belongs to, wherever the app was left. A
  protected note still opens locked and asks for Face ID first. A tap that lands
  before the notes are readable is kept and routed once they are, rather than
  opening nothing — a store that has read nothing cannot say a note is gone
- The icon stays bare while the app is open. The badge counts reminders you have
  been handed but not yet seen, and being in the app means you have seen them —
  which is now written down when you open it, rather than being implied by an
  icon that gets cleared. The reminders themselves deliberately stay in
  Notification Centre, since that is where a missed one is still reviewable, so
  without that mark the ones you had already read went on being counted into the
  number the *next* reminder arrived carrying: three read yesterday and one set
  today showed up as four
- A badge is fixed into the notification when it is scheduled, so setting a
  reminder that fires ahead of one already waiting — or cancelling the one that
  was next in line — re-numbers the rest. Without that, a reminder arriving
  second still showed the number it was given while it was first
- If the notification will not fire — because notifications are denied, or
  because iOS is already holding as many pending reminders as it keeps — the note
  says so and keeps the date you picked
- That last check counts the whole queue, not just the reminders due ahead of the
  new one. iOS keeps the *soonest* 64 and drops the rest silently, so a reminder
  set for this afternoon joined a full queue at the front, was kept — and pushed
  the latest one out. The reminder that stopped existing was one you had set
  earlier and had no reason to look at again, and the new one was being protected
  at its expense
- A reminder that has already passed keeps its date too, so editing anything else
  about the note does not quietly drop it out of the calendar

### 🔐 Privacy & Security

- Data stored locally on your device — nothing is sent to a server
- Notes file written with `.completeFileProtection`, so it is unreadable while the device is locked
- Individual notes can be locked behind Face ID / Touch ID, and an unlocked one
  is covered before iOS takes its app-switcher snapshot — while it is being read
  and while it is being edited
- A locked note's reminder reaches the lock screen with neither its title nor
  its body — both are user text, so both give way to a label
- Search does not look inside a locked note's body. Its title and tags are
  searchable, since the row shows those either way, but a note surfacing for a
  word only its body contains would give the body away
- Privacy-focused design with PrivacyInfo manifest

### 🧩 System Integration

- **Home screen widget** (small, medium and large) showing recent notes, pinned
  first. Tapping a note opens that note, not the list — the medium family shows
  three and the large one six, so a link for the widget as a whole would have been
  wrong most of the time. The link names the note and the app resolves it against
  the store, so one that has been edited, locked or trashed since the widget last
  drew it opens in whatever state it is in now — and one followed from a locked
  home screen, before the notes file is readable, is kept and opened once it is,
  exactly as a tapped reminder is
- **Lock Screen widgets** in all three accessory shapes: the newest note as a
  line, as a title with a body line, or just how many notes there are. Nothing
  extra is withheld for them — the payload they read is already written for a
  screen that is by definition not unlocked, with a protected note carrying
  neither its title nor its body
- A protected note shows its padlock in every widget family. The small one drew
  the redacted bullets alone, which reads as broken text rather than as something
  deliberately held back
- The splash screen gets out of the way of a launch that already has somewhere to
  go. Six tenths of a second is not much, but it was being spent on precisely the
  launches where the user had already said what they wanted: a tapped reminder, a
  note pressed on the home screen
- **Dark and tinted app icon** variants, so the home screen icon follows the
  appearance the rest of iOS 18 does instead of being auto-darkened
- **Siri / Shortcuts** support for creating a note by voice, localized through
  `Localizable.strings` and `AppShortcuts.strings`. A shortcut run with nothing to
  put in the note is refused rather than saved, by the same rule the form applies
  — a note with no body is a blank row that opens onto nothing
- **Backup and restore** notes as a JSON file

### ♿️ Accessibility

- VoiceOver labels on every icon-only control, which would otherwise announce as
  the raw SF Symbol name
- Body copy follows Dynamic Type, including the checkbox in a checklist line and
  the zone in which tapping it ticks the line off — that zone is measured in the
  font the box is drawn in rather than being a fixed distance that only matched at
  one text size
- A checklist line announces its text as the label and whether it is ticked as the
  value, as one element rather than the two pieces it is drawn from. Left to itself
  VoiceOver read the row as the bare glyph "▢" followed by the text, which conveys
  neither that the line can be ticked nor whether it already is — the tick being
  the whole point of a checklist, and the one thing the row would not say
- A note's row is one element too, in every display style and in the calendar, the
  map's sheet and the trash alike. Left to itself VoiceOver made a separate stop of
  each of the five to eight pieces a row is drawn from, so reaching the next note
  meant swiping past a timestamp, a title, two lines of body, a date and then every
  tag in turn. The row is combined rather than relabelled, so what is spoken is
  assembled from the `Text`s actually on screen and cannot drift from them — and
  the status glyphs carry labels of their own, since a bare SF Symbol contributes
  only its generic description: the pin, the lock and the reminder bell said nothing
  about being pinned, locked or due
- The unlock button shows the way in the device actually offers — Face ID, Touch ID
  or a padlock for passcode-only. Resolved when the note is opened rather than once
  per process, so enrolling Face ID and coming back from Settings does not leave the
  button offering an open padlock on a device that now has biometry
- Text on the accent colour meets the 4.5:1 contrast ratio. The app's accent is
  `systemOrange`, a light colour in both appearances, so white on it came to about
  2.2:1 — and accent-on-accent tag pills to about 1.9:1, the least legible text in
  the app

### 🌐 Localization

- Multi-language support (English, Czech), including plural rules

## Technical Stack

- **Framework**: SwiftUI
- **Language**: Swift 6
- **Platforms**: iOS, iPadOS
- **Architecture**: MVVM with `@Observable` state
- **Storage**: File-based JSON with complete file protection, encoded and written
  off the main actor and one write at a time — a note's drawing strokes and
  background photo are base64 inside that JSON, so encoding the list is work
  proportional to the whole library, and every checkbox tick and pin used to pay
  for it before the UI could move again
- **Services**:
  - PencilKit for drawing
  - CoreLocation for location tracking
  - UserNotifications for reminders
  - MapKit for map visualization
  - LocalAuthentication for protected notes
  - WidgetKit + App Group for the home screen widget
  - AppIntents for Siri and Shortcuts

## Project Structure

```
notes/                        # App target
├── AppGroup.swift            # Shared identifiers, widget payload,
│                             # widget deep link
├── Info.plist                # CFBundleURLTypes only — everything else in
│                             # this target's Info.plist is generated from
│                             # INFOPLIST_KEY_* build settings, which cannot
│                             # express an array of dictionaries
├── Log.swift                 # os.Logger categories
├── notesApp.swift            # App entry point, Date extension,
│                             # background-save assertion
├── Models/
│   ├── NoteModel.swift
│   └── ViewEnums.swift       # Sort options, display styles
├── Views/
│   ├── ContentView.swift
│   ├── LaunchScreenView.swift
│   ├── NotesView.swift
│   ├── CalendarView.swift
│   ├── MapView.swift
│   └── Notes/
│       ├── NoteListView.swift
│       ├── NoteRowView.swift
│       ├── NoteDetailView.swift
│       ├── NoteFormView.swift
│       ├── DeletedNotesView.swift
│       ├── DrawingView.swift
│       ├── PrivacyCover.swift    # App-switcher cover for locked notes
│       └── UndoableTextEditor.swift
├── Stores/
│   └── NotesStore.swift
├── Managers/
│   ├── LocationManager.swift
│   └── NotificationManager.swift  # Scheduling, badge rules, and
│                                  # NotificationRouter — foreground
│                                  # presentation and tap-to-note routing
├── Intents/
│   └── CreateNoteIntent.swift
├── en.lproj/ , cs.lproj/     # Localizable.strings, .stringsdict,
│                             # InfoPlist.strings, AppShortcuts.strings
└── PrivacyInfo.xcprivacy

NotesWidget/                  # Widget extension target
notesTests/                   # Unit tests
```

## Requirements

- iOS 18.0+ / iPadOS 18.0+
- Xcode 26.0+
- Swift 6.0

## Installation

1. Clone the repository:

```bash
git clone https://github.com/RobertLib/j-notes.git
cd j-notes
```

2. Open the project in Xcode:

```bash
open notes.xcodeproj
```

3. Select your target device or simulator

4. Build and run the project (⌘R)

> The app and the widget share an App Group (`group.cz.rob.notes`). If you build
> with your own team, update the group identifier in `notes/AppGroup.swift`,
> `NotesWidget/NotesWidget.swift` and both entitlements files.

## Usage

### Creating a Note

1. Tap the "+" button in the notes view
2. Choose a text or drawing note
3. Enter a title and content
4. Optionally add:
   - A color
   - Tags
   - A reminder date/time
   - Biometric protection
5. Save your note

### Organizing Notes

- **Pin**: Swipe a note from the left to keep it at the top
- **Color code**: Assign colors to categorize your notes
- **Tags**: Add tags and filter by them from the chip row. Case does not make a
  new tag, and the filter clears itself once no note carries the tag any more
- **Search**: Use the search bar to search titles, content and tags
- **Sort / display**: Choose ordering and row density from the toolbar menu

### Views

- **List View**: See all your notes in a list format
- **Calendar View**: Browse notes by their reminder date
- **Map View**: Visualize notes with location data on a map

### Backup

Use **Backup Notes** in the toolbar menu to export a JSON file, and **Restore
from Backup** to merge it back or replace everything.

## Testing

```bash
# In Xcode
⌘U

# From the command line
xcodebuild test -scheme notes \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Test coverage includes:

- Note model, Codable round-trip and legacy-format decoding
- Colour stored as its components, including files written before the alpha channel
- Notes store: add / update / delete, trash lifecycle and auto-purge, tags,
  notification identifier handling, persistence, backup and restore
- Emptying the trash taking only what is in it, reporting that it had nothing to
  do rather than scheduling a write of an unchanged list, and the notes being gone
  from the file and not merely from memory — it is the one trash action with no
  undo behind it
- Refusal to save or restore over notes whose bytes could not be read, and
  recovery once they can
- A notes file that reads but does not decode being set aside instead, so the app
  stays usable and a backup can still be restored over it — and the UserDefaults
  copy still winning over that, when there is one
- A file that only turns out to be undecodable on the retry still saying so,
  rather than the recovery clearing that message along with the stale one it
  replaces
- The legacy UserDefaults copy never being written over a file that is merely
  unreadable, and the undecodable file's bytes surviving that recovery too
- The backup's suggested filename being the same in every locale, with nothing in
  it that cannot be part of a filename
- A note's coordinate being `nil` rather than (0, 0) for a stored position too
  short to be one, so no note is pinned in the Gulf of Guinea
- Backup restores accepting either date encoding
- A reminder date surviving a notification the system would not schedule, and
  surviving an edit that never touched the reminder toggle
- Scheduling refused unless the granted permission would actually deliver the
  reminder — the notification centre accepts a request it will never deliver and
  reports no error, so only the authorization status can tell
- The badge staying bare while the app is on screen, and counting delivered
  reminders once it is not
- Reminders read in an earlier session not being counted a second time into the
  badge the next one carries, counted from delivery dates rather than a running
  total so that clearing one by hand cannot leave the tally adrift
- Pending reminders being re-numbered in fire order when one is added ahead of
  them or the one ahead of them is cancelled, and nothing being rewritten when
  the numbering already agrees
- A tapped reminder routing to its own note, and routing nowhere when the note it
  named is gone or in the trash — but being kept for another attempt while the
  store has not read its notes, since that is not the same answer
- A pending debounced save being flushed when the app leaves the foreground, and
  not rewriting the file when there is nothing to save
- Location manager parsing, fallback behaviour and fix staleness
- Two deliveries of the same coordinates counting as two deliveries, so a map that
  moves its camera on a *change* still moves when the fix repeats
- A fix being asked for only when authorization actually changes into a granted
  one, not when the same status is merely reported back — which is what an app
  launch provokes
- Which notes share a pin on the map: the tolerance in both axes, coordinates that
  cannot be placed at all, a pair straddling a grid boundary still grouping, the
  grid not quietly making the tolerance transitive, and pin identities staying
  stable across evaluations while remaining distinct from each other
- How a checklist line is spelled and round-trips, so the two box glyphs have one
  spelling shared by the renderer, the toggle and the editor rather than four
- Notification manager scheduling and cancellation
- Widget payload redaction for protected notes, its ordering and its truncation,
  and that neither a note's tags nor its creation date reach the shared container
  at all
- An unprotected note's body being cut to what the widget can draw before it is
  shared, while a body short enough to fit travels whole
- A restore that replaces everything deduplicating notes the backup file repeats,
  keeping the first of them — a hand-edited or concatenated file can name the same
  note twice, and two rows sharing an id leave the second impossible to edit or
  delete, since every lookup in the app can only reach the first
- A note's tags being deduplicated as it is decoded, for the same reason one level
  down: the form deduplicates as they are typed, but a backup is whatever the user
  hands over, and every list renders tags by their own text as the identity
- An edit that lands while a save is in flight still counting as pending, now that
  the write suspends: the older write must not report "nothing to flush" for an
  edit it never carried, and the flush has to get that edit down
- Two overlapping saves leaving the newest notes on the disk rather than whichever
  write happened to finish last
- A store that could not read its notes leaving the widget's shared container
  untouched instead of publishing "no notes" over it, and the recovery bringing
  it back in line
- What the form counts as enough to save, including a drawing whose only content
  is its background photo
- A locked note's title being kept off the lock screen
- Checklist toggling landing on the text view's undo stack, and staying
  well-behaved around emoji
- The zone in which a tap ticks a line off being the width of the box it is
  aiming at, in the font that box is drawn in, rather than a fixed distance that
  only matched at one text size
- An undecodable file being reported even when the UserDefaults copy recovers the
  notes, and an ordinary migration — which sets nothing aside — still reporting
  nothing
- The cursor after a checklist toggle: a caret follows the checkbox that was
  inserted rather than coming back as a selection over the text just typed, while
  a real selection still covers every line it covered
- A drawing whose stored canvas size is zero — a note saved before its canvas was
  ever laid out — falling back to the drawing's own bounds instead of rendering as
  a blank white box, while a real canvas size is still honoured
- How far a zoomed drawing may be dragged: to its own edge and no further, in
  either direction and on each axis independently, with a picture that fits its
  frame pinned centred — and an offset that was legal at full zoom being pulled
  back inside the limit as the pinch zooms out. Unbounded, the drag could push the
  picture clean out of frame, leaving a blank white box and a double tap as the
  only way back
- Tags being one tag whatever case they were typed in, at every level that decides
  it — the decoder, the store's chip row and the form's own duplicate check — and
  diacritics still telling two tags apart, since those are different words
- Which spelling of a tag the chip row keeps not depending on the order the notes
  happen to sit in the file, so the row does not rename itself when an unrelated
  note is added
- A tag filter being dropped once no note carries its tag, including the case that
  used to leave no way back at all: it was the only tag, so the chip row went with
  it and left an empty list and nothing to clear the filter with
- A tag filter re-anchoring onto the spelling still on screen, so one set on
  "Práce" goes on working when the last note spelling it that way is gone
- A reminder being refused into a full pending queue even when nothing is due
  ahead of it — iOS keeps the soonest 64, so it would have been kept at the cost
  of one already waiting, and nothing would have said so
- A widget link opening its note, routing nowhere when that note is in the trash,
  and being kept for another attempt while the store has not read its notes —
  the same three answers a tapped reminder gets, through the same rule
- A widget link round-tripping through the URL it is built from, and an unrelated
  URL naming no note: `onOpenURL` sees every URL the app is asked to open
- A kept request counting as a destination, which is what the splash screen reads
  in order to get out of the way of a launch that was started by one

CI runs the build, the test suite and a localization parity check on every push
and pull request — see [.github/workflows/ci.yml](.github/workflows/ci.yml). The
parity check covers every localized file, `InfoPlist.strings` included, and holds
the usage descriptions in it against the `INFOPLIST_KEY_*` build settings that
generate the plist in the first place: a fourth description added to the project
and left out of those files is untranslated everywhere, and an entry left behind
whose setting has gone localizes nothing at all. Neither is visible at build time,
and the untranslated case ships an English sentence to a Czech user in the one
dialog the system puts in front of them before handing over the camera or Face ID.
CI also asserts that the camera, Face ID and location usage descriptions survive
into the built `Info.plist`, that both privacy manifests ship, and that the app
and the widget still agree on the App Group identifier, the payload's shape and
the deep link's URL scheme — which has to be declared in `notes/Info.plist` as
well, or iOS routes the tap nowhere
([scripts/check-shared-contract.sh](scripts/check-shared-contract.sh)). The two
targets share no code, and a mismatch just leaves the widget reading "No notes"
forever, or its taps landing on the list as though it had no links at all. All of
those are silent, runtime-only failures otherwise.

The two shell checks run before the build rather than after it. They need nothing
but the checkout and finish in seconds, where the build and the test run take
minutes on a macOS runner — so a renamed localization key fails the job straight
away instead of after the slowest part of it has already been paid for. The
`Info.plist` and privacy-manifest assertions stay at the end, since they read the
built app.

The `notes` scheme is shared in `xcshareddata` so CI and other contributors get
the same build and test actions.

## Data Migration

The app automatically migrates data from UserDefaults (legacy storage) to
file-based storage on first launch, ensuring backward compatibility. If the
notes file is ever unreadable, the UserDefaults copy is used as a fallback
before it is discarded — taken into memory, but never written over the file it is
standing in for. Those notes are intact and merely out of reach, and a copy left
behind by a migration that never finished is no reason to replace them.

The notes file is written with `.completeFileProtection`, so it cannot be read
while the device is locked. When its bytes cannot be read, saving is blocked
rather than allowed to overwrite the stored notes with an empty list; the app
retries the load — and merges anything created in the meantime — the next time it
becomes active.

A file that reads but does not decode is a different case, and it used to be
treated as the same one. Waiting cannot help it, so blocking writes blocked them
for ever — and a restore is a write, so the one action that would have fixed it was
the one action ruled out. Such a file is renamed out of the way instead
(`notes-unreadable-<uuid>.json`, kept rather than deleted, since those bytes are
all that is left of whatever was in there). It is renamed before anything else
runs, so the UserDefaults recovery — which writes to exactly that path — cannot
land on those bytes first. The app then starts as the empty store it truthfully
is, says so, and points at Restore from Backup. It says so on the retry too: the
compound case, where the file could not be read at all at launch and turns out not
to decode once it can, is the one that used to leave an emptied list and no reason
for it.

It says so even when the recovery goes well. A UserDefaults copy left behind by a
migration that never finished still wins over starting empty — but those notes can
be older than what the file held, and the file is now in the container under
another name, so that branch reports the set-aside rather than clearing the error
outright. It was the one path that moved a file out of the way and said nothing.

The widget's shared container is held to the same rule. It has no file
protection of its own and it is what the home screen renders, so a store that
never read its notes publishes nothing at all rather than replacing the widget
with "No notes" — which is exactly what a process starting on a locked device (a
Siri shortcut, a background launch) would otherwise do.

## Privacy

J-Notes respects your privacy:

- All data is stored locally on your device
- No data is sent to external servers
- Location is captured only when authorized, and only when a note is created —
  and only from a fix taken within the last few minutes, so a note is never
  stamped with a coordinate from an earlier session
- Notifications require user permission
- Protected notes never expose their title or content to the widget's shared
  container, and their reminders reach the lock screen carrying neither the
  note's title nor its body
- Tags are never shared with the widget at all, for any note, and neither is a
  note's creation date. The widget renders neither — and it never needed the
  dates to sort by either, since the payload's order is decided in the app —
  while the shared container, unlike the notes file, is readable with the device
  locked
- An unprotected note's body is truncated to what the widget can actually draw
  before it is shared, rather than sent whole. Same reason: the widget renders at
  most three short lines of it, so the rest was only ever sitting in a container
  that survives the lock screen
- Inside the app a protected note still shows its title and tags in lists, so
  the user can find their own note; only its body is masked until they
  authenticate. Everything that leaves the app — the widget's shared container
  and the lock screen — is redacted in full

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Author

Created by Robert Libšanský

## Acknowledgments

- Built with SwiftUI
- Uses Apple's native frameworks for a seamless iOS experience
