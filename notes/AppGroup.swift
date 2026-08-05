//
//  AppGroup.swift
//  notes
//

import Foundation

enum AppGroup {
    // Must match the App Group identifier configured in Xcode Signing & Capabilities
    // for both the main app and widget extension targets.
    static let identifier = "group.cz.rob.notes"
    static let widgetDataKey = "widgetNotes"

    /// How many active notes there are in total. Stored separately because the
    /// payload itself is truncated — the widget's counter used to read the
    /// array's length and so stopped climbing past the truncation limit.
    static let widgetTotalKey = "widgetNotesTotal"
}

/// The link the widget opens a particular note with.
///
/// The widget used to carry no link at all, so tapping the note you could see on
/// the home screen opened the app on the list and left you to find it again —
/// which is most of the work a glanceable widget is there to save. A tapped
/// reminder had exactly the same problem, and this reuses the answer to it: the
/// URL names the note, and `NotificationRouter` resolves it against the store,
/// so a note that has been edited, locked or trashed since the widget last drew
/// it opens in whatever state it is in now.
///
/// Spelled out in the widget as well — the two targets share no code, the same
/// arrangement as the App Group identifier above — and `check-shared-contract.sh`
/// asserts the two agree, along with the scheme's declaration in the app's
/// `Info.plist`. Every part of that is a silent failure: a drifted scheme, or an
/// undeclared one, just opens the app on the list, which is exactly what it did
/// before the link existed.
enum NoteDeepLink {
    static let scheme = "j-notes"
    static let noteHost = "note"

    static func url(for id: UUID) -> URL? {
        var components = URLComponents()

        components.scheme = scheme
        components.host = noteHost
        components.path = "/\(id.uuidString)"

        return components.url
    }

    /// The note `url` names, or `nil` when it names none.
    ///
    /// Deliberately strict about the scheme and the host rather than reading the
    /// last path component of anything handed to it: `onOpenURL` sees every URL
    /// the app is ever asked to open.
    static func noteID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == noteHost else { return nil }

        return UUID(uuidString: url.lastPathComponent)
    }
}

// Lightweight note representation shared via App Group UserDefaults with the widget.
// Must have the same JSON structure as WidgetNote in NotesWidget.swift.
struct WidgetNoteEntry: Codable {
    /// How much of a note's body travels to the shared container.
    ///
    /// The widget never draws more than this: `WidgetNote.displayTitle` falls back
    /// to `content.prefix(60)` for an untitled note, and `bodyPreview` renders one
    /// line in the medium family and three in the small one. Truncated rather than
    /// sent whole for the same reason a protected note's body is dropped entirely —
    /// App Group `UserDefaults` has none of the `.completeFileProtection` the notes
    /// file is written with, so it stays readable while the device is locked.
    /// Sending the rest put the full text of every recent note in there, for
    /// characters nothing would ever render.
    static let bodyPreviewLimit = 200

    let id: UUID
    let title: String
    let content: String
    let isDrawing: Bool
    let isPinned: Bool
    let isProtected: Bool

    init(from note: NoteModel) {
        self.id = note.id
        // Title and content of a protected note are both omitted — App Group
        // UserDefaults lacks the .completeFileProtection used by the main notes
        // file, and the widget renders on the lock screen. The widget
        // substitutes a placeholder for the empty title.
        self.title = note.isProtected ? "" : note.title
        self.content = note.isProtected
            ? ""
            : String(note.content.prefix(Self.bodyPreviewLimit))
        self.isDrawing = note.type == .drawing
        self.isPinned = note.pinned
        self.isProtected = note.isProtected
        // Tags are deliberately not shared, and neither is `createdAt`. The
        // widget renders neither, so sending them only put more of the user's
        // record into a container that is readable while the device is locked —
        // for nothing. The payload's order is decided here, by
        // `NotesStore.widgetPayload`, so the widget never needed the dates to
        // sort by either. Everything that leaves the app is redacted as far as it
        // can be.
    }
}
