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
}

// Lightweight note representation shared via App Group UserDefaults with the widget.
// Must have the same JSON structure as WidgetNote in NotesWidget.swift.
struct WidgetNoteEntry: Codable {
    let id: UUID
    let title: String
    let content: String
    let isDrawing: Bool
    let isPinned: Bool
    let isProtected: Bool
    let tags: [String]
    let createdAt: Date

    init(from note: NoteModel) {
        self.id = note.id
        self.title = note.title
        // Protected note content is omitted — App Group UserDefaults lacks
        // .completeFileProtection used by the main notes file.
        self.content = note.isProtected ? "" : note.content
        self.isDrawing = note.type == .drawing
        self.isPinned = note.pinned
        self.isProtected = note.isProtected
        self.tags = note.tags
        self.createdAt = note.createdAt
    }
}
