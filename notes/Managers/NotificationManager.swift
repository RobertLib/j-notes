//
//  NotificationManager.swift
//  notes
//
//  Created by Robert Libšanský on 24.07.2022.
//

import SwiftUI
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let instance = NotificationManager()

    private init() {}

    func requestAuthorization() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: options)
            if granted {
                print("✅ Notification authorization granted")
            } else {
                print("⚠️ Notification authorization denied")
            }
            return granted
        } catch {
            print("❌ Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    func scheduleNotification(
        title: String,
        subtitle: String,
        date: Date
    ) async -> String {
        let content = UNMutableNotificationContent()

        content.title = title
        content.subtitle = subtitle
        content.sound = .default

        // Badge will be set based on pending notifications count
        let pendingCount = await UNUserNotificationCenter.current()
            .pendingNotificationRequests().count
        content.badge = NSNumber(value: pendingCount + 1)

        let dateMatching = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateMatching,
            repeats: false
        )

        let identifier = UUID().uuidString

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Notification scheduled for \(date)")
        } catch {
            print("❌ Failed to schedule notification: \(error.localizedDescription)")
        }

        return identifier
    }

    func removeNotifications(identifiers: [String]?) async {
        guard let identifiers = identifiers, !identifiers.isEmpty else {
            return
        }

        let center = UNUserNotificationCenter.current()

        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        // Update badge count after removal
        await updateBadgeCount()

        print("✅ Removed \(identifiers.count) notification(s)")
    }

    func updateBadgeCount() async {
        do {
            let center = UNUserNotificationCenter.current()
            let pendingRequests = await center.pendingNotificationRequests()
            let deliveredNotifications = await center.deliveredNotifications()

            // Set badge to total of pending + delivered notifications
            let totalCount = pendingRequests.count + deliveredNotifications.count
            try await center.setBadgeCount(totalCount)

            print("✅ Badge count updated to \(totalCount)")
        } catch {
            print("❌ Failed to update badge count: \(error.localizedDescription)")
        }
    }

    /// Reset badge count to 0
    func resetBadgeCount() async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
            print("✅ Badge count reset to 0")
        } catch {
            print("❌ Failed to reset badge count: \(error.localizedDescription)")
        }
    }
}
