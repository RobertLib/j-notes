//
//  NotesView.swift
//  notes
//
//  Created by Robert Libšanský on 17.07.2022.
//

import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var notesStore: NotesStore
    
    @State private var searchText = ""
    
    var searchedNotes: [NoteModel] {
        notesStore.notes.filter({ note in
            searchText.isEmpty ||
            note.title.lowercased().contains(searchText.lowercased()) ||
            note.content.lowercased().contains(searchText.lowercased())
        }).sorted { $0.createdAt > $1.createdAt }
    }
    
    var pinnedNotes: [NoteModel] {
        searchedNotes.filter({
            $0.pinned == true
        })
    }
    
    var unpinnedNotes: [NoteModel] {
        searchedNotes.filter({
            $0.pinned == false
        })
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                List {
                    if !pinnedNotes.isEmpty {
                        Section("pinned") {
                            NoteListView(notes: pinnedNotes)
                        }
                    }
                    
                    if !unpinnedNotes.isEmpty {
                        Section {
                            NoteListView(notes: unpinnedNotes)
                        }
                    }
                }
                
                if searchedNotes.isEmpty {
                    Text("noNotes")
                        .font(.system(size: 25))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("notes")
            .navigationBarItems(
                leading: EditButton(),
                trailing:
                    NavigationLink {
                        NoteFormView().navigationTitle("newNote")
                    } label: {
                        Image(systemName: "plus").font(.system(size: 20))
                    }
            )
            .searchable(text: $searchText)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct NotesView_Previews: PreviewProvider {
    static var previews: some View {
        NotesView().environmentObject(NotesStore())
    }
}
