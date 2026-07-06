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
}

// Mirrors WidgetNoteEntry in AppGroup.swift — must stay in sync.
struct WidgetNote: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let isDrawing: Bool
    let isPinned: Bool
    let isProtected: Bool
    let tags: [String]
    let createdAt: Date

    var displayTitle: String {
        if !title.isEmpty { return title }
        if isProtected { return "•••••••••••" }
        if isDrawing { return String(localized: "Drawing note") }
        return String(content.prefix(60))
    }
}

// MARK: - Timeline

struct NotesEntry: TimelineEntry {
    let date: Date
    let notes: [WidgetNote]
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: .now, notes: [
            WidgetNote(id: UUID(), title: "Shopping list", content: "Milk, eggs, bread", isDrawing: false, isPinned: true, isProtected: false, tags: ["personal"], createdAt: .now),
            WidgetNote(id: UUID(), title: "Meeting notes", content: "Discuss Q4 roadmap", isDrawing: false, isPinned: false, isProtected: false, tags: ["work"], createdAt: .now),
            WidgetNote(id: UUID(), title: "", content: "Call dentist tomorrow", isDrawing: false, isPinned: false, isProtected: false, tags: [], createdAt: .now)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(NotesEntry(date: .now, notes: loadNotes()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        let entry = NotesEntry(date: .now, notes: loadNotes())
        // Reload triggered by the app via WidgetCenter.shared.reloadAllTimelines()
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadNotes() -> [WidgetNote] {
        guard
            let defaults = UserDefaults(suiteName: WidgetAppGroup.identifier),
            let data = defaults.data(forKey: WidgetAppGroup.widgetDataKey),
            let notes = try? JSONDecoder().decode([WidgetNote].self, from: data)
        else { return [] }
        return notes
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
        default:
            MediumWidgetView(entry: entry)
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
                Text("\(entry.notes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let first = entry.notes.first {
                Text(first.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                if !first.isProtected && !first.isDrawing && !first.content.isEmpty {
                    Text(first.content)
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
    }
}

struct MediumWidgetView: View {
    let entry: NotesEntry

    private var displayNotes: [WidgetNote] { Array(entry.notes.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .font(.subheadline)
                Text("J-Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entry.notes.count)")
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
                    HStack(spacing: 6) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
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
                                if !note.isDrawing && !note.content.isEmpty {
                                    Text(note.content)
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

                    if idx < displayNotes.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
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
        .description("See your recent notes at a glance")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    NotesWidget()
} timeline: {
    NotesEntry(date: .now, notes: [
        WidgetNote(id: UUID(), title: "Shopping", content: "Milk, eggs", isDrawing: false, isPinned: true, isProtected: false, tags: [], createdAt: .now),
        WidgetNote(id: UUID(), title: "Meeting", content: "Q4 roadmap", isDrawing: false, isPinned: false, isProtected: false, tags: [], createdAt: .now)
    ])
}
