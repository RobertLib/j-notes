//
//  NotesWidget.swift
//  NotesWidget
//

import SwiftUI
import WidgetKit

// Must match AppGroup.swift in the main app target.
private enum WidgetAppGroup {
    static let identifier = "group.cz.rob.notes"
    static let widgetDataKey = "widgetNotes"
    static let widgetTotalKey = "widgetNotesTotal"

    // Mirrors NoteDeepLink in AppGroup.swift — must stay in sync, and the scheme
    // must stay declared in the app's Info.plist. Both are checked by
    // scripts/check-shared-contract.sh: a drifted or undeclared scheme still
    // compiles and still opens the app, just on the list rather than on the note
    // that was tapped, which is indistinguishable from having no link at all.
    static let scheme = "j-notes"
    static let noteHost = "note"

    static func noteURL(for id: UUID) -> URL? {
        var components = URLComponents()

        components.scheme = scheme
        components.host = noteHost
        components.path = "/\(id.uuidString)"

        return components.url
    }
}

// Mirrors WidgetNoteEntry in AppGroup.swift — must stay in sync.
struct WidgetNote: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let isDrawing: Bool
    let isPinned: Bool
    let isProtected: Bool

    var displayTitle: String {
        if !title.isEmpty { return title }
        if isProtected { return "•••••••••••" }
        if isDrawing { return String(localized: "Drawing note") }
        return String(content.prefix(60))
    }

    /// The body line shown underneath `displayTitle`, or `nil` when there is
    /// nothing left to show.
    ///
    /// An untitled note has no title of its own, so `displayTitle` already falls
    /// back to its content — rendering `content` below it as well printed the
    /// same text twice, once as the headline and once as the caption, on every
    /// home screen. A protected note's body is never shared in the first place,
    /// and a drawing has none.
    var bodyPreview: String? {
        guard !title.isEmpty, !isProtected, !isDrawing, !content.isEmpty else {
            return nil
        }

        return content
    }
}

// MARK: - Timeline

struct NotesEntry: TimelineEntry {
    let date: Date
    let notes: [WidgetNote]

    /// Total number of active notes, which is not the same as `notes.count` —
    /// the app truncates the payload it shares.
    let totalCount: Int

    init(date: Date, notes: [WidgetNote], totalCount: Int? = nil) {
        self.date = date
        self.notes = notes
        self.totalCount = totalCount ?? notes.count
    }
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: .now, notes: [
            WidgetNote(id: UUID(), title: "Shopping list", content: "Milk, eggs, bread", isDrawing: false, isPinned: true, isProtected: false),
            WidgetNote(id: UUID(), title: "Meeting notes", content: "Discuss Q4 roadmap", isDrawing: false, isPinned: false, isProtected: false),
            WidgetNote(id: UUID(), title: "", content: "Call dentist tomorrow", isDrawing: false, isPinned: false, isProtected: false)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        // Reload triggered by the app via WidgetCenter.shared.reloadAllTimelines()
        completion(Timeline(entries: [loadEntry()], policy: .never))
    }

    private func loadEntry() -> NotesEntry {
        guard
            let defaults = UserDefaults(suiteName: WidgetAppGroup.identifier),
            let data = defaults.data(forKey: WidgetAppGroup.widgetDataKey),
            let notes = try? JSONDecoder().decode([WidgetNote].self, from: data)
        else { return NotesEntry(date: .now, notes: []) }

        // `integer(forKey:)` yields 0 for a payload written by a build that did
        // not store the total yet; fall back to what was actually shared.
        let stored = defaults.integer(forKey: WidgetAppGroup.widgetTotalKey)

        return NotesEntry(
            date: .now,
            notes: notes,
            totalCount: max(stored, notes.count)
        )
    }
}

// MARK: - Views

struct NotesWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NotesEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemLarge:
            // Roughly twice the medium family's height, but the header and the
            // dividers eat a row's worth of it — so six rather than the seven the
            // arithmetic alone would allow. `NotesStore.widgetPayloadLimit` shares
            // twenty, so there is always more than this to draw from.
            NotesListWidgetView(entry: entry, rowLimit: 6)
        case .accessoryInline:
            InlineAccessoryView(entry: entry)
        case .accessoryCircular:
            CircularAccessoryView(entry: entry)
        case .accessoryRectangular:
            RectangularAccessoryView(entry: entry)
        default:
            NotesListWidgetView(entry: entry, rowLimit: 3)
        }
    }
}

struct SmallWidgetView: View {
    let entry: NotesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let first = entry.notes.first {
                // The lock is what tells a redacted note from a damaged one. The
                // medium family has drawn it all along; here the note arrived as a
                // row of bullets and nothing else, which reads as broken text
                // rather than as something deliberately withheld.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if first.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(first.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                }

                if let body = first.bodyPreview {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                Text("No notes")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        // The small family draws one note, so the whole widget is that note's
        // link. `nil` with nothing to show, which leaves the tap opening the app
        // on the list — the right place to land when the widget is empty.
        .widgetURL(entry.notes.first.flatMap { WidgetAppGroup.noteURL(for: $0.id) })
    }
}

/// The families that draw a list of notes: medium and large, which differ only in
/// how many rows they have room for.
///
/// One view rather than one per family. They were already the same layout, and a
/// second copy of it is how the pinned marker, the lock and the per-row link come
/// to be present in one size and missing in the next.
struct NotesListWidgetView: View {
    let entry: NotesEntry

    /// How many notes this family has room for.
    let rowLimit: Int

    private var displayNotes: [WidgetNote] { Array(entry.notes.prefix(rowLimit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .font(.subheadline)
                Text("J-Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entry.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if displayNotes.isEmpty {
                Spacer()
                Text("No notes")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(Array(displayNotes.enumerated()), id: \.element.id) { idx, note in
                    // A link per row rather than one `widgetURL` for the whole
                    // widget: these families show several notes, and a tap that
                    // opened whichever one happened to be first would be wrong
                    // most of the time — more so the larger the family.
                    if let url = WidgetAppGroup.noteURL(for: note.id) {
                        Link(destination: url) { row(for: note) }
                    } else {
                        row(for: note)
                    }

                    if idx < displayNotes.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// One note's row. Split out of the loop above so the linked and unlinked
    /// spellings of it cannot drift apart.
    @ViewBuilder
    private func row(for note: WidgetNote) -> some View {
        HStack(spacing: 6) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    // The app's accent, as the list's own pin uses.
                    // Spelled `.orange` before, which happened to
                    // match — but the widget's AccentColor asset was
                    // empty, so `accentColor` here would have come out
                    // system blue. Both are fixed together.
                    .foregroundStyle(Color.accentColor)
            }
            if note.isProtected {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(note.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.displayTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let body = note.bodyPreview {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        // A `Link` tints its content like a button otherwise, which would turn
        // every row of the widget accent-coloured.
        .foregroundStyle(.primary)
        // The whole row is the tap target, not just the text in it.
        .contentShape(Rectangle())
    }
}

// MARK: - Lock Screen accessories

// The three accessory families render on the Lock Screen, where the device is by
// definition not unlocked. Nothing extra is withheld for them: the payload they
// read is already written for exactly this — a protected note arrives with neither
// its title nor its body, because App Group `UserDefaults` has none of the
// `.completeFileProtection` the notes file is written with, and the home screen is
// no more private than the lock screen. See `WidgetNoteEntry`.
//
// They also paint no background of their own. The system draws the slot and tints
// the content to match the wallpaper, so a `.fill.tertiary` container — right for
// the home screen families above — would show up as a grey block on top of it.

/// The Lock Screen's one-line slot: the newest note.
struct InlineAccessoryView: View {
    let entry: NotesEntry

    var body: some View {
        Group {
            if let first = entry.notes.first {
                // No lock glyph: the inline slot renders a single line of text and
                // drops anything else, and `displayTitle` already stands in for a
                // protected note's title.
                Text(first.displayTitle)
            } else {
                Text("No notes")
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(entry.notes.first.flatMap { WidgetAppGroup.noteURL(for: $0.id) })
    }
}

/// The Lock Screen's circular slot: how many notes there are.
///
/// A count rather than a note. The slot is a little over a centimetre across, and
/// the two or three words of a title that would fit are not enough to recognise a
/// note by — where the number is the one thing about the library that is legible
/// at that size. Deliberately carries no `widgetURL`, so the tap opens the list,
/// which is what the count is about.
struct CircularAccessoryView: View {
    let entry: NotesEntry

    var body: some View {
        ZStack {
            // The system's own backdrop for the slot, so the glyph stays legible
            // over a light wallpaper.
            AccessoryWidgetBackground()

            VStack(spacing: 0) {
                Image(systemName: "note.text")
                    .font(.caption2)

                Text("\(entry.totalCount)")
                    .font(.headline)
                    // A four-figure library still has to fit inside the circle.
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

/// The Lock Screen's rectangular slot: the newest note, title and a body line.
struct RectangularAccessoryView: View {
    let entry: NotesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let first = entry.notes.first {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if first.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                    }

                    Text(first.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let body = first.bodyPreview {
                    Text(body)
                        .font(.caption)
                        .lineLimit(2)
                }
            } else {
                Text("No notes")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.clear, for: .widget)
        .widgetURL(entry.notes.first.flatMap { WidgetAppGroup.noteURL(for: $0.id) })
    }
}

// MARK: - Widget definition

struct NotesWidget: Widget {
    let kind = "NotesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NotesProvider()) { entry in
            NotesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("J-Notes")
        .description(Text("widgetDescription"))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

#Preview(as: .systemMedium) {
    NotesWidget()
} timeline: {
    NotesEntry(date: .now, notes: [
        WidgetNote(id: UUID(), title: "Shopping", content: "Milk, eggs", isDrawing: false, isPinned: true, isProtected: false),
        WidgetNote(id: UUID(), title: "Meeting", content: "Q4 roadmap", isDrawing: false, isPinned: false, isProtected: false)
    ])
}
