//
//  ChecklistItemTests.swift
//  notesTests
//

import XCTest
@testable import J_Notes

/// How a note's body spells a checklist line. The two box glyphs used to be
/// written out at four call sites, which is the arrangement `redactedBody` exists
/// to warn about — one spelling drifts and the same line reads as a checkbox in one
/// view and as ordinary text in the next.
final class ChecklistItemTests: XCTestCase {

    func testAnUncheckedLineIsRecognised() {
        let item = ChecklistItem(line: "▢ Buy milk")

        XCTAssertEqual(item?.box, .unchecked)
        XCTAssertEqual(item?.label, "Buy milk")
        XCTAssertEqual(item?.isChecked, false)
    }

    func testACheckedLineIsRecognised() {
        let item = ChecklistItem(line: "▣ Buy milk")

        XCTAssertEqual(item?.box, .checked)
        XCTAssertEqual(item?.label, "Buy milk")
        XCTAssertEqual(item?.isChecked, true)
    }

    func testOrdinaryTextIsNotAChecklistItem() {
        XCTAssertNil(ChecklistItem(line: "Buy milk"))
        XCTAssertNil(ChecklistItem(line: ""))
    }

    /// The marker is the glyph *and* the space after it. A glyph on its own is a
    /// character the user typed, not a checkbox — and treating it as one would put a
    /// tappable row where they wrote text.
    func testABoxWithoutItsSeparatingSpaceIsNotAChecklistItem() {
        XCTAssertNil(ChecklistItem(line: "▢"))
        XCTAssertNil(ChecklistItem(line: "▢Buy milk"))
    }

    func testLeadingWhitespaceIsNotSkipped() {
        XCTAssertNil(ChecklistItem(line: " ▢ Buy milk"))
    }

    // MARK: - Round-tripping

    func testTheLineIsRebuiltExactlyAsItWasRead() {
        for line in ["▢ Buy milk", "▣ Buy milk", "▢ ", "▣ ▢ nested-looking text"] {
            XCTAssertEqual(ChecklistItem(line: line)?.line, line)
        }
    }

    func testTogglingSwapsTheBoxAndKeepsTheText() {
        let unchecked = ChecklistItem(line: "▢ Buy milk")

        XCTAssertEqual(unchecked?.toggled.line, "▣ Buy milk")
        XCTAssertEqual(unchecked?.toggled.toggled.line, "▢ Buy milk")
    }

    /// The label is what VoiceOver reads and what the detail view draws beside the
    /// box, so a marker occurring later in the line must survive as text.
    func testOnlyTheLeadingMarkerIsTakenOff() {
        let item = ChecklistItem(line: "▢ ▢ two boxes")

        XCTAssertEqual(item?.label, "▢ two boxes")
        XCTAssertEqual(item?.toggled.line, "▣ ▢ two boxes")
    }

    func testAnEmptyLabelSurvivesTheRoundTrip() {
        let item = ChecklistItem(line: "▢ ")

        XCTAssertEqual(item?.label, "")
        XCTAssertEqual(item?.toggled.line, "▣ ")
    }

    // MARK: - The markers themselves

    /// The editor measures its tap zone from `marker`, and the detail view draws
    /// `rawValue` — so the two have to be the glyph and the glyph plus one space,
    /// not two independent strings.
    func testEachMarkerIsItsGlyphFollowedByASingleSpace() {
        for box in ChecklistItem.Box.allCases {
            XCTAssertEqual(box.marker, box.rawValue + " ")
            XCTAssertEqual(box.marker.count, 2)
        }
    }

    func testTheTwoBoxesAreDistinct() {
        XCTAssertNotEqual(
            ChecklistItem.Box.checked.rawValue,
            ChecklistItem.Box.unchecked.rawValue
        )
        XCTAssertEqual(ChecklistItem.Box.unchecked.toggled, .checked)
        XCTAssertEqual(ChecklistItem.Box.checked.toggled, .unchecked)
    }
}
