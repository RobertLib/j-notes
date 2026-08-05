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

    /// Set when the user asks to be located, cleared once the resulting fix has
    /// moved the camera. Following every fix unconditionally yanked the map back
    /// to the user and undid whatever they had just panned to — and the note form
    /// requests a fix of its own, so it happened without them touching the map.
    @State private var isFollowingUserLocation = false

    /// Whether the camera has been framed for this map at all yet.
    ///
    /// `onAppear` fires every time the tab comes back, and framing there threw the
    /// user's pan away on each return — the very thing `isFollowingUserLocation`
    /// exists to prevent, arriving by the other door. The camera is `@State` and
    /// survives a tab switch, so there is nothing to redo.
    @State private var hasFramedCamera = false

    /// Raised when the locate button is pressed with location access refused.
    /// Asking again produces neither a prompt nor a fix, so without this the
    /// button was simply inert.
    @State private var isLocationDeniedPresented = false

    enum SheetType: Identifiable {
        case singleNote(NoteModel)

        /// Identified by the notes it lists rather than by the notes themselves:
        /// the sheet resolves each one out of the store as it draws, so an edit
        /// made while it is open shows up. It used to carry `[NoteModel]`, which
        /// froze every row at the moment the pin was tapped.
        case notesList([UUID])

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
                                    // Two layers, back to front. The white one is
                                    // load-bearing: a note's colour can carry an
                                    // alpha of its own, and without an opaque
                                    // ground the map shows straight through the
                                    // pin. It used to be a second `.background`
                                    // stacked on the first, which reads as a
                                    // leftover rather than as the deliberate
                                    // backdrop it is.
                                    .background {
                                        Circle().fill(.white)
                                        Circle().fill(group.pinColor)
                                    }
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
                case .notesList(let ids):
                    NotesListSheet(noteIds: ids)
                        .presentationDetents([.medium, .large])
                }
            }
            .onAppear {
                // Once only — see `hasFramedCamera`.
                guard !hasFramedCamera else { return }
                hasFramedCamera = true

                // With no stored fix to frame on there is nothing to lose by
                // following the first one, and a first launch would otherwise
                // leave the user staring at the default centre.
                let hasNoStoredFix = locationManager.lastLocation == nil
                isFollowingUserLocation = hasNoStoredFix
                updateCameraPosition()

                // And a fix has to be asked for, or there is none to follow. Only
                // the locate button and the new-note form used to ask, so opening
                // the map on a fresh install parked it on the default centre and
                // left it there — the permission prompt never even appeared.
                if hasNoStoredFix {
                    locationManager.requestLocation()
                }
            }
            .onChange(of: locationManager.latestFix) { _, fix in
                guard isFollowingUserLocation, fix != nil else { return }
                isFollowingUserLocation = false
                updateCameraPosition()
            }
            .alert("locationDenied", isPresented: $isLocationDeniedPresented) {
                Button("ok") {}
            } message: {
                Text("locationDeniedMessage")
            }

            locationButton
                .padding()
        }
    }

    @ViewBuilder
    private var locationButton: some View {
        let button = Button {
            // Refused access produces neither a prompt nor a fix, so the press
            // would otherwise land on nothing at all. `.notDetermined` is
            // deliberately not caught here: there the request *is* the feedback,
            // since it puts the system prompt on screen.
            guard !locationManager.isDenied else {
                isLocationDeniedPresented = true
                return
            }

            isFollowingUserLocation = true

            // Moved with the fix already on hand rather than only once a new one
            // lands. The stale one is good enough to frame a map with — that is
            // what `region` is kept for — and waiting meant the button did nothing
            // whenever Core Location had nothing newer to say, which standing
            // still is precisely the case of.
            if locationManager.lastLocation != nil {
                updateCameraPosition()
            }

            locationManager.requestLocation()
        } label: {
            Image(systemName: "location")
                .font(.system(size: 20))
                .frame(width: 50, height: 50)
        }
        .accessibilityLabel("myLocation")

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

    private var groupedNotes: [NoteGroup] {
        NoteClustering.groups(for: notesStore.activeNotes)
    }

    private func annotationTitle(for group: NoteGroup) -> String {
        if group.notes.count == 1 {
            return group.notes[0].displayTitle
        }

        // Plural form comes from Localizable.stringsdict so each language
        // applies its own rules.
        return String.localizedStringWithFormat(
            NSLocalizedString("notesCount", comment: "Number of notes at one map location"),
            group.notes.count
        )
    }

    private func handleAnnotationTap(for group: NoteGroup) {
        if group.notes.count == 1 {
            sheetType = .singleNote(group.notes[0])
        } else {
            sheetType = .notesList(group.notes.map(\.id))
        }
    }
}

// Helper structure for grouping notes
struct NoteGroup: Identifiable {
    let coordinate: CLLocationCoordinate2D
    var notes: [NoteModel]

    // Derived from the location rather than a fresh UUID: `groupedNotes` is a
    // computed property, so a generated id would change on every evaluation and
    // make ForEach tear down and rebuild every annotation on each redraw.
    var id: String {
        "\(coordinate.latitude),\(coordinate.longitude)"
    }

    /// The pin's fill. A group of notes has no single colour to speak for it, so
    /// it falls back to grey — the same grey a lone note without a colour gets.
    var pinColor: Color {
        guard notes.count == 1 else { return .gray.opacity(0.6) }

        return notes[0].color ?? .gray.opacity(0.6)
    }
}

/// Which notes share a pin on the map.
///
/// A type of its own rather than a computed property on `MapView`, so the rule can
/// be exercised at all — the same reason `NoteContentRule`, `ReminderFormState`
/// and `NoteLock` live outside the views they serve. It was the one non-trivial
/// algorithm in the app that no test could reach, and the grid below is an
/// optimisation whose whole claim is that it changes nothing about the result.
enum NoteClustering {
    /// How close two notes have to be to share a pin — roughly 10 metres.
    static let coordinateTolerance = 0.0001

    /// Whether two coordinates are near enough to be drawn as one pin.
    static func areCoordinatesEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < coordinateTolerance &&
            abs(lhs.longitude - rhs.longitude) < coordinateTolerance
    }

    /// The pins to draw for `notes`, in the order the notes arrive.
    ///
    /// Notes with no usable coordinate are left out entirely rather than gathered
    /// somewhere arbitrary — see `NoteModel.coordinate`.
    static func groups(for notes: [NoteModel]) -> [NoteGroup] {
        var groups: [NoteGroup] = []

        // Grid cell to the indices of the groups whose coordinate falls in it.
        // Comparing each note against every group made so far was quadratic, and
        // `Map`'s camera binding writes back as the user pans — so this ran on
        // every frame of a drag, over the whole library. A cell is exactly one
        // `coordinateTolerance` wide, so a group near enough to match can only
        // sit in the note's own cell or one of the eight around it, and those
        // are the only ones compared.
        var cells: [GridCell: [Int]] = [:]

        for note in notes {
            // `nil` for a note with no location, and for one whose stored array is
            // too short to be a coordinate — see `NoteModel.coordinate`.
            guard let coordinate = note.coordinate else { continue }

            // A coordinate outside the valid ranges cannot be put on a map
            // anyway, and one arriving from a hand-edited backup would otherwise
            // have to be snapped to a grid cell — which is arithmetic no bogus
            // value should be trusted with.
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }

            let cell = GridCell(coordinate)
            var match: Int?

            search: for latitudeStep in -1...1 {
                for longitudeStep in -1...1 {
                    let neighbour = GridCell(
                        latitude: cell.latitude + latitudeStep,
                        longitude: cell.longitude + longitudeStep
                    )

                    for candidate in cells[neighbour, default: []] {
                        if areCoordinatesEqual(groups[candidate].coordinate, coordinate) {
                            match = candidate
                            break search
                        }
                    }
                }
            }

            if let match {
                groups[match].notes.append(note)
            } else {
                cells[cell, default: []].append(groups.count)
                groups.append(NoteGroup(coordinate: coordinate, notes: [note]))
            }
        }

        return groups
    }

    /// A coordinate snapped to a `coordinateTolerance`-wide grid.
    ///
    /// Only an index into the notes being grouped — the pin itself still sits on a
    /// real note's coordinate, and two notes still share a pin only if they pass
    /// the same tolerance test as before. The cell just narrows down which pairs
    /// are worth testing at all.
    struct GridCell: Hashable {
        let latitude: Int
        let longitude: Int

        init(latitude: Int, longitude: Int) {
            self.latitude = latitude
            self.longitude = longitude
        }

        /// Safe to convert: the caller has already established that the coordinate
        /// is within the valid ranges, so neither axis can overflow `Int`.
        init(_ coordinate: CLLocationCoordinate2D) {
            latitude = Int((coordinate.latitude / coordinateTolerance).rounded(.down))
            longitude = Int((coordinate.longitude / coordinateTolerance).rounded(.down))
        }
    }
}

// Sheet for selecting a note from multiple notes at the same location
struct NotesListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NotesStore.self) private var notesStore

    /// The notes at this pin, by identity. Resolved against the store on every
    /// pass rather than held as models, so a note edited while the sheet is open
    /// redraws — and one deleted from underneath it drops out instead of lingering
    /// as a row that leads nowhere.
    let noteIds: [UUID]

    private var sortedNotes: [NoteModel] {
        let wanted = Set(noteIds)

        return notesStore.activeNotes
            .filter { wanted.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The sheet's two sections, in a single pass over the store. Same reason
    /// `NotesView` binds `noteSections`: read per section, each of the four reads
    /// below filtered and sorted the whole library again.
    private var sections: (pinned: [NoteModel], unpinned: [NoteModel]) {
        let sorted = sortedNotes

        return (
            pinned: sorted.filter(\.pinned),
            unpinned: sorted.filter { !$0.pinned }
        )
    }

    var body: some View {
        let sections = sections

        return NavigationStack {
            List {
                if !sections.pinned.isEmpty {
                    Section("pinned") {
                        ForEach(sections.pinned) { note in
                            noteRow(note: note)
                        }
                    }
                }

                if !sections.unpinned.isEmpty {
                    Section {
                        ForEach(sections.unpinned) { note in
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
                    .accessibilityLabel("close")
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(note: NoteModel) -> some View {
        NavigationLink {
            // Lazily — see `LazyNoteDetail`.
            LazyNoteDetail(note: note, fromMap: true)
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
                                // The body below renders "Drawing note" already.
                                .accessibilityHidden(true)
                        }
                    }

                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }

                    if note.type == .text {
                        Text(note.isProtected ? NoteModel.redactedBody : note.content)
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
                                    // A bare date says nothing about being a
                                    // reminder — see `NoteRowView`.
                                    .accessibilityLabel("reminder")

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
            // One element rather than the pieces it is drawn from — the same
            // treatment as the list's own rows. See `NoteRowView`.
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    MapView()
        .environment(LocationManager())
        .environment(NotesStore())
}
