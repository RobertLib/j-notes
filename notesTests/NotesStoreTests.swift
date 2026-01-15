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

    // MARK: - Export/Import Tests (Version 1.0.8)

    func testExportNotes() {
        // Add test notes
        store.add(title: "Test 1", content: "Content 1", color: .blue, isColorOn: true)
        store.add(title: "Test 2", content: "Content 2", color: .green, isColorOn: true)

        // Export notes
        let exportData = store.exportNotes()

        // Verify data was created
        XCTAssertNotNil(exportData)
        XCTAssertGreaterThan(exportData?.count ?? 0, 0)

        // Verify data is valid JSON
        if let data = exportData {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testImportNotesMerge() {
        // Add existing note
        store.add(title: "Existing", content: "Content")
        let initialCount = store.notes.count

        // Create test data for import
        let importNotes = [
            NoteModel(title: "Imported 1", content: "Content 1", color: .blue),
            NoteModel(title: "Imported 2", content: "Content 2", color: .green)
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let importData = try! encoder.encode(importNotes)

        // Import with merge (replaceExisting: false)
        let success = store.importNotes(from: importData, replaceExisting: false)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, initialCount + 2)
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Existing" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Imported 1" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Imported 2" }))
    }

    func testImportNotesReplace() {
        // Add existing notes
        store.add(title: "Existing 1", content: "Content")
        store.add(title: "Existing 2", content: "Content")

        // Create test data for import
        let importNotes = [
            NoteModel(title: "New 1", content: "Content 1", color: .blue),
            NoteModel(title: "New 2", content: "Content 2", color: .green)
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let importData = try! encoder.encode(importNotes)

        // Import with replace (replaceExisting: true)
        let success = store.importNotes(from: importData, replaceExisting: true)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertFalse(store.notes.contains(where: { $0.title == "Existing 1" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "New 1" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "New 2" }))
    }

    func testImportNotesDuplicatePrevention() {
        // Add a note
        store.add(title: "Test", content: "Content")
        let note = store.notes.last!

        // Create import data with same ID (duplicate)
        let importNotes = [
            NoteModel(
                id: note.id, // Same ID as existing note
                createdAt: note.createdAt,
                title: "Duplicate",
                content: "Content",
                pinned: false,
                color: .blue,
                isDeleted: false,
                deletedAt: nil
            )
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let importData = try! encoder.encode(importNotes)

        let initialCount = store.notes.count

        // Import with merge - duplicate should not be added
        let success = store.importNotes(from: importData, replaceExisting: false)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, initialCount) // Count should not change
    }

    func testExportImportRoundTrip() {
        // Add notes with various properties
        store.add(title: "Note 1", content: "Content 1", color: .blue, isColorOn: true)
        store.add(title: "Note 2", content: "Content 2", color: .green, isColorOn: true)
        let note = store.notes.last!
        store.update(note: note, pinned: true)

        let originalCount = store.notes.count
        let originalTitles = Set(store.notes.map { $0.title })

        // Export
        guard let exportData = store.exportNotes() else {
            XCTFail("Export failed")
            return
        }

        // Delete all notes
        let notesToRemove = store.notes
        for note in notesToRemove {
            store.remove(note: note)
        }
        XCTAssertEqual(store.notes.count, 0)

        // Import back
        let success = store.importNotes(from: exportData, replaceExisting: false)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, originalCount)
        XCTAssertEqual(Set(store.notes.map { $0.title }), originalTitles)

        // Verify that pinned note remained pinned
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Note 2" && $0.pinned }))
    }

    func testImportInvalidData() {
        let invalidData = "This is not JSON".data(using: .utf8)!

        let success = store.importNotes(from: invalidData, replaceExisting: false)

        XCTAssertFalse(success)
        XCTAssertNotNil(store.saveError)
    }

    func testSetError() {
        store.setError("Test error message")
        XCTAssertEqual(store.saveError, "Test error message")
    }
}
