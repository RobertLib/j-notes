//
//  NotesStore.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
final class NotesStore {
    /// Shared instance used by the app and App Intents so they operate on the same data
    static let shared = NotesStore()

    private(set) var notes: [NoteModel] = []
    private(set) var saveError: String?

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    // Exposed for test teardown; production code always uses the default.
    let fileURL: URL

    private static let defaultFileURL: URL = {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("notes.json")
    }()

    private func load() {
        var fileLoadError: Error? = nil

        // Try to load from file first (current storage)
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([NoteModel].self, from: data)
            notes = decoded
            print("✅ Loaded \(notes.count) notes from file storage")

            // Clean up old UserDefaults if they exist (migration already completed)
            if UserDefaults.standard.data(forKey: "notes") != nil {
                UserDefaults.standard.removeObject(forKey: "notes")
                print("🧹 Cleaned up old UserDefaults data")
            }
            return
        } catch CocoaError.fileReadNoSuchFile {
            // File doesn't exist - check for migration from UserDefaults
            print("ℹ️ No notes file found - checking for UserDefaults migration")
        } catch {
            // File exists but is corrupted - save error and try UserDefaults fallback
            print("⚠️ File corrupted, trying UserDefaults fallback: \(error.localizedDescription)")
            fileLoadError = error
        }

        // Migration: Load from UserDefaults if file doesn't exist OR is corrupted
        if let data = UserDefaults.standard.data(forKey: "notes"),
           let decoded = try? JSONDecoder().decode([NoteModel].self, from: data) {
            notes = decoded

            if fileLoadError != nil {
                print("✅ Recovered \(notes.count) notes from UserDefaults backup after file corruption")
            } else {
                print("⚠️ Found \(notes.count) notes in UserDefaults, migrating to file storage...")
            }

            // Perform SYNCHRONOUS migration/recovery to file
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let encoded = try encoder.encode(notes)
                try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])

                // Only remove from UserDefaults AFTER confirmed successful save
                UserDefaults.standard.removeObject(forKey: "notes")
                print("✅ Successfully saved \(notes.count) notes to file storage")
                saveError = nil
            } catch {
                print("❌ Failed to save to file: \(error.localizedDescription)")
                print("⚠️ Notes remain in UserDefaults as backup")
                saveError = "Failed to save notes"
            }
            return
        }

        // No data anywhere - either first launch or both sources failed
        if fileLoadError != nil {
            print("❌ Both file and UserDefaults failed - data may be lost")
            saveError = "Failed to load notes: \(fileLoadError!.localizedDescription)"
        } else {
            print("ℹ️ Starting fresh - no existing notes found")
        }
    }

    private func save() async -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(notes)
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
            saveError = nil
            print("✅ Successfully saved \(notes.count) notes")
            syncWidgetData()
            return true
        } catch {
            print("❌ Failed to save notes: \(error.localizedDescription)")
            saveError = String(localized: "Failed to save notes: \(error.localizedDescription)")
            return false
        }
    }

    private func syncWidgetData() {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return }
        let entries = activeNotes
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map { WidgetNoteEntry(from: $0) }
        if let data = try? JSONEncoder().encode(Array(entries)) {
            defaults.set(data, forKey: AppGroup.widgetDataKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func scheduleSave() {
        // Cancel previous save task if still running
        saveTask?.cancel()

        // Schedule new save task with debouncing
        saveTask = Task {
            // Small delay to debounce rapid changes
            try? await Task.sleep(for: .milliseconds(100))

            guard !Task.isCancelled else { return }
            _ = await save()
        }
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()
    }

    /// Saves immediately, cancelling any pending debounced save.
    /// Use when the caller needs a guarantee that data hit the disk (e.g. App Intents).
    @discardableResult
    func saveNow() async -> Bool {
        saveTask?.cancel()
        return await save()
    }

    func setError(_ message: String) {
        saveError = message
    }

    func add(
        title: String,
        content: String,
        type: NoteType? = nil,
        drawingData: Data? = nil,
        drawingCanvasSize: CGSize? = nil,
        backgroundImageData: Data? = nil,
        color: Color? = nil,
        isColorOn: Bool? = nil,
        reminder: Date? = nil,
        isReminderOn: Bool? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil,
        tags: [String]? = nil,
        isProtected: Bool? = nil
    ) {
        notes.append(
            NoteModel(
                title: title,
                content: content,
                type: type ?? .text,
                drawingData: drawingData,
                drawingCanvasSize: drawingCanvasSize,
                backgroundImageData: backgroundImageData,
                color: isColorOn == false ? nil : color,
                reminder: isReminderOn == false ? nil : reminder,
                notificationIdentifiers: notificationIdentifiers?.count == 0
                    ? nil
                    : notificationIdentifiers,
                location: location,
                tags: tags,
                isProtected: isProtected
            )
        )
        scheduleSave()
    }

    func update(
        note: NoteModel,
        title: String? = nil,
        content: String? = nil,
        type: NoteType? = nil,
        drawingData: Data?? = nil,
        drawingCanvasSize: CGSize?? = nil,
        backgroundImageData: Data?? = nil,
        pinned: Bool? = nil,
        color: Color? = nil,
        isColorOn: Bool? = nil,
        reminder: Date? = nil,
        isReminderOn: Bool? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil,
        tags: [String]? = nil,
        isProtected: Bool? = nil
    ) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = NoteModel(
                id: note.id,
                createdAt: note.createdAt,
                title: title ?? note.title,
                content: content ?? note.content,
                type: type ?? note.type,
                drawingData: drawingData ?? note.drawingData,
                drawingCanvasSize: drawingCanvasSize ?? note.drawingCanvasSize,
                backgroundImageData: backgroundImageData ?? note.backgroundImageData,
                pinned: pinned ?? note.pinned,
                color: isColorOn == false ? nil : color ?? note.color,
                reminder:
                    isReminderOn == false ? nil : reminder ?? note.reminder,
                notificationIdentifiers: notificationIdentifiers?.count == 0
                    ? nil
                    : notificationIdentifiers,
                location: location ?? note.location,
                isDeleted: note.isDeleted,
                deletedAt: note.deletedAt,
                tags: tags ?? note.tags,
                isProtected: isProtected ?? note.isProtected
            )
            scheduleSave()
        }
    }

    // Simplified update that accepts full note
    func update(note: NoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            scheduleSave()
        }
    }

    // Soft delete - move to trash
    func moveToTrash(note: NoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = NoteModel(
                id: note.id,
                createdAt: note.createdAt,
                title: note.title,
                content: note.content,
                type: note.type,
                drawingData: note.drawingData,
                drawingCanvasSize: note.drawingCanvasSize,
                backgroundImageData: note.backgroundImageData,
                pinned: note.pinned,
                color: note.color,
                reminder: note.reminder,
                notificationIdentifiers: note.notificationIdentifiers,
                location: note.location,
                isDeleted: true,
                deletedAt: Date(),
                tags: note.tags,
                isProtected: note.isProtected
            )
            scheduleSave()
        }
    }

    // Restore from trash
    func restoreFromTrash(note: NoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = NoteModel(
                id: note.id,
                createdAt: note.createdAt,
                title: note.title,
                content: note.content,
                type: note.type,
                drawingData: note.drawingData,
                drawingCanvasSize: note.drawingCanvasSize,
                backgroundImageData: note.backgroundImageData,
                pinned: note.pinned,
                color: note.color,
                reminder: note.reminder,
                notificationIdentifiers: note.notificationIdentifiers,
                location: note.location,
                isDeleted: false,
                deletedAt: nil,
                tags: note.tags,
                isProtected: note.isProtected
            )
            scheduleSave()
        }
    }

    // Permanently delete
    func remove(note: NoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
            scheduleSave()
        }
    }

    func removeNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        scheduleSave()
    }

    func moveNote(from offsets: IndexSet, to offset: Int) {
        notes.move(fromOffsets: offsets, toOffset: offset)
        scheduleSave()
    }

    // Export notes to JSON data
    func exportNotes() -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            print("✅ Exported \(notes.count) notes")
            return data
        } catch {
            print("❌ Failed to export notes: \(error.localizedDescription)")
            saveError = "Failed to export notes: \(error.localizedDescription)"
            return nil
        }
    }

    // Import notes from JSON data
    func importNotes(from data: Data, replaceExisting: Bool = false) -> Bool {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let importedNotes = try decoder.decode([NoteModel].self, from: data)

            if replaceExisting {
                // Replace all existing notes
                notes = importedNotes
                print("✅ Replaced all notes with \(importedNotes.count) imported notes")
            } else {
                // Merge - add only notes with IDs that don't exist
                var addedCount = 0
                for importedNote in importedNotes {
                    if !notes.contains(where: { $0.id == importedNote.id }) {
                        notes.append(importedNote)
                        addedCount += 1
                    }
                }
                print("✅ Imported \(addedCount) new notes (skipped \(importedNotes.count - addedCount) duplicates)")
            }

            scheduleSave()
            return true
        } catch {
            print("❌ Failed to import notes: \(error.localizedDescription)")
            saveError = "Failed to import notes: \(error.localizedDescription)"
            return false
        }
    }

    // Computed properties for filtered notes
    var activeNotes: [NoteModel] {
        notes.filter { !$0.isDeleted }
    }

    var deletedNotes: [NoteModel] {
        notes.filter { $0.isDeleted }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var allTags: [String] {
        Set(activeNotes.flatMap { $0.tags }).sorted()
    }
}
