//
//  ReminderFormStateTests.swift
//  notesTests
//

import XCTest
@testable import J_Notes

/// The note form's reminder rule. Regression cover for a silent data loss: a note
/// whose reminder had already passed opened with the toggle off, and saving any
/// other field then cleared the date — so correcting a typo in the title removed
/// the note from the calendar for that day, without a word.
final class ReminderFormStateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var future: Date { now.addingTimeInterval(3600) }
    private var past: Date { now.addingTimeInterval(-3600) }

    // MARK: - Where the toggle starts

    func testToggleStartsOffForANoteWithoutAReminder() {
        let state = ReminderFormState(reminder: nil, now: now)

        XCTAssertFalse(state.isOnInitially)
        XCTAssertFalse(state.startedElapsed)
    }

    func testToggleStartsOnForAPendingReminder() {
        let state = ReminderFormState(reminder: future, now: now)

        XCTAssertTrue(state.isOnInitially)
        XCTAssertFalse(state.startedElapsed)
    }

    /// An elapsed reminder has nothing left to fire, so the toggle reads as off —
    /// but the form has to remember why.
    func testToggleStartsOffForAnElapsedReminderButRemembersIt() {
        let state = ReminderFormState(reminder: past, now: now)

        XCTAssertFalse(state.isOnInitially)
        XCTAssertTrue(state.startedElapsed)
    }

    // MARK: - What a save does with the stored date

    /// The regression itself: saving an untouched form must not erase the date.
    func testAnUntouchedElapsedReminderIsKept() {
        let state = ReminderFormState(reminder: past, now: now)

        XCTAssertTrue(
            state.keepsStoredReminder(isReminderOn: false, didTouchToggle: false),
            "An edit that never touched the toggle must leave the date alone"
        )
    }

    /// Switching the toggle off is an explicit instruction, elapsed or not —
    /// otherwise a past reminder could never be removed.
    func testDeliberatelyClearingAnElapsedReminderIsHonoured() {
        let state = ReminderFormState(reminder: past, now: now)

        XCTAssertFalse(
            state.keepsStoredReminder(isReminderOn: false, didTouchToggle: true)
        )
    }

    /// Toggling an elapsed reminder back on replaces the date, so there is
    /// nothing to protect.
    func testReArmingAnElapsedReminderReplacesTheDate() {
        let state = ReminderFormState(reminder: past, now: now)

        XCTAssertFalse(
            state.keepsStoredReminder(isReminderOn: true, didTouchToggle: true)
        )
    }

    /// A reminder that was still pending when the form opened has no reason to be
    /// protected: the toggle only reads off because the user switched it off.
    func testTurningOffAPendingReminderClearsIt() {
        let state = ReminderFormState(reminder: future, now: now)

        XCTAssertFalse(
            state.keepsStoredReminder(isReminderOn: false, didTouchToggle: true)
        )
        // Belt and braces: even without the touch flag, a note that never had an
        // elapsed reminder must not have its clearing suppressed.
        XCTAssertFalse(
            state.keepsStoredReminder(isReminderOn: false, didTouchToggle: false)
        )
    }

    func testANoteWithoutAReminderIsNeverProtected() {
        let state = ReminderFormState(reminder: nil, now: now)

        XCTAssertFalse(
            state.keepsStoredReminder(isReminderOn: false, didTouchToggle: false)
        )
    }
}

/// What the form counts as enough to save. The Save button and `submit()` both
/// go through this, so a note can never look saveable and then be refused — or
/// the other way round, which is what happened to a drawing that was only a
/// photo.
final class NoteContentRuleTests: XCTestCase {

    private func hasContent(
        type: NoteType,
        content: String = "",
        strokes: Bool = false,
        image: Bool = false
    ) -> Bool {
        NoteContentRule.hasContentToSave(
            type: type,
            trimmedContent: content,
            hasStrokes: strokes,
            hasBackgroundImage: image
        )
    }

    // MARK: - Text notes

    func testATextNoteNeedsABody() {
        XCTAssertTrue(hasContent(type: .text, content: "Milk"))
        XCTAssertFalse(hasContent(type: .text, content: ""))
    }

    /// A drawing's picture is no substitute for a text note's body: the text
    /// editor is what a text note shows, and a blank one renders as an empty row
    /// with nothing to open.
    func testATextNoteIsNotSavedByADrawingsLeftovers() {
        XCTAssertFalse(hasContent(type: .text, content: "", strokes: true, image: true))
    }

    // MARK: - Drawing notes

    func testADrawingWithStrokesCanBeSaved() {
        XCTAssertTrue(hasContent(type: .drawing, strokes: true))
    }

    /// The regression: a photo picked from the library or taken with the camera is
    /// the whole point of some drawing notes, and it is what they render. The Save
    /// button used to stay greyed out until the user drew on top of it, with
    /// nothing on screen explaining the refusal.
    func testADrawingThatIsOnlyABackgroundPhotoCanBeSaved() {
        XCTAssertTrue(
            hasContent(type: .drawing, image: true),
            "A photo is content — it is what the note shows"
        )
    }

    func testAnEmptyDrawingCannotBeSaved() {
        XCTAssertFalse(hasContent(type: .drawing))
    }

    /// A drawing note has no text body — `submit` stores an empty string for it —
    /// so text typed before the type was switched over must not stand in for a
    /// picture that is not there.
    func testADrawingIsNotSavedByTextTypedBeforeTheSwitch() {
        XCTAssertFalse(hasContent(type: .drawing, content: "Typed as text first"))
    }
}
