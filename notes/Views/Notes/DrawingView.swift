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

    var ink: PKInkingTool = PKInkingTool(.pen, color: .black, width: 3)

    let eraser = PKEraserTool(.bitmap)

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = isDraw ? ink : eraser
        canvas.backgroundColor = .white
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = isDraw ? ink : eraser
    }
}

struct DrawingCanvasView: View {
    @Binding var canvas: PKCanvasView
    @Binding var isDraw: Bool
    @Binding var color: Color
    @Binding var type: PKInkingTool.InkType
    @Binding var penWidth: CGFloat

    @State private var showPenSettings = false
    @State private var showClearConfirmation = false

    var body: some View {
        ZStack(alignment: .top) {
            // Canvas - full screen
            DrawingCanvasRepresentable(
                canvas: $canvas,
                isDraw: $isDraw,
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
                    // Pen type menu
                    Menu {
                        Button(action: {
                            type = .pen
                            isDraw = true
                        }) {
                            Label("pen", systemImage: "pencil.tip")
                        }
                        Button(action: {
                            type = .marker
                            isDraw = true
                        }) {
                            Label("marker", systemImage: "highlighter")
                        }
                        Button(action: {
                            type = .pencil
                            isDraw = true
                        }) {
                            Label("pencilTool", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: type == .pen ? "pencil.tip" : type == .marker ? "highlighter" : "pencil")
                            .font(.title3)
                            .foregroundColor(isDraw ? .accentColor : .secondary)
                            .frame(width: 40, height: 40)
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
    }
}
