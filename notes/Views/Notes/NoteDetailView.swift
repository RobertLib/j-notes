//
//  NoteDetailView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import PencilKit
import SwiftUI

struct ZoomableDrawingView: View {
    let image: UIImage
    let canvasSize: CGSize

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale < 1 {
                                withAnimation {
                                    scale = 1
                                    offset = .zero
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
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

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notesStore: NotesStore

    let noteId: UUID
    let fromMap: Bool

    init(note: NoteModel) {
        self.noteId = note.id
        self.fromMap = false
    }

    init(note: NoteModel, fromMap: Bool) {
        self.noteId = note.id
        self.fromMap = fromMap
    }

    @State private var isDeleteNoteConfirmPresented = false

    private var currentNote: NoteModel? {
        notesStore.notes.first { $0.id == noteId }
    }

    var body: some View {
        Group {
            if let note = currentNote {
                noteDetailContent(note: note)
            } else {
                Text("Note not found")
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func noteDetailContent(note: NoteModel) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if fromMap {
                        Text(note.createdAt.timeAgoDisplay())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 25)

                        if !note.title.isEmpty {
                            Text(note.title).font(.title2)
                        }

                        // Show reminder before drawing, but after text
                        if note.type == .drawing {
                            if let reminder = note.reminder {
                                if reminder > Date() {
                                    HStack {
                                        Image(systemName: "bell")
                                            .foregroundColor(.accentColor)

                                        Text(reminder.formatted())
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 3)
                                }
                            }
                        }
                    }

                // Display content based on note type
                if note.type == .text {
                    InteractiveTextView(note: note, notesStore: notesStore)
                } else if note.type == .drawing {
                    if let drawingData = note.drawingData,
                       let drawing = try? PKDrawing(data: drawingData) {
                        let canvasSize = note.drawingCanvasSize ?? drawing.bounds.size
                        let drawingRect = CGRect(origin: .zero, size: canvasSize)

                        // Create composite image with background + drawing
                        let compositeImage: UIImage = {
                            // Force light mode to render drawing with proper colors
                            var drawingImage: UIImage?
                            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                                drawingImage = drawing.image(from: drawingRect, scale: 2.0)
                            }

                            guard let drawingImage = drawingImage else {
                                return drawing.image(from: drawingRect, scale: 2.0)
                            }

                            UIGraphicsBeginImageContextWithOptions(canvasSize, true, 2.0)
                            defer { UIGraphicsEndImageContext() }

                            // Fill with white background
                            UIColor.white.setFill()
                            UIRectFill(CGRect(origin: .zero, size: canvasSize))

                            // Draw background image if available with aspect fit
                            if let backgroundImageData = note.backgroundImageData,
                               let backgroundImage = UIImage(data: backgroundImageData) {
                                let imageSize = backgroundImage.size
                                let imageAspect = imageSize.width / imageSize.height
                                let canvasAspect = canvasSize.width / canvasSize.height

                                let drawRect: CGRect
                                if imageAspect > canvasAspect {
                                    // Image is wider - fit to width
                                    let height = canvasSize.width / imageAspect
                                    let y = (canvasSize.height - height) / 2
                                    drawRect = CGRect(x: 0, y: y, width: canvasSize.width, height: height)
                                } else {
                                    // Image is taller - fit to height
                                    let width = canvasSize.height * imageAspect
                                    let x = (canvasSize.width - width) / 2
                                    drawRect = CGRect(x: x, y: 0, width: width, height: canvasSize.height)
                                }

                                backgroundImage.draw(in: drawRect)
                            }

                            // Draw the PKDrawing image created in light mode
                            drawingImage.draw(in: drawingRect)

                            return UIGraphicsGetImageFromCurrentImageContext() ?? drawingImage
                        }()

                        ZoomableDrawingView(image: compositeImage, canvasSize: canvasSize)
                            .frame(height: 400)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                }

                if fromMap && note.type == .text {
                    if let reminder = note.reminder {
                        if reminder > Date() {
                            HStack {
                                Image(systemName: "bell")
                                    .foregroundColor(.accentColor)

                                Text(reminder.formatted())
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            }

        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(fromMap ? .inline : .automatic)
        .toolbar {
            if fromMap {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                let shareContent = note.title.isEmpty ? note.content : "\(note.title): \(note.content)"
                ShareLink(item: shareContent, subject: Text(note.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    NoteFormView(note: note).navigationTitle("editNote")
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.orange)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    isDeleteNoteConfirmPresented = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .confirmationDialog(
                    "deleteNoteConfirm",
                    isPresented: $isDeleteNoteConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("delete", role: .destructive) {
                        Task {
                            await NotificationManager.instance.removeNotifications(
                                identifiers: note.notificationIdentifiers
                            )

                            // Move to trash instead of permanent delete
                            notesStore.moveToTrash(note: note)

                            dismiss()
                        }
                    }

                    Button("cancel", role: .cancel) {
                        isDeleteNoteConfirmPresented = false
                    }
                }
            }
        }
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
                if line.hasPrefix("▢ ") || line.hasPrefix("▣ ") {
                    CheckboxLineView(
                        line: line,
                        onToggle: {
                            toggleCheckboxAtLine(index)
                        }
                    )
                } else {
                    Text(line)
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
        guard lineIndex < lines.count else { return }

        let line = lines[lineIndex]
        let uncheckedBox = "▢ "
        let checkedBox = "▣ "

        if line.hasPrefix(uncheckedBox) {
            // Toggle to checked
            lines[lineIndex] = checkedBox + String(line.dropFirst(uncheckedBox.count))
        } else if line.hasPrefix(checkedBox) {
            // Toggle to unchecked
            lines[lineIndex] = uncheckedBox + String(line.dropFirst(checkedBox.count))
        }

        let newContent = lines.joined(separator: "\n")
        localContent = newContent

        // Update the note in store - create new instance with updated content
        let updatedNote = NoteModel(
            id: note.id,
            createdAt: note.createdAt,
            title: note.title,
            content: newContent,
            type: note.type,
            drawingData: note.drawingData,
            drawingCanvasSize: note.drawingCanvasSize,
            backgroundImageData: note.backgroundImageData,
            pinned: note.pinned,
            color: note.color,
            reminder: note.reminder,
            notificationIdentifiers: note.notificationIdentifiers,
            location: note.location
        )
        notesStore.update(note: updatedNote)
    }
}

// View for a single checkbox line
struct CheckboxLineView: View {
    let line: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 4) {
                Text(String(line.prefix(1)))
                    .font(.system(size: 20))
                Text(String(line.dropFirst(2)))
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        NoteDetailView(
            note: NoteModel(title: "Title", content: "Lorem ipsum")
        )
    }.environmentObject(NotesStore())
}
