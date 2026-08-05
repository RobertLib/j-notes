//
//  CreateNoteIntentTests.swift
//  notesTests
//

import AppIntents
import XCTest
@testable import J_Notes

/// The Siri and Shortcuts way into the store.
///
/// Driven through `CreateNoteIntent.createNote(title:content:in:)` rather than
/// `perform()`, which reaches `NotesStore.shared` — the real Documents file — and
/// hands back an opaque `IntentResult` there is nothing to assert on. See that
/// method for why the seam exists.
///
/// This was the one file in either target with no coverage at all, and what it
/// decides is not decoration. It is the only way into the store that goes around
/// the form, so the form's rules have to be restated here or they do not apply;
/// and it is the only one whose process can be terminated the moment it answers,
/// so an answer of "note created" has to mean the bytes are down.
@MainActor
final class CreateNoteIntentTests: XCTestCase {

    private var store: NotesStore!

    /// Files the test made unreadable, so teardown can make them removable again.
    private var unreadableFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        store = NotesStore(fileURL: Self.temporaryFileURL())
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

    private static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-intent-notes-\(UUID().uuidString).json")
    }

    /// A store whose file cannot be read at all — what `.completeFileProtection`
    /// produces while the device is locked, and the case `notSaved` exists for. The
    /// same fixture `NotesStoreTests` uses: POSIX permissions raise the same
    /// `NSFileReadNoPermissionError` the real thing does.
    private func makeBlockedStore() throws -> NotesStore {
        let url = Self.temporaryFileURL()

        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: url.path
        )
        unreadableFiles.append(url)

        let blocked = NotesStore(fileURL: url)

        // Both asserted here rather than left to the tests below. A fixture that
        // quietly produced a writable store, or one that picked notes up from a
        // legacy `UserDefaults` copy another test left behind, would make every
        // assertion that follows pass for the wrong reason.
        XCTAssertFalse(blocked.isLoaded, "The fixture has to produce a store that refuses to save")
        XCTAssertTrue(blocked.notes.isEmpty, "The fixture has to start empty, or the counts below mean nothing")

        return blocked
    }

    /// The error a run refused with, or `nil` when it went through.
    private func refusal(
        title: String?,
        content: String,
        in store: NotesStore
    ) async -> CreateNoteError? {
        do {
            _ = try await CreateNoteIntent.createNote(
                title: title,
                content: content,
                in: store
            )
            return nil
        } catch let error as CreateNoteError {
            return error
        } catch {
            XCTFail("Refused with something other than a CreateNoteError: \(error)")
            return nil
        }
    }

    // MARK: - Writing the note

    func testCreatesTheNoteTheShortcutAskedFor() async throws {
        let created = try await CreateNoteIntent.createNote(
            title: "Shopping",
            content: "Milk, eggs",
            in: store
        )

        XCTAssertEqual(
            created,
            CreateNoteIntent.CreatedNote(title: "Shopping", content: "Milk, eggs")
        )
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Shopping")
        XCTAssertEqual(store.notes.first?.content, "Milk, eggs")
    }

    /// A note made by voice is a plain text note and nothing else. The intent takes
    /// a title and a body and no more, so everything the form can attach has to
    /// come out of `add`'s defaults — a shortcut must not mint a note that arrives
    /// pinned, locked, or carrying the coordinate of wherever the phone last was.
    func testTheNoteCarriesNothingTheShortcutDidNotAskFor() async throws {
        _ = try await CreateNoteIntent.createNote(
            title: "Shopping",
            content: "Milk",
            in: store
        )

        let note = try XCTUnwrap(store.notes.first)

        XCTAssertEqual(note.type, .text)
        XCTAssertFalse(note.pinned)
        XCTAssertFalse(note.isProtected)
        XCTAssertFalse(note.isDeleted)
        XCTAssertNil(note.reminder)
        XCTAssertNil(note.location)
        XCTAssertNil(note.color)
        XCTAssertTrue(note.tags.isEmpty)
    }

    /// Trimmed the way the form trims. Dictation leaves a trailing space behind and
    /// Shortcuts passes a text field along exactly as it was given, so without this
    /// the same note would be stored one way when spoken and another when typed.
    func testTrimsTitleAndBodyTheWayTheFormDoes() async throws {
        let created = try await CreateNoteIntent.createNote(
            title: "  Shopping \n",
            content: "\n  Milk, eggs  ",
            in: store
        )

        XCTAssertEqual(created.title, "Shopping")
        XCTAssertEqual(created.content, "Milk, eggs")
        XCTAssertEqual(store.notes.first?.title, "Shopping")
        XCTAssertEqual(store.notes.first?.content, "Milk, eggs")
    }

    /// The intent returning is the only signal the shortcut gets, and the process
    /// running it can be terminated straight afterwards — so "note created" has to
    /// mean the bytes are on the disk, not merely in an array. Asserted by reading
    /// the file back rather than by trusting `saveNow`'s answer.
    func testTheNoteReachesTheFileAndNotOnlyMemory() async throws {
        _ = try await CreateNoteIntent.createNote(
            title: "Shopping",
            content: "Milk",
            in: store
        )

        let stored = try NotesCodec.decodeStored(Data(contentsOf: store.fileURL))

        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.title, "Shopping")
        XCTAssertEqual(stored.first?.content, "Milk")
    }

    // MARK: - Refusing a note with no body

    /// The same rule the form's Save button is bound to. This is the one way into
    /// the store that goes around the form, and it used to create the note anyway —
    /// which renders as a blank row that opens onto nothing, indistinguishable from
    /// the notes the user meant to keep.
    func testRefusesABodyThatIsEmpty() async {
        let refused = await refusal(title: "Shopping", content: "", in: store)

        XCTAssertEqual(refused, .noContent)
        XCTAssertTrue(store.notes.isEmpty, "A refused shortcut must leave nothing behind")
    }

    /// The half of the same rule that `isEmpty` alone does not catch: `" "` is not
    /// empty, and a dictated note that picked up nothing but a space is exactly
    /// what arrives here.
    func testRefusesABodyOfNothingButWhitespace() async {
        let refused = await refusal(title: "Shopping", content: "  \n\t ", in: store)

        XCTAssertEqual(refused, .noContent)
        XCTAssertTrue(store.notes.isEmpty, "A refused shortcut must leave nothing behind")
    }

    /// A title is not a body. Refusing has to survive the note having something in
    /// it, or the rule would just be "the shortcut passed no arguments".
    func testATitleAloneIsNotEnoughToSaveANote() async {
        let refused = await refusal(title: "Shopping", content: "   ", in: store)

        XCTAssertEqual(refused, .noContent)
    }

    // MARK: - Which confirmation the user hears

    /// An untitled note has nothing to name, so the spoken answer falls back to the
    /// generic wording rather than reading out an empty pair of quotes.
    func testANoteWithNoTitleIsNotNamed() async throws {
        let created = try await CreateNoteIntent.createNote(
            title: nil,
            content: "Milk",
            in: store
        )

        XCTAssertEqual(created.title, "")
        XCTAssertFalse(created.isNamed)
    }

    /// And a title of nothing but whitespace is an untitled note, not a note named
    /// with a space — the trim happens before the confirmation is chosen, so the
    /// two cannot come apart.
    func testATitleOfNothingButWhitespaceIsNotNamed() async throws {
        let created = try await CreateNoteIntent.createNote(
            title: "   \n ",
            content: "Milk",
            in: store
        )

        XCTAssertEqual(created.title, "")
        XCTAssertFalse(created.isNamed)
    }

    func testANoteWithATitleIsNamedByIt() async throws {
        let created = try await CreateNoteIntent.createNote(
            title: "Shopping",
            content: "Milk",
            in: store
        )

        XCTAssertTrue(created.isNamed)
        XCTAssertEqual(created.title, "Shopping")
    }

    // MARK: - A store that cannot save

    /// A shortcut can be run while the device is locked, which is much of the point
    /// of one — and the notes file is written with `.completeFileProtection`, so
    /// the store it lands on may not have been able to read what is already in
    /// there. Saving then would put this one note where the user's whole library
    /// should be, so the store refuses; the intent must pass that on rather than
    /// answer "note created" for a note that is nowhere.
    func testAStoreThatCannotSaveIsReportedRatherThanClaimedAsSaved() async throws {
        let blocked = try makeBlockedStore()

        let refused = await refusal(title: "Shopping", content: "Milk", in: blocked)

        XCTAssertEqual(refused, .notSaved)
    }

    /// The note itself is deliberately kept. Where this is the running app rather
    /// than a one-shot intent process, `NotesStore.refresh()` folds it back in once
    /// storage becomes readable — so reporting the failure must not also throw away
    /// the thing it is reporting on.
    func testANoteThatCouldNotBeSavedIsStillKeptInMemory() async throws {
        let blocked = try makeBlockedStore()

        _ = await refusal(title: "Shopping", content: "Milk", in: blocked)

        XCTAssertEqual(blocked.notes.count, 1)
        XCTAssertEqual(blocked.notes.first?.content, "Milk")
    }

    /// An empty note is refused before the store is ever asked, so a blocked store
    /// reports the reason the shortcut can actually do something about. Nothing is
    /// left behind either way.
    func testAnEmptyNoteIsRefusedBeforeTheStoreIsAsked() async throws {
        let blocked = try makeBlockedStore()

        let refused = await refusal(title: nil, content: " ", in: blocked)

        XCTAssertEqual(refused, .noContent)
        XCTAssertTrue(blocked.notes.isEmpty)
    }

    // MARK: - What the user is told

    /// The two refusals say different things, and each says the right one. The
    /// message is all the user gets — a thrown intent surfaces as that sentence in
    /// Shortcuts and nothing else — so the two being swapped would tell someone
    /// whose note *was* refused for being empty that their device could not save
    /// it, and send them looking for a storage problem that is not there.
    ///
    /// Asserted by key rather than by rendered text, which is what makes this a
    /// test of the mapping rather than of the translation.
    /// `check-localization.sh` already asserts both keys exist in every language.
    func testEachRefusalCarriesItsOwnMessage() {
        XCTAssertEqual(
            CreateNoteError.noContent.localizedStringResource.key,
            "intentEmptyContent"
        )
        XCTAssertEqual(
            CreateNoteError.notSaved.localizedStringResource.key,
            "intentSaveFailed"
        )
    }
}
