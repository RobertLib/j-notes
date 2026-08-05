//
//  LocationManagerTests.swift
//  notesTests
//
//  Created by Robert Libšanský on 04.10.2025.
//

import XCTest
import CoreLocation
import MapKit
@testable import J_Notes

@MainActor
final class LocationManagerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        clearStoredFix()
    }

    override func tearDown() async throws {
        clearStoredFix()
        try await super.tearDown()
    }

    private func clearStoredFix() {
        UserDefaults.standard.removeObject(forKey: "lastLocation")
        UserDefaults.standard.removeObject(forKey: "lastLocationDate")
    }

    func testLocationManagerInitialization() {
        let manager = LocationManager()
        XCTAssertNotNil(manager.region)
    }

    func testLastLocationParsesStoredFix() {
        let manager = LocationManager()
        manager.lastLocationStorage = "50.0,14.0"

        let location = manager.lastLocation
        XCTAssertEqual(location?.count, 2)
        XCTAssertEqual(location?[0], 50.0)
        XCTAssertEqual(location?[1], 14.0)
    }

    /// A note must never be stamped with a placeholder coordinate, so
    /// `lastLocation` stays nil until the device reports a real fix.
    func testLastLocationIsNilWithoutAFix() {
        let manager = LocationManager()
        XCTAssertNil(manager.lastLocation)
    }

    func testLastLocationIsNilForMalformedStorage() {
        let manager = LocationManager()

        manager.lastLocationStorage = "not-a-coordinate"
        XCTAssertNil(manager.lastLocation)

        manager.lastLocationStorage = "50.0"
        XCTAssertNil(manager.lastLocation)

        manager.lastLocationStorage = ""
        XCTAssertNil(manager.lastLocation)
    }

    /// The map still needs somewhere to point when there is no fix.
    func testRegionFallsBackToDefaultCenter() {
        let manager = LocationManager()

        XCTAssertEqual(manager.region.center.latitude, defaultMapCenter.latitude, accuracy: 0.0001)
        XCTAssertEqual(manager.region.center.longitude, defaultMapCenter.longitude, accuracy: 0.0001)
    }

    func testRegionUsesStoredFixWhenAvailable() {
        LocationManager().lastLocationStorage = "49.1951,16.6068" // Brno

        let restored = LocationManager()
        XCTAssertEqual(restored.region.center.latitude, 49.1951, accuracy: 0.0001)
        XCTAssertEqual(restored.region.center.longitude, 16.6068, accuracy: 0.0001)
    }

    /// A fix restored from `UserDefaults` is not a new delivery. The map follows
    /// `latestFix` to decide whether to move its camera, so treating a stored one
    /// as fresh would snap the map away from wherever the user had panned.
    func testLatestFixIsNilUntilOneIsDelivered() {
        LocationManager().lastLocationStorage = "50.0,14.0"

        let restored = LocationManager()
        XCTAssertEqual(restored.lastLocation, [50.0, 14.0])
        XCTAssertNil(restored.latestFix)
    }

    // MARK: - Telling one delivery from the next

    /// The map moves its camera from `onChange(of: latestFix)`, which compares. Two
    /// deliveries of the same coordinates therefore have to be different values, or
    /// the locate button does nothing at all whenever Core Location has nothing
    /// newer to say — which standing still is precisely the case of, since
    /// `requestLocation()` hands back a recent cached reading.
    func testTwoDeliveriesOfTheSameCoordinatesAreNotEqual() {
        let first = LocationFix(latitude: 50.0, longitude: 14.0, sequence: 1)
        let second = LocationFix(latitude: 50.0, longitude: 14.0, sequence: 2)

        XCTAssertNotEqual(first, second)
    }

    func testTheSameDeliveryIsEqualToItself() {
        XCTAssertEqual(
            LocationFix(latitude: 50.0, longitude: 14.0, sequence: 3),
            LocationFix(latitude: 50.0, longitude: 14.0, sequence: 3)
        )
    }

    // MARK: - Reacting to authorization

    /// Core Location calls `locationManagerDidChangeAuthorization` once merely
    /// because a delegate was assigned, reporting whatever status was already in
    /// force. Treating that as a fresh grant meant every launch of an
    /// already-authorized app went and fetched the user's location — status bar
    /// indicator and all — however little of the app they then used.
    func testAStatusMerelyReportedBackAsksForNoFix() {
        for status in [CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways] {
            XCTAssertFalse(
                LocationManager.shouldRequestFix(for: status, previously: status),
                "\(status.rawValue) reported unchanged should not request a fix"
            )
        }
    }

    /// The grant `requestLocation()` asked for landing is the one case that should:
    /// the fix it could not make at the time is made then.
    func testAGrantThatHasJustLandedAsksForAFix() {
        XCTAssertTrue(
            LocationManager.shouldRequestFix(
                for: .authorizedWhenInUse,
                previously: .notDetermined
            )
        )
        XCTAssertTrue(
            LocationManager.shouldRequestFix(
                for: .authorizedAlways,
                previously: .denied
            )
        )
    }

    func testLosingAuthorizationAsksForNoFix() {
        XCTAssertFalse(
            LocationManager.shouldRequestFix(
                for: .denied,
                previously: .authorizedWhenInUse
            )
        )
        XCTAssertFalse(
            LocationManager.shouldRequestFix(
                for: .notDetermined,
                previously: .authorizedAlways
            )
        )
    }

    func testAuthorizedStatusesAreRecognised() {
        XCTAssertTrue(LocationManager.isAuthorized(.authorizedAlways))
        XCTAssertTrue(LocationManager.isAuthorized(.authorizedWhenInUse))
        XCTAssertFalse(LocationManager.isAuthorized(.notDetermined))
        XCTAssertFalse(LocationManager.isAuthorized(.denied))
        XCTAssertFalse(LocationManager.isAuthorized(.restricted))
    }

    /// What the map's locate button checks before asking: refusal produces neither a
    /// prompt nor a fix, so the press has to be answered with a word rather than
    /// with nothing. `.notDetermined` deliberately is not refusal — there the
    /// request itself is the feedback, since it puts the system prompt on screen.
    func testOnlyARefusalCountsAsDenied() {
        XCTAssertTrue(LocationManager.isDenied(.denied))
        XCTAssertTrue(LocationManager.isDenied(.restricted))
        XCTAssertFalse(LocationManager.isDenied(.notDetermined))
        XCTAssertFalse(LocationManager.isDenied(.authorizedWhenInUse))
        XCTAssertFalse(LocationManager.isDenied(.authorizedAlways))
    }

    // MARK: - Fix freshness

    func testRecentLocationReturnsAFreshFix() {
        let manager = LocationManager()
        manager.lastLocationStorage = "50.0,14.0"
        manager.lastLocationDateStorage = Date()

        XCTAssertEqual(manager.recentLocation, [50.0, 14.0])
    }

    /// A new note must not inherit a coordinate from wherever the app was opened
    /// days ago, even though the map still frames itself with it.
    func testRecentLocationRejectsAStaleFix() {
        let manager = LocationManager()
        manager.lastLocationStorage = "49.1951,16.6068"
        manager.lastLocationDateStorage = Date()
            .addingTimeInterval(-LocationManager.maxFixAge - 60)

        XCTAssertNil(manager.recentLocation)
        XCTAssertEqual(manager.lastLocation, [49.1951, 16.6068])
    }

    /// Fixes stored by versions that kept no timestamp cannot be dated, so they
    /// are treated as stale rather than assumed current.
    func testRecentLocationRejectsAnUndatedFix() {
        let manager = LocationManager()
        manager.lastLocationStorage = "50.0,14.0"

        XCTAssertNil(manager.recentLocation)
    }
}
