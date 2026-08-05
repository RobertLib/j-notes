//
//  UndoableTextEditorTests.swift
//  notesTests
//

import XCTest
import SwiftUI
@testable import J_Notes

@MainActor
final class UndoableTextEditorTests: XCTestCase {

    private let placeholder = "Content"

    /// Builds a coordinator wired to a text view and placeholder label the same
    /// way `makeUIView` does, without needing a SwiftUI `Context`.
    private func makeCoordinator(
        text: Binding<String>
    ) -> (UndoableTextEditor, UndoableTextEditor.Coordinator, UITextView, UILabel) {
        let editor = UndoableTextEditor(text: text, placeholder: placeholder)
        let coordinator = editor.makeCoordinator()

        let textView = UITextView()
        textView.text = text.wrappedValue
        let label = UILabel()
        label.text = placeholder

        coordinator.textView = textView
        coordinator.placeholderLabel = label
        coordinator.updatePlaceholderVisibility()

        return (editor, coordinator, textView, label)
    }

    func testPlaceholderShowsOnlyWhileEmpty() {
        var stored = ""
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, label) = makeCoordinator(text: binding)
        XCTAssertFalse(label.isHidden, "An empty editor must show its placeholder")

        textView.text = "Milk"
        coordinator.textViewDidChange(textView)

        XCTAssertTrue(label.isHidden)
        XCTAssertEqual(stored, "Milk")
    }

    /// The regression this guards: the placeholder used to be written into the
    /// text view itself, so typing the placeholder word was read back as "empty"
    /// and the visible text was wiped.
    func testTypingThePlaceholderWordIsKeptAsRealContent() {
        var stored = ""
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, label) = makeCoordinator(text: binding)

        textView.text = placeholder
        coordinator.textViewDidChange(textView)

        XCTAssertEqual(textView.text, placeholder, "Content equal to the placeholder must survive")
        XCTAssertEqual(stored, placeholder, "…and must reach the binding")
        XCTAssertTrue(label.isHidden, "The placeholder must not be drawn over real content")
    }

    /// A SwiftUI update pass over content equal to the placeholder is exactly
    /// what used to blank the editor.
    func testSyncKeepsContentEqualToThePlaceholder() {
        let binding = Binding(get: { self.placeholder }, set: { _ in })

        let (editor, coordinator, textView, label) = makeCoordinator(text: binding)
        editor.sync(textView, coordinator: coordinator)

        XCTAssertEqual(textView.text, placeholder, "A redraw must not wipe placeholder-shaped content")
        XCTAssertTrue(label.isHidden)
        XCTAssertEqual(textView.textColor, .label, "Real content must not be drawn in placeholder grey")
    }

    // MARK: - Checklist toggling

    /// Toggling used to assign straight to `textView.text`, which bypasses the
    /// undo manager: the toolbar's undo button could not reverse a toggle, and
    /// the edits made before it were dropped from the stack too.
    func testTogglingACheckboxCanBeUndone() {
        var stored = "▢ Milk"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, _) = makeCoordinator(text: binding)
        textView.selectedRange = NSRange(location: 0, length: 0)

        coordinator.toggleCheckbox()
        XCTAssertEqual(textView.text, "▣ Milk")
        XCTAssertEqual(stored, "▣ Milk")

        XCTAssertTrue(textView.undoManager?.canUndo ?? false, "The toggle must land on the undo stack")

        textView.undoManager?.undo()
        XCTAssertEqual(textView.text, "▢ Milk", "Undo must put the checkbox back")
    }

    /// Selection offsets are UTF-16, and `String.count` counts characters. The
    /// two agree right up until the note holds an emoji, and the clamp built
    /// from the wrong one used to land the cursor in the wrong place — or past
    /// the end of the text.
    func testTogglingKeepsTheSelectionValidAroundEmoji() {
        var stored = "🎉 Party 🎈 time"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, _) = makeCoordinator(text: binding)
        let caret = (stored as NSString).length
        textView.selectedRange = NSRange(location: caret, length: 0)

        coordinator.toggleCheckbox()

        XCTAssertEqual(textView.text, "▢ 🎉 Party 🎈 time")

        let selection = textView.selectedRange
        let length = (textView.text as NSString).length
        XCTAssertLessThanOrEqual(
            selection.location + selection.length,
            length,
            "The restored selection must stay inside the text"
        )
    }

    // MARK: - Where the cursor ends up

    /// The regression: adding a checkbox used to grow the *selection* by the two
    /// characters it inserted rather than move the caret past them, so a caret
    /// came back as a two-character selection sitting over the text just typed.
    /// Tapping the checklist button and carrying on typing replaced those two
    /// characters instead of appending to the line.
    func testACaretStaysACaretAfterAddingACheckbox() {
        var stored = "Milk"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, _) = makeCoordinator(text: binding)
        textView.selectedRange = NSRange(location: 4, length: 0)

        coordinator.toggleCheckbox()

        XCTAssertEqual(textView.text, "▢ Milk")
        XCTAssertEqual(
            textView.selectedRange,
            NSRange(location: 6, length: 0),
            "The caret must follow the inserted checkbox, not select the text behind it"
        )
    }

    /// A caret at the very start of the line lands after the checkbox, where the
    /// item's own text begins — not in front of a box the user is about to type
    /// over.
    func testACaretAtTheLineStartLandsAfterTheCheckbox() {
        var stored = "Milk"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, _) = makeCoordinator(text: binding)
        textView.selectedRange = NSRange(location: 0, length: 0)

        coordinator.toggleCheckbox()

        XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 0))
    }

    /// The mirror case, and the reason the caret is clamped: removing a checkbox
    /// shortens the line, so a caret sitting at its start would be pushed to a
    /// negative offset.
    func testRemovingACheckboxKeepsTheCaretInsideTheText() {
        var stored = "▣ Milk"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, _) = makeCoordinator(text: binding)
        textView.selectedRange = NSRange(location: 0, length: 0)

        coordinator.toggleCheckbox()

        XCTAssertEqual(textView.text, "Milk")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 0))
    }

    /// A real selection is not a caret and keeps the old rule: it grows by the
    /// whole batch so it still covers the lines it covered, checkboxes included.
    func testAMultiLineSelectionStillCoversItsLines() {
        var stored = "Milk\nEggs"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (_, coordinator, textView, _) = makeCoordinator(text: binding)
        textView.selectedRange = NSRange(location: 0, length: 9)

        coordinator.toggleCheckbox()

        XCTAssertEqual(textView.text, "▢ Milk\n▢ Eggs")
        XCTAssertEqual(
            textView.selectedRange,
            NSRange(location: 0, length: 13),
            "Both lines, both checkboxes, must stay selected"
        )
    }

    /// The mirror case: an empty binding brings the placeholder back without
    /// pushing its text into the note.
    func testSyncShowsPlaceholderForAnEmptyBinding() {
        var stored = "Milk"
        let binding = Binding(get: { stored }, set: { stored = $0 })

        let (editor, coordinator, textView, label) = makeCoordinator(text: binding)
        XCTAssertTrue(label.isHidden)

        stored = ""
        editor.sync(textView, coordinator: coordinator)

        XCTAssertTrue(textView.text.isEmpty, "The placeholder must never become the note's text")
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(stored, "")
    }

    // MARK: - Where a tap ticks a line off

    private func bodyFont(_ category: UIContentSizeCategory) -> UIFont {
        UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
    }

    /// The zone in which a tap toggles the box has to be as wide as the box the
    /// user is aiming at. It was a flat 30 points, which is about right for the
    /// body font at its default size and wrong at every other — so at the
    /// accessibility sizes the box outgrew its own hit zone and its right-hand
    /// side stopped toggling anything.
    func testTheCheckboxHitZoneGrowsWithTheFont() {
        let small = UndoableTextEditor.checkboxHitWidth(
            font: bodyFont(.extraSmall),
            leadingInset: 5
        )
        let large = UndoableTextEditor.checkboxHitWidth(
            font: bodyFont(.accessibilityExtraExtraExtraLarge),
            leadingInset: 5
        )

        XCTAssertLessThan(
            small,
            large,
            "The box grows with the text it sits in, so the zone has to grow with it"
        )
        XCTAssertGreaterThan(
            large,
            30,
            "The size at which the old fixed 30 points no longer reached across the box"
        )
        XCTAssertLessThan(
            small,
            30,
            "...and the size at which they reached well past it, into the text"
        )
    }

    /// The box is drawn after the text container's own leading inset, so the zone
    /// starts where the text does rather than at the view's edge.
    func testTheCheckboxHitZoneStartsWhereTheTextDoes() {
        let font = bodyFont(.large)

        XCTAssertEqual(
            UndoableTextEditor.checkboxHitWidth(font: font, leadingInset: 12)
                - UndoableTextEditor.checkboxHitWidth(font: font, leadingInset: 0),
            12,
            accuracy: 0.001
        )
    }
}
