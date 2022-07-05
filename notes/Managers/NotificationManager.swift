//
//  NotificationManager.swift
//  notes
//
//  Created by Robert Libšanský on 24.07.2022.
//

import SwiftUI
import UserNotifications

class NotificationManager {
    @AppStorage("badge") var badge = 0
    
    static let instance = NotificationManager()
    
    func requestAuthorization() {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        
        UNUserNotificationCenter
            .current()
            .requestAuthorization(options: options) { success, error in
                if let error = error {
                    print("ERROR: \(error)")
                } else {
                    print("REQUEST FOR AUTHORIZATION WAS SUCCESSFUL")
                }
            }
    }
    
    func scheduleNotification(
        title: String,
        subtitle: String,
        date: Date
    ) -> String {
        let content = UNMutableNotificationContent()
        
        badge += 1
        
        content.title = title
        content.subtitle = subtitle
        content.sound = .default
        content.badge = badge as NSNumber
        
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
        
        UNUserNotificationCenter.current().add(request)
        
        return identifier
    }
    
    func removeNotifications(identifiers: [String]?) {
        guard let identifiers = identifiers else {
            return
        }
        
        UNUserNotificationCenter
            .current()
            .removeDeliveredNotifications(withIdentifiers: identifiers)
        
        UNUserNotificationCenter
            .current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
