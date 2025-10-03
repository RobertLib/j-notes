//
//  CreateNoteIntent.swift
//  notes
//
//  Created by Robert Libšanský on 03.10.2025.
//

import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Create a new note with title and content")

    @Parameter(title: "Title")
    var title: String?

    @Parameter(title: "Content")
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create note \(\.$title) with content \(\.$content)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Use shared NotesStore instance to ensure notes are saved to the same storage
        // Create a temporary instance and wait for save to complete
        let notesStore = NotesStore()

        notesStore.add(
            title: title ?? "",
            content: content
        )

        // Give the store time to save asynchronously
        try? await Task.sleep(for: .milliseconds(200))

        let dialog: IntentDialog
        if let noteTitle = title, !noteTitle.isEmpty {
            dialog = "Created note '\(noteTitle)'"
        } else {
            dialog = "Note created successfully"
        }

        return .result(dialog: dialog)
    }
}

@available(iOS 16.0, *)
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
