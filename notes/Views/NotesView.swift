//
//  NotesView.swift
//  notes
//
//  Created by Robert Libšanský on 17.07.2022.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Somewhere the list can send the user.
///
/// A value rather than a destination owned by the link, for two reasons. The link
/// to the trash only exists while there is something in the trash — and a
/// destination owned by a link goes when the link does. So emptying the trash from
/// inside it (restoring the last note, or deleting it for good) tore the screen out
/// from under the user instead of letting it say the trash is now empty, and
/// `DeletedNotesView`'s empty state could never be seen.
///
/// And it is what lets one list serve both containers `NotesView` puts it in: a
/// stack pushes the value, a split view selects it. Neither knows about the other.
enum NotesRoute: Hashable {
    case note(UUID)
    case trash
}

/// Which tag the list is narrowed by, and what becomes of that choice when the
/// tags themselves change underneath it.
///
/// Split out of `NotesView` so the rule can be exercised at all — a view's
/// `@State` is not reachable from a test, the same reason `NoteContentRule`,
/// `ReminderFormState` and `NoteLock` live outside the views they serve.
enum TagFilter {
    /// Whether this chip is the one currently filtering the list.
    ///
    /// Matched through `NoteModel.tagsMatch`, not `==`, so the chip stays
    /// highlighted when the surviving spelling of a tag changes — `allTags` keeps
    /// one of "Práce" and "práce", and which one it keeps depends on what else is
    /// in the library.
    static func isSelected(_ tag: String, selected: String?) -> Bool {
        guard let selected else { return false }

        return NoteModel.tagsMatch(tag, selected)
    }

    /// Whether a note belongs in a list narrowed to `selected`. No selection
    /// narrows nothing.
    static func matches(_ note: NoteModel, selected: String?) -> Bool {
        guard let selected else { return true }

        return note.tags.contains { NoteModel.tagsMatch($0, selected) }
    }

    /// The filter that survives a change to the tags on offer: the same tag as it
    /// is now spelled, or `nil` once no note carries it any more.
    ///
    /// The selection is view state and the chip row is drawn from the store, so
    /// the two used to part company the moment the last note carrying the selected
    /// tag was deleted or edited. The chip disappeared; the filter did not. The
    /// list then said "no notes match your search" for a filter nothing on screen
    /// was showing, with no chip highlighted — not even "All", since a selection
    /// was still in force.
    ///
    /// Where it was the *only* tag in the library the whole chip row went with it,
    /// which left no way back at all: an empty list, no explanation, and the one
    /// control that would have cleared the filter gone along with the tag. The
    /// selection is `@State`, so only relaunching the app recovered it.
    ///
    /// Re-anchored onto the spelling that is actually on the screen rather than
    /// simply kept, so a filter set on "Práce" goes on working once the last note
    /// spelling it that way is gone and "práce" is what the row now shows.
    static func surviving(_ selected: String?, in tags: [String]) -> String? {
        guard let selected else { return nil }

        return tags.first { NoteModel.tagsMatch($0, selected) }
    }
}

struct NotesView: View {
    @Environment(NotesStore.self) private var notesStore
    @Environment(NotificationRouter.self) private var notificationRouter

    /// Which container the list gets — see `body`.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @AppStorage("sortOption") private var sortOption: NoteSortOption = .dateNewest
    @AppStorage("displayStyle") private var displayStyle: NoteDisplayStyle = .standard
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var showImportOptions = false
    @State private var showNewNoteSheet = false
    @State private var importData: Data?
    @State private var selectedTag: String?

    /// What the stack has pushed. Compact width only.
    @State private var path: [NotesRoute] = []

    /// What the split view's detail column is showing. Regular width only.
    @State private var selection: NotesRoute?

    /// The encoded backup, held only between the user asking for an export and
    /// the sheet closing. See `startExport()`.
    @State private var exportDocument: NotesDocument?
    @State private var exportFilename: String?

    var searchedNotes: [NoteModel] {
        // The match rule itself lives on `NoteModel` so it can be tested — see
        // `NoteModel.matches(query:)`, which is also what keeps a locked note's
        // body out of the results.
        let filtered = notesStore.activeNotes.filter({ note in
            // The tag rule lives on `TagFilter` so the list, the chip row and the
            // recovery below all read the same one — and so that a tag matches
            // whatever case it was typed in, as the search field already did.
            note.matches(query: searchText) && TagFilter.matches(note, selected: selectedTag)
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

    /// The searched list split into the two sections the list renders, in a single
    /// pass over it.
    ///
    /// `body` binds this once. It used to read `searchedNotes` five times per pass
    /// — directly for the empty state, and twice through each of two derived
    /// properties — so every keystroke in the search field filtered and sorted the
    /// whole library five times over.
    private var noteSections: (pinned: [NoteModel], unpinned: [NoteModel], isEmpty: Bool) {
        let searched = searchedNotes

        return (
            pinned: searched.filter(\.pinned),
            unpinned: searched.filter { !$0.pinned },
            isEmpty: searched.isEmpty
        )
    }

    /// The glyph beside each entry of the sort menu.
    ///
    /// One per option, all four distinct. The two title options both drew
    /// `textformat.abc`, so "Title (A-Z)" and "Title (Z-A)" sat in the menu as the
    /// same icon twice — the glyph said "sort by text" and left the direction, the
    /// only thing separating the two rows, to the label alone. The date pair was
    /// distinguished all along.
    ///
    /// `text.line.first`/`text.line.last` are the system's own ascending and
    /// descending sort symbols, so the direction reads the same way here as it does
    /// everywhere else in iOS. Both date back to iOS 16, well under this app's 18.0
    /// deployment target.
    private func sortIcon(for option: NoteSortOption) -> String {
        switch option {
        case .dateNewest:
            return "calendar.badge.clock"
        case .dateOldest:
            return "calendar"
        case .titleAZ:
            return "text.line.first.and.arrowtriangle.forward"
        case .titleZA:
            return "text.line.last.and.arrowtriangle.forward"
        }
    }

    /// Whether a search or a tag is narrowing the list. Decides which empty
    /// state to show: "you have no notes" is a lie when the user has plenty and
    /// merely searched for something that is not among them.
    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || selectedTag != nil
    }

    /// Encodes the backup once, when the user actually asks for one.
    ///
    /// `fileExporter`'s `document:` is an ordinary argument rather than an
    /// autoclosure, so building it inline ran a pretty-printed encode of every
    /// note — drawing strokes and background photos base64'd along with them —
    /// on every pass through `body`. That is once per keystroke in the search
    /// field, several megabytes allocated each time as soon as the file holds a
    /// few drawings. It also logged an export that never happened, and on a
    /// failed encode wrote `saveError` from inside the view update.
    private func startExport() async {
        guard let data = await notesStore.exportNotes() else {
            // `exportNotes` has already set `saveError`, which raises the alert.
            return
        }

        exportDocument = NotesDocument(data: data)
        exportFilename = NotesDocument.defaultFilename(for: Date())
        showExportSheet = true
    }

    /// Sends the user to `route`, in whichever container the list is currently in.
    ///
    /// The rows do this for themselves through `NavigationLink(value:)`, which both
    /// containers understand. This is for the callers that cannot: a toolbar button
    /// has no row selection to set, and the router names a note from outside the
    /// view entirely.
    private func open(_ route: NotesRoute) {
        if horizontalSizeClass == .regular {
            selection = route
        } else {
            // Replaces the stack rather than pushing onto it. A reminder tapped
            // while the user is three screens deep asks for that note, not for it
            // to be stacked on top of whatever they had open.
            path = [route]
        }
    }

    /// Lets go of the note the router asked for, once it is on screen — or once the
    /// user has moved on, which spends the request just as thoroughly.
    ///
    /// Held on to, the value would stop being a *change*: a second reminder naming
    /// the same note leaves `noteToOpen` exactly as it was, so `onChange` does not
    /// fire and nothing moves. The stack used to get this for free, because
    /// `navigationDestination(item:)` writes `nil` back when its screen is popped —
    /// and the split view, which has nothing to pop, never would have.
    ///
    /// Deliberately not done in the same breath as `open`: `ContentView` watches
    /// the same value to bring the list's tab forward, and clearing it there and
    /// then would race that. Both handlers see the arrival; this runs a view update
    /// later, off the back of the navigation it caused.
    private func clearRoutedNote() {
        if notificationRouter.noteToOpen != nil {
            notificationRouter.noteToOpen = nil
        }
    }

    /// What a route puts on screen. One spelling for both containers — the stack
    /// pushes it, the split view's detail column shows it.
    ///
    /// Serving both is why the note goes through `LazyNoteDetail`. The stack calls
    /// this from `navigationDestination`, whose closure is stored and run only once
    /// a route is actually pushed; the split view's `detail:` is an ordinary
    /// `@ViewBuilder` argument, so it runs on *every* pass through `body` — once per
    /// keystroke in the search field, and again on any change to the store. Building
    /// `NoteDetailView` there ran its initialiser each time, and that initialiser
    /// asks `LocalAuthentication` whether the device can authenticate anybody, which
    /// is a cross-process query. The same cost `LazyNoteDetail` was written to keep
    /// out of the list's rows, arriving by the other door.
    @ViewBuilder
    private func destination(for route: NotesRoute) -> some View {
        switch route {
        case .note(let id):
            // Resolved here rather than carried by whatever named it, so the note
            // arrives in whatever state it is in now — and a protected one still
            // opens locked, because `NoteDetailView` decides that from the note it
            // is handed.
            if let note = notesStore.notes.first(where: { $0.id == id }) {
                LazyNoteDetail(note: note)
            } else {
                Text("noteNotFound")
                    .foregroundStyle(.secondary)
            }

        case .trash:
            DeletedNotesView()
        }
    }

    var body: some View {
        // Bound once rather than read per section — see `noteSections`.
        let sections = noteSections

        // Same reason: the chip row asked for this twice, once to decide whether
        // to render at all and once to iterate, and each read built a `Set` over
        // every active note's tags and sorted it.
        let tags = notesStore.allTags

        // Two containers, one list. An iPad at full width has room to show a note
        // beside the list it was picked from, and a stack there spends seven
        // hundred points of screen on a column of text down the middle. Compact
        // width — every iPhone, and an iPad in Slide Over — keeps the stack, since
        // a split view collapsed into a single column is a stack with extra
        // machinery bolted to it.
        //
        // Only the container differs. The list, its toolbar, its search field and
        // its sheets are all `notesList`, and its rows are value-based
        // `NavigationLink`s either way — see `NotesRoute`. Two spellings of the
        // list is how a swipe action or a filter comes to exist in one size class
        // and not in the other.
        //
        // The `Group` is for the handler below rather than for the layout, which
        // it does not affect. The two branches are separate view identities, so
        // changing size class does not update the old container — it removes it,
        // and everything hung off it goes too. The carry-across used to be written
        // inside `notesList`, which is to say inside both branches: it was attached
        // to precisely the view the change destroys, and a modifier being torn down
        // is not one that reliably gets a change callback first. Out here it hangs
        // off a position that survives the swap.
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    notesList(sections: sections, tags: tags, detailSelection: $selection)
                } detail: {
                    // A stack of its own, so the column can push further: the edit
                    // form, and the note behind a row of the trash.
                    NavigationStack {
                        if let selection {
                            destination(for: selection)
                        } else {
                            ContentUnavailableView("selectNote", systemImage: "note.text")
                        }
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    notesList(sections: sections, tags: tags, detailSelection: nil)
                        .navigationDestination(for: NotesRoute.self) { route in
                            destination(for: route)
                        }
                }
            }
        }
        // Rotating an iPad, or dragging the app in and out of Split View, swaps
        // the container underneath the user. Carried across rather than dropped:
        // the note being read has no reason to close because the window changed
        // shape. There is somewhere to carry it *to* because `path` and `selection`
        // both live on this view, which is not the thing being rebuilt — only the
        // container inside it is.
        .onChange(of: horizontalSizeClass) { _, newValue in
            if newValue == .regular {
                if let last = path.last { selection = last }
                path = []
            } else {
                if let selection { path = [selection] }
                selection = nil
            }
        }
    }

    /// The list, and everything hung off it. Identical in both containers — see
    /// `body`.
    ///
    /// - Parameter detailSelection: the split view's detail selection, or `nil` in
    ///   a stack, where a row's value is pushed rather than selected. It doubles as
    ///   which container this is, since only a split view has a selection to bind.
    @ViewBuilder
    private func notesList(
        sections: (pinned: [NoteModel], unpinned: [NoteModel], isEmpty: Bool),
        tags: [String],
        detailSelection: Binding<NotesRoute?>?
    ) -> some View {
        List(selection: detailSelection) {
            if !tags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TagFilterChip(
                                label: String(localized: "allTags"),
                                isSelected: selectedTag == nil
                            ) {
                                withAnimation { selectedTag = nil }
                            }
                            ForEach(tags, id: \.self) { tag in
                                let isSelected = TagFilter.isSelected(
                                    tag,
                                    selected: selectedTag
                                )

                                TagFilterChip(label: tag, isSelected: isSelected) {
                                    withAnimation {
                                        selectedTag = isSelected ? nil : tag
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .listSectionSpacing(8)
            }

            // A row rather than an overlay on top of the list: the
            // message used to be stacked over the tag chips, covering the
            // one control that would have cleared the filter that emptied
            // the list in the first place.
            if sections.isEmpty {
                Section {
                    // A semantic font, not a fixed 20pt: this is body copy the
                    // user reads, so it has to follow Dynamic Type. The fixed
                    // sizes left in the app are all glyphs inside frames of a
                    // fixed size, where growing the symbol only clips it.
                    Text(isFiltering ? "noSearchResults" : "noNotes")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !sections.pinned.isEmpty {
                Section("pinned") {
                    NoteListView(notes: sections.pinned, displayStyle: displayStyle)
                }
            }

            if !sections.unpinned.isEmpty {
                Section {
                    NoteListView(notes: sections.unpinned, displayStyle: displayStyle)
                }
            }
        }
        .navigationTitle("notes")
        // Where a tapped reminder or a followed widget link lands. `initial`
        // covers the cold launch, where the router resolved the request before
        // this view existed.
        .onChange(of: notificationRouter.noteToOpen, initial: true) { _, id in
            guard let id else { return }

            open(.note(id))
        }
        // Both of these spend the router's request — see `clearRoutedNote`.
        // Whichever container is in force, only one of the two ever moves.
        .onChange(of: path) { _, _ in
            clearRoutedNote()
        }
        .onChange(of: selection) { _, _ in
            clearRoutedNote()
        }
        .toolbar {
            // Compact only. `EditButton` is what drives the list's `onDelete`,
            // and the split view's list already carries a selection binding —
            // edit mode there puts a selection circle beside every row and
            // turns the button into something else entirely. Swiping a row
            // still deletes it in both.
            if detailSelection == nil {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }

            // A slot of its own on iPhone, where the bar is the full width of the
            // screen and has room for it. The split view's sidebar is around 300
            // points wide and already carries the title, the options menu, the "+"
            // and the system's own column toggle — one more item and the title
            // truncates to "J-…". So in the split view it moves into the menu
            // below, alongside the other things that act on the library as a whole.
            if notesStore.hasDeletedNotes && detailSelection == nil {
                ToolbarItem(placement: .topBarLeading) {
                    // A button rather than a `NavigationLink(value:)`: outside
                    // the list there is nothing for a value-based link to
                    // select, and in the split view the list's own selection is
                    // what drives the detail column. `open` names the route for
                    // both containers.
                    Button {
                        open(.trash)
                    } label: {
                        Text("deleted")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if notesStore.hasDeletedNotes && detailSelection != nil {
                        Section {
                            Button {
                                open(.trash)
                            } label: {
                                Label("deleted", systemImage: "trash")
                            }
                        }
                    }

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
                            // The encode runs off the main actor now, so the
                            // menu closes rather than waiting on it.
                            Task { await startExport() }
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
                .accessibilityLabel("menuOptions")
            }

            ToolbarItem(placement: .topBarTrailing) {
                if let detailSelection {
                    // A sheet in the split view, because the form cannot be the
                    // detail column's root: it calls `dismiss()` once the note
                    // is written, and `dismiss()` at the root of a stack has
                    // nothing to pop — the form would sit there over a note
                    // that had already been saved. Pushing it into the sidebar
                    // instead would compose a note in a 320-point column with
                    // the list it belongs to hidden behind it.
                    Button {
                        // Nothing is selected yet, so the column is not left
                        // showing a note the user is no longer looking at.
                        detailSelection.wrappedValue = nil
                        showNewNoteSheet = true
                    } label: {
                        Image(systemName: "plus").font(.system(size: 20))
                    }
                    .accessibilityLabel("newNote")
                } else {
                    NavigationLink {
                        LazyNoteForm(note: nil, title: "newNote")
                    } label: {
                        Image(systemName: "plus").font(.system(size: 20))
                    }
                    .accessibilityLabel("newNote")
                }
            }
        }
        .sheet(isPresented: $showNewNoteSheet) {
            // Its own stack: the form's Save button is a toolbar item, which
            // needs a navigation bar to sit in.
            NavigationStack {
                LazyNoteForm(note: nil, title: "newNote")
            }
        }
        // Pinned open in the sidebar, left to the system on iPhone. `.automatic`
        // hides the field until the list is pulled down, which is right for a
        // full-width bar the user scrolls anyway — and wrong for a column that is
        // the app's whole index, where a search field nobody can see reads as a
        // search field that does not exist.
        .searchable(
            text: $searchText,
            placement: detailSelection == nil
                ? .automatic
                : .navigationBarDrawer(displayMode: .always)
        )
        // The filter cannot outlive the tag it names — see
        // `TagFilter.surviving`. Without this, deleting the last note carrying
        // the selected tag left the list filtered by a chip that was no longer
        // on screen, and where it was the only tag there was nothing left to
        // clear it with short of relaunching.
        .onChange(of: tags) { _, newTags in
            selectedTag = TagFilter.surviving(selectedTag, in: newTags)
        }
        .fileExporter(
            isPresented: $showExportSheet,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            // Megabytes for a file with drawings in it — released as soon as
            // the sheet is done rather than held until the next export.
            exportDocument = nil

            switch result {
            case .success:
                Log.files.info("Export successful")
            case .failure(let error):
                Log.files.error("Export failed: \(error.localizedDescription)")
                notesStore.setError(String(localized: "errorExportFailed \(error.localizedDescription)"))
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

                // Read by the store, which does it off the main actor and holds
                // the file's security scope across the whole read — see
                // `NotesStore.readBackup`. It sets its own error message, so a
                // failure here just means there is nothing to offer.
                Task {
                    guard let data = await notesStore.readBackup(at: url) else {
                        return
                    }

                    importData = data
                    showImportOptions = true
                }
            case .failure(let error):
                Log.files.error("Import failed: \(error.localizedDescription)")
                notesStore.setError(String(localized: "errorImportFailed \(error.localizedDescription)"))
            }
        }
        .alert("importNotes", isPresented: $showImportOptions) {
            Button("cancel", role: .cancel) {
                importData = nil
            }
            // The decode runs off the main actor, so both of these hand the work
            // to a task rather than holding the alert's dismissal on it.
            Button("mergeNotes") {
                if let data = importData {
                    Task {
                        _ = await notesStore.importNotes(
                            from: data,
                            replaceExisting: false
                        )
                    }
                }
                importData = nil
            }
            Button("replaceNotes", role: .destructive) {
                if let data = importData {
                    Task {
                        _ = await notesStore.importNotes(
                            from: data,
                            replaceExisting: true
                        )
                    }
                }
                importData = nil
            }
        } message: {
            Text("importOptionsMessage")
        }
    }
}

struct TagFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                // Black on the accent fill, not white. The app's accent is
                // `systemOrange`, which is a light colour in both appearances —
                // white on it comes to about 2.2:1, well under the 4.5:1 body text
                // needs, where black is around 9:1. Fixed rather than `.primary`
                // for the same reason: the fill does not follow the appearance, so
                // neither should what sits on it.
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Document for file export
struct NotesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    /// What the export sheet offers to call the backup.
    ///
    /// ISO-8601 rather than the locale's own numeric date, which is what this used
    /// to be. `en_US` renders that as `8/6/2026` — and a slash is a path separator,
    /// so the name handed to the exporter could not survive as one; `cs_CZ` gives
    /// `6. 8. 2026`, spaces and all. The date here names a file rather than being
    /// read by anyone, so it wants the one spelling that is the same everywhere and
    /// sorts correctly besides.
    ///
    /// Split out as a static so the shape can be tested — a view's private helper
    /// is not reachable from a test, the same reason `ReminderFormState` lives on
    /// its own.
    static func defaultFilename(for date: Date) -> String {
        let day = date.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .dateSeparator(.dash)
        )

        return "j-notes-backup-\(day)"
    }

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
        .environment(NotesStore())
        .environment(NotificationRouter.shared)
}
