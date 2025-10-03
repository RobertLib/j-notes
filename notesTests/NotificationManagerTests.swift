//
//  NotificationManagerTests.swift
//  notesTests
//
//  Created by Robert Libšanský on 04.10.2025.
//

import XCTest
@testable import J_Notes

@MainActor
final class NotificationManagerTests: XCTestCase {

    func testSingleton() {
        let instance1 = NotificationManager.instance
        let instance2 = NotificationManager.instance
        XCTAssertTrue(instance1 === instance2)
    }

    func testScheduleNotification() async {
        let manager = NotificationManager.instance
        let date = Date().addingTimeInterval(3600)
        let id = await manager.scheduleNotification(title: "Test", subtitle: "Test", date: date)
        XCTAssertFalse(id.isEmpty)
        await manager.removeNotifications(identifiers: [id])
    }
}
