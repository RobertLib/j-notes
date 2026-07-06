//
//  NoteFormView.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import PencilKit
import SwiftUI

struct NoteFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
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
    @State private var textViewUndoManager: UndoManager?
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
    @State private var hasDrawingContent = false

    init(note: NoteModel? = nil) {
        self.note = note

        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.content ?? "")
        _color = State(initialValue: note?.color ?? .primary)
        _isColorOn = State(initialValue: note?.color != nil)
        _reminder = State(initialValue: note?.reminder ?? Date())
        _noteType = State(initialValue: note?.type ?? .text)
        _tags = State(initialValue: note?.tags ?? [])
        _isProtected = State(initialValue: note?.isProtected ?? false)

        _isReminderOn = State(
            initialValue: note?.reminder == nil
                ? false
                : note?.reminder ?? Date() > Date()
        )

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
        }
    }

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tags.contains(tag) else {
            newTagText = ""
            return
        }
        tags.append(tag)
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    private func submit() {
        // Validate content based on note type
        if noteType == .text && content.isEmpty {
            isContentErrorPresented = true
            return
        }

        if noteType == .drawing && canvas.drawing.strokes.isEmpty {
            isContentErrorPresented = true
            return
        }

        Task {
            // Remove old notifications if updating
            await NotificationManager.instance.removeNotifications(
                identifiers: note?.notificationIdentifiers
            )

            var notificationIdentifiers: [String] = []

            let notificationContent = noteType == .drawing
                ? String(localized: "drawingNote")
                : (isProtected ? String(localized: "lockedNote") : content)

            if isReminderOn {
                let notificationIdentifier =
                    await NotificationManager.instance.scheduleNotification(
                        title: title.isEmpty ? String(localized: "note") : title,
                        subtitle: notificationContent,
                        date: reminder
                    )

                notificationIdentifiers.append(notificationIdentifier)
            }

            // Get drawing data if it's a drawing note
            // Use Optional wrapping to explicitly send nil when data is cleared
            let drawingData: Data?? = noteType == .drawing ? Optional(canvas.drawing.dataRepresentation()) : nil
            let canvasSize: CGSize?? = noteType == .drawing ? Optional(canvas.bounds.size) : nil
            let backgroundImageData: Data?? = noteType == .drawing ? Optional(backgroundImage?.jpegData(compressionQuality: 0.8)) : nil

            if let note = note {
                notesStore.update(
                    note: note,
                    title: title,
                    content: content,
                    type: noteType,
                    drawingData: drawingData,
                    drawingCanvasSize: canvasSize,
                    backgroundImageData: backgroundImageData,
                    color: color,
                    isColorOn: isColorOn,
                    reminder: reminder,
                    isReminderOn: isReminderOn,
                    notificationIdentifiers: notificationIdentifiers,
                    location: locationManager.isAuthorized
                        ? locationManager.lastLocation
                        : nil,
                    tags: tags,
                    isProtected: isProtected
                )
            } else {
                notesStore.add(
                    title: title,
                    content: content,
                    type: noteType,
                    drawingData: drawingData ?? nil,
                    drawingCanvasSize: canvasSize ?? nil,
                    backgroundImageData: backgroundImageData ?? nil,
                    color: color,
                    isColorOn: isColorOn,
                    reminder: reminder,
                    isReminderOn: isReminderOn,
                    notificationIdentifiers: notificationIdentifiers,
                    location: locationManager.isAuthorized
                        ? locationManager.lastLocation
                        : nil,
                    tags: tags,
                    isProtected: isProtected
                )
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
                        placeholder: String(localized: "content"),
                        undoManager: $textViewUndoManager
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
                    ColorPicker("", selection: $color)
                }

                Toggle("reminder", isOn: $isReminderOn.animation())
                    .onChange(of: isReminderOn) { oldValue, newValue in
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
                .disabled(noteType == .text ? content.isEmpty : !hasDrawingContent)
            }
        }
        .alert(
            "contentError",
            isPresented: $isContentErrorPresented
        ) {}
        .onAppear() {
            locationManager.requestLocation()

            // Reset canvas for new notes
            if note == nil {
                canvas.drawing = PKDrawing()
                hasDrawingContent = false
            }
        }
        .onSubmit {
            submit()
        }
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
        .background(Color.accentColor.opacity(0.12))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}

#Preview {
    NoteFormView()
        .environment(LocationManager())
        .environment(NotesStore())
}
