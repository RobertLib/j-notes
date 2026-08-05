//
//  CreateNoteIntent.swift
//  notes
//
//  Created by Robert Libšanský on 03.10.2025.
//

import AppIntents
import OSLog
import SwiftUI

/// Raised when the note could not be written to disk — most likely because the
/// device is locked, which leaves the notes file unreadable behind
/// `.completeFileProtection`.
///
/// Thrown rather than reported as a cheerful dialog: this process can be
/// terminated the moment `perform()` returns, so "note created" would name a
/// note that no longer exists anywhere. The same stance `NotesStore.importNotes`
/// takes for the same reason.
enum CreateNoteError: Error, CustomLocalizedStringResourceConvertible {
    case notSaved

    /// The shortcut was run with nothing to put in the note.
    ///
    /// Refused rather than saved, because the form refuses the same thing through
    /// `NoteContentRule` and this is the one way into the store that went around
    /// it: a note with no body renders as a blank row that opens onto nothing, and
    /// the user has no way to tell it apart from the notes they meant to keep.
    case noContent

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSaved: "intentSaveFailed"
        case .noContent: "intentEmptyContent"
        }
    }
}

struct CreateNoteIntent: AppIntent {
    // `LocalizedStringResource` resolves against Localizable.strings in the main
    // bundle, so these are keys like everywhere else in the app. They used to be
    // bare English sentences, which left the Shortcuts app untranslated.
    static let title: LocalizedStringResource = "intentCreateNote"
    static let description = IntentDescription("intentCreateNoteDescription")

    @Parameter(title: "intentParameterTitle")
    var title: String?

    @Parameter(title: "intentParameterContent")
    var content: String

    /// Stays written out in English because that literal doubles as the lookup
    /// key — App Intents records the summary as a bare format string rather than
    /// a key of its own, so `Localizable.strings` is keyed by the whole sentence,
    /// `${title}` placeholders and all. Same arrangement as `AppShortcuts.strings`
    /// and the widget's keys; `check-localization.sh` asserts the two agree.
    static var parameterSummary: some ParameterSummary {
        Summary("Create note \(\.$title) with content \(\.$content)")
    }

    /// A note the intent has just written, reduced to what the spoken
    /// confirmation needs to know about it.
    struct CreatedNote: Equatable {
        /// The title as it was stored: trimmed, and empty for an untitled note.
        let title: String

        /// The body as it was stored.
        let content: String

        /// Whether the confirmation names the note. An untitled one has nothing
        /// to name, so it gets the generic wording instead.
        var isNamed: Bool { !title.isEmpty }
    }

    /// Writes the note the shortcut asked for, and reports what was stored.
    ///
    /// Split out of `perform()` so the intent's rules can be exercised at all, the
    /// same reason `NoteContentRule`, `ReminderFormState` and `NoteLock` live
    /// outside the views they serve. Two things made `perform()` unreachable from a
    /// test: it goes straight to `NotesStore.shared`, which is the real Documents
    /// file — a test running it would write into the notes of whatever is installed
    /// — and it hands back an opaque `IntentResult`, which says nothing that can be
    /// asserted on. This was the last file in either target with no coverage at
    /// all, and what it decides is not decoration: an empty note refused, and a
    /// note that could not be written never reported as saved.
    ///
    /// - Parameter store: where the note goes. `perform()` passes the shared store;
    ///   a test passes one over a file of its own.
    @MainActor
    static func createNote(
        title: String?,
        content: String,
        in store: NotesStore
    ) async throws -> CreatedNote {
        // Trimmed the way the form trims, so a note dictated with a trailing
        // space is stored the same whichever way it was made.
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // The same rule the form's Save button is bound to. A shortcut run with an
        // empty body — or one that is nothing but whitespace, which `isEmpty` says
        // nothing about — used to create a note regardless. See `noContent`.
        guard NoteContentRule.hasContentToSave(
            type: .text,
            trimmedContent: trimmedContent,
            hasStrokes: false,
            hasBackgroundImage: false
        ) else {
            Log.store.notice("Intent refused: the shortcut supplied no content")
            throw CreateNoteError.noContent
        }

        store.add(
            title: trimmedTitle,
            content: trimmedContent
        )

        // Persist immediately - the intent may be terminated right after perform() returns.
        // The note is deliberately left in memory on failure: if this process is
        // the running app, `NotesStore.refresh()` folds it back in once storage
        // becomes readable. It just must not be reported as saved.
        guard await store.saveNow() else {
            Log.store.error("Intent could not persist the new note")
            throw CreateNoteError.notSaved
        }

        return CreatedNote(title: trimmedTitle, content: trimmedContent)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Use the shared NotesStore so the running app and the intent
        // operate on the same in-memory data and storage file
        let created = try await Self.createNote(
            title: title,
            content: content,
            in: .shared
        )

        return .result(
            dialog: created.isNamed
                ? IntentDialog(LocalizedStringResource("intentNoteCreatedNamed \(created.title)"))
                : IntentDialog("intentNoteCreated")
        )
    }
}

struct NotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Spoken phrases are localized through AppShortcuts.strings — they are
        // the one part of App Intents that does not read Localizable.strings.
        // They stay written out in English here because that literal doubles as
        // the lookup key.
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Add a new note in \(.applicationName)"
            ],
            shortTitle: "intentCreateNote",
            systemImageName: "note.text.badge.plus"
        )
    }
}
