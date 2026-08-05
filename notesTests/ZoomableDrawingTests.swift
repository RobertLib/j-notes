//
//  ZoomableDrawingTests.swift
//  notesTests
//

import XCTest
@testable import J_Notes

/// How far a zoomed drawing may be dragged.
///
/// The regression these cover: the drag accumulated with no limit, so a zoomed
/// drawing could be pushed clean out of its frame — leaving a blank white box with
/// nothing on screen saying the picture was still there, just off the side of it.
/// The only way back was a double tap, which nothing advertises.
///
/// A view's gesture is not reachable from a test, which is why the rule is a pair of
/// pure functions on `ZoomableDrawingView` — the same reason `NoteLock`,
/// `NoteContentRule` and `ReminderFormState` exist outside the views they serve.
///
/// `@MainActor` because they are statics on a `View`, which carries that isolation
/// with it even for arithmetic that needs none — the same reason
/// `UndoableTextEditorTests` and `DrawingRendererTests` are annotated.
@MainActor
final class ZoomableDrawingTests: XCTestCase {

    private let frame = CGSize(width: 300, height: 400)

    // MARK: - The limit itself

    /// A picture no bigger than its frame has nowhere to go, so it is pinned.
    /// This is also the unzoomed case, where the canvas matches the frame.
    func testAPictureThatFitsCannotBePanned() {
        XCTAssertEqual(
            ZoomableDrawingView.panLimit(scaledSize: frame, in: frame),
            .zero
        )
    }

    /// Smaller than the frame is still pinned — the overflow is negative, and half
    /// of a negative overflow is not a licence to drag.
    func testAPictureSmallerThanItsFrameCannotBePanned() {
        XCTAssertEqual(
            ZoomableDrawingView.panLimit(
                scaledSize: CGSize(width: 100, height: 120),
                in: frame
            ),
            .zero
        )
    }

    /// Half the overflow on each axis: the picture is centred, so that is the point
    /// at which its own edge reaches the frame's.
    func testTheLimitIsHalfTheOverflow() {
        let limit = ZoomableDrawingView.panLimit(
            scaledSize: CGSize(width: 500, height: 600),
            in: frame
        )

        XCTAssertEqual(limit.width, 100)
        XCTAssertEqual(limit.height, 100)
    }

    /// The axes are independent: a drawing wider than its frame but no taller may
    /// be dragged sideways only.
    func testEachAxisIsLimitedOnItsOwn() {
        let limit = ZoomableDrawingView.panLimit(
            scaledSize: CGSize(width: 900, height: 200),
            in: frame
        )

        XCTAssertEqual(limit.width, 300)
        XCTAssertEqual(limit.height, 0)
    }

    // MARK: - Clamping an offset to it

    /// An offset inside the limit is the user's to keep, untouched.
    func testAnOffsetWithinTheLimitIsLeftAlone() {
        let offset = CGSize(width: 40, height: -60)

        XCTAssertEqual(
            ZoomableDrawingView.clamped(
                offset,
                scaledSize: CGSize(width: 500, height: 600),
                in: frame
            ),
            offset
        )
    }

    /// The regression: a drag that would carry the picture past its own edge stops
    /// at it instead of running on.
    func testAnOffsetPastTheEdgeIsHeldAtIt() {
        let clamped = ZoomableDrawingView.clamped(
            CGSize(width: 5_000, height: 5_000),
            scaledSize: CGSize(width: 500, height: 600),
            in: frame
        )

        XCTAssertEqual(clamped.width, 100)
        XCTAssertEqual(clamped.height, 100)
    }

    /// And in the other direction, which is the same rule mirrored — dragging the
    /// far way used to lose the picture just as thoroughly.
    func testANegativeOffsetPastTheEdgeIsHeldAtItToo() {
        let clamped = ZoomableDrawingView.clamped(
            CGSize(width: -5_000, height: -5_000),
            scaledSize: CGSize(width: 500, height: 600),
            in: frame
        )

        XCTAssertEqual(clamped.width, -100)
        XCTAssertEqual(clamped.height, -100)
    }

    /// With nothing to pan, every offset collapses to centred — so a picture that
    /// fits cannot be nudged off its frame at all.
    func testAPictureThatFitsIsAlwaysRecentred() {
        XCTAssertEqual(
            ZoomableDrawingView.clamped(
                CGSize(width: 200, height: 200),
                scaledSize: CGSize(width: 100, height: 100),
                in: frame
            ),
            .zero
        )
    }

    /// What the pinch relies on: zooming back out shrinks the room there is to pan,
    /// so an offset that was legal at the old scale has to come back inside the new
    /// limit rather than stay where it was. Without this, pinching out left the
    /// picture off-centre with no overflow to justify it.
    func testZoomingOutPullsAnOffsetBackInside() {
        let canvas = CGSize(width: 300, height: 400)
        let atFullZoom = ZoomableDrawingView.clamped(
            CGSize(width: 300, height: 400),
            scaledSize: CGSize(width: canvas.width * 3, height: canvas.height * 3),
            in: frame
        )

        XCTAssertEqual(atFullZoom.width, 300, "Three times over, there is room to spare")

        let afterZoomingOut = ZoomableDrawingView.clamped(
            atFullZoom,
            scaledSize: CGSize(width: canvas.width * 1.5, height: canvas.height * 1.5),
            in: frame
        )

        XCTAssertEqual(afterZoomingOut.width, 75)
        XCTAssertEqual(afterZoomingOut.height, 100)
    }
}
