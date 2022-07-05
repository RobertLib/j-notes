//
//  NotesStore.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import SwiftUI

class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteModel] = [] {
        didSet {
            save()
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: "notes"),
           let decoded = try? JSONDecoder().decode([NoteModel].self, from: data) {
            notes = decoded
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: "notes")
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
        }
    }
    
    func remove(note: NoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
        }
    }
    
    func removeNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
    }
    
    func moveNote(from offsets: IndexSet, to offset: Int) {
        notes.move(fromOffsets: offsets, toOffset: offset)
    }
}
