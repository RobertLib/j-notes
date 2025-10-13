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
    @State private var showErrorAlert = false
    @State private var sortOption: NoteSortOption = .dateNewest
    @State private var displayStyle: NoteDisplayStyle = .standard

    var searchedNotes: [NoteModel] {
        // Filter only active (non-deleted) notes
        let filtered = notesStore.activeNotes.filter({ note in
            searchText.isEmpty ||
            note.title.lowercased().contains(searchText.lowercased()) ||
            note.content.lowercased().contains(searchText.lowercased())
        })

        switch sortOption {
        case .dateNewest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .dateOldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .titleAZ:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
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

    private func sortIcon(for option: NoteSortOption) -> String {
        switch option {
        case .dateNewest:
            return "calendar.badge.clock"
        case .dateOldest:
            return "calendar"
        case .titleAZ:
            return "textformat.abc"
        case .titleZA:
            return "textformat.abc"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if !pinnedNotes.isEmpty {
                        Section("pinned") {
                            NoteListView(notes: pinnedNotes, displayStyle: displayStyle)
                        }
                    }

                    if !unpinnedNotes.isEmpty {
                        Section {
                            NoteListView(notes: unpinnedNotes, displayStyle: displayStyle)
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
            .alert("error", isPresented: $showErrorAlert) {
                Button("ok") {
                    showErrorAlert = false
                }
            } message: {
                if let error = notesStore.saveError {
                    Text(error)
                }
            }
            .onChange(of: notesStore.saveError) { oldValue, newValue in
                if newValue != nil {
                    showErrorAlert = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }

                if !notesStore.deletedNotes.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink {
                            DeletedNotesView()
                        } label: {
                            Text("deleted")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Section {
                            Picker("sortBy", selection: $sortOption) {
                                ForEach(NoteSortOption.allCases) { option in
                                    Label(option.localizedName, systemImage: sortIcon(for: option))
                                        .tag(option)
                                }
                            }
                        }

                        Section {
                            Picker("displayStyle", selection: $displayStyle) {
                                ForEach(NoteDisplayStyle.allCases) { style in
                                    Label(style.localizedName, systemImage: style.icon)
                                        .tag(style)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 18))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        NoteFormView().navigationTitle("newNote")
                    } label: {
                        Image(systemName: "plus").font(.system(size: 20))
                    }
                }
            }
            .searchable(text: $searchText)
        }
    }
}

#Preview {
    NotesView()
        .environmentObject(NotesStore())
}
