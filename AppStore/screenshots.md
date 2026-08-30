# Screenshots and App Preview

The media is **not made by hand and is not in git** — the scripts below produce
it. Uploading is manual: in App Store Connect drag the files into the *App
Preview and Screenshots* section (language switch at the top, one locale at a
time).

## What the scripts produce

| What | Where | Resolution | Count |
|---|---|---|---|
| iPhone 6.5" screenshots | `screenshots/<locale>/iphone-6.5/` | 1242 × 2688 | 7 |
| iPad 13" screenshots | `screenshots/<locale>/ipad-13/` | 2064 × 2752 | 7 |
| The same, composed for the store | `screenshots-composed/<locale>/<device>/` | same | 7 + 7 |
| iPhone App Preview | `preview/<locale>/iphone-6.5.mp4` | 886 × 1920, 30 fps, AAC | 1 |
| iPad 13" App Preview | `preview/<locale>/ipad-13.mp4` | 1200 × 1600, 30 fps, AAC | 1 |

**iPhone 6.5" is the slot this listing uses.** Apple derives every *smaller* size
from the file you upload, but only within a slot — the slot is picked per upload
in Connect, and a listing sitting on the 6.5" slot refuses a 6.9" file outright.
The shots currently on the store are 6.9", so replacing them means moving the
listing to the 6.5" slot rather than mixing the two. Shooting one iPhone size
rather than both also halves the run. If 6.9" is ever wanted as well, add
*iPhone 17 Pro Max* at 1320 × 2868 alongside the 6.5" device in
`appstore_media.sh`; `shoot` already takes the device and its expected size as
arguments.

**The iPad set is not optional.** The app is universal, and a universal build
with no iPad screenshots is rejected.

The App Preview has no 6.5/6.9 split: the one 886 × 1920 file is what Apple lists
for the 6.9", 6.5", 6.3" and 6.1" displays alike, so `iphone-6.5.mp4` is the
video for every iPhone slot.

The locales are `cs` and `en-US`, everything in portrait. `en-GB` gets no media
of its own — upload the `en-US` set into it.

```bash
Tools/appstore_media.sh              # screenshots and videos
Tools/appstore_media.sh screenshots  # screenshots only
Tools/appstore_media.sh video        # videos only
Tools/appstore_compose.sh            # the colour, the heading and the device frame
```

**Upload the composed set, not the plain one** — same file names, same order,
they differ only in the wrapper. The plain set is what the app actually looks
like and is worth keeping to diff against; the composed set is what a listing
needs, and it is where the "no ads, no account" promise gets to be said out loud.

`appstore_media.sh` needs Xcode, the *iPad Pro 13-inch (M5)* simulator and
ImageMagick (`brew install imagemagick`). The iPhone one is *iPhone 11 Pro Max* —
Xcode ships the device type but does not always leave a ready-made simulator for
it, so the script creates one on the newest installed runtime if it has to.

## How the poses work

Nothing here is mocked up. Every shot **seeds the notes file and then asks the
app to open something**, so what is photographed is the app reading its own store
through its own code path. The catalogue is `Shots` in
[`notes/Support/ScreenshotScenes.swift`](../notes/Support/ScreenshotScenes.swift),
which is `#if DEBUG` and reaches no App Store build; the script picks a pose with
`-shot <name>`.

That is a deliberate trade. A mocked screen would be quicker to write and would
quietly drift away from the app as the app changed; a screen reached by seeding
and navigating either still renders or stops rendering. The navigation goes
through `NotificationRouter.noteToOpen` — the same door a tapped reminder and a
tapped widget come through — rather than through a second path written for the
camera.

One library serves every pose, seeded once per launch: eight notes, three of them
with reminders, three with coordinates in Prague, one locked, one a drawing, one
a checklist. The list, the calendar and the map are three views of the same
notes, and seeding each separately is how a set comes to show four notes on the
list and six on the map.

Three things the simulator has to be told before a pose will photograph properly,
all of them in `boot_and_install`:

- **Location must be granted ahead of time** (`simctl privacy … grant location`).
  Without it the map shot is the system's permission prompt sitting over the map
  — and the prompt is modal enough to survive into the next pose, so it takes the
  shot after it down too.
- **Biometry must be enrolled**, which has no `simctl` verb — the script posts
  `com.apple.BiometricKit.enrollmentChanged` instead. Without it `NoteLock`
  correctly decides the device can authenticate nobody and shows the protected
  note unlocked, which is the right behaviour and the wrong screenshot.
- **The battery is `discharging` at 100%, not `charged`.** `charged` is the
  plugged-in glyph, a green cell with a bolt through it, which reads as a phone
  on charge rather than as a phone.

A pose is seeded *before the first frame is drawn* — `Shots.seed` is called from
`NotesStore.init`, which is the last moment at which the file can still be
decided, because the store loads in its own initialiser. What the script waits
for afterwards is SwiftUI settling: a push animation, the map's tiles arriving, a
drawing being rendered. It waits for a **marker file** the app drops when the
pose is ready (`Shots.markReady`), not for a guessed number of seconds — and the
settle times live next to the poses they belong to, so the map's four seconds are
not paid on the other six shots.

**The drawing is seeded as a real `PKDrawing` archive**, built stroke by stroke,
because there is no way to put a finger on a simulator from a script and a canvas
nobody has touched is the one thing the drawing screen must not be photographed
as. Two things about that cost a round trip each to find out:

- `PKStrokePath` interpolates its control points as a cubic spline and needs four
  of them before there is a curve to draw. A straight line given as its two
  endpoints comes out as a dot or as nothing — eleven strokes seeded, two
  rendered. Each leg is subdivided into eight steps instead.
- `drawingCanvasSize` is **points, not pixels**: for a real note it is
  `canvas.bounds.size`, the editor's own view, and the detail screen gives the
  drawing a frame 400 points tall. A canvas of 900 × 1200 is therefore not a big
  drawing, it is a drawing shown at two and a half times life size with three
  quarters of it off the side of the screen.

## The seven shots, in order

The order matters more than the count: most people never scroll past the second
one, so the first two have to carry the app on their own. The two that lead are
deliberately the two things the plain-notepad tier of the category does not have.

| # | Shot | What it shows |
|---|---|---|
| 1 | `01-list` | The hero. The full list: a pinned note at the top, four colours, tag chips, a padlock, a checklist showing through into the row. |
| 2 | `02-locked` | A protected note's unlock gate, with the Face ID button. This is where the "no ads, no account" promise goes in the caption. |
| 3 | `03-drawing` | The kitchen sketch — pen and marker, drawn with PencilKit's own strokes. |
| 4 | `04-checklist` | A shopping list half ticked off, inside the note rather than beside it. |
| 5 | `05-calendar` | The calendar with today's reminder listed under it. |
| 6 | `06-map` | Three notes pinned where they were written, labelled, across Prague. |
| 7 | `07-detail` | A note with its reminder and its tag — and the caption that says what the app does not do. |

The calendar shot is why one of the eight seeded notes carries a reminder earlier
**today**, deliberately in the past: the calendar opens on today and lists what is
due on the day it is showing, so without one it opens on "No notes for this date"
— a true screen, and the least useful one the calendar has. A reminder that has
already fired keeps its date and stays in the calendar, which is the behaviour
being photographed; it is only the row's bell that a passed reminder loses, and
the bell is on the three notes below it.

**The widgets are not in the set.** Adding a widget to a simulator's Home Screen
cannot be scripted, and the Home Screen is not the app's to pose. If a widget
shot is wanted it has to be taken by hand: add the medium widget and an accessory
one, then `xcrun simctl io <udid> screenshot`. It would be the strongest shot in
the set — nothing else in the plain-notepad tier of the category has Lock Screen
widgets — which is the argument for doing it by hand rather than for leaving it
out.

## Composition

`Tools/appstore_compose.sh` builds the shot that actually goes up: a flat
saturated colour, a heading in white across the top, and the screenshot in a
device frame below it running off the bottom edge. Every proportion in it was
measured off the shots currently on the store rather than invented, so a new set
drops in beside the old one without the listing changing character halfway down —
the device is 79.3% of the canvas width, its top edge sits at 28.2% of the height,
and the bezel is 3% of the width.

Three things in there are less obvious than they look:

- **The notch is painted on.** The simulator's framebuffer does not have one; the
  status bar simply leaves a gap where the hardware would be. Without painting it
  the shot reads as a phone that does not exist.
- **The heading is SF Pro Rounded, thickened with a stroke of its own colour.**
  ImageMagick instantiates a variable font at its default weight, so the face
  comes out Regular however it is asked for, and the alternative with a real bold
  — Arial Rounded Bold — has neither `ť` nor `ě` and drops them silently. Four per
  cent of the point size in stroke is about a Bold, matched against the live
  shots letter by letter.
- **The heading shrinks itself to fit.** Measured, not guessed, and it is the
  Czech set that needs it: the captions are broken by hand, and a size chosen to
  suit English runs "Ve vašem telefonu." off both edges.

The captions live in `en_caption` and `cs_caption` in that script, two or three
hand-broken lines each, and the per-shot background colours in `colour_for`
beside them.

## App Preview

**One continuous take of the app walking itself through its own navigation** —
list, a checklist note, a drawing, the calendar, the map, a locked note — cut to
about seventeen seconds per device.

Not three clips, and the reason is worth knowing before anyone tries to make it
three again. `simctl io recordVideo` writes a frame when the screen *changes* and
not otherwise, so a recording of a notes app sitting still is a recording of
nothing. Measured on the list pose: the app is up at 1.0 s and the last frame in
a twelve-second recording is at **1.92 s**. There is no bot to hand the app to,
the way the card game in the sister project has one, so the first preview built
here was three separate launches cut together — and it held three still pictures
for eighteen seconds, each opening on the splash screen, because the splash was
the only thing in shot that moved.

The tour is `Shots.tour` in
[`notes/Support/ScreenshotScenes.swift`](../notes/Support/ScreenshotScenes.swift),
next to the notes it opens. Every step goes through the app's own doors — the tab
selection the tab bar sets, and the router a tapped reminder comes through — so
what is filmed is the real transition between real screens.

Three things constrain it:

- **Nothing pops.** The list's `path` is its own `@State` and there is no hook to
  unwind it from outside, so opening a second note *replaces* the first
  (`NotesView.open` assigns rather than appends). The tour swaps one note for
  another instead of going back and in again, which films better anyway.
- **Notes before tabs.** Opening a note forces the list's tab forward — that is
  `ContentView` doing what a tapped reminder makes it do — so a tab step placed
  after a note step would be undone by the next one.
- **The tour outlasts the cut on purpose.** The recording ends at its last
  movement, so the cut has to end before the tour does or it is silently clamped
  and the preview comes out under Apple's fifteen seconds. The tour's last step
  is therefore a tail nobody sees: the preview ends holding the locked note for
  two and a half seconds, and the step underneath that hold is what keeps the
  frames coming.

Check it after any change to the pacing, the poses or the animations — nothing
fails loudly if a beat drifts, it just goes still:

```bash
swift Tools/appstore_frames.swift AppStore/preview/en-US/iphone-6.5.mp4 \
    /tmp/frames 0.3 2.5 4.5 7.5 10.5 13.5 15.0 16.5
magick montage /tmp/frames/*.png -tile 8x -geometry 160x+4+4 \
    -font /System/Library/Fonts/SFNSRounded.ttf /tmp/sheet.png
```

Frames come out of the *finished* preview, not the raw recording: the raw file is
variable frame rate and an exact seek into it comes back with whatever frame it
could find, which on a screen that has stopped changing is the last one — asking
for 6.0 s returns the frame from 1.92 s, reported as a success.

What the last run produced, on both devices and in both languages:

```
886 x 1920   16.8 s  H.264 High 4.0  11.2 Mbit/s  AAC 48 kHz stereo 236 kbit/s  22.8 MB
1200 x 1600  17.0 s  H.264 High 4.0  11.4 Mbit/s  AAC 48 kHz stereo 236 kbit/s  23.5 MB
```

**There is no music, and the audio track is not empty either.** Apple requires
stereo AAC at 256 kbps, and digital silence encodes to about 2 kbps — two orders
of magnitude under it — which Connect reports as an unsupported audio
configuration rather than as a quiet film. So the track carries dither: white
noise at −84 dBFS, three counts of a 16-bit sample, inaudible on any playback
chain and, unlike silence, incompressible. Measured on twenty seconds of stereo
at 48 kHz asked for at 256 kbps:

| Track | Rate | Size |
|---|---|---|
| digital silence | 2.2 kbit/s | 10 kB |
| dither at −84 dBFS | 236.8 kbit/s | 584 kB |

`appstore_conform.swift` checks the rate that came out before it exits, because
the failure it guards against is otherwise reported a whole upload later.
