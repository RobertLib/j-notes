//
//  NoteDetailView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import CoreTransferable
import LocalAuthentication
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

struct ZoomableDrawingView: View {
    let image: UIImage
    let canvasSize: CGSize

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// How far the picture may be dragged on each axis before its own edge would
    /// come inside the frame: half of whatever the scaled picture overflows by, and
    /// zero when it does not overflow at all.
    ///
    /// The drag used to accumulate with no limit, so a zoomed drawing could be
    /// pushed clean out of the frame — leaving a blank white box, with nothing on
    /// screen saying the picture was still there just off the side of it. The way
    /// back was the double tap, which is not a gesture anything advertises.
    ///
    /// A pure function of the two sizes so the rule can be exercised at all — a
    /// view's gesture is not reachable from a test, the same reason `NoteLock`,
    /// `NoteContentRule` and `ReminderFormState` live outside the views they serve.
    static func panLimit(scaledSize: CGSize, in frame: CGSize) -> CGSize {
        CGSize(
            width: max(0, (scaledSize.width - frame.width) / 2),
            height: max(0, (scaledSize.height - frame.height) / 2)
        )
    }

    /// `offset` brought back inside `panLimit`.
    static func clamped(_ offset: CGSize, scaledSize: CGSize, in frame: CGSize) -> CGSize {
        let limit = panLimit(scaledSize: scaledSize, in: frame)

        return CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }

    /// `clamped` against the picture as it is drawn right now — the canvas at the
    /// current `scale`, which is what `scaleEffect` below renders.
    private func clamp(_ offset: CGSize, in frame: CGSize) -> CGSize {
        Self.clamped(
            offset,
            scaledSize: CGSize(
                width: canvasSize.width * scale,
                height: canvasSize.height * scale
            ),
            in: frame
        )
    }

    var body: some View {
        // The reader is here for its sizing behaviour, so the zoomed image gets the
        // whole space to move around in rather than collapsing to the frame below.
        // Its proxy used to be discarded; it is what the pan is held inside — see
        // `panLimit`.
        GeometryReader { proxy in
            let frame = proxy.size

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let delta = value.magnification / lastScale
                            lastScale = value.magnification
                            scale = min(max(scale * delta, 1), 5)

                            // Zooming out shrinks the room there is to pan, so an
                            // offset that was legal at the old scale can be past
                            // the edge at the new one. Re-clamped as the pinch
                            // goes, rather than left for the next drag to fix.
                            offset = clamp(offset, in: frame)
                            lastOffset = offset
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale < 1 {
                                withAnimation {
                                    scale = 1
                                    offset = .zero
                                }
                            }
                            lastOffset = offset
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1 {
                                offset = clamp(
                                    CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    ),
                                    in: frame
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Whether a protected note has to be unlocked before its text is shown.
///
/// A type of its own so the rule can be exercised at all — a view's `@State` is
/// not reachable from a test, the same reason `ReminderFormState` and
/// `NoteContentRule` live outside the form.
enum NoteLock {
    /// `false` for an unprotected note and, deliberately, for a protected one on
    /// a device that can authenticate nobody.
    ///
    /// With no passcode enrolled `evaluatePolicy` fails with `.passcodeNotSet`
    /// whichever policy it is handed, biometry included — so the lock was a
    /// one-way door. The note could not be opened, and therefore could not be
    /// edited or un-protected either, since both of those live in the toolbar
    /// behind it; the only thing left to do with it was delete it from the list
    /// unread.
    ///
    /// There is also nothing on the far side of that door left to protect. A
    /// device with no passcode has no `.completeFileProtection` behind it either,
    /// so the note's text is already readable to whoever is holding it — the lock
    /// was keeping out only its owner.
    static func requiresAuthentication(isProtected: Bool, canAuthenticate: Bool) -> Bool {
        isProtected && canAuthenticate
    }

    /// Whether this device can evaluate any authentication policy at all.
    ///
    /// `.deviceOwnerAuthentication` is the widest one there is — biometry where it
    /// is enrolled, the passcode otherwise — so a `false` here means there is no
    /// way in by any route.
    static func deviceCanAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// The glyph for the way in this device actually offers: Face ID, Touch ID, or
    /// a plain padlock where no biometry is enrolled and the passcode is all there
    /// is.
    ///
    /// Lives here, beside `deviceCanAuthenticate()`, rather than as a `static let`
    /// on the view that draws it — which is what it was, and so one answer for the
    /// whole life of the process. Enrolling Face ID means a trip to Settings, which
    /// backgrounds the app and rebuilds the detail view on the way back:
    /// `deviceCanAuthenticate()` picks that change up, because it is read per push,
    /// and the icon beside it did not. The button went on offering an open padlock
    /// on a device that now has Face ID, until the app was relaunched. Two answers
    /// to the same question, one of them stale — so they are asked together, in
    /// `NoteDetailView.init`.
    static func biometryIcon() -> String {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {
            return "lock.open"
        }

        return context.biometryType == .faceID ? "faceid" : "touchid"
    }
}

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NotesStore.self) private var notesStore

    let noteId: UUID
    let fromMap: Bool

    /// Whether this device can authenticate anybody — see `NoteLock`. Read once,
    /// when the screen is pushed: enrolling a passcode means a trip to Settings,
    /// which backgrounds the app and rebuilds this view on the way back.
    private let canAuthenticate: Bool

    /// Which glyph the unlock button carries — see `NoteLock.biometryIcon()`. Read
    /// here, in the same breath as `canAuthenticate`, so both answers are as fresh
    /// as this push and cannot come to disagree about what the device can do.
    private let biometryIcon: String

    @State private var isAuthenticated: Bool
    @State private var isDeleteNoteConfirmPresented = false
    @State private var isPermanentDeleteConfirmPresented = false
    @State private var authError: String?

    init(note: NoteModel, fromMap: Bool = false) {
        self.noteId = note.id
        self.fromMap = fromMap

        let canAuthenticate = NoteLock.deviceCanAuthenticate()
        self.canAuthenticate = canAuthenticate
        self.biometryIcon = NoteLock.biometryIcon()
        _isAuthenticated = State(
            initialValue: !NoteLock.requiresAuthentication(
                isProtected: note.isProtected,
                canAuthenticate: canAuthenticate
            )
        )
    }

    private var currentNote: NoteModel? {
        notesStore.notes.first { $0.id == noteId }
    }

    /// Whether the note as it stands *now* has to be unlocked. Read from the
    /// store rather than latched in `init`, because the note can be protected
    /// from the edit form while this screen is sitting behind it.
    private var locksCurrentNote: Bool {
        NoteLock.requiresAuthentication(
            isProtected: currentNote?.isProtected == true,
            canAuthenticate: canAuthenticate
        )
    }

    private func authenticate() {
        authError = nil
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        context.evaluatePolicy(policy, localizedReason: String(localized: "authenticateReason")) { success, authErr in
            Task { @MainActor in
                if success {
                    isAuthenticated = true
                    authError = nil
                } else if let laError = authErr as? LAError,
                          laError.code != .userCancel,
                          laError.code != .appCancel,
                          laError.code != .systemCancel {
                    authError = laError.localizedDescription
                }
            }
        }
    }

    var body: some View {
        Group {
            if let note = currentNote {
                if locksCurrentNote && !isAuthenticated {
                    LockedNoteView(
                        onUnlock: authenticate,
                        authError: authError,
                        biometryIcon: biometryIcon
                    )
                        .navigationTitle(note.displayTitle)
                        .navigationBarTitleDisplayMode(fromMap ? .inline : .automatic)
                        .toolbar {
                            if fromMap {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button { dismiss() } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityLabel("close")
                                }
                            }
                        }
                } else {
                    noteDetailContent(note: note)
                }
            } else {
                Text("noteNotFound")
                    .foregroundStyle(.secondary)
            }
        }
        .privacyCover(
            isProtected: currentNote?.isProtected == true,
            isRevealed: isAuthenticated
        )
        .onChange(of: scenePhase) { _, newPhase in
            // Re-locking waits for `.background` rather than `.inactive`, because
            // the Face ID prompt deactivates the scene too and would otherwise
            // undo the unlock it just granted. Hiding the text happens earlier
            // than this — see `privacyCover`.
            //
            // Keyed on `locksCurrentNote` rather than on `isProtected` alone, so a
            // device that cannot authenticate does not re-lock a note it has no
            // way of unlocking again — see `NoteLock`.
            guard locksCurrentNote, newPhase == .background else {
                return
            }

            isAuthenticated = false
        }
        .onChange(of: currentNote?.isProtected) { _, _ in
            // Same rule as above: protecting a note from the edit form locks it
            // behind us, but only where there is something to unlock it with.
            if locksCurrentNote {
                isAuthenticated = false
            }
        }
    }

    /// The note's reminder, while it still has something left to fire.
    ///
    /// Shown wherever the note was opened from. It used to appear only in the
    /// map's sheet, so a note pushed from the list gave no sign of the reminder
    /// its own row had just shown.
    @ViewBuilder
    private func reminderRow(note: NoteModel) -> some View {
        if let reminder = note.reminder, reminder > Date() {
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

    /// The note's tags, laid out as in `NoteRowView` so the detail view does not
    /// drop information the row it was opened from displayed.
    @ViewBuilder
    private func tagRow(note: NoteModel) -> some View {
        if !note.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// A drawing note shares its picture, a text note its text.
    ///
    /// Sharing used to hand `content` over for either — which a drawing note does
    /// not have, so an untitled drawing shared an empty string and a titled one
    /// shared its title with a dangling colon.
    @ViewBuilder
    private func shareLink(for note: NoteModel) -> some View {
        if note.type == .drawing, let drawingData = note.drawingData {
            ShareLink(
                item: SharedDrawing(
                    drawingData: drawingData,
                    canvasSize: note.drawingCanvasSize,
                    backgroundImageData: note.backgroundImageData
                ),
                subject: Text(note.displayTitle),
                // Title only, no thumbnail: rendering one here would mean a full
                // `UIGraphics` pass on every redraw of the toolbar, which is the
                // cost `DrawingPreview` exists to cache away. `SharedDrawing`
                // defers the render to the moment the sheet asks for the file.
                preview: SharePreview(note.displayTitle)
            ) {
                shareIcon
            }
            .accessibilityLabel("share")
        } else {
            ShareLink(item: shareText(for: note), subject: Text(note.displayTitle)) {
                shareIcon
            }
            .accessibilityLabel("share")
        }
    }

    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .foregroundStyle(.secondary)
    }

    /// Title and body joined only where both exist, so an untitled note shares no
    /// leading separator and a body-less one shares no trailing one.
    private func shareText(for note: NoteModel) -> String {
        [note.title, note.content]
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
    }

    @ViewBuilder
    private func noteDetailContent(note: NoteModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Only for the map's sheet: a pushed view carries the title in
                // its navigation bar, a sheet has no such context to borrow.
                if fromMap {
                    Text(note.createdAt.timeAgoDisplay())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 25)

                    if !note.title.isEmpty {
                        Text(note.title).font(.title2)
                    }
                }

                // Above the picture for a drawing, below the body for text: a
                // drawing fills its whole 400pt frame, so anything underneath it
                // starts off screen.
                if note.type == .drawing {
                    reminderRow(note: note)
                }

                // Display content based on note type
                if note.type == .text {
                    InteractiveTextView(note: note, notesStore: notesStore)
                } else if let drawingData = note.drawingData {
                    DrawingPreview(
                        drawingData: drawingData,
                        canvasSize: note.drawingCanvasSize,
                        backgroundImageData: note.backgroundImageData
                    )
                }

                if note.type == .text {
                    reminderRow(note: note)
                }

                tagRow(note: note)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(fromMap ? .inline : .automatic)
        .toolbar {
            if fromMap {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("close")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                shareLink(for: note)
            }

            // A note opened out of the trash gets the two actions the trash
            // offers instead of the two it does not. Editing something already
            // deleted writes to a note nobody can see, and Delete would move a
            // note into a trash it is already in — a button that looks
            // destructive and does nothing at all.
            //
            // Restoring deliberately stays on this screen rather than dismissing:
            // the toolbar flips back to Edit and Delete the moment the note is
            // live again, which says what happened without taking away what the
            // user was reading.
            if note.isDeleted {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        notesStore.restoreFromTrash(note: note)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("restore")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isPermanentDeleteConfirmPresented = true
                    } label: {
                        Image(systemName: "trash.slash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("permanentDelete")
                    // On the button rather than beside the dialog below, which is
                    // still registered on this view for the live-note case: two
                    // `confirmationDialog`s on one view compete for the same
                    // presentation and one of them silently never appears.
                    .confirmationDialog(
                        "permanentDeleteConfirm",
                        isPresented: $isPermanentDeleteConfirmPresented,
                        titleVisibility: .visible
                    ) {
                        Button("permanentDelete", role: .destructive) {
                            // Cancelling the note's notifications is the store's
                            // job — see `NotesStore.remove`, which does it for the
                            // same reason `moveToTrash` does.
                            notesStore.remove(note: note)
                            dismiss()
                        }

                        Button("cancel", role: .cancel) {}
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LazyNoteForm(note: note, title: "editNote")
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityLabel("editNote")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isDeleteNoteConfirmPresented = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("delete")
                }
            }
        }
        .confirmationDialog(
            "deleteNoteConfirm",
            isPresented: $isDeleteNoteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("delete", role: .destructive) {
                // Move to trash instead of permanent delete. Cancelling the
                // note's reminder is the store's job — see
                // `NotesStore.moveToTrash`.
                notesStore.moveToTrash(note: note)
                dismiss()
            }

            Button("cancel", role: .cancel) {
                isDeleteNoteConfirmPresented = false
            }
        }
    }
}

/// The drawing composited over its background image.
///
/// Rendering used to happen inline in `NoteDetailView.body`, which meant a full
/// 2× `UIGraphics` pass every time the view redrew — and it redraws on any
/// change to the store. The bitmap is now built once per revision of the
/// underlying data instead.
struct DrawingPreview: View {
    let drawingData: Data
    let canvasSize: CGSize?
    let backgroundImageData: Data?

    /// Compared byte-for-byte rather than hashed: an `==` that walks the blobs
    /// is still far cheaper than the render it guards, and it cannot collide.
    private struct RenderKey: Equatable {
        let drawing: Data
        let background: Data?
        let canvasSize: CGSize?
    }

    @State private var rendered: RenderedDrawing?

    private var renderKey: RenderKey {
        RenderKey(
            drawing: drawingData,
            background: backgroundImageData,
            canvasSize: canvasSize
        )
    }

    var body: some View {
        Group {
            if let rendered {
                ZoomableDrawingView(image: rendered.image, canvasSize: rendered.size)
            } else {
                // Matches the canvas the drawing was made on, so the layout
                // does not jump once the bitmap arrives.
                Color.white
            }
        }
        .frame(height: 400)
        .background(Color.white)
        .cornerRadius(8)
        .task(id: renderKey) {
            rendered = DrawingRenderer.render(
                drawingData: drawingData,
                canvasSize: canvasSize,
                backgroundImageData: backgroundImageData
            )
        }
    }
}

/// A drawing note's bitmap and the canvas it was drawn on.
struct RenderedDrawing {
    let image: UIImage
    let size: CGSize
}

/// Composites a drawing note into a bitmap: its strokes over its background
/// image, on white.
///
/// Lives outside `DrawingPreview` because the share sheet needs the same picture
/// — sharing a drawing used to offer the note's `content`, which a drawing note
/// does not have.
enum DrawingRenderer {
    @MainActor
    static func render(
        drawingData: Data,
        canvasSize: CGSize?,
        backgroundImageData: Data?
    ) -> RenderedDrawing? {
        guard let drawing = try? PKDrawing(data: drawingData) else { return nil }

        // A stored size of zero is no more usable than none at all, so it falls
        // back the same way rather than being taken at its word. A note saved
        // before its canvas was ever laid out carries exactly that, and honouring
        // it meant the guard below refused to draw — the note rendered as a blank
        // white box and shared as nothing, for a drawing that was perfectly
        // intact. The form no longer writes such a size; this is what rescues the
        // notes that already have one.
        let stored = canvasSize.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        let size = stored ?? drawing.bounds.size

        // A zero-size context yields nothing but a console complaint. Reachable
        // now only for a drawing with no strokes at all, which has no bounds to
        // fall back on either.
        guard size.width > 0, size.height > 0 else { return nil }

        let drawingRect = CGRect(origin: .zero, size: size)

        // Force light mode to render drawing with proper colors
        var drawingImage: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            drawingImage = drawing.image(from: drawingRect, scale: 2.0)
        }

        guard let drawingImage else {
            return RenderedDrawing(image: drawing.image(from: drawingRect, scale: 2.0), size: size)
        }

        UIGraphicsBeginImageContextWithOptions(size, true, 2.0)
        defer { UIGraphicsEndImageContext() }

        // Fill with white background
        UIColor.white.setFill()
        UIRectFill(drawingRect)

        // Draw background image if available with aspect fit
        if let backgroundImageData,
           let backgroundImage = UIImage(data: backgroundImageData) {
            let imageSize = backgroundImage.size
            let imageAspect = imageSize.width / imageSize.height
            let canvasAspect = size.width / size.height

            let drawRect: CGRect
            if imageAspect > canvasAspect {
                // Image is wider - fit to width
                let height = size.width / imageAspect
                let y = (size.height - height) / 2
                drawRect = CGRect(x: 0, y: y, width: size.width, height: height)
            } else {
                // Image is taller - fit to height
                let width = size.height * imageAspect
                let x = (size.width - width) / 2
                drawRect = CGRect(x: x, y: 0, width: width, height: size.height)
            }

            backgroundImage.draw(in: drawRect)
        }

        // Draw the PKDrawing image created in light mode
        drawingImage.draw(in: drawingRect)

        return RenderedDrawing(
            image: UIGraphicsGetImageFromCurrentImageContext() ?? drawingImage,
            size: size
        )
    }
}

/// A drawing note on its way to the share sheet, rendered to PNG only if the
/// user actually goes through with it.
///
/// `ShareLink` takes its item eagerly, so rendering the bitmap to build one would
/// put a full `UIGraphics` pass on every redraw of the toolbar — the very cost
/// `DrawingPreview` caches away. A `Transferable` defers it to the moment the
/// sheet asks for the file.
struct SharedDrawing: Transferable {
    let drawingData: Data
    let canvasSize: CGSize?
    let backgroundImageData: Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { shared in
            // Encoded inside the hop rather than after it: `UIImage` is not
            // `Sendable`, `Data` is.
            let png = await MainActor.run {
                DrawingRenderer.render(
                    drawingData: shared.drawingData,
                    canvasSize: shared.canvasSize,
                    backgroundImageData: shared.backgroundImageData
                )?.image.pngData()
            }

            guard let png else { throw CocoaError(.fileWriteUnknown) }
            return png
        }
        .suggestedFileName("drawing.png")
    }
}

/// A `NoteDetailView` that is not built until the link to it is actually followed.
///
/// The same shape of fix as `LazyNoteForm`, and for the same reason:
/// `NavigationLink`'s destination is an ordinary `@ViewBuilder` argument rather
/// than an autoclosure, so `NavigationLink { NoteDetailView(note: note) }` runs
/// the detail view's initialiser on every pass through the *linking* view's body
/// — once for every visible row of the list, again on every keystroke in the
/// search field, and again on any change to the store.
///
/// That initialiser asks `LocalAuthentication` whether this device can
/// authenticate anybody, which is a cross-process query costing the better part
/// of a millisecond. Ten visible rows therefore spent half a frame's budget
/// answering a question about screens nobody had opened. Building inside `body`
/// hands the timing to SwiftUI, which asks only once the destination is on
/// screen.
///
/// The query itself deliberately stays in `NoteDetailView.init`: `isAuthenticated`
/// starts out from its answer, so deferring it would leave a protected note's text
/// on screen for the frame before the answer arrived.
struct LazyNoteDetail: View {
    let note: NoteModel

    /// `true` when the note is opened from the map's sheet rather than pushed —
    /// see `NoteDetailView.fromMap`.
    var fromMap: Bool = false

    var body: some View {
        NoteDetailView(note: note, fromMap: fromMap)
    }
}

struct LockedNoteView: View {
    let onUnlock: () -> Void
    let authError: String?

    /// Which way in the button offers — see `NoteLock.biometryIcon()`.
    ///
    /// Handed in rather than resolved here. This view is rebuilt on every pass
    /// through the detail view's body, and `canEvaluatePolicy` is a cross-process
    /// query — the same cost `LazyNoteDetail` exists to keep out of the list's rows.
    /// Resolving it in `NoteDetailView.init` is what makes it exactly as current as
    /// the push, without paying for it per redraw.
    let biometryIcon: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("lockedNote")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onUnlock) {
                Label("authenticate", systemImage: biometryIcon)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    // Filled rather than a wash of the accent with accent-coloured
                    // text, which came to about 1.9:1 — the least legible thing on
                    // the screen, on the one screen that exists to be acted on.
                    // Black on the fill for the same reason as the tag chips: the
                    // accent is `systemOrange`, light in both appearances.
                    .background(Color.accentColor)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// Interactive text view that allows tapping checkboxes
struct InteractiveTextView: View {
    let note: NoteModel
    let notesStore: NotesStore

    @State private var localContent: String

    init(note: NoteModel, notesStore: NotesStore) {
        self.note = note
        self.notesStore = notesStore
        self._localContent = State(initialValue: note.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(localContent.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                if let item = ChecklistItem(line: line) {
                    CheckboxLineView(
                        item: item,
                        onToggle: {
                            toggleCheckboxAtLine(index)
                        }
                    )
                } else {
                    // A blank line is drawn as a space. `Text("")` lays out at
                    // zero height, so every paragraph break the user typed
                    // collapsed to the stack's 4pt spacing here — present in the
                    // stored note and in the editor, gone in the one view that is
                    // meant to be read. A space gives the line its height back.
                    Text(line.isEmpty ? " " : line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // Update local content when view appears
            localContent = note.content
        }
        .onChange(of: note.content) { _, newValue in
            // Update local content when note content changes
            localContent = newValue
        }
    }

    private func toggleCheckboxAtLine(_ lineIndex: Int) {
        var lines = localContent.components(separatedBy: "\n")

        // A line that is not a checklist item has nothing to toggle, and the two
        // markers are spelled once — see `ChecklistItem`.
        guard lineIndex < lines.count,
              let item = ChecklistItem(line: lines[lineIndex])
        else { return }

        lines[lineIndex] = item.toggled.line

        let newContent = lines.joined(separator: "\n")
        localContent = newContent

        // Copy-and-tweak so nothing else about the note can be lost on the way
        // through — listing the fields by hand used to drop `isDeleted`.
        var updatedNote = note
        updatedNote.content = newContent
        notesStore.replace(note: updatedNote)
    }
}

// View for a single checkbox line
struct CheckboxLineView: View {
    let item: ChecklistItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 4) {
                // A semantic font, not a fixed 20pt. The box is a character in a
                // `Text`, not a glyph inside a frame of a fixed size, so the rule
                // the rest of the app follows applies to it: it has to grow with
                // the line it belongs to. `.title3` is 20pt at the default size,
                // so nothing moves until the user asks it to — but at the
                // accessibility sizes the box no longer stays small beside text
                // twice its height.
                Text(item.box.rawValue)
                    .font(.title3)
                Text(item.label)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element rather than the two `Text`s it is drawn from, with the box
        // spoken as the control's *value*. Left to itself VoiceOver read the row as
        // its two labels in sequence — the bare glyph "▢" and then the text —
        // which conveys neither that the row can be ticked nor whether it already
        // is. The tick is the whole point of a checklist, and it was the one thing
        // the row would not say.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue(Text(item.isChecked ? "checkboxChecked" : "checkboxUnchecked"))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack {
        NoteDetailView(
            note: NoteModel(title: "Title", content: "Lorem ipsum")
        )
    }.environment(NotesStore())
}
