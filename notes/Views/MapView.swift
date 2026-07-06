//
//  MapView.swift
//  notes
//
//  Created by Robert Libšanský on 20.08.2022.
//

import MapKit
import SwiftUI

struct MapView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(NotesStore.self) private var notesStore

    @State private var sheetType: SheetType? = nil
    @State private var position: MapCameraPosition = .automatic

    enum SheetType: Identifiable {
        case singleNote(NoteModel)
        case notesList([NoteModel])

        var id: String {
            switch self {
            case .singleNote(let note): return "single-\(note.id)"
            case .notesList: return "list"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(groupedNotes) { group in
                    Annotation(annotationTitle(for: group), coordinate: group.coordinate) {
                        Button {
                            handleAnnotationTap(for: group)
                        } label: {
                            ZStack {
                                Image(systemName: "note.text")
                                    .frame(width: 40, height: 40)
                                    .background(
                                        group.notes.count > 1
                                            ? Color.gray.opacity(0.6)
                                            : (group.notes.first?.color ?? .gray.opacity(0.6))
                                    )
                                    .background(.white)
                                    .foregroundStyle(.white)
                                    .font(.system(size: 20))
                                    .clipShape(Circle())

                                if group.notes.count > 1 {
                                    Text("\(group.notes.count)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 12, y: -12)
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea(.all, edges: .top)
            .sheet(item: $sheetType) { type in
                switch type {
                case .singleNote(let note):
                    NavigationStack {
                        NoteDetailView(note: note, fromMap: true)
                    }
                case .notesList(let notes):
                    NotesListSheet(notes: notes)
                        .presentationDetents([.medium, .large])
                }
            }
            .onAppear {
                updateCameraPosition()
            }
            .onChange(of: locationManager.region) { _, newRegion in
                position = .region(newRegion)
            }

            locationButton
                .padding()
        }
    }

    @ViewBuilder
    private var locationButton: some View {
        let button = Button {
            locationManager.requestLocation()
        } label: {
            Image(systemName: "location")
                .font(.system(size: 20))
                .frame(width: 50, height: 50)
        }

        if #available(iOS 26.0, *) {
            button.glassEffect(.regular.interactive())
        } else {
            button.background(.regularMaterial, in: Circle())
        }
    }

    private func updateCameraPosition() {
        let region = locationManager.region
        position = .region(region)
    }

    // Group notes by coordinates (with tolerance)
    private var groupedNotes: [NoteGroup] {
        var groups: [NoteGroup] = []

        for note in notesStore.activeNotes where note.location != nil {
            if let index = groups.firstIndex(where: { areCoordinatesEqual($0.coordinate, note.coordinate) }) {
                groups[index].notes.append(note)
            } else {
                groups.append(NoteGroup(coordinate: note.coordinate, notes: [note]))
            }
        }

        return groups
    }

    private func areCoordinatesEqual(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Bool {
        let tolerance = 0.0001 // approximately 10 meters
        return abs(coord1.latitude - coord2.latitude) < tolerance &&
               abs(coord1.longitude - coord2.longitude) < tolerance
    }

    private func notesAt(coordinate: CLLocationCoordinate2D) -> [NoteModel] {
        notesStore.activeNotes.filter { areCoordinatesEqual($0.coordinate, coordinate) }
    }

    private func annotationTitle(for group: NoteGroup) -> String {
        if group.notes.count == 1 {
            return group.notes[0].title
        } else {
            return "\(group.notes.count) notes"
        }
    }

    private func handleAnnotationTap(for group: NoteGroup) {
        if group.notes.count == 1 {
            sheetType = .singleNote(group.notes[0])
        } else {
            sheetType = .notesList(group.notes)
        }
    }
}

// Helper structure for grouping notes
struct NoteGroup: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    var notes: [NoteModel]
}

// Sheet for selecting a note from multiple notes at the same location
struct NotesListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notes: [NoteModel]

    var sortedNotes: [NoteModel] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    var pinnedNotes: [NoteModel] {
        sortedNotes.filter { $0.pinned == true }
    }

    var unpinnedNotes: [NoteModel] {
        sortedNotes.filter { $0.pinned == false }
    }

    var body: some View {
        NavigationStack {
            List {
                if !pinnedNotes.isEmpty {
                    Section("pinned") {
                        ForEach(pinnedNotes) { note in
                            noteRow(note: note)
                        }
                    }
                }

                if !unpinnedNotes.isEmpty {
                    Section {
                        ForEach(unpinnedNotes) { note in
                            noteRow(note: note)
                        }
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("selectNote"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(note: NoteModel) -> some View {
        NavigationLink {
            NoteDetailView(note: note, fromMap: true)
        } label: {
            HStack {
                Circle()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(note.color ?? .gray.opacity(0.4))

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(note.createdAt.timeAgoDisplay())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if note.type == .drawing {
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                        }
                    }

                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }

                    if note.type == .text {
                        Text(note.isProtected ? "•••••••••••" : note.content)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    } else {
                        Text("drawingNote")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    if let reminder = note.reminder {
                        if reminder > Date() {
                            HStack {
                                Image(systemName: "bell")
                                    .foregroundStyle(Color.accentColor)

                                Text(reminder.formatted())
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MapView()
        .environment(LocationManager())
        .environment(NotesStore())
}
