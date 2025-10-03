//
//  LocationManagerTests.swift
//  notesTests
//
//  Created by Robert Libšanský on 04.10.2025.
//

import XCTest
import CoreLocation
@testable import J_Notes

@MainActor
final class LocationManagerTests: XCTestCase {

    func testLocationManagerInitialization() {
        let manager = LocationManager()
        XCTAssertNotNil(manager)
        XCTAssertNotNil(manager.region)
    }

    func testLastLocation() {
        let manager = LocationManager()
        manager.lastLocationStorage = "50.0,14.0"
        let location = manager.lastLocation
        XCTAssertEqual(location.count, 2)
    }
}
