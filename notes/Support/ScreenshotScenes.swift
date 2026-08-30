//
//  ScreenshotScenes.swift
//  notes
//
//  Poses the app for an App Store screenshot or an App Preview.
//
//  `#if DEBUG` in its entirety, so none of it reaches the build that goes to the
//  App Store — and the two hooks that call into it (`NotesStore.init` and
//  `ContentView`) are guarded the same way.
//
//  Driven by launch arguments, which is what `Tools/appstore_media.sh` passes:
//
//      -shot 01-list          which pose to build
//      -AppleLanguages (cs)   the locale the pose writes its notes in
//
//  Nothing here mocks a screen. A pose seeds the notes file and then asks the
//  app to open something; what is photographed is the app reading its own store
//  through its own code path, which is the difference between a screenshot that
//  stops rendering when the app changes and one that quietly drifts away from it.
//
//  The one thing it does *not* do is drive the drawing canvas or the widgets.
//  A drawing is seeded as a real `PKDrawing` archive — the same bytes the editor
//  writes — and the widget shots are taken by hand; see AppStore/screenshots.md.
//
#if DEBUG
import Foundation
import PencilKit
import SwiftUI

enum Shots {
    // MARK: - Which pose, and whether there is one at all

    /// The `-shot` value, or `nil` on an ordinary launch.
    ///
    /// Read once. `ProcessInfo.arguments` does not change under a running
    /// process, and the store asks for this from its initialiser while the views
    /// ask again later — reparsing per call would be work for no answer.
    static let name: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-shot"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool { name != nil }

    /// Whether the pose is in Czech. Taken from the language the launch argument
    /// set rather than from `Locale.current`, so the seeded notes are in the same
    /// language as the interface photographed around them — a Czech screenshot
    /// showing English notes is the tell that a listing is machine-translated.
    private static var isCzech: Bool {
        Locale.preferredLanguages.first?.hasPrefix("cs") ?? false
    }

    // MARK: - The notes each pose is photographed against

    /// Now, on the hour.
    ///
    /// A note's age is an offset from this, so a row reads "2 hours ago" whenever
    /// the shot is taken rather than on the day the catalogue was written.
    /// Snapped to the top of the hour so two runs an hour apart produce the same
    /// picture, and so nothing photographs a stray "1 minute ago".
    private static let anchor: Date = {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: Date())
        return calendar.date(from: components) ?? Date()
    }()

    /// How long ago a note was written.
    private static func hoursAgo(_ count: Double) -> Date {
        anchor.addingTimeInterval(-count * 3600)
    }

    /// A reminder, as a whole hour on a day ahead of today.
    ///
    /// Counted from the start of today rather than from `anchor`, so the times
    /// are round — "tomorrow at 09:00" rather than "in 22 hours" — and so a shot
    /// taken late in the evening does not push a reminder past midnight into a
    /// day the calendar would file it under differently. Every one of them is in
    /// the future by construction: a reminder that has already passed still keeps
    /// its date, but the row stops showing its bell, and the bell is half of what
    /// the reminder shots are for.
    /// A reminder earlier today.
    ///
    /// Deliberately in the past. The calendar shot opens on today and lists what
    /// is due on the day it is showing, so without a note dated today it opens on
    /// "No notes for this date" — a true screen, and the least useful one the
    /// calendar has. A reminder that has already fired keeps its date and stays
    /// in the calendar, which is exactly the behaviour being photographed; it is
    /// only the row's bell that a passed reminder loses, and the bell is on the
    /// three notes below.
    private static func todayAt(hour: Int) -> Date {
        Calendar.current.startOfDay(for: anchor).addingTimeInterval(Double(hour) * 3600)
    }

    private static func upcoming(inDays days: Int, atHour hour: Int) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: anchor)
        let day = calendar.date(byAdding: .day, value: days, to: startOfToday) ?? anchor
        return day.addingTimeInterval(Double(hour) * 3600)
    }

    /// Prague, because the map has to be somewhere and a map centred on Cupertino
    /// in a Czech listing looks like a stock photo. The three coordinates are far
    /// enough apart to draw three pins and close enough to frame together.
    private enum Place {
        static let vinohrady = [50.0755, 14.4378]
        static let letna = [50.0980, 14.4160]
        static let smichov = [50.0700, 14.4030]
    }

    private enum Palette {
        static let red = Color(red: 1.0, green: 0.23, blue: 0.19)
        static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let blue = Color(red: 0.0, green: 0.48, blue: 1.0)
        static let orange = Color(red: 1.0, green: 0.58, blue: 0.0)
        static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)
    }

    /// Fixed ids, so a pose can name the note it wants to open without having to
    /// look one up by title — and so two runs of the same pose photograph the
    /// same note.
    private enum ID {
        static let shopping = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000001")!
        static let meeting = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000002")!
        static let locked = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000003")!
        static let sketch = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000004")!
        static let trip = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000005")!
        static let idea = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000006")!
        static let recipe = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000007")!
        static let today = UUID(uuidString: "5A17E5C0-0000-4000-8000-000000000008")!
    }

    /// The library every pose is photographed against.
    ///
    /// One library rather than one per shot: the list, the calendar and the map
    /// are three views of the same notes, and seeding each of them separately is
    /// how a screenshot set comes to show four notes on the list and six on the
    /// map. Which of them a pose puts on screen is decided by `route` below, not
    /// by what was seeded.
    private static func library() -> [NoteModel] {
        let cs = isCzech
        let box = ChecklistItem.Box.unchecked.rawValue
        let tick = ChecklistItem.Box.checked.rawValue

        return [
            NoteModel(
                id: ID.shopping,
                createdAt: hoursAgo(2),
                title: cs ? "Nákup na víkend" : "Weekend shopping",
                content: cs
                    ? "\(tick) mouka a droždí\n\(tick) máslo\n\(box) tvaroh\n\(box) jablka\n\(box) skořice"
                    : "\(tick) flour and yeast\n\(tick) butter\n\(box) curd cheese\n\(box) apples\n\(box) cinnamon",
                pinned: true,
                color: Palette.green,
                tags: cs ? ["domov"] : ["home"]
            ),
            NoteModel(
                id: ID.meeting,
                createdAt: hoursAgo(5),
                title: cs ? "Schůzka s Petrou" : "Meeting with Petra",
                content: cs
                    ? "Projít rozpočet na druhé pololetí a domluvit termín předání. Přinést tištěnou verzi."
                    : "Go through the second-half budget and agree a handover date. Bring a printed copy.",
                color: Palette.blue,
                reminder: upcoming(inDays: 1, atHour: 9),
                location: Place.vinohrady,
                tags: cs ? ["práce"] : ["work"]
            ),
            NoteModel(
                id: ID.locked,
                createdAt: hoursAgo(26),
                title: cs ? "Osobní" : "Personal",
                content: cs
                    ? "Tohle je jen moje. Poznámka se otevře až po Face ID."
                    : "This one is mine alone. The note opens only after Face ID.",
                color: Palette.purple,
                tags: cs ? ["soukromé"] : ["private"],
                isProtected: true
            ),
            NoteModel(
                id: ID.sketch,
                createdAt: hoursAgo(30),
                title: cs ? "Náčrt kuchyně" : "Kitchen sketch",
                content: "",
                type: .drawing,
                drawingData: sketchDrawing(),
                drawingCanvasSize: sketchCanvas,
                color: Palette.orange,
                tags: cs ? ["nápady"] : ["ideas"]
            ),
            NoteModel(
                id: ID.trip,
                createdAt: hoursAgo(52),
                title: cs ? "Letná — místo na piknik" : "Letná — spot for a picnic",
                content: cs
                    ? "Kousek nad kolotočem, ve stínu. Nejlepší světlo kolem sedmé večer."
                    : "Just above the carousel, in the shade. Best light around seven in the evening.",
                color: Palette.red,
                reminder: upcoming(inDays: 3, atHour: 18),
                location: Place.letna,
                tags: cs ? ["výlety"] : ["trips"]
            ),
            NoteModel(
                id: ID.idea,
                createdAt: hoursAgo(74),
                title: cs ? "Co si zapamatovat" : "Worth remembering",
                content: cs
                    ? "Poznámka si pamatuje místo, kde vznikla — a najdeš ji potom na mapě."
                    : "A note remembers where it was written, and you find it again on the map.",
                location: Place.smichov,
                tags: cs ? ["nápady"] : ["ideas"]
            ),
            NoteModel(
                id: ID.today,
                createdAt: hoursAgo(7),
                title: cs ? "Vyzvednout balík" : "Pick up the parcel",
                content: cs
                    ? "Výdejní box u zastávky, kód přišel do e-mailu. Otevřeno do osmi."
                    : "The locker by the tram stop, the code came by email. Open until eight.",
                color: Palette.red,
                reminder: todayAt(hour: 8),
                tags: cs ? ["domov"] : ["home"]
            ),
            NoteModel(
                id: ID.recipe,
                createdAt: hoursAgo(98),
                title: cs ? "Babiččin jablečný závin" : "Grandma's apple strudel",
                content: cs
                    ? "Těsto nechat hodinu odpočinout. Jablka nastrouhat nahrubo, orestovat s cukrem a skořicí."
                    : "Let the dough rest for an hour. Grate the apples coarsely, cook them down with sugar and cinnamon.",
                color: Palette.orange,
                reminder: upcoming(inDays: 5, atHour: 17),
                tags: cs ? ["recepty"] : ["recipes"]
            ),
        ]
    }

    /// A `PKDrawing` archive, built stroke by stroke.
    ///
    /// Real bytes in the real format, so what the drawing note renders is
    /// PencilKit drawing PencilKit's own data — not a picture pasted in beside
    /// it. Seeded rather than drawn on the canvas because there is no way to put
    /// a finger on a simulator from a script, and a canvas nobody has touched is
    /// the one thing the drawing screen must not be photographed as.
    /// The canvas the sketch is drawn on, in points.
    ///
    /// Sized to the frame the detail screen gives a drawing — 400 points tall,
    /// and narrow enough to sit inside an iPhone's width with a margin. That is
    /// what a canvas measured off a real editor on a phone looks like, and it is
    /// what makes the drawing show whole on both devices: a note drawn on a phone
    /// and opened on an iPad is drawn at the size it was made at, centred, which
    /// is the app's own behaviour rather than something arranged for the camera.
    private static let sketchCanvas = CGSize(width: 340, height: 400)

    private static func sketchDrawing() -> Data? {
        let pen = PKInk(.pen, color: UIColor(Palette.blue))
        let marker = PKInk(.marker, color: UIColor(Palette.orange))

        /// One stroke along `corners`, sampled every few points.
        ///
        /// The sampling is not decoration. `PKStrokePath` interpolates its
        /// control points as a cubic spline and needs four of them before it has
        /// a curve to draw at all — a straight line given as its two endpoints
        /// comes out as a dot or as nothing, which is what the first version of
        /// this drawing did: eleven strokes seeded, two rendered. Subdividing
        /// each leg into eight steps gives the spline enough to work with, and
        /// the wobble it puts between them is what keeps the result looking
        /// drawn rather than plotted.
        func stroke(_ ink: PKInk, _ corners: [CGPoint], width: CGFloat) -> PKStroke {
            let steps = 8
            var points: [CGPoint] = [corners[0]]
            for (from, to) in zip(corners, corners.dropFirst()) {
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    points.append(CGPoint(x: from.x + (to.x - from.x) * t,
                                          y: from.y + (to.y - from.y) * t))
                }
            }

            let controls = points.enumerated().map { index, point in
                PKStrokePoint(
                    location: point,
                    timeOffset: Double(index) * 0.02,
                    size: CGSize(width: width, height: width),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
        }

        // A room in plan: four walls in one stroke, a counter along the top, a
        // table, two chairs either side of it and a rug.
        //
        // Laid out inside `sketchCanvas`, and that size is the whole trick. The
        // renderer draws a drawing at its stored canvas size *in points* — which
        // for a real note is `canvas.bounds.size`, the editor's own view — and
        // the detail screen gives it a frame 400 points tall. A canvas of 900 by
        // 1200 is therefore not a big drawing, it is a drawing shown at two and a
        // half times life size with three quarters of it off the side of the
        // screen, which is what the first version of this pose photographed.
        let strokes: [PKStroke] = [
            stroke(pen, [CGPoint(x: 30, y: 40), CGPoint(x: 310, y: 38),
                         CGPoint(x: 312, y: 362), CGPoint(x: 32, y: 364),
                         CGPoint(x: 30, y: 40)], width: 4),
            stroke(marker, [CGPoint(x: 46, y: 64), CGPoint(x: 296, y: 62)], width: 13),
            stroke(pen, [CGPoint(x: 122, y: 182), CGPoint(x: 222, y: 181),
                         CGPoint(x: 221, y: 257), CGPoint(x: 121, y: 258),
                         CGPoint(x: 122, y: 182)], width: 3),
            stroke(pen, [CGPoint(x: 88, y: 200), CGPoint(x: 110, y: 200),
                         CGPoint(x: 110, y: 240), CGPoint(x: 88, y: 240),
                         CGPoint(x: 88, y: 200)], width: 3),
            stroke(pen, [CGPoint(x: 234, y: 200), CGPoint(x: 256, y: 200),
                         CGPoint(x: 256, y: 240), CGPoint(x: 234, y: 240),
                         CGPoint(x: 234, y: 200)], width: 3),
            stroke(marker, [CGPoint(x: 140, y: 305), CGPoint(x: 204, y: 304)], width: 10),
        ]

        return PKDrawing(strokes: strokes).dataRepresentation()
    }

    // MARK: - Seeding

    /// Writes the pose's library over `fileURL`, before the store reads it.
    ///
    /// Called from `NotesStore.init`, which is the last moment at which the file
    /// can still be decided: the store loads in its own initialiser, and the
    /// initialiser runs before anything a view could hook.
    ///
    /// A pose is a clean slate every time. `simctl` reinstalls between shots so
    /// there is normally nothing to overwrite, but a preview recorded twice in a
    /// row would otherwise photograph whatever the first run left behind.
    static func seed(into fileURL: URL) {
        guard isActive else { return }

        do {
            try NotesCodec.write(library(), to: fileURL)
        } catch {
            // Loud on purpose. A pose whose seed failed photographs an empty
            // list and reports nothing, which is exactly the kind of silent
            // wrong picture this whole file exists to avoid.
            FileHandle.standardError.write(Data("Shots: could not seed \(fileURL.path): \(error)\n".utf8))
        }
    }

    // MARK: - What the pose puts on screen

    /// Which tab the pose opens on.
    static var tab: AppTab {
        switch name {
        case "05-calendar": return .calendar
        case "06-map": return .map
        default: return .list
        }
    }

    /// The note the pose opens, or `nil` for a pose that stays on the list.
    ///
    /// Routed through `NotificationRouter.noteToOpen`, which is the same door a
    /// tapped reminder and a tapped widget come through — so the pose exercises
    /// the app's own navigation instead of a second one written for photography.
    static var noteToOpen: UUID? {
        switch name {
        case "02-locked": return ID.locked
        case "03-drawing": return ID.sketch
        case "04-checklist": return ID.shopping
        case "07-detail": return ID.recipe
        default: return nil
        }
    }

    // MARK: - The App Preview's tour

    /// Whether this launch is the one the App Preview is recorded from.
    static var isTour: Bool { name == "preview-tour" }

    /// One thing the tour does at one moment.
    enum TourStep {
        case tab(AppTab)
        case open(UUID)
    }

    /// The tour, as seconds from the app appearing.
    ///
    /// **Why there is a tour at all.** `simctl io recordVideo` writes a frame
    /// when the screen changes and not otherwise, so a recording of a notes app
    /// sitting still is a recording of nothing: the app is up about a second
    /// after launch and then emits no further frames until something moves. The
    /// first App Preview built here was three such recordings cut together —
    /// eighteen seconds holding three still pictures, each opening on the splash
    /// screen, because the splash was the only thing in shot that animated.
    ///
    /// So the preview is one continuous take of the app walking itself through
    /// its own navigation. Every step below goes through the app's own doors —
    /// the tab selection the tab bar sets, and the router a tapped reminder comes
    /// through — so what is filmed is the real transition between real screens,
    /// not a slideshow assembled afterwards.
    ///
    /// Nothing here pops a navigation stack, and that is a constraint rather than
    /// a preference: the list's `path` is its own `@State` and there is no hook
    /// to unwind it from outside. Opening a second note *replaces* the stack —
    /// `NotesView.open` assigns rather than appends — so the last two steps swap
    /// one note for another instead of going back and in again, which films
    /// better anyway.
    ///
    /// The holds are three seconds. Long enough to read the screen, short enough
    /// that something is always about to happen — and, less obviously, they are
    /// what sets the length of the recording: the file ends at its last frame,
    /// and its last frame is the last thing that moved. A tour that finishes at
    /// fourteen seconds cannot be cut into a preview of the fifteen Apple asks
    /// for, however long the script was told to record. That is how the first
    /// version of this failed, and `appstore_conform.swift` caught it.
    ///
    /// The order is deliberate. Opening a note forces the list's tab forward —
    /// that is `ContentView` doing what a tapped reminder makes it do — so the
    /// notes come first and the tabs after, or every tab step would be undone by
    /// the next note.
    ///
    /// **The last entry never appears in the preview.** The cut ends before it,
    /// and it is there so that the recording does not: a file that stops
    /// changing stops having frames, and a window reaching past the final
    /// movement is clamped back to it. So the tour ends, as far as anyone
    /// watching is concerned, holding the locked note for two and a half
    /// seconds — and the step after that exists only to keep the tape rolling
    /// underneath the hold. Move the cut in `appstore_media.sh` and this entry
    /// has to move with it.
    static let tour: [(seconds: Double, step: TourStep)] = [
        (3.0, .open(ID.shopping)),
        (6.0, .open(ID.sketch)),
        (9.0, .tab(.calendar)),
        (12.0, .tab(.map)),
        (15.5, .open(ID.locked)),
        (18.3, .open(ID.meeting)),   // the tail; see above
    ]

    /// Runs `tour`, handing each step back to the view that owns the state.
    ///
    /// The two closures are the view's own assignments rather than anything this
    /// file reaches for: `Shots` knows what the tour does and `ContentView` knows
    /// how to do it, which is the only arrangement in which this file can stay
    /// out of the app's way.
    @MainActor
    static func runTour(tab: (AppTab) -> Void, open: (UUID) -> Void) async {
        var elapsed = 0.0
        for entry in tour {
            let wait = entry.seconds - elapsed
            if wait > 0 {
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                elapsed = entry.seconds
            }
            guard !Task.isCancelled else { return }

            switch entry.step {
            case .tab(let destination): tab(destination)
            case .open(let id): open(id)
            }
        }
    }

    // MARK: - Telling the script the pose has landed

    /// How long the pose is given to settle before it declares itself ready.
    ///
    /// Not a guess at how long the app takes to launch — the marker is written
    /// from `onAppear`, so the app has already drawn by then. This covers what
    /// happens *after* the first frame: a push animation, the map's tiles
    /// arriving, the drawing being rendered. The longest of those is the map,
    /// which has to fetch.
    private static var settleTime: Duration {
        switch name {
        case "06-map": return .milliseconds(4000)
        case "03-drawing": return .milliseconds(1500)
        case nil: return .zero
        default: return .milliseconds(1200)
        }
    }

    /// Drops the file `appstore_media.sh` waits on.
    ///
    /// A marker rather than a fixed sleep in the script: the settle times above
    /// are known here, next to the poses they belong to, and a script that slept
    /// for the longest of them would pay for the map on all eight shots.
    static func markReady() {
        guard isActive else { return }

        Task { @MainActor in
            try? await Task.sleep(for: settleTime)
            let marker = URL.documentsDirectory.appendingPathComponent("shot-ready")
            try? Data().write(to: marker)
        }
    }
}
#endif
