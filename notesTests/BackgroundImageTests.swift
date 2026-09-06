//
//  BackgroundImageTests.swift
//  notesTests
//

import XCTest
@testable import J_Notes

/// What a picture picked for a drawing's background is reduced to before the app
/// keeps it.
///
/// The regression these cover: nothing scaled a photo down, so a capture went into
/// `notes.json` at the sensor's full resolution — base64, alongside every other
/// note, in a file `NotesCodec.encode` rewrites on every checkbox tick — while
/// `DrawingRenderer` never composites more than the canvas at 2×. Megabytes per
/// note, repeatedly, for pixels nothing renders.
@MainActor
final class BackgroundImageTests: XCTestCase {

    /// An image of an exact pixel size. `scale: 1` so points and pixels agree
    /// unless a test deliberately says otherwise.
    private func image(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        let size = CGSize(width: width / scale, height: height / scale)

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// The image's size in pixels, which is what `prepared` caps — not its size in
    /// points, which is that divided by whatever scale it carries.
    private func pixelSize(_ image: UIImage) -> CGSize {
        CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
    }

    // MARK: - Scaling down

    /// The case the whole thing exists for: a camera-sized photo comes back inside
    /// the cap.
    func testScalesDownAPhotoSizedImage() {
        let prepared = BackgroundImage.prepared(image(width: 4032, height: 3024))
        let size = pixelSize(prepared)

        XCTAssertEqual(size.width, BackgroundImage.maxDimension)
        XCTAssertEqual(size.height, (BackgroundImage.maxDimension * 3024 / 4032).rounded())
    }

    /// The longest side is what is capped, whichever one it is — a portrait photo
    /// is bounded by its height.
    func testCapsTheLongestSideOfAPortraitImage() {
        let prepared = BackgroundImage.prepared(image(width: 3024, height: 4032))
        let size = pixelSize(prepared)

        XCTAssertEqual(size.height, BackgroundImage.maxDimension)
        XCTAssertLessThan(size.width, BackgroundImage.maxDimension)
    }

    /// Aspect ratio survives the trip. A background is drawn aspect-fit over the
    /// canvas, so a stretched copy would be visibly wrong rather than merely
    /// smaller.
    func testPreservesAspectRatio() {
        let original = image(width: 4000, height: 2000)
        let prepared = BackgroundImage.prepared(original)
        let size = pixelSize(prepared)

        XCTAssertEqual(size.width / size.height, 2, accuracy: 0.01)
    }

    /// Both sides are capped, so nothing comes back longer than the limit in any
    /// direction.
    func testNeverExceedsTheLimitOnEitherSide() {
        for (width, height) in [(4032.0, 3024.0), (3024.0, 4032.0), (8000.0, 400.0)] {
            let size = pixelSize(BackgroundImage.prepared(image(width: width, height: height)))

            XCTAssertLessThanOrEqual(size.width, BackgroundImage.maxDimension)
            XCTAssertLessThanOrEqual(size.height, BackgroundImage.maxDimension)
        }
    }

    /// An extremely long, thin picture keeps at least one pixel on its short side.
    /// Rounding it to zero would render as nothing at all rather than as something
    /// small.
    func testKeepsAtLeastOnePixelOnTheShortSide() {
        let size = pixelSize(BackgroundImage.prepared(image(width: 20000, height: 3)))

        XCTAssertEqual(size.width, BackgroundImage.maxDimension)
        XCTAssertGreaterThanOrEqual(size.height, 1)
    }

    // MARK: - Leaving well alone

    /// Never scales up. A small picture is worth exactly what it already is, and
    /// resampling it larger would cost bytes for no detail.
    func testLeavesASmallImageAlone() {
        let original = image(width: 600, height: 400)
        let prepared = BackgroundImage.prepared(original)

        XCTAssertTrue(prepared === original)
    }

    /// An image exactly at the limit is already within it, so it is handed back
    /// untouched rather than re-encoded to the same size.
    func testLeavesAnImageAtTheLimitAlone() {
        let original = image(
            width: BackgroundImage.maxDimension,
            height: BackgroundImage.maxDimension
        )

        XCTAssertTrue(BackgroundImage.prepared(original) === original)
    }

    // MARK: - Pixels, not points

    /// Measured in pixels rather than points. A 3× image reports a third of its
    /// pixel size in `size`, so measuring the wrong one would let it through at
    /// three times the cap.
    func testMeasuresPixelsRatherThanPoints() {
        // 1800×1800 pixels described as 600×600 points at 3×. Under the cap by
        // points, over it by pixels.
        let original = image(width: 1800, height: 1800, scale: 3)

        XCTAssertEqual(original.size.width, 600, accuracy: 0.5)

        let size = pixelSize(BackgroundImage.prepared(original))

        XCTAssertEqual(size.width, BackgroundImage.maxDimension)
        XCTAssertEqual(size.height, BackgroundImage.maxDimension)
    }

    /// And a 3× image that is genuinely small in pixels is still left alone, so the
    /// rule above does not simply scale everything with a scale factor.
    func testLeavesASmallHighScaleImageAlone() {
        let original = image(width: 900, height: 900, scale: 3)

        XCTAssertTrue(BackgroundImage.prepared(original) === original)
    }

    // MARK: - What it saves

    /// The point of all of it, end to end: the bytes a note actually stores. The
    /// form encodes the background at `jpegData(compressionQuality: 0.8)`, so this
    /// asserts against that same encoding.
    func testShrinksTheBytesANoteWouldStore() throws {
        // Noise rather than a flat fill, so JPEG has something real to compress and
        // the comparison is not decided by an artificially compressible source.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024))
        let photo = renderer.image { context in
            for _ in 0..<4000 {
                UIColor(
                    red: .random(in: 0...1),
                    green: .random(in: 0...1),
                    blue: .random(in: 0...1),
                    alpha: 1
                ).setFill()
                context.fill(
                    CGRect(
                        x: .random(in: 0...4032),
                        y: .random(in: 0...3024),
                        width: .random(in: 10...120),
                        height: .random(in: 10...120)
                    )
                )
            }
        }

        let before = try XCTUnwrap(photo.jpegData(compressionQuality: 0.8)).count
        let after = try XCTUnwrap(
            BackgroundImage.prepared(photo).jpegData(compressionQuality: 0.8)
        ).count

        XCTAssertLessThan(after, before)
        // Deliberately loose. What is being asserted is the order of magnitude —
        // the pixel count falls by around 8× here — not a particular JPEG's exact
        // output, which no test should be pinned to.
        XCTAssertLessThan(after, before / 2)
    }

    // MARK: - Off the main actor

    /// The asynchronous entry points hand back what the pure rule does. They exist
    /// only to move the work off the main actor, so they must not decide anything
    /// of their own.
    func testAsyncEntryPointMatchesTheRule() async {
        let original = image(width: 4032, height: 3024)
        let expected = pixelSize(BackgroundImage.prepared(original))

        let prepared = await BackgroundImage.prepare(original)

        XCTAssertEqual(pixelSize(prepared), expected)
    }

    /// The data entry point decodes and then applies the same rule.
    func testAsyncDataEntryPointDecodesAndScales() async throws {
        let data = try XCTUnwrap(
            image(width: 4032, height: 3024).jpegData(compressionQuality: 0.9)
        )

        // Awaited before it is unwrapped: `XCTUnwrap` takes an autoclosure, which
        // cannot carry the suspension.
        let decoded = await BackgroundImage.prepare(data: data)
        let size = pixelSize(try XCTUnwrap(decoded))

        XCTAssertEqual(size.width, BackgroundImage.maxDimension)
        XCTAssertLessThanOrEqual(size.height, BackgroundImage.maxDimension)
    }

    /// Bytes that are not an image produce nothing, rather than a blank picture the
    /// note would then store.
    func testAsyncDataEntryPointRejectsNonImageBytes() async {
        let prepared = await BackgroundImage.prepare(data: Data("not an image".utf8))

        XCTAssertNil(prepared)
    }
}
