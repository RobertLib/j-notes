//
//  DrawingView.swift
//  notes
//
//  Created by Robert Libšanský on 09.10.2025.
//

import PencilKit
import PhotosUI
import SwiftUI

/// How a picture picked for a drawing's background is prepared before the app
/// keeps it.
///
/// A capture arrives at the sensor's full resolution — twelve megapixels on a
/// modest iPhone, forty-eight on a recent one — and the photo library hands over
/// whatever the file holds. Nothing ever draws that. `DrawingRenderer.render`
/// composites the note at the canvas's own size at 2×, which is around 722×800
/// pixels, and `ZoomableDrawingView` magnifies *that* bitmap rather than the
/// source — so the detail past it was never on its way to the screen at any zoom.
///
/// It was on its way to the notes file, though, and that is what made it
/// expensive rather than merely wasteful: `backgroundImageData` is base64 inside
/// `notes.json` alongside every other note, `NotesCodec.encode` rewrites the
/// whole file on every save — a checkbox tick, a pin, a swipe to the trash — and
/// `NotesStore.notes` holds the bytes in memory for the life of the process. A
/// handful of photo notes therefore cost megabytes on each of those, repeatedly,
/// for pixels nothing renders.
///
/// Applied where a picture enters the app rather than where one is written, for
/// the same reason `NoteModel.uniqueTags` is applied at decode: that is the edge.
/// A note already carrying an oversized photo keeps its bytes untouched —
/// `jpegData` on an image that was itself decoded from JPEG loses a little more
/// every pass, which is exactly what `NoteFormView.backgroundImageDataToStore`
/// exists to avoid, and quietly degrading a picture the user already has would be
/// a worse bargain than the space it saves.
enum BackgroundImage {
    /// The longest side a stored background may have, in pixels.
    ///
    /// The canvas is 400 points tall and as wide as the form around it — roughly
    /// 700 on an iPad — and it is composited at 2×, so this clears the largest
    /// bitmap the app ever builds from one of these with room to spare.
    static let maxDimension: CGFloat = 1600

    /// `image` scaled down to fit inside `maxDimension`, or the image itself when
    /// it already does.
    ///
    /// Never scales up: a small picture is left exactly as it is rather than
    /// resampled into a larger file carrying no more detail than it started with.
    ///
    /// Split out as a pure function so the rule can be exercised at all — a photo
    /// picker is not reachable from a test, the same reason `NoteContentRule`,
    /// `ReminderFormState` and `NoteLock` live outside the views they serve.
    nonisolated static func prepared(_ image: UIImage) -> UIImage {
        // Measured in pixels rather than points. `size` is in points and an image
        // carries a `scale` of its own, so measuring the wrong one lets a 3×
        // picture through at three times the size this is meant to cap.
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longestSide = max(pixelWidth, pixelHeight)

        // Also what turns away a degenerate image: a zero or NaN side fails this
        // comparison, so it is handed back untouched rather than fed to the
        // arithmetic below.
        guard longestSide > maxDimension else { return image }

        let ratio = maxDimension / longestSide

        // At least one pixel on each side. An extremely long, thin picture would
        // otherwise round its short side to zero, which renders as nothing at all
        // rather than as something small.
        let target = CGSize(
            width: max(1, (pixelWidth * ratio).rounded()),
            height: max(1, (pixelHeight * ratio).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        // One pixel per point, so the result measures exactly `target` in pixels
        // rather than that times whatever the screen's scale happens to be.
        format.scale = 1
        // Alpha is kept. `jpegData` flattens it on the way to storage either way,
        // but the form draws this very image over white while the note is being
        // edited — an opaque context would turn a transparent PNG's background
        // black on that screen alone.
        format.opaque = false

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // `draw(in:)` applies the image's orientation, so the copy comes out
            // upright rather than carrying a rotation as metadata for each
            // separate thing that reads it to remember to honour.
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// `prepared(_:)`, off the main actor.
    ///
    /// Resampling forty-eight megapixels is long enough to drop frames, and both
    /// callers are on screen when it runs — one is dismissing the camera, the
    /// other is coming back from the photo picker.
    nonisolated static func prepare(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) { prepared(image) }.value
    }

    /// The picture `data` holds, decoded and scaled down, both off the main actor.
    ///
    /// The decode is the heavier half and it used to run on the main actor, where
    /// a full-resolution JPEG costs more than the resampling that now follows it.
    nonisolated static func prepare(data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data).map(prepared)
        }.value
    }
}

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
        canvas.overrideUserInterfaceStyle = .light // Force light mode for canvas
        canvas.delegate = context.coordinator
        applyBackgroundTransparency(canvas)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = isDraw ? ink : eraser
        applyBackgroundTransparency(uiView)
    }

    /// Lets the picture behind the canvas show through, or paints it white when
    /// there is none.
    ///
    /// The photo itself is drawn by `DrawingCanvasView`, in the layer below this
    /// one. This used to insert a tagged `UIImageView` into the canvas as well,
    /// which drew the very same picture at the very same aspect-fit rect a second
    /// time — two copies of every background photo in memory, and a stack of
    /// subview bookkeeping (a tag to find it by, an identity check to avoid
    /// rebuilding it, a flicker workaround for when that went wrong) that only
    /// existed to keep the duplicate in step with the original.
    private func applyBackgroundTransparency(_ canvasView: PKCanvasView) {
        if backgroundImage != nil {
            canvasView.backgroundColor = .clear
            canvasView.isOpaque = false
        } else {
            // Opaque white in both light and dark mode — the same ground the
            // drawing is composited onto when it is rendered for the detail view
            // and the share sheet. See `DrawingRenderer.render`.
            canvasView.backgroundColor = .white
            canvasView.isOpaque = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    @MainActor
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
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ZStack(alignment: .top) {
            // The drawing's backdrop, and the only copy of it — the canvas above
            // goes transparent so this shows through. See
            // `applyBackgroundTransparency`.
            ZStack {
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
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel("penType")
                    } else {
                        // When eraser is active, button switches back to last used pen
                        Button(action: {
                            isDraw = true
                        }) {
                            Image(systemName: type == .pen ? "pencil.tip" : type == .marker ? "highlighter" : "pencil")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("penType")
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
                                .foregroundStyle(showPenSettings ? Color.accentColor : Color.primary)
                            Text("\(Int(penWidth))")
                                .font(.caption2)
                                .foregroundStyle(showPenSettings ? Color.accentColor : Color.primary)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("penWidth")
                    .accessibilityValue("\(Int(penWidth))")

                    Divider()
                        .frame(height: 25)

                    // Color picker
                    ColorPicker("", selection: $color)
                        .labelsHidden()
                        .frame(width: 40, height: 40)
                        .accessibilityLabel("drawingColor")
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
                            .foregroundStyle(isDraw ? Color.secondary : Color.red)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("eraser")

                    Spacer()

                    // Clear button
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("clear")
                    .confirmationDialog(
                        "clearDrawingConfirm",
                        isPresented: $showClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("clear", role: .destructive) {
                            canvas.drawing = PKDrawing()
                            backgroundImage = nil
                            // Assigning `drawing` does not reliably reach the
                            // canvas delegate, and the form's Save button is
                            // bound to what that callback reports — so it is
                            // called here rather than waited for. Without it a
                            // cleared drawing could still look saveable.
                            onDrawingChanged?()
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
                            .foregroundStyle(.secondary)

                        Slider(value: $penWidth, in: 1...20, step: 1)

                        Text("\(Int(penWidth)) \(String(localized: "pt"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 8)
            .modifier(GlassBackground(cornerRadius: 12))
            .padding(6)
        }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }

            Task {
                // Decoded and scaled down off the main actor before it is kept —
                // the library hands over the file at whatever size it was taken
                // at, and nothing here draws more than the canvas. See
                // `BackgroundImage`.
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = await BackgroundImage.prepare(data: data) {
                    backgroundImage = image
                }
                selectedPhotoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $backgroundImage)
                .ignoresSafeArea()
        }
    }
}

// Applies Liquid Glass on iOS 26+, falls back to a material background on older systems
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        }
    }
}

// Camera capture picker (photo library uses PhotosPicker)
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                // Scaled down off the main actor — a capture arrives at the
                // sensor's full resolution, and resampling one of those is long
                // enough to stutter the camera's dismissal. See `BackgroundImage`.
                //
                // The dismissal below deliberately does not wait for it: the
                // picture lands in the binding a moment later, which is the same
                // way the photo library's already arrives.
                Task { parent.image = await BackgroundImage.prepare(uiImage) }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
