//
//  notesApp.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI
import UserNotifications

fileprivate extension Color {
    var colorComponents: (
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    )? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard
            UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else
        {
            return nil
        }

        return (r, g, b, a)
    }
}

extension Color: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let r = try container.decode(Double.self, forKey: .red)
        let g = try container.decode(Double.self, forKey: .green)
        let b = try container.decode(Double.self, forKey: .blue)
        let a = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0

        self.init(red: r, green: g, blue: b, opacity: a)
    }

    public func encode(to encoder: Encoder) throws {
        guard let colorComponents = self.colorComponents else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unable to extract color components"
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(colorComponents.red, forKey: .red)
        try container.encode(colorComponents.green, forKey: .green)
        try container.encode(colorComponents.blue, forKey: .blue)
        try container.encode(colorComponents.alpha, forKey: .alpha)
    }
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        let now = Date()

        formatter.unitsStyle = .full

        if (self + 60) > now {
            return String(localized: "new")
        } else {
            return formatter.localizedString(for: self, relativeTo: now)
        }
    }

    /// Modern iOS 18+ formatting helper
    func formatted(style: Date.FormatStyle.DateStyle = .abbreviated,
                   timeStyle: Date.FormatStyle.TimeStyle = .shortened) -> String {
        self.formatted(date: style, time: timeStyle)
    }
}

@main
struct notesApp: App {
    @StateObject var locationManager = LocationManager()
    @StateObject var notesStore = NotesStore()

    var body: some Scene {
        WindowGroup {
            LaunchScreenView()
                .environmentObject(locationManager)
                .environmentObject(notesStore)
                .task {
                    // Reset badge when app opens
                    await NotificationManager.instance.resetBadgeCount()
                }
        }
    }
}
