//
//  NotesView.swift
//  notes
//
//  Created by Robert Libšanský on 17.07.2022.
//

import SwiftUI
import UniformTypeIdentifiers

struct NotesView: View {
    @EnvironmentObject private var notesStore: NotesStore

    @State private var searchText = ""
    @State private var showErrorAlert = false
    @State private var sortOption: NoteSortOption = .dateNewest
    @State private var displayStyle: NoteDisplayStyle = .standard
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var showImportOptions = false
    @State private var importData: Data?

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

                        Section {
                            Button {
                                showExportSheet = true
                            } label: {
                                Label("exportNotes", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                showImportSheet = true
                            } label: {
                                Label("importNotes", systemImage: "square.and.arrow.down")
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
            .fileExporter(
                isPresented: $showExportSheet,
                document: NotesDocument(data: notesStore.exportNotes()),
                contentType: .json,
                defaultFilename: "j-notes-backup-\(Date().formatted(date: .numeric, time: .omitted))"
            ) { result in
                switch result {
                case .success:
                    print("✅ Export successful")
                case .failure(let error):
                    print("❌ Export failed: \(error.localizedDescription)")
                    notesStore.setError("Export failed: \(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $showImportSheet,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }

                    // Request access to security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        print("❌ Failed to access security-scoped resource")
                        notesStore.setError("Failed to access file")
                        return
                    }

                    defer {
                        url.stopAccessingSecurityScopedResource()
                    }

                    do {
                        let data = try Data(contentsOf: url)
                        importData = data
                        showImportOptions = true
                    } catch {
                        print("❌ Failed to read file: \(error.localizedDescription)")
                        notesStore.setError("Failed to read file: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    print("❌ Import failed: \(error.localizedDescription)")
                }
            }
            .alert("importNotes", isPresented: $showImportOptions) {
                Button("cancel", role: .cancel) {
                    importData = nil
                }
                Button("mergeNotes") {
                    if let data = importData {
                        _ = notesStore.importNotes(from: data, replaceExisting: false)
                    }
                    importData = nil
                }
                Button("replaceNotes", role: .destructive) {
                    if let data = importData {
                        _ = notesStore.importNotes(from: data, replaceExisting: true)
                    }
                    importData = nil
                }
            } message: {
                Text("importOptionsMessage")
            }
        }
    }
}

// Document for file export
struct NotesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data?

    init(data: Data?) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = data else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    NotesView()
        .environmentObject(NotesStore())
}
