//
//  DeletedNotesView.swift
//  notes
//
//  Created by Robert Libšanský on 13.10.2025.
//

import SwiftUI

struct DeletedNotesView: View {
    @EnvironmentObject private var notesStore: NotesStore
    @State private var isDeleteNoteConfirmPresented = false
    @State private var noteToDelete: NoteModel?

    var body: some View {
        List {
            if notesStore.deletedNotes.isEmpty {
                Text("noDeletedNotes")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(notesStore.deletedNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        if !note.title.isEmpty {
                            Text(note.title)
                                .font(.headline)
                        }

                        if note.type == .text {
                            Text(note.content.prefix(100))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("drawingNote")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                        }

                        if let deletedAt = note.deletedAt {
                            Text("deletedAt") + Text(": \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            withAnimation {
                                notesStore.restoreFromTrash(note: note)
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            noteToDelete = note
                            isDeleteNoteConfirmPresented = true
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .navigationTitle("deletedNotes")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "permanentDeleteConfirm",
            isPresented: $isDeleteNoteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("permanentDelete", role: .destructive) {
                if let note = noteToDelete {
                    Task {
                        // Cancel notification if exists
                        await NotificationManager.instance.removeNotifications(
                            identifiers: note.notificationIdentifiers
                        )

                        notesStore.remove(note: note)
                        noteToDelete = nil
                    }
                }
            }

            Button("cancel", role: .cancel) {
                noteToDelete = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeletedNotesView()
    }
    .environmentObject(NotesStore())
}
