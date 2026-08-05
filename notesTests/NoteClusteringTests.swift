//
//  NoteClusteringTests.swift
//  notesTests
//

import XCTest
import CoreLocation
import SwiftUI
@testable import J_Notes

/// Which notes share a pin on the map. The rule used to live inside `MapView` as a
/// computed property, where nothing could reach it — and the grid it is built on is
/// an optimisation whose whole claim is that it changes none of these answers.
final class NoteClusteringTests: XCTestCase {

    private func note(at coordinate: [Double]?, color: Color? = nil) -> NoteModel {
        NoteModel(title: "", content: "x", color: color, location: coordinate)
    }

    // MARK: - What gets a pin at all

    func testNotesWithoutALocationGetNoPin() {
        let groups = NoteClustering.groups(for: [note(at: nil), note(at: nil)])

        XCTAssertTrue(groups.isEmpty)
    }

    /// A bare array of doubles can arrive from a hand-edited backup one element
    /// short, and (0, 0) is a real place in the Gulf of Guinea — see
    /// `NoteModel.coordinate`.
    func testATruncatedCoordinateGetsNoPin() {
        let groups = NoteClustering.groups(for: [note(at: [50.0])])

        XCTAssertTrue(groups.isEmpty)
    }

    /// Out-of-range values would otherwise be snapped to a grid cell, which is
    /// arithmetic no bogus coordinate should be trusted with.
    func testAnOutOfRangeCoordinateGetsNoPin() {
        let groups = NoteClustering.groups(
            for: [note(at: [91.0, 14.0]), note(at: [50.0, 181.0])]
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testAPlacedNoteGetsItsOwnPin() {
        let groups = NoteClustering.groups(for: [note(at: [50.0, 14.0])])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].notes.count, 1)
        XCTAssertEqual(groups[0].coordinate.latitude, 50.0, accuracy: 1e-9)
        XCTAssertEqual(groups[0].coordinate.longitude, 14.0, accuracy: 1e-9)
    }

    /// One unusable coordinate must not take the usable ones with it.
    func testUnplaceableNotesAreSkippedWithoutDroppingTheRest() {
        let groups = NoteClustering.groups(
            for: [note(at: nil), note(at: [50.0, 14.0]), note(at: [91.0, 14.0])]
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].notes.count, 1)
    }

    // MARK: - Tolerance

    func testNotesCloserThanTheToleranceShareAPin() {
        let groups = NoteClustering.groups(
            for: [
                note(at: [50.0, 14.0]),
                note(at: [50.0 + NoteClustering.coordinateTolerance / 2, 14.0])
            ]
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].notes.count, 2)
    }

    func testNotesFurtherApartThanTheToleranceGetSeparatePins() {
        let groups = NoteClustering.groups(
            for: [
                note(at: [50.0, 14.0]),
                note(at: [50.0 + NoteClustering.coordinateTolerance * 2, 14.0])
            ]
        )

        XCTAssertEqual(groups.count, 2)
    }

    /// Longitude is tested on its own, not folded into a single distance: two notes
    /// a whole degree apart east-west used to be one pin if a comparison lost a
    /// term.
    func testLongitudeIsComparedAsWellAsLatitude() {
        let groups = NoteClustering.groups(
            for: [note(at: [50.0, 14.0]), note(at: [50.0, 15.0])]
        )

        XCTAssertEqual(groups.count, 2)
    }

    /// The grid is one tolerance wide, so a matching group can sit in a
    /// neighbouring cell rather than the note's own — which is the whole reason the
    /// eight around it are searched. A pair straddling a cell boundary is what
    /// catches a search that only ever looked in one.
    func testNotesStraddlingAGridBoundaryStillShareAPin() {
        let tolerance = NoteClustering.coordinateTolerance

        // Just under a cell edge, and just over it: within tolerance of each
        // other, but on opposite sides of the grid line.
        let below = 50.0 + tolerance * 0.999
        let above = 50.0 + tolerance * 1.001

        XCTAssertNotEqual(
            NoteClustering.GridCell(CLLocationCoordinate2D(latitude: below, longitude: 14.0)),
            NoteClustering.GridCell(CLLocationCoordinate2D(latitude: above, longitude: 14.0)),
            "the two coordinates have to land in different cells for this to test anything"
        )

        let groups = NoteClustering.groups(
            for: [note(at: [below, 14.0]), note(at: [above, 14.0])]
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].notes.count, 2)
    }

    /// The tolerance test is not transitive, and the grid must not quietly make it
    /// so: A and B pair up, C is too far from A — the coordinate the group is
    /// anchored to — so it gets its own pin even though it is close to B.
    func testAThirdNoteIsComparedAgainstTheGroupsAnchorNotItsMembers() {
        let step = NoteClustering.coordinateTolerance * 0.9

        let groups = NoteClustering.groups(
            for: [
                note(at: [50.0, 14.0]),
                note(at: [50.0 + step, 14.0]),
                note(at: [50.0 + step * 2, 14.0])
            ]
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].notes.count, 2)
        XCTAssertEqual(groups[1].notes.count, 1)
    }

    // MARK: - Identity and order

    /// `groupedNotes` is recomputed on every pass through `body`, so an id that
    /// changed between passes would make `ForEach` rebuild every annotation.
    func testAGroupsIdentityIsStableAcrossEvaluations() {
        let notes = [note(at: [50.0, 14.0]), note(at: [49.0, 16.0])]

        let first = NoteClustering.groups(for: notes).map(\.id)
        let second = NoteClustering.groups(for: notes).map(\.id)

        XCTAssertEqual(first, second)
    }

    /// Two pins on the same map must not share an id, or the `ForEach` drawing them
    /// is ill-defined.
    func testSeparatePinsHaveDistinctIdentities() {
        let groups = NoteClustering.groups(
            for: [note(at: [50.0, 14.0]), note(at: [49.0, 16.0]), note(at: [48.0, 17.0])]
        )

        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
    }

    func testGroupsKeepTheOrderTheNotesArrivedIn() {
        let groups = NoteClustering.groups(
            for: [note(at: [49.0, 16.0]), note(at: [50.0, 14.0])]
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].coordinate.latitude, 49.0, accuracy: 1e-9)
        XCTAssertEqual(groups[1].coordinate.latitude, 50.0, accuracy: 1e-9)
    }

    // MARK: - Pin colour

    func testALoneNoteLendsItsColourToThePin() {
        let groups = NoteClustering.groups(for: [note(at: [50.0, 14.0], color: .red)])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].pinColor, Color.red)
    }

    /// A group has no single colour to speak for it, so it falls back to the same
    /// grey a colourless note gets.
    func testAGroupedPinFallsBackToGrey() {
        let grouped = NoteClustering.groups(
            for: [
                note(at: [50.0, 14.0], color: .red),
                note(at: [50.0, 14.0], color: .blue)
            ]
        )
        let colourless = NoteClustering.groups(for: [note(at: [49.0, 16.0])])

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(colourless.count, 1)
        XCTAssertEqual(grouped[0].pinColor, colourless[0].pinColor)
        XCTAssertNotEqual(grouped[0].pinColor, Color.red)
    }
}
