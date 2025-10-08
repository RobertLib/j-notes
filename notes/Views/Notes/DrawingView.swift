//
//  DrawingView.swift
//  notes
//
//  Created by Robert Libšanský on 09.10.2025.
//

import PencilKit
import SwiftUI

struct DrawingCanvasRepresentable: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    @Binding var isDraw: Bool
    @Binding var backgroundImage: UIImage?
    var onDrawingChanged: (() -> Void)?

    var ink: PKInkingTool = PKInkingTool(.pen, color: .black, width: 3)

    let eraser = PKEraserTool(.bitmap)

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = isDraw ? ink : eraser
        canvas.backgroundColor = .white
        canvas.delegate = context.coordinator
        updateBackgroundImage(canvas)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = isDraw ? ink : eraser
        updateBackgroundImage(uiView)
    }

    private func updateBackgroundImage(_ canvasView: PKCanvasView) {
        // Remove existing background image views
        canvasView.subviews.forEach { subview in
            if subview.tag == 999 {
                subview.removeFromSuperview()
            }
        }

        // Make canvas background clear if there's an image
        if backgroundImage != nil {
            canvasView.backgroundColor = .clear
            canvasView.isOpaque = false
        } else {
            canvasView.backgroundColor = .white
            canvasView.isOpaque = true
        }

        // Add new background image if available
        if let image = backgroundImage {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.frame = canvasView.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.tag = 999
            canvasView.insertSubview(imageView, at: 0)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var onDrawingChanged: (() -> Void)?

        init(onDrawingChanged: (() -> Void)?) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged?()
        }
    }
}

struct DrawingCanvasView: View {
    @Binding var canvas: PKCanvasView
    @Binding var isDraw: Bool
    @Binding var color: Color
    @Binding var type: PKInkingTool.InkType
    @Binding var penWidth: CGFloat
    @Binding var backgroundImage: UIImage?
    var onDrawingChanged: (() -> Void)?

    @State private var showPenSettings = false
    @State private var showClearConfirmation = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background layer
            ZStack {
                // Background image if available
                if let image = backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.white
                }
            }

            // Canvas layer - transparent background when image exists
            DrawingCanvasRepresentable(
                canvas: $canvas,
                isDraw: $isDraw,
                backgroundImage: $backgroundImage,
                onDrawingChanged: onDrawingChanged,
                ink: PKInkingTool(
                    type,
                    color: UIColor(color),
                    width: penWidth
                )
            )

            // Toolbar overlay - Compact version for iPhone
            VStack(spacing: 8) {
                // Main toolbar row
                HStack(spacing: 12) {
                    // Pen type menu/button
                    if isDraw {
                        // When drawing is active, show menu to choose pen type
                        Menu {
                            Button(action: {
                                type = .pen
                            }) {
                                Label("pen", systemImage: "pencil.tip")
                            }
                            Button(action: {
                                type = .marker
                            }) {
                                Label("marker", systemImage: "highlighter")
                            }
                            Button(action: {
                                type = .pencil
                            }) {
                                Label("pencilTool", systemImage: "pencil")
                            }

                            Divider()

                            Button(action: {
                                showPhotoLibrary = true
                            }) {
                                Label(String(localized: "photoLibrary"), systemImage: "photo.on.rectangle")
                            }
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button(action: {
                                    showCamera = true
                                }) {
                                    Label(String(localized: "camera"), systemImage: "camera")
                                }
                            }
                        } label: {
                            Image(systemName: type == .pen ? "pencil.tip" : type == .marker ? "highlighter" : "pencil")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                                .frame(width: 40, height: 40)
                        }
                    } else {
                        // When eraser is active, button switches back to last used pen
                        Button(action: {
                            isDraw = true
                        }) {
                            Image(systemName: type == .pen ? "pencil.tip" : type == .marker ? "highlighter" : "pencil")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .frame(height: 25)

                    // Width toggle/settings
                    Button(action: {
                        withAnimation {
                            showPenSettings.toggle()
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "lineweight")
                                .font(.caption)
                                .foregroundColor(showPenSettings ? .accentColor : .primary)
                            Text("\(Int(penWidth))")
                                .font(.caption2)
                                .foregroundColor(showPenSettings ? .accentColor : .primary)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 25)

                    // Color picker
                    ColorPicker("", selection: $color)
                        .labelsHidden()
                        .frame(width: 40, height: 40)
                        .onChange(of: color) { _, _ in
                            // When color changes, switch back to drawing mode
                            isDraw = true
                        }

                    Divider()
                        .frame(height: 25)

                    // Eraser button
                    Button(action: {
                        isDraw = false
                    }) {
                        Image(systemName: "eraser.fill")
                            .font(.title3)
                            .foregroundColor(isDraw ? .secondary : .red)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Clear button
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.red)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "clearDrawingConfirm",
                        isPresented: $showClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("clear", role: .destructive) {
                            canvas.drawing = PKDrawing()
                            backgroundImage = nil
                        }
                        Button("cancel", role: .cancel) {}
                    }
                }
                .padding(.horizontal, 8)

                // Width settings row - shows when showPenSettings
                if showPenSettings {
                    HStack(spacing: 8) {
                        Text("thickness")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Slider(value: $penWidth, in: 1...20, step: 1)

                        Text("\(Int(penWidth)) \(String(localized: "pt"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.95))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(image: $backgroundImage, sourceType: .photoLibrary)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(image: $backgroundImage, sourceType: .camera)
                .ignoresSafeArea()
        }
    }
}

// Image Picker for selecting photos
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
