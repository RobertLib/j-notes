//
//  UndoableTextEditor.swift
//  notes
//
//  Created by Robert Libšanský on 13.10.2025.
//

import SwiftUI

/// A text editor with its own undo/redo and checklist toolbar.
///
/// The text view's `UndoManager` is deliberately not published outwards: undo is
/// driven entirely by the toolbar below, so a binding for it had nothing to read
/// it.
struct UndoableTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        // The font is resolved once, here, and `sync` does not revisit it — so
        // without this the editor kept whatever size was current when it was
        // built. Changing the text size in Settings and coming back left the one
        // screen the user actually writes on at the old size, until something
        // happened to rebuild the form.
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        // Create toolbar with checklist and undo/redo buttons
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let checkboxButton = UIBarButtonItem(
            image: UIImage(systemName: "checklist"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.toggleCheckbox)
        )

        let undoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.undoTapped)
        )

        let redoButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.redoTapped)
        )

        // Icon-only bar buttons announce as the raw symbol name without these.
        checkboxButton.accessibilityLabel = String(localized: "checklist")
        undoButton.accessibilityLabel = String(localized: "undo")
        redoButton.accessibilityLabel = String(localized: "redo")

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [checkboxButton, flexSpace, undoButton, redoButton]
        textView.inputAccessoryView = toolbar

        // The placeholder lives in its own label rather than in `text`. Writing
        // it into the text view meant content that happened to equal the
        // placeholder ("Content", "Obsah") was mistaken for empty and wiped.
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = textView.font
        // Grows with the text it stands in for — see the text view above.
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        let inset = textView.textContainerInset
        let padding = textView.textContainer.lineFragmentPadding
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: inset.top),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor,
                constant: inset.left + padding
            ),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: textView.trailingAnchor,
                constant: -(inset.right + padding)
            )
        ])

        textView.text = text
        textView.textColor = .label

        context.coordinator.textView = textView
        context.coordinator.undoButton = undoButton
        context.coordinator.redoButton = redoButton
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.updatePlaceholderVisibility()

        // Add tap gesture recognizer for checkboxes
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        sync(uiView, coordinator: context.coordinator)
    }

    /// Brings the text view in line with the binding. Split out of
    /// `updateUIView` so it can be exercised directly — a `Context` cannot be
    /// built in a test, and this is the code path that once mistook content
    /// equal to the placeholder for an empty editor and wiped it.
    func sync(_ uiView: UITextView, coordinator: Coordinator) {
        // Refresh the coordinator's copy so its callbacks always write through
        // the current binding.
        coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        uiView.textColor = .label
        coordinator.placeholderLabel?.text = placeholder
        coordinator.updatePlaceholderVisibility()
    }

    /// How far into a line the checkbox reaches, measured from the text view's
    /// leading edge — the zone in which a tap ticks the line off instead of
    /// placing the caret.
    ///
    /// Was a flat 30 points, which is about right for the body font at its
    /// default size and wrong at every other. By the larger accessibility sizes
    /// the box is wider than that, so its right-hand side stopped toggling
    /// anything; at the smallest sizes the zone reached well past the box into
    /// the text, where a tap meant to place the caret ticked the line off
    /// instead. Measuring the box in the font it is actually drawn in is the only
    /// spelling of this that holds at every size.
    ///
    /// Split out as a pure function for the same reason as `sync`: a `Context`
    /// cannot be built in a test, and neither can a tap.
    static func checkboxHitWidth(font: UIFont, leadingInset: CGFloat) -> CGFloat {
        let marker = ChecklistItem.Box.unchecked.marker as NSString
        return leadingInset + marker.size(withAttributes: [.font: font]).width
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: UndoableTextEditor
        weak var textView: UITextView?
        weak var undoButton: UIBarButtonItem?
        weak var redoButton: UIBarButtonItem?
        weak var placeholderLabel: UILabel?

        func updatePlaceholderVisibility() {
            placeholderLabel?.isHidden = !(textView?.text ?? "").isEmpty
        }

        init(_ parent: UndoableTextEditor) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = textView else { return }

            let location = gesture.location(in: textView)
            let position = textView.closestPosition(to: location)

            guard let position = position,
                  let range = textView.textRange(from: position, to: position) else {
                return
            }

            // Get character index
            let offset = textView.offset(from: textView.beginningOfDocument, to: range.start)
            let text = textView.text ?? ""
            let nsText = text as NSString

            // Get line range
            let lineRange = nsText.lineRange(for: NSRange(location: offset, length: 0))
            let lineText = nsText.substring(with: lineRange)

            // Check if tap was on a checkbox line and near the beginning. The two
            // markers are spelled once — see `ChecklistItem`.
            if ChecklistItem(line: lineText) != nil {
                // The width the box actually occupies in the font it is drawn in,
                // rather than a fixed 30 points — see `checkboxHitWidth`.
                let hitWidth = UndoableTextEditor.checkboxHitWidth(
                    font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
                    leadingInset: textView.textContainerInset.left
                        + textView.textContainer.lineFragmentPadding
                )

                if location.x < hitWidth {
                    // Toggle the checkbox for this line
                    textView.selectedRange = NSRange(location: lineRange.location, length: 0)
                    toggleCheckbox()
                }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        @objc func undoTapped() {
            textView?.undoManager?.undo()
            updateButtonStates()
        }

        @objc func redoTapped() {
            textView?.undoManager?.redo()
            updateButtonStates()
        }

        @objc func toggleCheckbox() {
            guard let textView = textView else { return }

            let text = textView.text ?? ""
            let selectedRange = textView.selectedRange
            let nsText = text as NSString

            // Ballot box symbols, spelled once for the whole app — see
            // `ChecklistItem`.
            let uncheckedBox = ChecklistItem.Box.unchecked.marker
            let checkedBox = ChecklistItem.Box.checked.marker

            // Find all line ranges that intersect with the selection
            var lineRanges: [NSRange] = []
            var currentLocation = selectedRange.location
            let selectionEnd = selectedRange.location + selectedRange.length

            while currentLocation < selectionEnd {
                let lineRange = nsText.lineRange(for: NSRange(location: currentLocation, length: 0))
                lineRanges.append(lineRange)
                currentLocation = lineRange.location + lineRange.length

                // Prevent infinite loop
                if lineRange.length == 0 {
                    break
                }
            }

            // If no lines found (cursor at end or empty selection), get current line
            if lineRanges.isEmpty {
                lineRanges.append(nsText.lineRange(for: selectedRange))
            }

            // Determine the action: check if first line has checkbox to decide toggle behavior
            let firstLineText = nsText.substring(with: lineRanges[0])
            let shouldAdd: Bool
            let shouldCheck: Bool

            if firstLineText.hasPrefix(uncheckedBox) {
                shouldAdd = false
                shouldCheck = true // Toggle to checked
            } else if firstLineText.hasPrefix(checkedBox) {
                shouldAdd = false
                shouldCheck = false // Remove checkbox
            } else {
                shouldAdd = true // Add unchecked checkbox
                shouldCheck = false
            }

            // Apply the same action to all lines
            let mutableText = NSMutableString(string: text)
            var offset = 0

            /// How much longer the *first* line got. The checkbox goes in at that
            /// line's start, which is at or before wherever the selection began,
            /// so this is the part of `offset` that lands ahead of the caret and
            /// therefore has to move it along. The rest lands after it.
            var firstLineDelta = 0

            for (index, lineRange) in lineRanges.enumerated() {
                let adjustedRange = NSRange(location: lineRange.location + offset, length: lineRange.length)
                let lineText = mutableText.substring(with: adjustedRange)
                let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)

                // Skip empty lines
                if trimmedLine.isEmpty {
                    continue
                }

                var newLineText = lineText

                if shouldAdd {
                    // Add unchecked checkbox if not already present
                    if !lineText.hasPrefix(uncheckedBox) && !lineText.hasPrefix(checkedBox) {
                        newLineText = uncheckedBox + lineText
                    }
                } else if shouldCheck {
                    // Toggle unchecked to checked
                    if lineText.hasPrefix(uncheckedBox) {
                        newLineText = checkedBox + String(lineText.dropFirst(uncheckedBox.count))
                    }
                } else {
                    // Remove checkbox
                    if lineText.hasPrefix(checkedBox) {
                        newLineText = String(lineText.dropFirst(checkedBox.count))
                    } else if lineText.hasPrefix(uncheckedBox) {
                        newLineText = String(lineText.dropFirst(uncheckedBox.count))
                    }
                }

                // Replace the line
                let lengthDifference = (newLineText as NSString).length - adjustedRange.length
                mutableText.replaceCharacters(in: adjustedRange, with: newLineText)
                offset += lengthDifference

                if index == 0 { firstLineDelta = lengthDifference }
            }

            // Routed through the text view's own text-input API rather than
            // assigned to `.text`: a direct assignment bypasses the undo
            // manager, so the toolbar's undo button could not reverse a toggle
            // and the edits made before it were dropped from the stack too.
            if let documentRange = textView.textRange(
                from: textView.beginningOfDocument,
                to: textView.endOfDocument
            ) {
                textView.replace(documentRange, withText: mutableText as String)
            } else {
                textView.text = mutableText as String
            }

            // Restore selection. Measured in UTF-16 units to match the NSRange
            // offsets above — `String.count` counts characters, and the two
            // drift apart as soon as the note holds an emoji.
            let length = (textView.text as NSString).length

            if selectedRange.length == 0 {
                // A caret has to stay a caret, riding along with what was
                // inserted ahead of it. Growing the *length* by `offset` — the
                // rule the selection below needs — turned it into a two-character
                // selection sitting over the text just typed, so tapping the
                // checklist button and carrying on typing replaced those two
                // characters instead of appending. `max(0,)` is for the removal
                // case, where a caret at the very start of the line would
                // otherwise be pushed to a negative offset.
                let caret = min(max(0, selectedRange.location + firstLineDelta), length)
                textView.selectedRange = NSRange(location: caret, length: 0)
            } else {
                // A real selection keeps its anchor and grows by the whole batch,
                // so it still covers the lines it covered — checkboxes included.
                let newLocation = min(selectedRange.location, length)
                let newLength = min(selectedRange.length + offset, length - newLocation)
                textView.selectedRange = NSRange(location: newLocation, length: max(0, newLength))
            }

            parent.text = textView.text
            updatePlaceholderVisibility()
            updateButtonStates()
        }

        func updateButtonStates() {
            undoButton?.isEnabled = textView?.undoManager?.canUndo ?? false
            redoButton?.isEnabled = textView?.undoManager?.canRedo ?? false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updatePlaceholderVisibility()
            updateButtonStates()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            updateButtonStates()
        }
    }
}
