//
//  NoteListView.swift
//  notes
//
//  Created by Robert Libšanský on 16.07.2022.
//

import SwiftUI

struct NoteListView: View {
    @EnvironmentObject private var notesStore: NotesStore

    let notes: [NoteModel]
    let displayStyle: NoteDisplayStyle

    private func togglePinned(note: NoteModel) {
        withAnimation {
            notesStore.update(note: note, pinned: !note.pinned)
        }
    }

    private func deleteNote(note: NoteModel) {
        withAnimation {
            // Move to trash instead of permanent delete
            notesStore.moveToTrash(note: note)
        }

        Task {
            await NotificationManager.instance.removeNotifications(
                identifiers: note.notificationIdentifiers
            )
        }
    }

    private func moveNote(offsets: IndexSet, offset: Int) {
        withAnimation {
            notesStore.moveNote(from: offsets, to: offset)
        }
    }

    var body: some View {
        ForEach(notes) { note in
            NoteRowView(note: note, displayStyle: displayStyle)
                .swipeActions(edge: .leading) {
                    Button {
                        togglePinned(note: note)
                    } label: {
                        let systemName =
                            "pin\(note.pinned ? ".slash" : "").fill"

                        Image(systemName: systemName)
                    }.tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteNote(note: note)
                    } label: {
                        Image(systemName: "trash.fill")
                    }.tint(.red)
                }
        }
        .onDelete { indexSet in
            indexSet.forEach { index in
                let note = notes[index]
                deleteNote(note: note)
            }
        }
    }
}

#Preview {
    NoteListView(
        notes: [
            NoteModel(title: "Title", content: "Lorem ipsum")
        ],
        displayStyle: .standard
    )
    .environmentObject(NotesStore())
}
