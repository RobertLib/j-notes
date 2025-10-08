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
                    Text("\(note.content)")
                } else if note.type == .drawing {
                    if let drawingData = note.drawingData,
                       let drawing = try? PKDrawing(data: drawingData) {
                        let canvasSize = note.drawingCanvasSize ?? drawing.bounds.size
                        let drawingRect = CGRect(origin: .zero, size: canvasSize)

                        // Create composite image with background + drawing
                        let compositeImage: UIImage = {
                            UIGraphicsBeginImageContextWithOptions(canvasSize, false, 2.0)
                            defer { UIGraphicsEndImageContext() }

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

                            // Draw the drawing on top
                            let drawingImage = drawing.image(from: drawingRect, scale: 2.0)
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

                            notesStore.remove(note: note)

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

#Preview {
    NavigationStack {
        NoteDetailView(
            note: NoteModel(title: "Title", content: "Lorem ipsum")
        )
    }.environmentObject(NotesStore())
}
