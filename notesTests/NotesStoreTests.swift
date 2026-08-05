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

    /// Files the test made unreadable, so teardown can make them removable again.
    private var unreadableFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-notes-\(UUID().uuidString).json")
        store = NotesStore(fileURL: tempURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: store.fileURL)
        store = nil

        for url in unreadableFiles {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path
            )
            try? FileManager.default.removeItem(at: url)
        }
        unreadableFiles = []

        try await super.tearDown()
    }

    // MARK: - Storage-failure fixtures

    /// A notes file whose bytes cannot be read at all — what
    /// `.completeFileProtection` produces while the device is locked, and the only
    /// case a blocked store exists for. POSIX permissions raise the same
    /// `NSFileReadNoPermissionError` the real thing does.
    ///
    /// Deliberately not a file full of garbage. That reads fine and merely fails to
    /// decode, which the store now handles differently: waiting cannot help, so the
    /// file is set aside rather than blocking every write for ever. See
    /// `testAnUndecodableFileIsSetAsideSoTheAppStaysUsable`.
    private func makeUnreadableFile(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).json")

        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: url.path
        )
        unreadableFiles.append(url)

        return url
    }

    /// Makes an unreadable file readable again — for a test that has to assert on
    /// what is still in it, or hand it back to the store.
    private func makeReadable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: url.path
        )
        unreadableFiles.removeAll { $0 == url }
    }

    /// The copy the store set aside for `url`, if it set one aside.
    private func fileSetAside(for url: URL) throws -> URL? {
        let prefix = "\(url.deletingPathExtension().lastPathComponent)-unreadable-"

        return try FileManager.default
            .contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .first { $0.lastPathComponent.hasPrefix(prefix) }
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

    // MARK: - Export/Import Tests

    func testExportNotes() async {
        // Add test notes
        store.add(title: "Test 1", content: "Content 1", color: .blue, isColorOn: true)
        store.add(title: "Test 2", content: "Content 2", color: .green, isColorOn: true)

        // Export notes
        let exportData = await store.exportNotes()

        // Verify data was created
        XCTAssertNotNil(exportData)
        XCTAssertGreaterThan(exportData?.count ?? 0, 0)

        // Verify data is valid JSON
        if let data = exportData {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testImportNotesMerge() async {
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
        let success = await store.importNotes(from: importData, replaceExisting: false)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, initialCount + 2)
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Existing" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Imported 1" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Imported 2" }))
    }

    func testImportNotesReplace() async {
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
        let success = await store.importNotes(from: importData, replaceExisting: true)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertFalse(store.notes.contains(where: { $0.title == "Existing 1" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "New 1" }))
        XCTAssertTrue(store.notes.contains(where: { $0.title == "New 2" }))
    }

    func testImportNotesDuplicatePrevention() async {
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
        let success = await store.importNotes(from: importData, replaceExisting: false)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, initialCount) // Count should not change
    }

    /// A restore file is whatever the user handed over — hand-edited, or two backups
    /// concatenated — so it can carry the same note twice. `notes` is what every
    /// `ForEach` and every `firstIndex(where: { $0.id == … })` in the app indexes
    /// by, so two rows sharing one id leaves SwiftUI's list ill-defined and makes
    /// the second copy impossible to edit or delete: the lookup can only ever reach
    /// the first. Replacing used to store the file verbatim.
    func testReplacingDeduplicatesNotesRepeatedInsideTheBackup() async throws {
        let repeated = NoteModel(title: "Twice over", content: "Content")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // The same note twice, plus one that only appears once.
        let data = try encoder.encode([
            repeated,
            NoteModel(title: "Once", content: "Content"),
            repeated
        ])

        let replaced = await store.importNotes(from: data, replaceExisting: true)
        XCTAssertTrue(replaced)

        XCTAssertEqual(store.notes.count, 2)
        XCTAssertEqual(store.notes.filter { $0.id == repeated.id }.count, 1)
        XCTAssertEqual(
            Set(store.notes.map(\.id)).count,
            store.notes.count,
            "Every stored note must be reachable by its own id"
        )
    }

    /// The first copy wins, so the note the user sees is the one at the top of their
    /// backup rather than whichever the decoder happened to finish on.
    func testReplacingKeepsTheFirstOfTwoNotesSharingAnId() async throws {
        let id = UUID()
        let createdAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([
            NoteModel(id: id, createdAt: createdAt, title: "First", content: "c"),
            NoteModel(id: id, createdAt: createdAt, title: "Second", content: "c")
        ])

        let replaced = await store.importNotes(from: data, replaceExisting: true)
        XCTAssertTrue(replaced)

        XCTAssertEqual(store.notes.map(\.title), ["First"])
    }

    /// The merge path has to hold the same line as the replace path above, and for
    /// the same reason: two rows sharing one id make the second impossible to edit
    /// or delete. It got there by rescanning `notes` for each imported note, which
    /// was quadratic; the `Set` that replaced that scan has to keep counting what
    /// it has already appended, or a backup carrying the same new note twice would
    /// land it twice.
    func testMergingDeduplicatesNotesRepeatedInsideTheBackup() async throws {
        store.add(title: "Already here", content: "Content")

        let repeated = NoteModel(title: "Twice over", content: "Content")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([
            repeated,
            NoteModel(title: "Once", content: "Content"),
            repeated
        ])

        let merged = await store.importNotes(from: data, replaceExisting: false)
        XCTAssertTrue(merged)

        XCTAssertEqual(store.notes.count, 3, "One existing note plus two distinct new ones")
        XCTAssertEqual(store.notes.filter { $0.id == repeated.id }.count, 1)
        XCTAssertEqual(
            Set(store.notes.map(\.id)).count,
            store.notes.count,
            "Every stored note must be reachable by its own id"
        )
    }

    func testExportImportRoundTrip() async {
        // Add notes with various properties
        store.add(title: "Note 1", content: "Content 1", color: .blue, isColorOn: true)
        store.add(title: "Note 2", content: "Content 2", color: .green, isColorOn: true)
        let note = store.notes.last!
        store.update(note: note, pinned: true)

        let originalCount = store.notes.count
        let originalTitles = Set(store.notes.map { $0.title })

        // Export
        guard let exportData = await store.exportNotes() else {
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
        let success = await store.importNotes(from: exportData, replaceExisting: false)

        XCTAssertTrue(success)
        XCTAssertEqual(store.notes.count, originalCount)
        XCTAssertEqual(Set(store.notes.map { $0.title }), originalTitles)

        // Verify that pinned note remained pinned
        XCTAssertTrue(store.notes.contains(where: { $0.title == "Note 2" && $0.pinned }))
    }

    func testImportInvalidData() async {
        let invalidData = "This is not JSON".data(using: .utf8)!

        let success = await store.importNotes(from: invalidData, replaceExisting: false)

        XCTAssertFalse(success)
        XCTAssertNotNil(store.saveError)
    }

    func testSetError() {
        store.setError("Test error message")
        XCTAssertEqual(store.saveError, "Test error message")
    }

    // MARK: - Notification identifier lifecycle

    /// Regression: a partial update (e.g. swipe-to-pin) used to wipe the note's
    /// notification identifiers, orphaning the scheduled reminder so it could
    /// neither be cancelled nor replaced.
    func testPartialUpdateKeepsNotificationIdentifiers() {
        store.add(
            title: "With reminder",
            content: "Content",
            reminder: Date().addingTimeInterval(3600),
            isReminderOn: true,
            notificationIdentifiers: ["notification-1"]
        )
        let note = store.notes.last!
        XCTAssertEqual(note.notificationIdentifiers, ["notification-1"])

        store.update(note: note, pinned: true)

        let updated = store.notes.first(where: { $0.id == note.id })
        XCTAssertEqual(updated?.pinned, true)
        XCTAssertEqual(updated?.notificationIdentifiers, ["notification-1"])
        XCTAssertNotNil(updated?.reminder)
    }

    func testUpdateWithEmptyIdentifiersClearsReminder() {
        store.add(
            title: "With reminder",
            content: "Content",
            reminder: Date().addingTimeInterval(3600),
            isReminderOn: true,
            notificationIdentifiers: ["notification-1"]
        )
        let note = store.notes.last!

        store.update(note: note, isReminderOn: false, notificationIdentifiers: [])

        let updated = store.notes.first(where: { $0.id == note.id })
        XCTAssertNil(updated?.notificationIdentifiers)
        XCTAssertNil(updated?.reminder)
    }

    /// The reminder date is user data — the calendar view lists notes by it — so
    /// it survives even when no notification could be armed for it. Only the
    /// identifiers go, because there is nothing for them to point at. This is
    /// the contract the note form relies on after a denied notification
    /// permission, where the date used to be wiped without a word.
    func testReminderSurvivesWhenNoNotificationCouldBeScheduled() {
        let due = Date().addingTimeInterval(3600)
        store.add(
            title: "With reminder",
            content: "Content",
            reminder: due,
            isReminderOn: true,
            notificationIdentifiers: ["notification-1"]
        )
        let note = store.notes.last!

        // What the form does when `scheduleNotification` hands back nil.
        store.update(note: note, reminder: due, isReminderOn: true, notificationIdentifiers: [])

        let updated = store.notes.first(where: { $0.id == note.id })
        XCTAssertEqual(updated?.reminder, due, "The date the user picked must not be discarded")
        XCTAssertNil(updated?.notificationIdentifiers, "Nothing may point at a notification that does not exist")
    }

    /// Regression: a note whose reminder had already elapsed opened the form with
    /// the reminder toggle off, and saving any other field then cleared the date
    /// the calendar view lists notes by — so fixing a typo in the title erased the
    /// note's place in the calendar. The form now passes neither reminder field in
    /// that case, which is the store contract asserted here.
    func testPartialUpdateKeepsAnElapsedReminder() {
        let elapsed = Date().addingTimeInterval(-3600)
        store.add(
            title: "Yesterday",
            content: "Content",
            reminder: elapsed,
            isReminderOn: true
        )
        let note = store.notes.last!
        XCTAssertEqual(note.reminder, elapsed)

        store.update(note: note, title: "Yesterday, fixed")

        let updated = store.notes.first(where: { $0.id == note.id })
        XCTAssertEqual(updated?.title, "Yesterday, fixed")
        XCTAssertEqual(
            updated?.reminder,
            elapsed,
            "An edit that never touched the reminder must not erase its date"
        )
    }

    /// Switching the toggle off is still an explicit instruction to clear it,
    /// elapsed or not — otherwise a past reminder could never be removed.
    func testExplicitlyClearingAnElapsedReminderStillWorks() {
        store.add(
            title: "Yesterday",
            content: "Content",
            reminder: Date().addingTimeInterval(-3600),
            isReminderOn: true
        )
        let note = store.notes.last!

        store.update(note: note, isReminderOn: false)

        XCTAssertNil(store.notes.first(where: { $0.id == note.id })?.reminder)
    }

    func testUpdateReplacesIdentifiers() {
        store.add(
            title: "With reminder",
            content: "Content",
            reminder: Date().addingTimeInterval(3600),
            isReminderOn: true,
            notificationIdentifiers: ["old"]
        )
        let note = store.notes.last!

        store.update(
            note: note,
            reminder: Date().addingTimeInterval(7200),
            isReminderOn: true,
            notificationIdentifiers: ["new"]
        )

        XCTAssertEqual(
            store.notes.first(where: { $0.id == note.id })?.notificationIdentifiers,
            ["new"]
        )
    }

    func testAddWithoutReminderStoresNoIdentifiers() {
        store.add(title: "Plain", content: "Content", notificationIdentifiers: [])
        XCTAssertNil(store.notes.last?.notificationIdentifiers)
    }

    // MARK: - Trash

    func testMoveToTrashKeepsNoteButHidesItFromActive() {
        store.add(title: "Doomed", content: "Content")
        let note = store.notes.last!

        store.moveToTrash(note: note)

        XCTAssertEqual(store.notes.count, 1)
        XCTAssertTrue(store.activeNotes.isEmpty)
        XCTAssertEqual(store.deletedNotes.count, 1)
        XCTAssertNotNil(store.deletedNotes.first?.deletedAt)
    }

    func testRestoreFromTrash() {
        store.add(title: "Doomed", content: "Content")
        let note = store.notes.last!
        store.moveToTrash(note: note)

        store.restoreFromTrash(note: store.deletedNotes.first!)

        XCTAssertEqual(store.activeNotes.count, 1)
        XCTAssertTrue(store.deletedNotes.isEmpty)
        XCTAssertNil(store.activeNotes.first?.deletedAt)
    }

    /// The store cancels a trashed note's notifications itself, so the note must
    /// not go on naming them. Every view that deletes a note used to cancel them
    /// by hand, which left the two halves of one rule — cancel on the way in,
    /// re-arm on the way out — in different files.
    func testMoveToTrashDropsTheNotificationIdentifiers() {
        store.add(
            title: "Doomed",
            content: "Content",
            reminder: Date().addingTimeInterval(3600),
            notificationIdentifiers: ["stale-identifier"]
        )
        let note = store.notes.last!
        XCTAssertEqual(note.notificationIdentifiers, ["stale-identifier"])

        store.moveToTrash(note: note)

        XCTAssertNil(
            store.deletedNotes.first?.notificationIdentifiers,
            "A trashed note must not point at a notification that was cancelled"
        )
    }

    func testTrashKeepsNoteProperties() {
        store.add(
            title: "Doomed",
            content: "Content",
            color: .blue,
            isColorOn: true,
            tags: ["work"],
            isProtected: true
        )
        let note = store.notes.last!

        store.moveToTrash(note: note)
        store.restoreFromTrash(note: store.deletedNotes.first!)

        let restored = store.activeNotes.first
        XCTAssertEqual(restored?.title, "Doomed")
        XCTAssertEqual(restored?.tags, ["work"])
        XCTAssertEqual(restored?.isProtected, true)
        XCTAssertNotNil(restored?.color)
    }

    /// Emptying the trash drops what is in it and leaves everything else alone.
    /// The list the user is looking at is `activeNotes`, and a bug here would take
    /// notes out of it that were never deleted.
    func testEmptyTrashDropsOnlyTheTrashedNotes() {
        store.add(title: "Kept", content: "Content")
        store.add(title: "Doomed", content: "Content")
        store.moveToTrash(note: store.notes.last!)

        XCTAssertTrue(store.emptyTrash())

        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.activeNotes.first?.title, "Kept")
        XCTAssertTrue(store.deletedNotes.isEmpty)
    }

    /// Nothing in the trash means nothing to write. The return value is what the
    /// caller would otherwise have to work out for itself, and a `true` here would
    /// schedule a save of a list that did not change.
    func testEmptyTrashReportsNothingToDoOnAnEmptyTrash() {
        store.add(title: "Kept", content: "Content")

        XCTAssertFalse(store.emptyTrash())
        XCTAssertEqual(store.notes.count, 1)
    }

    /// The notes have to be gone from the file too, not just from memory — this is
    /// the one trash action with no undo behind it.
    func testEmptyTrashPersists() async throws {
        store.add(title: "Kept", content: "Content")
        store.add(title: "Doomed", content: "Content")
        store.moveToTrash(note: store.notes.last!)

        store.emptyTrash()
        await store.saveNow()

        let reloaded = NotesStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.title, "Kept")
    }

    func testExpiredTrashIsPurgedOnLoad() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let expiredAt = Date().addingTimeInterval(-NotesStore.trashRetention - 60)
        let recentAt = Date().addingTimeInterval(-60)
        let seeded = [
            NoteModel(title: "Active", content: "Keep me"),
            NoteModel(title: "Recently deleted", content: "Keep me", isDeleted: true, deletedAt: recentAt),
            NoteModel(title: "Long deleted", content: "Purge me", isDeleted: true, deletedAt: expiredAt)
        ]
        try JSONEncoder().encode(seeded).write(to: url)

        let reloaded = NotesStore(fileURL: url)

        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertTrue(reloaded.notes.contains { $0.title == "Active" })
        XCTAssertTrue(reloaded.notes.contains { $0.title == "Recently deleted" })
        XCTAssertFalse(reloaded.notes.contains { $0.title == "Long deleted" })
    }

    // MARK: - Tags

    func testAllTagsIsSortedAndDeduplicated() {
        store.add(title: "A", content: "c", tags: ["work", "urgent"])
        store.add(title: "B", content: "c", tags: ["urgent", "home"])

        XCTAssertEqual(store.allTags, ["home", "urgent", "work"])
    }

    /// Two notes tagged in different cases share one chip. They used to produce
    /// two, each filtering the other's note out — while the search field, which
    /// goes through `localizedCaseInsensitiveContains`, had always treated them as
    /// one tag.
    ///
    /// Which spelling is the survivor falls out of the sort, and it is the
    /// lowercase one because `localizedStandardCompare` ranks case as a tertiary
    /// difference. Under the bare `sorted()` this replaced it was "Práce", since
    /// "P" precedes "p" by code point. Pinned rather than left to whichever the
    /// implementation happens to pick: the chip's label is on screen, and the
    /// spelling has to be a property of the rule rather than of the sort's
    /// stability — see `NotesStore.allTags`.
    func testAllTagsFoldsCase() {
        store.add(title: "A", content: "c", tags: ["Práce"])
        store.add(title: "B", content: "c", tags: ["práce"])

        XCTAssertEqual(store.allTags, ["práce"])
    }

    /// The chip row reads in the reader's alphabet, not in Unicode scalar order.
    ///
    /// Every one of these is misplaced by a bare `sorted()`: it groups the
    /// capitalised tags ahead of all the lowercase ones and files "čas", "řeka",
    /// "škola" and "žito" past "z", giving "Byt", "Zebra", "auto", "dům", "čas",
    /// "řeka", "škola", "žito". Czech is the app's other language, so the row it
    /// produced was wrong in half of the localizations it ships.
    func testAllTagsUsesTheReadersAlphabetRatherThanCodePoints() {
        store.add(title: "A", content: "c", tags: ["auto", "Zebra", "škola", "Byt"])
        store.add(title: "B", content: "c", tags: ["čas", "řeka", "dům", "žito"])

        XCTAssertEqual(
            store.allTags,
            ["auto", "Byt", "čas", "dům", "řeka", "škola", "Zebra", "žito"]
        )
    }

    /// Which of two spellings survives is decided by the sort rather than by
    /// whichever note happens to come first in the file — the chip row must not
    /// rename itself when an unrelated note is added.
    func testAllTagsPicksTheSameSpellingWhicheverOrderTheNotesArriveIn() {
        store.add(title: "A", content: "c", tags: ["práce"])
        store.add(title: "B", content: "c", tags: ["Práce"])

        let firstOrder = store.allTags

        let other = NotesStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).json")
        )
        other.add(title: "B", content: "c", tags: ["Práce"])
        other.add(title: "A", content: "c", tags: ["práce"])

        XCTAssertEqual(firstOrder, other.allTags)
        try? FileManager.default.removeItem(at: other.fileURL)
    }

    func testAllTagsIgnoresDeletedNotes() {
        store.add(title: "A", content: "c", tags: ["work"])
        store.add(title: "B", content: "c", tags: ["trashed"])
        store.moveToTrash(note: store.notes.last!)

        XCTAssertEqual(store.allTags, ["work"])
    }

    // MARK: - Persistence

    /// Where a real store keeps its file.
    ///
    /// `defaultFileURL` was rewritten from `FileManager.urls(for:in:).first!` to
    /// `URL.documentsDirectory`, to be rid of the only force unwrap left in either
    /// target. The two spellings have to name the very same directory, and this is
    /// the assertion that they do — every note anyone has is in the file the old
    /// one produced, so a store that started looking somewhere else would read as
    /// an empty library and go on to write one. Nothing would be deleted; the notes
    /// would simply be sitting on the disk with nothing in the app ever asking for
    /// them again, which is worse, because no backup restore would look there
    /// either.
    ///
    /// Compares the directories rather than `defaultFileURL` itself, which is
    /// private — and it is the directory that moved, not the filename.
    func testTheDocumentsDirectoryIsTheOneTheOldSpellingNamed() throws {
        let old = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )

        XCTAssertEqual(
            URL.documentsDirectory.standardizedFileURL,
            old.standardizedFileURL
        )
    }

    func testNotesSurviveReload() async throws {
        store.add(title: "Persisted", content: "Content", tags: ["tag"])
        let saved = await store.saveNow()
        XCTAssertTrue(saved)

        let reloaded = NotesStore(fileURL: store.fileURL)

        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.title, "Persisted")
        XCTAssertEqual(reloaded.notes.first?.tags, ["tag"])
    }

    /// A save is debounced, and iOS suspends a backgrounded process without
    /// waiting for the delay to elapse — so leaving the foreground has to flush,
    /// or the last pin, checkbox or delete never reaches the disk. Deliberately
    /// no sleep here: this is exactly the race the flush exists to win.
    func testFlushPendingSaveWritesADebouncedEdit() async throws {
        store.add(title: "Backgrounded", content: "Content")

        await store.flushPendingSave()

        let reloaded = NotesStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.title, "Backgrounded")
    }

    /// Backgrounding is a hot path and the file carries base64 drawing blobs, so
    /// a flush with nothing pending must not re-encode and rewrite all of it.
    func testFlushPendingSaveDoesNothingWhenNothingIsPending() async throws {
        store.add(title: "Persisted", content: "Content")
        let saved = await store.saveNow()
        XCTAssertTrue(saved)

        // Removing the file makes a needless write impossible to miss, where
        // comparing timestamps would be at the mercy of clock granularity.
        try FileManager.default.removeItem(at: store.fileURL)

        await store.flushPendingSave()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.fileURL.path),
            "The file was rewritten with nothing to save"
        )
    }

    /// A partial update must not resurrect a trashed note. Rebuilding the model
    /// field by field used to drop `isDeleted` and do exactly that.
    func testUpdatingATrashedNoteKeepsItInTheTrash() {
        store.add(title: "Doomed", content: "Content")
        store.moveToTrash(note: store.notes.last!)

        store.update(note: store.deletedNotes.first!, content: "Edited")

        XCTAssertTrue(store.activeNotes.isEmpty)
        XCTAssertEqual(store.deletedNotes.count, 1)
        XCTAssertEqual(store.deletedNotes.first?.content, "Edited")
        XCTAssertNotNil(store.deletedNotes.first?.deletedAt)
    }

    // MARK: - Unreadable storage

    /// An unreadable notes file (the device was locked when the store was built)
    /// must never be replaced by the little that is in memory.
    func testSaveIsRefusedWhenTheFileCouldNotBeRead() async throws {
        let url = try makeUnreadableFile("unreadable-save")

        let blocked = NotesStore(fileURL: url)
        XCTAssertTrue(blocked.notes.isEmpty)
        XCTAssertNotNil(blocked.saveError)

        blocked.add(title: "Created while blocked", content: "Content")
        let saved = await blocked.saveNow()

        XCTAssertFalse(saved, "Saving must be refused while the stored notes are unread")

        try makeReadable(url)
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data("[]".utf8),
            "The unreadable file must be left untouched"
        )
        try? FileManager.default.removeItem(at: url)
    }

    /// A write that did not happen leaves the edit unsaved, so the flush on the
    /// way to the background — the retry `isSavePending` exists to trigger — has
    /// to still see it as pending. Clearing the flag on the way into the write
    /// meant the one case that needed the retry was the one that never got it.
    func testARefusedSaveLeavesTheEditPending() async throws {
        let url = try makeUnreadableFile("unreadable-pending")

        let blocked = NotesStore(fileURL: url)
        blocked.add(title: "Created while blocked", content: "Content")

        let saved = await blocked.saveNow()

        XCTAssertFalse(saved)
        XCTAssertTrue(
            blocked.isSavePending,
            "A refused write must stay pending, or the edit is never retried"
        )
    }

    /// The mirror of the above: once the bytes are down there is nothing left to
    /// flush, and backgrounding must not ask iOS for time it will not use.
    func testASuccessfulSaveClearsThePendingFlag() async throws {
        store.add(title: "Persisted", content: "Content")
        XCTAssertTrue(store.isSavePending)

        let saved = await store.saveNow()

        XCTAssertTrue(saved)
        XCTAssertFalse(store.isSavePending)
    }

    /// The encode and the write happen off the main actor now, so a save suspends —
    /// and an edit made while one is in flight has queued a save of its own. The
    /// older write must not report "nothing pending" on that edit's behalf, or the
    /// flush on the way to the background skips it and the edit is lost.
    ///
    /// The overlap is arranged rather than waited for, and with no sleep anywhere:
    /// this test leans only on two guarantees the runtime makes. `Task { }` created
    /// on the main actor is enqueued there, so the single `yield` below runs it
    /// ahead of this test's own continuation; and `save()`'s call into
    /// `NotesFileCoder` is a hop to another actor, so it is bound to suspend once
    /// it gets there. By the time the edit lands, the write is in flight.
    func testAnEditMadeDuringASaveStaysPending() async throws {
        store.add(title: "First", content: "Content")

        let inFlight = Task { await store.saveNow() }
        await Task.yield()

        // Lands mid-write, and queues a save of its own that supersedes it.
        store.add(title: "Made while saving", content: "Content")

        let firstSaveSucceeded = await inFlight.value
        XCTAssertTrue(firstSaveSucceeded)
        XCTAssertTrue(
            store.isSavePending,
            "The older write cleared the flag for an edit it never carried"
        )

        // And the flush that flag arms does get the newer note onto the disk.
        await store.flushPendingSave()

        let reloaded = NotesStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertTrue(reloaded.notes.contains { $0.title == "Made while saving" })
    }

    /// A save writes the notes as they stood when it started, and the edit that
    /// arrived mid-write is carried by the save that edit queued — so nothing is
    /// dropped and nothing older lands on top of something newer. Two writes going
    /// at once are serialised by `NotesFileCoder` precisely so the last one down is
    /// the newest.
    func testOverlappingSavesLeaveTheNewestNotesOnDisk() async throws {
        store.add(title: "First", content: "Content")

        let inFlight = Task { await store.saveNow() }
        await Task.yield()
        store.add(title: "Second", content: "Content")
        _ = await inFlight.value

        await store.flushPendingSave()

        let reloaded = NotesStore(fileURL: store.fileURL)
        XCTAssertEqual(
            Set(reloaded.notes.map(\.title)),
            ["First", "Second"]
        )
    }

    /// A restore cannot reach the disk while storage is unreadable, and
    /// `refresh()` would later fold the in-memory notes into whatever it manages
    /// to load — turning "replace everything" into a merge. Reporting the
    /// refusal beats reporting a success that did not happen.
    ///
    /// This holds for the locked device only, which unblocks itself. A file that
    /// will never decode must not refuse a restore — that was the dead end.
    func testImportIsRefusedWhenTheFileCouldNotBeRead() async throws {
        let url = try makeUnreadableFile("unreadable-import")

        let blocked = NotesStore(fileURL: url)
        XCTAssertTrue(blocked.notes.isEmpty)

        let imported = await blocked.importNotes(
            from: try backupData(titled: "From backup"),
            replaceExisting: true
        )
        XCTAssertFalse(
            imported,
            "A restore must not report success while the stored notes are unread"
        )
        XCTAssertTrue(blocked.notes.isEmpty, "Nothing may be taken on board")

        try makeReadable(url)
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data("[]".utf8),
            "The unreadable file must be left untouched"
        )
        try? FileManager.default.removeItem(at: url)
    }

    /// A backup file's bytes, in the format the app exports.
    private func backupData(titled title: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode([NoteModel(title: title, content: "Content")])
    }

    // MARK: - Undecodable storage

    /// A file whose bytes read fine but are not notes is a different case from one
    /// that could not be read at all: no later attempt will decode it either.
    /// Blocking writes therefore blocked them for ever — and `importNotes` refuses
    /// while writes are blocked, so restoring a backup, the one thing that would
    /// have fixed it, was ruled out too. The app was unusable with no way back.
    ///
    /// The file is set aside instead. Nothing is destroyed, and the store carries on
    /// as the empty one it now truthfully is.
    func testAnUndecodableFileIsSetAsideSoTheAppStaysUsable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("undecodable-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let garbage = Data("not json at all".utf8)
        try garbage.write(to: url)

        let recovered = NotesStore(fileURL: url)

        XCTAssertTrue(recovered.notes.isEmpty)
        XCTAssertNotNil(recovered.saveError, "The user has to be told their notes did not load")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "The undecodable file must be moved out of the store's way"
        )

        let setAside = try XCTUnwrap(
            try fileSetAside(for: url),
            "The bytes are all that is left of whatever was in there - they must be kept"
        )
        defer { try? FileManager.default.removeItem(at: setAside) }
        XCTAssertEqual(try Data(contentsOf: setAside), garbage)

        // And the app works: a new note saves, and the file it writes reloads.
        recovered.add(title: "After recovery", content: "Content")
        let saved = await recovered.saveNow()
        XCTAssertTrue(saved, "Saving must not stay blocked for ever")
        XCTAssertEqual(NotesStore(fileURL: url).notes.map(\.title), ["After recovery"])
    }

    /// The point of setting the file aside: the restore is reachable again.
    func testABackupCanBeRestoredOverAnUndecodableFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("undecodable-restore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("not json at all".utf8).write(to: url)

        let recovered = NotesStore(fileURL: url)
        defer { try? fileSetAside(for: url).map { try FileManager.default.removeItem(at: $0) } }

        let imported = await recovered.importNotes(
            from: try backupData(titled: "From backup"),
            replaceExisting: true
        )
        XCTAssertTrue(
            imported,
            "A restore is exactly what this state needs to allow"
        )
        XCTAssertEqual(recovered.notes.map(\.title), ["From backup"])

        let saved = await recovered.saveNow()
        XCTAssertTrue(saved, "The restore has to reach the disk, not just memory")
        XCTAssertEqual(NotesStore(fileURL: url).notes.map(\.title), ["From backup"])
    }

    /// The UserDefaults backup still wins over setting the file aside: it holds
    /// real notes, so there is something better to do than start empty.
    ///
    /// The recovery going well does not make the set-aside silent, though. This
    /// branch used to clear the error outright, which made it the one path that
    /// moved a file out of the store's way and told the user nothing about it.
    /// These notes came from a UserDefaults copy left behind by a migration that
    /// never finished, so they can be older than what the file held — and that
    /// file is now sitting in the container under another name.
    func testAnUndecodableFileStillPrefersTheUserDefaultsBackup() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("undecodable-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("not json at all".utf8).write(to: url)

        let legacy = try JSONEncoder().encode([NoteModel(title: "From UserDefaults", content: "Content")])
        UserDefaults.standard.set(legacy, forKey: "notes")
        defer { UserDefaults.standard.removeObject(forKey: "notes") }

        let recovered = NotesStore(fileURL: url)
        defer { try? fileSetAside(for: url).map { try FileManager.default.removeItem(at: $0) } }

        XCTAssertEqual(recovered.notes.map(\.title), ["From UserDefaults"])
        XCTAssertEqual(
            recovered.saveError,
            String(localized: "errorLoadCorruptRecovered"),
            "A file was set aside, and saying so is not the same as reporting a failure"
        )
        XCTAssertNil(
            UserDefaults.standard.data(forKey: "notes"),
            "The backup is dropped only once the notes are safely in the file"
        )
    }

    /// The other side of it: an ordinary migration sets nothing aside, so it has
    /// nothing to report. Without this the message above would be free to appear
    /// on the first launch of every upgrade, which is the plain success case.
    func testAnOrdinaryMigrationFromUserDefaultsReportsNothing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // No file at all — the state an install predating file storage is in.
        let legacy = try JSONEncoder().encode([NoteModel(title: "From UserDefaults", content: "Content")])
        UserDefaults.standard.set(legacy, forKey: "notes")
        defer { UserDefaults.standard.removeObject(forKey: "notes") }

        let migrated = NotesStore(fileURL: url)

        XCTAssertEqual(migrated.notes.map(\.title), ["From UserDefaults"])
        XCTAssertNil(migrated.saveError, "Migrating is a success, and nothing was set aside")
        XCTAssertNil(try fileSetAside(for: url), "There was no file to move out of the way")
    }

    // MARK: - Widget payload

    /// The widget renders the top of this list, so it has to be ordered the way
    /// the app's own list is — pinned first, then newest.
    func testWidgetPayloadPutsPinnedNotesFirst() {
        let old = Date().addingTimeInterval(-3600)
        let new = Date()

        let notes = [
            NoteModel(createdAt: new, title: "Newest", content: "c"),
            NoteModel(createdAt: old, title: "Pinned but old", content: "c", pinned: true)
        ]

        let payload = NotesStore.widgetPayload(for: notes)

        XCTAssertEqual(payload.map(\.title), ["Pinned but old", "Newest"])
    }

    /// The payload is deliberately truncated. The widget's counter therefore
    /// cannot be derived from it — it used to be, and so stopped climbing.
    func testWidgetPayloadIsTruncatedWhileTheTotalIsNot() {
        let total = NotesStore.widgetPayloadLimit + 5
        let notes = (0..<total).map { NoteModel(title: "Note \($0)", content: "c") }

        XCTAssertEqual(NotesStore.widgetPayload(for: notes).count, NotesStore.widgetPayloadLimit)
        XCTAssertGreaterThan(total, NotesStore.widgetPayload(for: notes).count)
    }

    /// The body is truncated on its way into the shared container, which has none
    /// of the notes file's `.completeFileProtection` and stays readable while the
    /// device is locked. The widget draws at most three short lines of it, so
    /// sending the whole of a long note put the rest of the user's text in an
    /// unprotected container for nothing.
    func testWidgetPayloadTruncatesTheBody() throws {
        let long = String(repeating: "a", count: WidgetNoteEntry.bodyPreviewLimit * 3)

        let entry = try XCTUnwrap(
            NotesStore.widgetPayload(
                for: [NoteModel(title: "Long", content: long)]
            ).first
        )

        XCTAssertEqual(entry.content.count, WidgetNoteEntry.bodyPreviewLimit)
        XCTAssertTrue(long.hasPrefix(entry.content), "The kept part must be the start of the body")
    }

    /// Nothing past the limit is ever rendered, so the truncation cannot cut into
    /// what the widget actually shows: `displayTitle` reaches at most 60 characters
    /// into the body for an untitled note.
    func testTheWidgetBodyLimitCoversEverythingTheWidgetRenders() {
        XCTAssertGreaterThanOrEqual(WidgetNoteEntry.bodyPreviewLimit, 60)
    }

    /// A body short enough to fit is passed through untouched — truncation must not
    /// be visible in the ordinary case.
    func testWidgetPayloadKeepsAShortBodyWhole() {
        let entry = NotesStore.widgetPayload(
            for: [NoteModel(title: "Short", content: "Milk, eggs, bread")]
        ).first

        XCTAssertEqual(entry?.content, "Milk, eggs, bread")
    }

    /// The shared container the widget reads, and whatever it held before the
    /// test touched it.
    ///
    /// Restored in full afterwards: this is the real App Group, so on a simulator
    /// it is the very container a widget on the home screen renders from.
    private func withWidgetContainer(
        _ body: (UserDefaults) async throws -> Void
    ) async throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: AppGroup.identifier),
            "The test host carries the app's App Group entitlement"
        )

        let previousData = defaults.data(forKey: AppGroup.widgetDataKey)
        let previousTotal = defaults.object(forKey: AppGroup.widgetTotalKey)
        defer {
            defaults.set(previousData, forKey: AppGroup.widgetDataKey)
            defaults.set(previousTotal, forKey: AppGroup.widgetTotalKey)
        }

        try await body(defaults)
    }

    /// A store that could not read its own file must not publish over the widget's
    /// copy. It holds nothing in memory, and — unlike the notes file — the shared
    /// container has no protection to hide behind, so publishing replaced the
    /// user's widget with "No notes". The same rule `save()` applies to the file:
    /// an unreadable store is not an empty one.
    ///
    /// Reached in practice by any process that starts while the device is locked,
    /// a Siri shortcut creating a note being the obvious one.
    func testAStoreThatCouldNotLoadLeavesTheWidgetPayloadAlone() async throws {
        try await withWidgetContainer { defaults in
            // What a working store published before the device was locked.
            let published = try JSONEncoder().encode(
                NotesStore.widgetPayload(for: [
                    NoteModel(title: "On the home screen", content: "Content")
                ])
            )
            defaults.set(published, forKey: AppGroup.widgetDataKey)
            defaults.set(1, forKey: AppGroup.widgetTotalKey)

            let url = try makeUnreadableFile("widget-blocked")

            let blocked = NotesStore(fileURL: url)
            XCTAssertTrue(blocked.notes.isEmpty)
            XCTAssertNotNil(blocked.saveError, "The premise: this store never read its notes")

            XCTAssertEqual(
                defaults.data(forKey: AppGroup.widgetDataKey),
                published,
                "The widget's notes were replaced by a store that had none"
            )
            XCTAssertEqual(
                defaults.integer(forKey: AppGroup.widgetTotalKey),
                1,
                "The widget's counter was zeroed by a store that had read nothing"
            )
        }
    }

    /// The mirror of the above: once the file becomes readable the container may
    /// be out of step with it, and no save is coming to republish it. Recovery is
    /// the one moment the store's contents change without an edit.
    func testRefreshRepublishesTheWidgetPayloadAfterRecovering() async throws {
        try await withWidgetContainer { defaults in
            defaults.removeObject(forKey: AppGroup.widgetDataKey)

            let url = try makeUnreadableFile("widget-recover")

            let blocked = NotesStore(fileURL: url)
            XCTAssertNil(
                defaults.data(forKey: AppGroup.widgetDataKey),
                "Nothing may be published while storage is unreadable"
            )

            // The device is unlocked, so the file the store could not read is
            // within reach again — with the notes that were always in it.
            try makeReadable(url)
            defer { try? FileManager.default.removeItem(at: url) }
            try JSONEncoder()
                .encode([NoteModel(title: "Was on disk", content: "Content")])
                .write(to: url)

            await blocked.refresh()

            let payload = try JSONDecoder().decode(
                [WidgetNoteEntry].self,
                from: try XCTUnwrap(
                    defaults.data(forKey: AppGroup.widgetDataKey),
                    "Recovery must bring the widget back in line with the file"
                )
            )

            XCTAssertEqual(payload.map(\.title), ["Was on disk"])
            XCTAssertEqual(defaults.integer(forKey: AppGroup.widgetTotalKey), 1)
        }
    }

    /// Once the file becomes readable, `refresh()` loads it and folds in whatever
    /// was created while storage was blocked.
    func testRefreshRecoversAndMergesNotesCreatedWhileBlocked() async throws {
        let url = try makeUnreadableFile("recover")

        let blocked = NotesStore(fileURL: url)
        blocked.add(title: "Created while blocked", content: "Content")
        let refused = await blocked.saveNow()
        XCTAssertFalse(refused)

        // The device is unlocked, so the file is within reach again.
        try makeReadable(url)
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder()
            .encode([NoteModel(title: "Was on disk", content: "Content")])
            .write(to: url)

        await blocked.refresh()

        XCTAssertEqual(blocked.notes.count, 2)
        XCTAssertTrue(blocked.notes.contains { $0.title == "Was on disk" })
        XCTAssertTrue(blocked.notes.contains { $0.title == "Created while blocked" })
        XCTAssertNil(blocked.saveError)

        // Both notes are now persisted rather than living only in memory.
        let reloaded = NotesStore(fileURL: url)
        XCTAssertEqual(reloaded.notes.count, 2)
    }

    /// `refresh()` also sweeps trash that expired while the process stayed alive.
    func testRefreshPurgesTrashThatExpiredWhileRunning() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("refresh-purge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try JSONEncoder()
            .encode([NoteModel(title: "Active", content: "Keep me")])
            .write(to: url)

        let running = NotesStore(fileURL: url)
        running.add(
            title: "Long deleted",
            content: "Purge me",
            reminder: nil
        )
        // Age the note past the retention window without touching the clock.
        var stale = running.notes.last!
        stale.isDeleted = true
        stale.deletedAt = Date().addingTimeInterval(-NotesStore.trashRetention - 60)
        running.replace(note: stale)

        await running.refresh()

        XCTAssertEqual(running.notes.count, 1)
        XCTAssertEqual(running.notes.first?.title, "Active")
    }

    /// A file that turns out to be undecodable on the *retry* has to say so.
    ///
    /// `refresh()` cleared `saveError` on every successful load, which is right for
    /// the stale "could not be read" it is replacing and wrong for anything the
    /// load itself has to report. Setting a file aside is exactly that: it is the
    /// one moment the user has to be pointed at Restore from Backup, and clearing
    /// afterwards meant they were shown an emptied list and no reason for it.
    ///
    /// Reached by the ordinary compound case — the app starts while the device is
    /// locked, so the first load cannot read the file at all, and by the time it
    /// can the bytes turn out not to be notes.
    func testRefreshReportsAFileItHadToSetAside() async throws {
        let url = try makeUnreadableFile("refresh-corrupt")

        let blocked = NotesStore(fileURL: url)
        XCTAssertTrue(blocked.notes.isEmpty)

        // The device is unlocked: the bytes are readable now, and they are not
        // notes.
        try makeReadable(url)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json at all".utf8).write(to: url)

        await blocked.refresh()

        defer { try? fileSetAside(for: url).map { try FileManager.default.removeItem(at: $0) } }

        XCTAssertNotNil(
            blocked.saveError,
            "The user has to be told the file was set aside, or an emptied list has no explanation"
        )
        XCTAssertEqual(blocked.saveError, String(localized: "errorLoadCorrupt"))
        XCTAssertNotNil(
            try fileSetAside(for: url),
            "The undecodable bytes must still be kept"
        )
    }

    /// …and it still says so when there are notes to write out on the way.
    ///
    /// The compound case above, plus the one thing that makes it worth
    /// recovering from: a note the user made while storage was blocked. That note
    /// is merged and saved immediately — and a successful save cleared
    /// `saveError` outright, so the very write that rescued it wrote off the
    /// explanation for the emptied list it landed in. `refresh()` clearing the
    /// stale error *before* the load was only half the fix; this is the other
    /// half, and it is the likelier half of the two to be reached, since a store
    /// blocked at launch is a store the user has been adding to.
    func testRefreshStillReportsASetAsideFileAfterSavingRescuedNotes() async throws {
        let url = try makeUnreadableFile("refresh-corrupt-pending")

        let blocked = NotesStore(fileURL: url)
        blocked.add(title: "Created while blocked", content: "Content")

        // The device is unlocked: the bytes are readable now, and they are not
        // notes.
        try makeReadable(url)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json at all".utf8).write(to: url)

        await blocked.refresh()

        defer { try? fileSetAside(for: url).map { try FileManager.default.removeItem(at: $0) } }

        XCTAssertEqual(
            blocked.saveError,
            String(localized: "errorLoadCorrupt"),
            "The save that rescued the pending note must not write off the reason the list is otherwise empty"
        )
        XCTAssertEqual(
            blocked.notes.map(\.title),
            ["Created while blocked"],
            "The note made while storage was blocked is still the point of the recovery"
        )
        XCTAssertNotNil(
            try fileSetAside(for: url),
            "The undecodable bytes must still be kept"
        )
    }

    /// A save that goes through still clears a message about *saving*.
    ///
    /// The other side of the rule above: only what the load had to say outlives a
    /// successful write. A blocked store that recovers has to stop telling the
    /// user saving is blocked, or the alert outlives the problem.
    func testASuccessfulSaveStillClearsASaveError() async throws {
        let url = try makeUnreadableFile("save-clears-save-error")

        let blocked = NotesStore(fileURL: url)
        blocked.add(title: "Created while blocked", content: "Content")
        let refused = await blocked.saveNow()
        XCTAssertFalse(refused)
        XCTAssertEqual(blocked.saveError, String(localized: "errorSaveBlocked"))

        // The file is within reach again, and it is perfectly good.
        try makeReadable(url)
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder()
            .encode([NoteModel]())
            .write(to: url)

        await blocked.refresh()

        XCTAssertNil(
            blocked.saveError,
            "Nothing is blocked any more, and the load had nothing of its own to report"
        )
    }

    /// The other half: a refresh that simply succeeds still clears the stale
    /// "could not be read" it was blocked on.
    func testRefreshClearsTheErrorItRecoveredFrom() async throws {
        let url = try makeUnreadableFile("refresh-clears")

        let blocked = NotesStore(fileURL: url)
        XCTAssertNotNil(blocked.saveError, "The premise: this store is blocked")

        try makeReadable(url)
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder()
            .encode([NoteModel(title: "Was on disk", content: "Content")])
            .write(to: url)

        await blocked.refresh()

        XCTAssertNil(blocked.saveError)
        XCTAssertEqual(blocked.notes.map(\.title), ["Was on disk"])
    }

    /// An unreadable file must not be written over by the UserDefaults backup
    /// either.
    ///
    /// The recovery path wrote to the store's own file unconditionally, so a legacy
    /// UserDefaults copy — which only exists on an install that never finished
    /// migrating — replaced notes that were merely out of reach behind
    /// `.completeFileProtection`. The same rule `save()` and `importNotes` enforce;
    /// this was the one write that sidestepped it.
    func testAnUnreadableFileIsNotOverwrittenByTheUserDefaultsBackup() async throws {
        let url = try makeUnreadableFile("unreadable-legacy")

        let legacy = try JSONEncoder().encode([NoteModel(title: "From UserDefaults", content: "Content")])
        UserDefaults.standard.set(legacy, forKey: "notes")
        defer { UserDefaults.standard.removeObject(forKey: "notes") }

        let blocked = NotesStore(fileURL: url)

        // The notes are on board, so nothing the user had is lost from view.
        XCTAssertEqual(blocked.notes.map(\.title), ["From UserDefaults"])

        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: "notes"),
            "The backup is the only durable copy while the file cannot be written - it must be kept"
        )
        let saved = await blocked.saveNow()
        XCTAssertFalse(
            saved,
            "Saving must stay blocked while the real notes are out of reach"
        )

        try makeReadable(url)
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data("[]".utf8),
            "The unreadable file must be left untouched"
        )
        try? FileManager.default.removeItem(at: url)
    }

    /// And the undecodable file's bytes survive the UserDefaults recovery too.
    ///
    /// That recovery writes to the store's own path, so the file had to be moved
    /// out of the way first. It used to be set aside only at the very end of the
    /// load — after the write had already landed on it — which destroyed the one
    /// copy of whatever was in there. Keeping those bytes is the entire reason the
    /// file is renamed rather than deleted.
    func testTheUndecodableFileIsKeptEvenWhenTheUserDefaultsBackupWins() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("undecodable-kept-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let garbage = Data("not json at all".utf8)
        try garbage.write(to: url)

        let legacy = try JSONEncoder().encode([NoteModel(title: "From UserDefaults", content: "Content")])
        UserDefaults.standard.set(legacy, forKey: "notes")
        defer { UserDefaults.standard.removeObject(forKey: "notes") }

        let recovered = NotesStore(fileURL: url)

        let setAside = try XCTUnwrap(
            try fileSetAside(for: url),
            "The undecodable bytes are all that is left of whatever was in there"
        )
        defer { try? FileManager.default.removeItem(at: setAside) }

        XCTAssertEqual(
            try Data(contentsOf: setAside),
            garbage,
            "The recovery must not have written over them"
        )

        // And the recovery itself still happened, as it did before.
        XCTAssertEqual(recovered.notes.map(\.title), ["From UserDefaults"])
        XCTAssertEqual(
            recovered.saveError,
            String(localized: "errorLoadCorruptRecovered"),
            "Setting a file aside is worth saying even when the recovery went well"
        )

        // Compared as notes rather than as bytes. `JSONEncoder` does not emit a
        // keyed container's fields in a fixed order — two encodes of the very
        // same note come back the same length with the keys shuffled — so
        // comparing the file against a fresh encode was a coin toss that happened
        // to be landing the right way up.
        let written = try JSONDecoder().decode([NoteModel].self, from: try Data(contentsOf: url))
        XCTAssertEqual(written.map(\.id), recovered.notes.map(\.id))
        XCTAssertEqual(written.map(\.title), recovered.notes.map(\.title))
        XCTAssertEqual(written.map(\.content), recovered.notes.map(\.content))
    }

    // MARK: - Backup filename

    /// The exported filename names a file; it is not read as a date by anyone.
    ///
    /// It used to be the locale's numeric date, which renders as `8/6/2026` in
    /// `en_US` — and a slash is a path separator, so the name could not survive as
    /// one. `cs_CZ` gave `6. 8. 2026`, spaces and all.
    func testTheBackupFilenameCarriesNoPathSeparatorsOrSpaces() {
        let filename = NotesDocument.defaultFilename(
            for: Date(timeIntervalSince1970: 1_754_500_000)
        )

        XCTAssertFalse(filename.contains("/"), "A slash would not survive as a filename")
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains(" "))
    }

    /// ISO-8601 so it is the same in every locale — and sorts correctly besides.
    func testTheBackupFilenameIsTheSameInEveryLocale() {
        let date = Date(timeIntervalSince1970: 1_754_500_000)

        XCTAssertEqual(
            NotesDocument.defaultFilename(for: date),
            "j-notes-backup-2025-08-06"
        )
    }

    // MARK: - Backup format tolerance

    /// Backups carry ISO-8601 dates, the on-disk store uses the compact default
    /// encoding. A restore has to accept either.
    func testImportAcceptsBothDateEncodings() async throws {
        let note = NoteModel(title: "Dated", content: "Content", reminder: Date(timeIntervalSince1970: 1_700_000_000))

        let iso8601Encoder = JSONEncoder()
        iso8601Encoder.dateEncodingStrategy = .iso8601
        let iso8601Imported = await store.importNotes(
            from: try iso8601Encoder.encode([note]),
            replaceExisting: true
        )
        XCTAssertTrue(iso8601Imported)
        XCTAssertEqual(store.notes.first?.title, "Dated")
        XCTAssertEqual(store.notes.first?.reminder, note.reminder)

        // Same note, the encoding used for the on-disk file.
        let compactImported = await store.importNotes(
            from: try JSONEncoder().encode([note]),
            replaceExisting: true
        )
        XCTAssertTrue(compactImported)
        XCTAssertEqual(store.notes.first?.reminder, note.reminder)
    }

    // MARK: - Errors

    func testClearErrorResetsSaveError() {
        store.setError("something went wrong")
        XCTAssertNotNil(store.saveError)

        store.clearError()
        XCTAssertNil(store.saveError)
    }
}
