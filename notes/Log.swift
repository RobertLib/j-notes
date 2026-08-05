//
//  Log.swift
//  notes
//

import OSLog

/// Central logging categories. Using `Logger` instead of `print` keeps note
/// contents out of release builds and off the console of shipped devices.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "cz.rob.notes"

    static let store = Logger(subsystem: subsystem, category: "store")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let files = Logger(subsystem: subsystem, category: "files")
}
