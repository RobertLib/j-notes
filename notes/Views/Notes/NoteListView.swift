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
    
    private func togglePinned(note: NoteModel) {
        withAnimation {
            notesStore.update(note: note, pinned: !note.pinned)
        }
    }
    
    private func deleteNote(note: NoteModel) {
        withAnimation {
            NotificationManager.instance.removeNotifications(
                identifiers: note.notificationIdentifiers
            )
            
            notesStore.remove(note: note)
        }
    }
    
    private func moveNote(offsets: IndexSet, offset: Int) {
        withAnimation {
            notesStore.moveNote(from: offsets, to: offset)
        }
    }
    
    var body: some View {
        ForEach(notes) { note in
            NoteRowView(note: note)
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
        .onDelete(perform: { offsets in })
//        .onMove(perform: moveNote)
    }
}

struct NoteListView_Previews: PreviewProvider {
    static var previews: some View {
        NoteListView(notes: [
            NoteModel(title: "Title", content: "Lorem ipsum")
        ])
    }
}
