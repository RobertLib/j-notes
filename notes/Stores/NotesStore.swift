//
//  NotesStore.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import SwiftUI

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteModel] = []
    @Published private(set) var saveError: String?

    private var saveTask: Task<Void, Never>?

    private static let notesFileURL: URL = {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("notes.json")
    }()

    private func load() {
        // Migration: Check UserDefaults first for backward compatibility
        if let data = UserDefaults.standard.data(forKey: "notes"),
           let decoded = try? JSONDecoder().decode([NoteModel].self, from: data) {
            notes = decoded
            // Migrate to file storage
            Task {
                await save()
            }
            UserDefaults.standard.removeObject(forKey: "notes")
            print("✅ Migrated notes from UserDefaults to file storage")
            return
        }

        // Load from file
        do {
            let data = try Data(contentsOf: Self.notesFileURL)
            let decoded = try JSONDecoder().decode([NoteModel].self, from: data)
            notes = decoded
            print("✅ Loaded \(notes.count) notes from file storage")
        } catch CocoaError.fileReadNoSuchFile {
            // First launch - no notes file exists yet
            print("ℹ️ No notes file found - starting fresh")
        } catch {
            print("❌ Failed to load notes: \(error.localizedDescription)")
            saveError = "Failed to load notes"
        }
    }

    private func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(notes)
            try encoded.write(to: Self.notesFileURL, options: [.atomic, .completeFileProtection])
            saveError = nil
            print("✅ Successfully saved \(notes.count) notes")
        } catch {
            print("❌ Failed to save notes: \(error.localizedDescription)")
            saveError = String(localized: "Failed to save notes: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        // Cancel previous save task if still running
        saveTask?.cancel()

        // Schedule new save task with debouncing
        saveTask = Task {
            // Small delay to debounce rapid changes
            try? await Task.sleep(for: .milliseconds(100))

            guard !Task.isCancelled else { return }
            await save()
        }
    }

    init() {
        load()
    }

    func add(
        title: String,
        content: String,
        color: Color? = nil,
        isColorOn: Bool? = nil,
        reminder: Date? = nil,
        isReminderOn: Bool? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil
    ) {
        notes.append(
            NoteModel(
                title: title,
                content: content,
                color: isColorOn == false ? nil : color,
                reminder: isReminderOn == false ? nil : reminder,
                notificationIdentifiers: notificationIdentifiers?.count == 0
                    ? nil
                    : notificationIdentifiers,
                location: location
            )
        )
        scheduleSave()
    }

    func update(
        note: NoteModel,
        title: String? = nil,
        content: String? = nil,
        pinned: Bool? = nil,
        color: Color? = nil,
        isColorOn: Bool? = nil,
        reminder: Date? = nil,
        isReminderOn: Bool? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil
    ) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = NoteModel(
                id: note.id,
                createdAt: note.createdAt,
                title: title ?? note.title,
                content: content ?? note.content,
                pinned: pinned ?? note.pinned,
                color: isColorOn == false ? nil : color ?? note.color,
                reminder:
                    isReminderOn == false ? nil : reminder ?? note.reminder,
                notificationIdentifiers: notificationIdentifiers?.count == 0
                    ? nil
                    : notificationIdentifiers,
                location: location ?? note.location
            )
            scheduleSave()
        }
    }

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
}
