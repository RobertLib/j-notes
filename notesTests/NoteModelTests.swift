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
        XCTAssertFalse(note.isDeleted)
        XCTAssertFalse(note.isProtected)
        XCTAssertEqual(note.tags, [])
        XCTAssertEqual(note.type, .text)
    }

    func testCoordinateWithValidLocation() throws {
        let note = NoteModel(
            title: "Prague Note",
            content: "Located in Prague",
            location: [50.0495641, 14.4362814]
        )

        let coordinate = try XCTUnwrap(note.coordinate)
        XCTAssertEqual(coordinate.latitude, 50.0495641, accuracy: 0.0001)
        XCTAssertEqual(coordinate.longitude, 14.4362814, accuracy: 0.0001)
    }

    func testCoordinateIsNilWithoutALocation() {
        XCTAssertNil(NoteModel(title: "Nowhere", content: "Content").coordinate)
    }

    /// `location` is a bare array of doubles, so a hand-edited or truncated backup
    /// can carry one that is not a coordinate. It used to fall back to (0, 0),
    /// which is a real place — the map pinned the note in the Gulf of Guinea.
    func testCoordinateIsNilForATruncatedLocation() {
        XCTAssertNil(
            NoteModel(title: "Half a fix", content: "Content", location: []).coordinate
        )
        XCTAssertNil(
            NoteModel(title: "Half a fix", content: "Content", location: [50.0495641]).coordinate
        )
    }

    // MARK: - Codable

    func testCodableRoundTripPreservesAllFields() throws {
        let original = NoteModel(
            title: "Full",
            content: "Content",
            type: .drawing,
            drawingData: Data([0x01, 0x02]),
            drawingCanvasSize: CGSize(width: 300, height: 400),
            backgroundImageData: Data([0x03]),
            pinned: true,
            color: .blue,
            reminder: Date(timeIntervalSince1970: 1_700_000_000),
            notificationIdentifiers: ["abc"],
            location: [50.0, 14.0],
            isDeleted: true,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_100),
            tags: ["work", "urgent"],
            isProtected: true
        )

        let decoded = try JSONDecoder().decode(
            NoteModel.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.type, .drawing)
        XCTAssertEqual(decoded.drawingData, original.drawingData)
        XCTAssertEqual(decoded.drawingCanvasSize, original.drawingCanvasSize)
        XCTAssertEqual(decoded.backgroundImageData, original.backgroundImageData)
        XCTAssertTrue(decoded.pinned)
        XCTAssertNotNil(decoded.color)
        XCTAssertEqual(decoded.reminder, original.reminder)
        XCTAssertEqual(decoded.notificationIdentifiers, ["abc"])
        XCTAssertEqual(decoded.location, [50.0, 14.0])
        XCTAssertTrue(decoded.isDeleted)
        XCTAssertEqual(decoded.deletedAt, original.deletedAt)
        XCTAssertEqual(decoded.tags, ["work", "urgent"])
        XCTAssertTrue(decoded.isProtected)
    }

    // MARK: - Colour storage

    /// The on-disk shape must not move: colours were encoded by a retroactive
    /// `Color: Codable` conformance before `CodableColor` took over, and every
    /// note already on a device was written with that layout.
    func testColorIsStoredAsItsComponents() throws {
        let note = NoteModel(title: "Coloured", content: "c", color: Color(red: 0.25, green: 0.5, blue: 0.75))

        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(note)
        ) as? [String: Any]

        let color = try XCTUnwrap(json?["color"] as? [String: Any])

        XCTAssertEqual(try XCTUnwrap(color["red"] as? Double), 0.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(color["green"] as? Double), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(color["blue"] as? Double), 0.75, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(color["alpha"] as? Double), 1.0, accuracy: 0.001)
    }

    /// A dynamic colour must encode to the same components whatever appearance
    /// happens to be current. It used to be read through `UITraitCollection`, so
    /// the same pick was stored differently in light and dark mode — and
    /// `.primary` was stored as white, which is invisible as a map pin.
    func testDynamicColorIsStoredIndependentlyOfTheCurrentAppearance() throws {
        func encodedComponents(inStyle style: UIUserInterfaceStyle) throws -> [Double] {
            var json: [String: Any]?

            UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                let note = NoteModel(title: "Dynamic", content: "c", color: .primary)
                json = try? JSONSerialization.jsonObject(
                    with: try JSONEncoder().encode(note)
                ) as? [String: Any]
            }

            let color = try XCTUnwrap(json?["color"] as? [String: Any])
            return try ["red", "green", "blue", "alpha"].map {
                try XCTUnwrap(color[$0] as? Double)
            }
        }

        let light = try encodedComponents(inStyle: .light)
        let dark = try encodedComponents(inStyle: .dark)

        XCTAssertEqual(light, dark, "The stored colour must not depend on the appearance at save time")
    }

    /// Colours written before the alpha channel existed decode as opaque
    /// rather than throwing and taking the whole file down with them.
    func testColorWithoutAlphaDecodesAsOpaque() throws {
        let json = Data("""
        {"red": 1.0, "green": 0.0, "blue": 0.0}
        """.utf8)

        let decoded = try JSONDecoder().decode(CodableColor.self, from: json)

        XCTAssertEqual(decoded.alpha, 1.0)
    }

    /// Notes written by older versions predate tags, trash and protection.
    func testDecodingLegacyNoteAppliesDefaults() throws {
        let legacy = """
        [{
            "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
            "createdAt": 700000000,
            "title": "Legacy",
            "content": "Written before tags existed",
            "type": "text",
            "pinned": false
        }]
        """.data(using: .utf8)!

        let notes = try JSONDecoder().decode([NoteModel].self, from: legacy)
        let note = try XCTUnwrap(notes.first)

        XCTAssertEqual(note.title, "Legacy")
        XCTAssertFalse(note.isDeleted)
        XCTAssertNil(note.deletedAt)
        XCTAssertEqual(note.tags, [])
        XCTAssertFalse(note.isProtected)
        XCTAssertNil(note.notificationIdentifiers)
    }

    // MARK: - Tags

    func testUniqueTagsKeepsTheFirstOfEachAndTheOrder() {
        XCTAssertEqual(
            NoteModel.uniqueTags(["work", "home", "work", "urgent", "home"]),
            ["work", "home", "urgent"]
        )
    }

    func testUniqueTagsLeavesAnAlreadyUniqueListAlone() {
        XCTAssertEqual(NoteModel.uniqueTags(["work", "home"]), ["work", "home"])
        XCTAssertEqual(NoteModel.uniqueTags([]), [])
    }

    /// Tags that differ only in case are the same tag, exactly as the form's own
    /// `addTag` and the store's `allTags` treat them — the three rules have to
    /// agree or a tag typed in the app would survive a round trip through a backup
    /// differently. They used to be distinct everywhere, which put two chips in the
    /// filter row for one tag, each hiding the other's notes, while the search
    /// field had always matched them case-insensitively.
    func testUniqueTagsFoldsCase() {
        XCTAssertEqual(
            NoteModel.uniqueTags(["Work", "work"]),
            ["Work"],
            "The first spelling is the one that survives"
        )
    }

    /// Diacritics are not case. Folding them too would merge tags the user can see
    /// are different words.
    func testUniqueTagsKeepsDiacriticsSignificant() {
        XCTAssertEqual(NoteModel.uniqueTags(["práce", "prace"]), ["práce", "prace"])
    }

    /// The one rule the form, the store and the decoder all read.
    func testTagsMatchIgnoresCaseOnly() {
        XCTAssertTrue(NoteModel.tagsMatch("Práce", "práce"))
        XCTAssertTrue(NoteModel.tagsMatch("WORK", "work"))
        XCTAssertTrue(NoteModel.tagsMatch("work", "work"))

        XCTAssertFalse(NoteModel.tagsMatch("práce", "prace"))
        XCTAssertFalse(NoteModel.tagsMatch("work", "works"))
        XCTAssertFalse(NoteModel.tagsMatch("work", " work"))
    }

    // MARK: - The widget's deep link

    /// The link the widget builds has to come back as the note it named, or the
    /// tap lands on the list — which is what it did before the link existed, and
    /// therefore invisible.
    func testADeepLinkRoundTripsToItsNote() throws {
        let id = UUID()
        let url = try XCTUnwrap(NoteDeepLink.url(for: id))

        XCTAssertEqual(NoteDeepLink.noteID(from: url), id)
    }

    /// `onOpenURL` sees every URL the app is asked to open, so anything that is
    /// not one of these links has to come back as nothing rather than as whatever
    /// its last path component happens to parse as.
    func testAnUnrelatedURLNamesNoNote() throws {
        let id = UUID().uuidString

        XCTAssertNil(
            NoteDeepLink.noteID(from: try XCTUnwrap(URL(string: "https://example.com/note/\(id)"))),
            "Right shape, wrong scheme"
        )
        XCTAssertNil(
            NoteDeepLink.noteID(from: try XCTUnwrap(URL(string: "j-notes://tag/\(id)"))),
            "Right scheme, wrong host"
        )
        XCTAssertNil(
            NoteDeepLink.noteID(from: try XCTUnwrap(URL(string: "j-notes://note/not-a-uuid"))),
            "Right shape, not an identifier"
        )
    }

    /// A backup is whatever the user hands over — hand-edited, or written by another
    /// build — and every list in the app renders tags through `ForEach(id: \.self)`,
    /// where two entries sharing an id leaves the layout ill-defined.
    func testDecodingDropsRepeatedTags() throws {
        let json = """
        [{
            "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3302",
            "createdAt": 700000000,
            "title": "Hand-edited",
            "content": "Body",
            "type": "text",
            "pinned": false,
            "tags": ["work", "home", "work"]
        }]
        """.data(using: .utf8)!

        let note = try XCTUnwrap(
            try JSONDecoder().decode([NoteModel].self, from: json).first
        )

        XCTAssertEqual(note.tags, ["work", "home"])
    }

    // MARK: - Widget payload

    /// The App Group container has no file protection and the widget renders on
    /// the home screen, so nothing readable may leave for a protected note.
    func testWidgetEntryOmitsProtectedNoteText() {
        let note = NoteModel(
            title: "Bank PIN",
            content: "1234",
            tags: ["private"],
            isProtected: true
        )

        let entry = WidgetNoteEntry(from: note)

        XCTAssertTrue(entry.title.isEmpty)
        XCTAssertTrue(entry.content.isEmpty)
        XCTAssertTrue(entry.isProtected)
    }

    func testWidgetEntryKeepsUnprotectedNoteText() {
        let note = NoteModel(title: "Shopping", content: "Milk", tags: ["home"])

        let entry = WidgetNoteEntry(from: note)

        XCTAssertEqual(entry.title, "Shopping")
        XCTAssertEqual(entry.content, "Milk")
        XCTAssertFalse(entry.isProtected)
    }

    /// Tags are not part of the payload at all, for any note. The widget has
    /// never rendered them, so sharing them only put more of the user's text into
    /// a container that — unlike the notes file — is readable while the device is
    /// locked.
    ///
    /// Asserted against the encoded bytes rather than the type: those bytes are
    /// what actually reaches the App Group, and a field added back would sail
    /// past a test that only reads the properties it already knows about.
    func testWidgetPayloadCarriesNoTags() throws {
        let note = NoteModel(title: "Shopping", content: "Milk", tags: ["home", "urgent"])

        let encoded = try JSONEncoder().encode(WidgetNoteEntry(from: note))
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertFalse(json.contains("tags"))
        XCTAssertFalse(json.contains("home"))
        XCTAssertFalse(json.contains("urgent"))
        // The fields that are meant to be there still are, so an empty payload
        // cannot pass this by accident.
        XCTAssertTrue(json.contains("Shopping"))
        XCTAssertTrue(json.contains("Milk"))
    }

    /// Nor is the note's creation date, by the same rule and for the same reason.
    /// The widget renders no dates, and it never needed them to sort by either —
    /// the payload's order is decided in the app, by `NotesStore.widgetPayload`.
    /// What was left was one more piece of the user's record sitting in a
    /// container that, unlike the notes file, is readable while the device is
    /// locked.
    func testWidgetPayloadCarriesNoCreationDate() throws {
        let note = NoteModel(title: "Shopping", content: "Milk")

        let encoded = try JSONEncoder().encode(WidgetNoteEntry(from: note))
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertFalse(json.contains("createdAt"))
        XCTAssertTrue(json.contains("Shopping"), "...and the payload is not simply empty")
    }

    // MARK: - Display and notification text

    func testDisplayTitleFallsBackForUntitledNote() {
        XCTAssertEqual(
            NoteModel(title: "", content: "Body").displayTitle,
            String(localized: "note")
        )
        XCTAssertEqual(
            NoteModel(title: "Groceries", content: "Body").displayTitle,
            "Groceries"
        )
    }

    /// A reminder lands on the lock screen, and a protected note's title is user
    /// text just as its body is — so it is redacted too. The widget payload
    /// already did this; the notification used to send the title verbatim.
    func testNotificationTitleHidesProtectedNoteTitle() {
        let plain = NoteModel(title: "Call", content: "Ring the dentist")
        XCTAssertEqual(plain.notificationTitle, "Call")

        let locked = NoteModel(title: "Bank PIN", content: "1234", isProtected: true)
        XCTAssertNotEqual(locked.notificationTitle, "Bank PIN")
        XCTAssertEqual(locked.notificationTitle, String(localized: "reminder"))

        // An untitled note still needs a non-empty title, protected or not.
        let untitled = NoteModel(title: "", content: "Body")
        XCTAssertEqual(untitled.notificationTitle, String(localized: "note"))
    }

    /// A reminder lands on the lock screen, so a protected note's body must not
    /// be used as the notification subtitle.
    func testNotificationSubtitleHidesProtectedContent() {
        let plain = NoteModel(title: "Call", content: "Ring the dentist")
        XCTAssertEqual(plain.notificationSubtitle, "Ring the dentist")

        let locked = NoteModel(title: "Bank", content: "PIN 1234", isProtected: true)
        XCTAssertEqual(locked.notificationSubtitle, String(localized: "lockedNote"))

        let drawing = NoteModel(title: "Sketch", content: "", type: .drawing)
        XCTAssertEqual(drawing.notificationSubtitle, String(localized: "drawingNote"))
    }

    // MARK: - Search

    /// The whole point of the lock is that the body stays unread, and a note
    /// surfacing in the results says the term is in there whether or not the row
    /// prints it. Title and tags stay searchable because the row shows them
    /// regardless.
    func testSearchDoesNotMatchAProtectedNoteBody() {
        let locked = NoteModel(
            title: "Bank",
            content: "PIN is 4321",
            tags: ["finance"],
            isProtected: true
        )

        XCTAssertFalse(locked.matches(query: "4321"))
        XCTAssertFalse(locked.matches(query: "PIN"))

        XCTAssertTrue(locked.matches(query: "Bank"))
        XCTAssertTrue(locked.matches(query: "finance"))
    }

    func testSearchMatchesAnUnprotectedNoteBody() {
        let note = NoteModel(title: "Shopping", content: "Milk and eggs")

        XCTAssertTrue(note.matches(query: "Milk"))
        XCTAssertTrue(note.matches(query: "milk"), "search is case-insensitive")
        XCTAssertFalse(note.matches(query: "bread"))
    }

    /// An empty query is not a filter — every note stays in the list. Whitespace
    /// counts as empty, since the field is trimmed before it is used.
    func testSearchWithAnEmptyQueryMatchesEverything() {
        let note = NoteModel(title: "Shopping", content: "Milk")
        let locked = NoteModel(title: "Bank", content: "PIN", isProtected: true)

        for query in ["", "   "] {
            XCTAssertTrue(note.matches(query: query))
            XCTAssertTrue(locked.matches(query: query))
        }
    }

    /// The query is trimmed, so a trailing space typed after a word does not empty
    /// the list.
    func testSearchTrimsTheQuery() {
        let note = NoteModel(title: "Shopping", content: "Milk")

        XCTAssertTrue(note.matches(query: " Milk "))
    }

    // MARK: - Copy and tweak

    /// Mutating a copy must not disturb the note's identity or its trash state —
    /// re-listing fields through the initialiser used to drop them.
    func testMutatingACopyPreservesIdentityAndTrashState() {
        let original = NoteModel(
            title: "Doomed",
            content: "Old",
            isDeleted: true,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        var copy = original
        copy.content = "New"

        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(copy.createdAt, original.createdAt)
        XCTAssertEqual(copy.content, "New")
        XCTAssertTrue(copy.isDeleted)
        XCTAssertEqual(copy.deletedAt, original.deletedAt)
    }
}
