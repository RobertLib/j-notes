//
//  NoteModelTests.swift
//  notesTests
//
//  Created by Robert Libšanský on 04.10.2025.
//

import XCTest
import CoreLocation
import SwiftUI
@testable import J_Notes

final class NoteModelTests: XCTestCase {

    func testNoteModelInitialization() {
        let note = NoteModel(title: "Test Note", content: "Test Content")

        XCTAssertNotNil(note.id)
        XCTAssertEqual(note.title, "Test Note")
        XCTAssertEqual(note.content, "Test Content")
        XCTAssertFalse(note.pinned)
    }

    func testCoordinateWithValidLocation() {
        let note = NoteModel(
            title: "Prague Note",
            content: "Located in Prague",
            location: [50.0495641, 14.4362814]
        )

        XCTAssertEqual(note.coordinate.latitude, 50.0495641, accuracy: 0.0001)
        XCTAssertEqual(note.coordinate.longitude, 14.4362814, accuracy: 0.0001)
    }
}
