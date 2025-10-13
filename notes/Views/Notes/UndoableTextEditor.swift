//
//  UndoableTextEditor.swift
//  notes
//
//  Created by Robert Libšanský on 13.10.2025.
//

import SwiftUI

struct UndoableTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var undoManager: Binding<UndoManager?>?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        // Create toolbar with formatting buttons
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let boldButton = UIBarButtonItem(
            image: UIImage(systemName: "bold"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.toggleBold)
        )

        let italicButton = UIBarButtonItem(
            image: UIImage(systemName: "italic"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.toggleItalic)
        )

        let underlineButton = UIBarButtonItem(
            image: UIImage(systemName: "underline"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.toggleUnderline)
        )

        let strikethroughButton = UIBarButtonItem(
            image: UIImage(systemName: "strikethrough"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.toggleStrikethrough)
        )

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

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [boldButton, italicButton, underlineButton, strikethroughButton, checkboxButton, flexSpace, undoButton, redoButton]
        textView.inputAccessoryView = toolbar

        context.coordinator.textView = textView
        context.coordinator.undoButton = undoButton
        context.coordinator.redoButton = redoButton

        // Add tap gesture recognizer for checkboxes
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)

        // Store reference to undoManager
        DispatchQueue.main.async {
            self.undoManager?.wrappedValue = textView.undoManager
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        // Update placeholder visibility
        if text.isEmpty && !uiView.isFirstResponder {
            uiView.text = placeholder
            uiView.textColor = UIColor.placeholderText
        } else if uiView.text == placeholder && uiView.isFirstResponder {
            uiView.text = ""
            uiView.textColor = UIColor.label
        } else if !text.isEmpty {
            uiView.textColor = UIColor.label
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: UndoableTextEditor
        weak var textView: UITextView?
        weak var undoButton: UIBarButtonItem?
        weak var redoButton: UIBarButtonItem?

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

            let uncheckedBox = "▢"
            let checkedBox = "▣"

            // Check if tap was on a checkbox line and near the beginning
            if lineText.hasPrefix(uncheckedBox + " ") || lineText.hasPrefix(checkedBox + " ") {
                // Calculate if tap was near the checkbox (first 30 points)
                let tapX = location.x
                if tapX < 30 {
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

        @objc func toggleBold() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }

            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let existingAttributes = attributedText.attributes(at: selectedRange.location, effectiveRange: nil)

            if let existingFont = existingAttributes[.font] as? UIFont {
                let isBold = existingFont.fontDescriptor.symbolicTraits.contains(.traitBold)
                let newFont: UIFont

                if isBold {
                    // Remove bold
                    if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(existingFont.fontDescriptor.symbolicTraits.subtracting(.traitBold)) {
                        newFont = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                    } else {
                        newFont = existingFont
                    }
                } else {
                    // Add bold
                    if let descriptor = existingFont.fontDescriptor.withSymbolicTraits([existingFont.fontDescriptor.symbolicTraits, .traitBold]) {
                        newFont = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                    } else {
                        newFont = existingFont
                    }
                }

                attributedText.addAttribute(.font, value: newFont, range: selectedRange)
            } else {
                // No existing font, add bold system font
                let boldFont = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)
                attributedText.addAttribute(.font, value: boldFont, range: selectedRange)
            }

            textView.attributedText = attributedText
            textView.selectedRange = selectedRange
            parent.text = textView.text
        }

        @objc func toggleItalic() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }

            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let existingAttributes = attributedText.attributes(at: selectedRange.location, effectiveRange: nil)

            if let existingFont = existingAttributes[.font] as? UIFont {
                let isItalic = existingFont.fontDescriptor.symbolicTraits.contains(.traitItalic)
                let newFont: UIFont

                if isItalic {
                    // Remove italic
                    if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(existingFont.fontDescriptor.symbolicTraits.subtracting(.traitItalic)) {
                        newFont = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                    } else {
                        newFont = existingFont
                    }
                } else {
                    // Add italic
                    if let descriptor = existingFont.fontDescriptor.withSymbolicTraits([existingFont.fontDescriptor.symbolicTraits, .traitItalic]) {
                        newFont = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                    } else {
                        newFont = existingFont
                    }
                }

                attributedText.addAttribute(.font, value: newFont, range: selectedRange)
            } else {
                // No existing font, add italic system font
                let italicFont = UIFont.italicSystemFont(ofSize: UIFont.systemFontSize)
                attributedText.addAttribute(.font, value: italicFont, range: selectedRange)
            }

            textView.attributedText = attributedText
            textView.selectedRange = selectedRange
            parent.text = textView.text
        }

        @objc func toggleUnderline() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }

            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let existingAttributes = attributedText.attributes(at: selectedRange.location, effectiveRange: nil)

            if existingAttributes[.underlineStyle] != nil {
                // Remove underline
                attributedText.removeAttribute(.underlineStyle, range: selectedRange)
            } else {
                // Add underline
                attributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }

            textView.attributedText = attributedText
            textView.selectedRange = selectedRange
            parent.text = textView.text
        }

        @objc func toggleStrikethrough() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }

            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let existingAttributes = attributedText.attributes(at: selectedRange.location, effectiveRange: nil)

            if existingAttributes[.strikethroughStyle] != nil {
                // Remove strikethrough
                attributedText.removeAttribute(.strikethroughStyle, range: selectedRange)
            } else {
                // Add strikethrough
                attributedText.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }

            textView.attributedText = attributedText
            textView.selectedRange = selectedRange
            parent.text = textView.text
        }

        @objc func toggleCheckbox() {
            guard let textView = textView else { return }

            let text = textView.text ?? ""
            let selectedRange = textView.selectedRange
            let nsText = text as NSString

            // Use ballot box symbols which are slightly larger and clearer
            let uncheckedBox = "▢ "
            let checkedBox = "▣ "

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

            for lineRange in lineRanges {
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
            }

            textView.text = mutableText as String

            // Restore selection
            let newLocation = min(selectedRange.location, textView.text.count)
            let newLength = min(selectedRange.length + offset, textView.text.count - newLocation)
            textView.selectedRange = NSRange(location: newLocation, length: max(0, newLength))

            parent.text = textView.text
        }

        func updateButtonStates() {
            undoButton?.isEnabled = textView?.undoManager?.canUndo ?? false
            redoButton?.isEnabled = textView?.undoManager?.canRedo ?? false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateButtonStates()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = UIColor.label
            }
            updateButtonStates()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
        }
    }
}
