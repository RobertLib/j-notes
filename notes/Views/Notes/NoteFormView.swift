//
//  NoteFormView.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import PencilKit
import SwiftUI

/// Where the reminder toggle starts out for a note, and the rule that stops an
/// untouched toggle from erasing the note's reminder date.
///
/// Split out of `NoteFormView` so it can be exercised directly — a view's
/// `@State` is not reachable from a test, and this is the rule that once let an
/// unrelated edit wipe the date the calendar view lists notes by.
struct ReminderFormState: Equatable {
    /// Where the toggle starts: on only while the reminder still has something
    /// left to fire.
    let isOnInitially: Bool

    /// `true` when the note arrived carrying a reminder that had already elapsed,
    /// so the toggle starts off for a reason that is not the user's doing.
    let startedElapsed: Bool

    init(reminder: Date?, now: Date = Date()) {
        let isPending = reminder.map { $0 > now } ?? false
        isOnInitially = isPending
        startedElapsed = reminder != nil && !isPending
    }

    /// Whether saving must leave the stored reminder date alone rather than clear
    /// it: the toggle is off, but only because the reminder had already elapsed
    /// and the user never moved it.
    func keepsStoredReminder(isReminderOn: Bool, didTouchToggle: Bool) -> Bool {
        !isReminderOn && startedElapsed && !didTouchToggle
    }
}

/// Whether a note has enough in it to be saved.
///
/// Split out of `NoteFormView` for the same reason as `ReminderFormState`: a
/// view's `@State` is not reachable from a test. It is also what lets the Save
/// button and `submit()` share one rule rather than two spellings of it — they
/// used to compare different things, and the button's copy is the one that left a
/// drawing whose whole point was its background photo permanently unsaveable.
enum NoteContentRule {
    static func hasContentToSave(
        type: NoteType,
        trimmedContent: String,
        hasStrokes: Bool,
        hasBackgroundImage: Bool
    ) -> Bool {
        switch type {
        case .text:
            return !trimmedContent.isEmpty
        case .drawing:
            // A background picture counts on its own. It is what such a note
            // renders — in the list, in the detail view and in the share sheet —
            // so requiring strokes on top of it greyed out the Save button with
            // nothing on screen saying why.
            return hasStrokes || hasBackgroundImage
        }
    }
}

struct NoteFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager
    @Environment(NotesStore.self) private var notesStore

    @FocusState private var isContentFocused: Bool
    @FocusState private var isTagFieldFocused: Bool

    let note: NoteModel?

    @State private var title: String
    @State private var content: String
    @State private var color: Color
    @State private var isColorOn: Bool
    @State private var reminder: Date
    @State private var isReminderOn: Bool
    @State private var noteType: NoteType
    @State private var tags: [String]
    @State private var newTagText: String = ""
    @State private var isProtected: Bool

    // Drawing states
    @State private var canvas = PKCanvasView()
    @State private var isDraw = true
    @State private var drawingColor: Color = .black
    @State private var penType: PKInkingTool.InkType = .pen
    @State private var penWidth: CGFloat = 3
    @State private var backgroundImage: UIImage? = nil

    @State private var isContentErrorPresented = false
    @State private var isReminderErrorPresented = false
    @State private var hasDrawingContent = false

    /// Guards against a second `submit()` slipping in while the first is still
    /// awaiting the notification centre — two taps used to create two notes.
    @State private var isSubmitting = false

    /// See `ReminderFormState`: a reminder that had already elapsed leaves the
    /// toggle off, and that must not be read as the user switching it off —
    /// saving would clear a date the calendar view lists notes by, so fixing a
    /// typo in the title silently erased it.
    private let reminderState: ReminderFormState

    /// Set once the user actually moves the reminder toggle. From then on the
    /// toggle speaks for them, so switching it off really does clear the date.
    @State private var didTouchReminderToggle = false

    /// The background picture the note arrived with, and the bytes it was stored
    /// as. Kept so an untouched picture can be written back verbatim instead of
    /// being re-encoded — `jpegData` on an image that was itself decoded from
    /// JPEG loses a little more every time, so editing a note's title repeatedly
    /// degraded the photo underneath its drawing.
    private let originalBackgroundImage: UIImage?
    private let originalBackgroundImageData: Data?

    /// Guards the one-shot canvas reset below. `onAppear` fires again whenever the
    /// form comes back on screen — after the camera closes, for instance — and
    /// resetting there would throw away strokes the user had already made.
    @State private var didPrepareCanvas = false

    init(note: NoteModel? = nil) {
        self.note = note

        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.content ?? "")
        // A concrete colour, not `.primary`: turning the toggle on without
        // touching the picker stored whatever `.primary` resolved to, which is
        // white in dark mode — an invisible dot in the list and an invisible pin
        // on the map, where the glyph is white too.
        _color = State(initialValue: note?.color ?? .blue)
        _isColorOn = State(initialValue: note?.color != nil)
        _reminder = State(initialValue: note?.reminder ?? Date())
        _noteType = State(initialValue: note?.type ?? .text)
        _tags = State(initialValue: note?.tags ?? [])
        _isProtected = State(initialValue: note?.isProtected ?? false)

        // A reminder that has already come and gone leaves the toggle off — there
        // is nothing left for it to fire — but the date itself is kept.
        let reminderState = ReminderFormState(reminder: note?.reminder)
        self.reminderState = reminderState
        _isReminderOn = State(initialValue: reminderState.isOnInitially)

        // Load existing drawing if available
        if let drawingData = note?.drawingData,
           let drawing = try? PKDrawing(data: drawingData) {
            let canvasView = PKCanvasView()
            canvasView.drawing = drawing
            _canvas = State(initialValue: canvasView)
            _hasDrawingContent = State(initialValue: !drawing.strokes.isEmpty)
        }

        // Load existing background image if available
        if let imageData = note?.backgroundImageData,
           let image = UIImage(data: imageData) {
            _backgroundImage = State(initialValue: image)
            originalBackgroundImage = image
            originalBackgroundImageData = imageData
        } else {
            originalBackgroundImage = nil
            originalBackgroundImageData = nil
        }
    }

    /// The bytes to store for the drawing's background picture.
    ///
    /// Re-encoded only when the picture has actually changed. `backgroundImage`
    /// still holds the very instance `init` decoded while the user has not
    /// replaced or cleared it, so identity is what distinguishes an untouched
    /// picture from a new one.
    private func backgroundImageDataToStore() -> Data? {
        guard let backgroundImage else { return nil }

        if let originalBackgroundImage,
           let originalBackgroundImageData,
           backgroundImage === originalBackgroundImage {
            return originalBackgroundImageData
        }

        return backgroundImage.jpegData(compressionQuality: 0.8)
    }

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces)

        // Compared through `NoteModel.tagsMatch` rather than by exact text, so
        // re-typing a tag the note already carries in another case is dropped as
        // the repeat it is. The store's `allTags` and the decoder's `uniqueTags`
        // apply the same rule, and they have to agree: a tag counted as new here
        // and as a duplicate there would appear on the note and never in the chip
        // row it is supposed to be filtered from.
        guard !tag.isEmpty, !tags.contains(where: { NoteModel.tagsMatch($0, tag) }) else {
            newTagText = ""
            return
        }

        tags.append(tag)
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    /// The note's title as it will be stored, with surrounding whitespace gone.
    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The note's body as it will be stored, and what decides whether it has a
    /// body at all.
    ///
    /// A body of nothing but spaces or newlines used to satisfy both the Save
    /// button's check and `submit`'s, because `isEmpty` is false for `" "` — so
    /// the note saved and then rendered as a blank row with nothing to open.
    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the note has enough in it to be saved. Bound to the Save button
    /// and re-checked in `submit()` through the same rule, so the two cannot
    /// disagree — see `NoteContentRule`.
    private var hasContentToSave: Bool {
        NoteContentRule.hasContentToSave(
            type: noteType,
            trimmedContent: trimmedContent,
            hasStrokes: hasDrawingContent,
            hasBackgroundImage: backgroundImage != nil
        )
    }

    private func submit() {
        // Checked before anything else: everything below runs while a first
        // submission may still be awaiting the notification centre, and two taps
        // used to create two notes.
        guard !isSubmitting else { return }

        // A tag typed but never committed — no Return, no "+" — is still a tag the
        // user asked for, and it used to be dropped on save without a word. Easy
        // to walk into precisely because the "+" sits right there looking like the
        // only way in. Done before the validation below so the tag survives even
        // when the save bounces off it.
        addTag()

        // The same rule the Save button is bound to, but reading the canvas
        // directly rather than through `hasDrawingContent` — that flag is only as
        // current as the last delegate callback.
        guard NoteContentRule.hasContentToSave(
            type: noteType,
            trimmedContent: trimmedContent,
            hasStrokes: !canvas.drawing.strokes.isEmpty,
            hasBackgroundImage: backgroundImage != nil
        ) else {
            isContentErrorPresented = true
            return
        }

        isSubmitting = true

        Task {
            // Comes off on every exit, including the reminder-alert path below,
            // which leaves the view on screen and hands dismissal to the alert's
            // button. Latching it on would strand the Save button disabled.
            defer { isSubmitting = false }

            // Remove old notifications if updating
            await NotificationManager.instance.removeNotifications(
                identifiers: note?.notificationIdentifiers
            )

            var notificationIdentifiers: [String] = []

            // A drawing note has no text body: its editor is never on screen, and
            // every view renders the picture instead. Text typed before the type
            // was switched over would otherwise be stored and then shown nowhere.
            let bodyText = noteType == .drawing ? "" : trimmedContent

            // Built from the note being written, so the wording matches what a
            // re-armed reminder (import, restore from trash) would produce.
            let pending = NoteModel(
                title: trimmedTitle,
                content: bodyText,
                type: noteType,
                isProtected: isProtected
            )

            // Whether the system actually accepted the request. The reminder
            // date is kept either way — it is user data the calendar view lists
            // notes by, and silently dropping it is how a denied notification
            // permission used to erase what the user had just typed. Only the
            // identifiers are withheld, so nothing points at a notification
            // that does not exist. Matches `NotesStore.rescheduleReminder`.
            var reminderScheduled = false

            if isReminderOn {
                // Awaited here, not just fired off when the toggle went on.
                // `scheduleNotification` counts `.notDetermined` as unschedulable,
                // and the request the toggle starts is not awaited by anything — so
                // a save landing in the gap before the prompt was answered reported
                // "reminder not set" for a permission the user was about to grant.
                // Asking again once the answer is in returns it without a second
                // prompt, so this is only a wait, never another interruption.
                _ = await NotificationManager.instance.requestAuthorization()

                if let notificationIdentifier =
                    await NotificationManager.instance.scheduleNotification(
                        title: pending.notificationTitle,
                        subtitle: pending.notificationSubtitle,
                        date: reminder
                    ) {
                    notificationIdentifiers.append(notificationIdentifier)
                    reminderScheduled = true
                }
            }

            // An elapsed reminder left the toggle off without the user ever
            // asking for it to be cleared, so the save passes neither reminder
            // field — `NotesStore.update` only clears on an explicit `false`.
            let keepsStoredReminder = reminderState.keepsStoredReminder(
                isReminderOn: isReminderOn,
                didTouchToggle: didTouchReminderToggle
            )

            // Get drawing data if it's a drawing note
            // Use Optional wrapping to explicitly send nil when data is cleared
            let drawingData: Data?? = noteType == .drawing ? Optional(canvas.drawing.dataRepresentation()) : nil
            let backgroundImageData: Data?? = noteType == .drawing ? Optional(backgroundImageDataToStore()) : nil

            // A canvas that has not been laid out yet measures zero, and storing
            // that is worse than storing nothing: no size at all falls back to the
            // drawing's own bounds and still renders, where a zero one used to be
            // taken at its word and left the note as a blank white box. Written as
            // `Optional(nil)` rather than omitted, so it still clears a stale size.
            let measuredCanvas = canvas.bounds.size
            let hasCanvasSize = measuredCanvas.width > 0 && measuredCanvas.height > 0
            let canvasSize: CGSize?? = noteType == .drawing
                ? Optional(hasCanvasSize ? measuredCanvas : nil)
                : nil

            if let note = note {
                notesStore.update(
                    note: note,
                    title: trimmedTitle,
                    content: bodyText,
                    type: noteType,
                    drawingData: drawingData,
                    drawingCanvasSize: canvasSize,
                    backgroundImageData: backgroundImageData,
                    color: color,
                    isColorOn: isColorOn,
                    reminder: keepsStoredReminder ? nil : reminder,
                    isReminderOn: keepsStoredReminder ? nil : isReminderOn,
                    notificationIdentifiers: notificationIdentifiers,
                    // Location is captured when the note is created and kept
                    // afterwards — editing text must not move the note's pin.
                    location: nil,
                    tags: tags,
                    isProtected: isProtected
                )
            } else {
                notesStore.add(
                    title: trimmedTitle,
                    content: bodyText,
                    type: noteType,
                    drawingData: drawingData ?? nil,
                    drawingCanvasSize: canvasSize ?? nil,
                    backgroundImageData: backgroundImageData ?? nil,
                    color: color,
                    isColorOn: isColorOn,
                    reminder: reminder,
                    isReminderOn: isReminderOn,
                    notificationIdentifiers: notificationIdentifiers,
                    // Only a fresh fix, so the note cannot inherit a coordinate
                    // from wherever the app was last opened.
                    location: locationManager.isAuthorized
                        ? locationManager.recentLocation
                        : nil,
                    tags: tags,
                    isProtected: isProtected
                )
            }

            // The note is saved either way; the user just needs to know the
            // reminder will not fire. Dismissal moves to the alert's button.
            if isReminderOn && !reminderScheduled {
                isReminderErrorPresented = true
                return
            }

            dismiss()
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("title", text: $title)

                // Note type picker
                Picker("noteType", selection: $noteType) {
                    Text("textNote").tag(NoteType.text)
                    Text("drawingNote").tag(NoteType.drawing)
                }
                .pickerStyle(.segmented)
                .disabled(note != nil) // Don't allow changing type when editing

                // Content based on type
                if noteType == .text {
                    UndoableTextEditor(
                        text: $content,
                        placeholder: String(localized: "content")
                    )
                    .frame(minHeight: 125)
                    .focused($isContentFocused)
                } else {
                    // Drawing canvas
                    DrawingCanvasView(
                        canvas: $canvas,
                        isDraw: $isDraw,
                        color: $drawingColor,
                        type: $penType,
                        penWidth: $penWidth,
                        backgroundImage: $backgroundImage,
                        onDrawingChanged: {
                            hasDrawingContent = !canvas.drawing.strokes.isEmpty
                        }
                    )
                    .frame(height: 400)
                    .background(Color.white)
                    .cornerRadius(8)
                }

                Toggle("color", isOn: $isColorOn.animation())

                if isColorOn {
                    // The visible label is deliberately empty — the toggle above
                    // already names the row — but VoiceOver still needs one, or
                    // the control announces itself as nothing at all.
                    ColorPicker("", selection: $color)
                        .accessibilityLabel("color")
                }

                Toggle("reminder", isOn: $isReminderOn.animation())
                    .onChange(of: isReminderOn) { oldValue, newValue in
                        didTouchReminderToggle = true

                        if newValue {
                            // Default to 5 minutes from now
                            let defaultReminderInterval: TimeInterval = 5 * 60
                            reminder = Date().addingTimeInterval(defaultReminderInterval)

                            Task {
                                await NotificationManager.instance.requestAuthorization()
                            }
                        }
                    }

                if isReminderOn {
                    DatePicker("", selection: $reminder, in: Date()...)
                        .accessibilityLabel("reminder")
                }

                Toggle("protected", isOn: $isProtected.animation())

                // Existing tags as removable chips
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                TagChip(tag: tag) { removeTag(tag) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Tag input row
                HStack {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    TextField("addTag", text: $newTagText)
                        .focused($isTagFieldFocused)
                        .autocorrectionDisabled()
                        .onSubmit { addTag() }
                        // Submit actions accumulate outwards, so without this
                        // the form's own `.onSubmit` also fired and Return in
                        // the tag field saved and closed the whole note.
                        .submitScope()
                    if !newTagText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: addTag) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }


                Color.clear
                    .frame(height: 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("save") {
                    submit()
                }
                .disabled(isSubmitting || !hasContentToSave)
            }
        }
        .alert(
            "contentError",
            isPresented: $isContentErrorPresented
        ) {}
        .alert(
            "reminderNotScheduled",
            isPresented: $isReminderErrorPresented
        ) {
            Button("ok") { dismiss() }
        } message: {
            Text("reminderNotScheduledMessage")
        }
        // A locked note's body is on screen here in an editable text view, so it
        // needs the same cover the detail view gets before iOS snapshots the app
        // for its switcher. Reaching this form means the note was already
        // unlocked, so there is nothing to keep revealed conditionally.
        .privacyCover(isProtected: isProtected)
        .onAppear() {
            // Both of the following are for a new note only. A note's location is
            // captured once, when it is created — an edit passes `location: nil`
            // on purpose, so as not to move the note's pin — which means a fix
            // asked for while editing could never be used by anything.
            guard note == nil else { return }

            locationManager.requestLocation()

            // Reset the canvas — once, on the first appearance. See
            // `didPrepareCanvas`.
            if !didPrepareCanvas {
                canvas.drawing = PKDrawing()
                hasDrawingContent = false
                didPrepareCanvas = true
            }
        }
        .onSubmit {
            submit()
        }
    }
}

/// A `NoteFormView` that is not built until the link to it is actually followed.
///
/// `NavigationLink`'s destination is an ordinary `@ViewBuilder` argument rather
/// than an autoclosure, so `NavigationLink { NoteFormView(note: note) }` runs the
/// form's initialiser on every pass through the *linking* view's body — once per
/// keystroke in the search field for the list's "+" button, and on every change
/// to the store for the detail view's edit button. That initialiser allocates a
/// `PKCanvasView` and decodes the note's `PKDrawing`, so it is real work, paid
/// repeatedly for a screen nobody has opened yet. Building inside `body` hands
/// the timing to SwiftUI, which asks only once the destination is on screen.
///
/// The same shape of fix as `NotesView.startExport()`, which pulled a full
/// re-encode of every note out of `body` for the same reason.
struct LazyNoteForm: View {
    /// The note to edit, or `nil` to compose a new one.
    let note: NoteModel?

    /// Navigation title for the pushed form — the callers' "New note" / "Edit
    /// note", applied here so the link site stays a single expression.
    let title: LocalizedStringKey

    var body: some View {
        NoteFormView(note: note).navigationTitle(title)
    }
}

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.15))
        // `.primary`, not the accent itself. Orange text on a wash of the same
        // orange comes to about 1.9:1 — the tint reads as a pill, but the tag
        // inside it was the least legible text in the app. This is also what the
        // read-only tag pills in `NoteRowView` and `NoteDetailView` already do, so
        // the same tag now looks the same wherever it appears.
        .foregroundStyle(.primary)
        .clipShape(Capsule())
    }
}

#Preview {
    NoteFormView()
        .environment(LocationManager())
        .environment(NotesStore())
}
