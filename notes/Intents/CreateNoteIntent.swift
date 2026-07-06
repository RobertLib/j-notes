//
//  CreateNoteIntent.swift
//  notes
//
//  Created by Robert Libšanský on 03.10.2025.
//

import AppIntents
import SwiftUI

struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Create a new note with title and content")

    @Parameter(title: "Title")
    var title: String?

    @Parameter(title: "Content")
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create note \(\.$title) with content \(\.$content)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Use the shared NotesStore so the running app and the intent
        // operate on the same in-memory data and storage file
        let notesStore = NotesStore.shared

        notesStore.add(
            title: title ?? "",
            content: content
        )

        // Persist immediately - the intent may be terminated right after perform() returns
        await notesStore.saveNow()

        let dialog: IntentDialog
        if let noteTitle = title, !noteTitle.isEmpty {
            dialog = "Created note '\(noteTitle)'"
        } else {
            dialog = "Note created successfully"
        }

        return .result(dialog: dialog)
    }
}

struct NotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Add a new note in \(.applicationName)"
            ],
            shortTitle: "Create Note",
            systemImageName: "note.text.badge.plus"
        )
    }
}
