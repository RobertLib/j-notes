//
//  NotesStoreTests.swift
//  notesTests
//
//  Created by Robert Libšanský on 04.10.2025.
//

import XCTest
import SwiftUI
@testable import J_Notes

@MainActor
final class NotesStoreTests: XCTestCase {

    var store: NotesStore!

    override func setUpWithError() throws {
        store = NotesStore()
    }

    func testAddNote() {
        let initialCount = store.notes.count
        store.add(title: "Test Note", content: "Test Content")
        XCTAssertEqual(store.notes.count, initialCount + 1)
    }

    func testUpdateNote() {
        store.add(title: "Original", content: "Content")
        let note = store.notes.last!
        store.update(note: note, title: "Updated")
        let updated = store.notes.first(where: { $0.id == note.id })
        XCTAssertEqual(updated?.title, "Updated")
    }

    func testRemoveNote() {
        store.add(title: "To Remove", content: "Content")
        let note = store.notes.last!
        store.remove(note: note)
        XCTAssertNil(store.notes.first(where: { $0.id == note.id }))
    }
}
