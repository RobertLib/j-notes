//
//  DrawingRendererTests.swift
//  notesTests
//

import PencilKit
import XCTest
@testable import J_Notes

/// The canvas a drawing note is rendered against.
///
/// The regression these cover: a note saved before its canvas had ever been laid
/// out stores a size of zero, and the renderer took that at its word — it refused
/// the zero-sized context and returned nil, so the note showed as a blank white
/// box and shared as nothing, for a drawing whose strokes were perfectly intact.
/// The form no longer writes such a size; the fallback here is what rescues the
/// notes that already carry one.
@MainActor
final class DrawingRendererTests: XCTestCase {

    /// A one-stroke drawing, so there are real bounds to fall back on. An empty
    /// `PKDrawing` has none, which is the one case that still renders nothing.
    private func drawingData() -> Data {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 30)]
            .enumerated()
            .map { index, location in
                PKStrokePoint(
                    location: location,
                    timeOffset: Double(index) / 10,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }

        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )

        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    /// The regression itself: zero is not a size, and honouring it lost the note.
    func testAZeroCanvasSizeFallsBackToTheDrawingsOwnBounds() {
        let rendered = DrawingRenderer.render(
            drawingData: drawingData(),
            canvasSize: .zero,
            backgroundImageData: nil
        )

        XCTAssertNotNil(rendered, "A stored size of zero must not stop the drawing rendering")
        XCTAssertGreaterThan(rendered?.size.width ?? 0, 0)
        XCTAssertGreaterThan(rendered?.size.height ?? 0, 0)
    }

    /// One axis missing is as unusable as both: the context is refused either way.
    func testACanvasSizeWithNoHeightFallsBackToo() {
        let rendered = DrawingRenderer.render(
            drawingData: drawingData(),
            canvasSize: CGSize(width: 300, height: 0),
            backgroundImageData: nil
        )

        XCTAssertNotNil(rendered)
        XCTAssertGreaterThan(rendered?.size.height ?? 0, 0)
    }

    /// Notes written before the canvas size was recorded at all rely on this, and
    /// always have.
    func testAMissingCanvasSizeStillRenders() {
        XCTAssertNotNil(
            DrawingRenderer.render(
                drawingData: drawingData(),
                canvasSize: nil,
                backgroundImageData: nil
            )
        )
    }

    /// The fallback must not take over from a real canvas: the strokes are stored
    /// in the coordinates of the canvas they were drawn on, so rendering against
    /// the drawing's own bounds instead would crop and rescale the picture.
    func testARealCanvasSizeIsKept() {
        let canvas = CGSize(width: 320, height: 400)

        let rendered = DrawingRenderer.render(
            drawingData: drawingData(),
            canvasSize: canvas,
            backgroundImageData: nil
        )

        XCTAssertEqual(rendered?.size, canvas)
    }

    /// Bytes that are not a drawing have nothing to draw and no bounds to fall
    /// back on, so the caller still gets `nil` — and shows its placeholder.
    func testDataThatIsNotADrawingRendersNothing() {
        XCTAssertNil(
            DrawingRenderer.render(
                drawingData: Data("not a drawing".utf8),
                canvasSize: CGSize(width: 100, height: 100),
                backgroundImageData: nil
            )
        )
    }
}
