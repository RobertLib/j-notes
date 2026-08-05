//
//  TagFilterTests.swift
//  notesTests
//

import XCTest
@testable import J_Notes

/// The rule that decides which notes a tag chip narrows the list to, and what
/// happens to that choice when the tags themselves change.
///
/// Exercised through `TagFilter` rather than through the view, for the reason the
/// type exists at all: `NotesView.selectedTag` is `@State` and not reachable from
/// a test.
final class TagFilterTests: XCTestCase {

    // MARK: - Which notes a filter narrows to

    func testNoSelectionNarrowsNothing() {
        let note = NoteModel(title: "A", content: "c", tags: ["work"])
        let untagged = NoteModel(title: "B", content: "c")

        XCTAssertTrue(TagFilter.matches(note, selected: nil))
        XCTAssertTrue(TagFilter.matches(untagged, selected: nil))
    }

    func testASelectionKeepsOnlyTheNotesCarryingThatTag() {
        let tagged = NoteModel(title: "A", content: "c", tags: ["work", "home"])
        let other = NoteModel(title: "B", content: "c", tags: ["home"])
        let untagged = NoteModel(title: "C", content: "c")

        XCTAssertTrue(TagFilter.matches(tagged, selected: "work"))
        XCTAssertFalse(TagFilter.matches(other, selected: "work"))
        XCTAssertFalse(TagFilter.matches(untagged, selected: "work"))
    }

    /// A note tagged "Práce" belongs under a filter set on "práce". They used to be
    /// two separate tags with two separate chips, each hiding the other's notes.
    func testAFilterMatchesWhateverCaseTheTagWasTypedIn() {
        let note = NoteModel(title: "A", content: "c", tags: ["Práce"])

        XCTAssertTrue(TagFilter.matches(note, selected: "práce"))
        XCTAssertTrue(TagFilter.matches(note, selected: "PRÁCE"))
        XCTAssertFalse(
            TagFilter.matches(note, selected: "prace"),
            "Diacritics are not case — those are different words"
        )
    }

    // MARK: - Which chip reads as selected

    func testTheSelectedChipIsTheOneMatchingTheFilter() {
        XCTAssertTrue(TagFilter.isSelected("work", selected: "work"))
        XCTAssertFalse(TagFilter.isSelected("home", selected: "work"))
    }

    func testNoChipIsSelectedWithoutAFilter() {
        XCTAssertFalse(TagFilter.isSelected("work", selected: nil))
    }

    /// `allTags` keeps one of "Práce" and "práce", and which one depends on what
    /// else is in the library — so the chip has to recognise itself through the
    /// same case-folding rule rather than by exact text, or the row would show a
    /// filter in force with nothing highlighted.
    func testTheChipStaysSelectedWhenTheSurvivingSpellingChanges() {
        XCTAssertTrue(TagFilter.isSelected("práce", selected: "Práce"))
    }

    // MARK: - Surviving a change to the tags on offer

    func testAFilterSurvivesWhileItsTagIsStillInUse() {
        XCTAssertEqual(
            TagFilter.surviving("work", in: ["home", "work"]),
            "work"
        )
    }

    /// The bug this rule exists for. The chip row is drawn from the store and the
    /// selection is view state, so deleting the last note carrying the selected tag
    /// took the chip away and left the filter behind: the list said "no notes match
    /// your search" for a filter nothing on screen was showing.
    func testAFilterIsDroppedOnceNoNoteCarriesItsTag() {
        XCTAssertNil(TagFilter.surviving("work", in: ["home"]))
    }

    /// The worst form of it: the selected tag was the only one, so the whole chip
    /// row went with it — an empty list, no explanation, and no control left to
    /// clear the filter with. The selection is `@State`, so only relaunching the
    /// app recovered from it.
    func testAFilterIsDroppedWhenTheLastTagInTheLibraryGoes() {
        XCTAssertNil(TagFilter.surviving("work", in: []))
    }

    /// Re-anchored onto the spelling that is actually on screen rather than merely
    /// kept, so a filter set on "Práce" goes on working once the last note spelling
    /// it that way is gone and "práce" is what the row now shows.
    func testAFilterFollowsTheSurvivingSpellingOfItsTag() {
        XCTAssertEqual(
            TagFilter.surviving("Práce", in: ["práce"]),
            "práce"
        )
    }

    func testNoSelectionSurvivesAsNoSelection() {
        XCTAssertNil(TagFilter.surviving(nil, in: ["work"]))
        XCTAssertNil(TagFilter.surviving(nil, in: []))
    }

    /// The end-to-end shape of the fix, spelled with the store: a tag filter set on
    /// the only tagged note, and the note then deleted. What the view does with the
    /// two is one line, but these are the two values it puts together.
    @MainActor
    func testDeletingTheLastTaggedNoteLeavesNoFilterBehind() {
        let store = NotesStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).json")
        )
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        store.add(title: "Tagged", content: "c", tags: ["work"])
        let selected = "work"

        XCTAssertEqual(TagFilter.surviving(selected, in: store.allTags), "work")

        store.moveToTrash(note: store.notes[0])

        XCTAssertEqual(store.allTags, [])
        XCTAssertNil(
            TagFilter.surviving(selected, in: store.allTags),
            "The chip is gone, so the filter it named must go with it"
        )
    }
}
