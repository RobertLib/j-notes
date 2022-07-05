//
//  notesApp.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

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

extension Color: Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let r = try container.decode(Double.self, forKey: .red)
        let g = try container.decode(Double.self, forKey: .green)
        let b = try container.decode(Double.self, forKey: .blue)
        
        self.init(red: r, green: g, blue: b)
    }

    public func encode(to encoder: Encoder) throws {
        guard let colorComponents = self.colorComponents else {
            return
        }
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(colorComponents.red, forKey: .red)
        try container.encode(colorComponents.green, forKey: .green)
        try container.encode(colorComponents.blue, forKey: .blue)
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
                .onAppear() {
                    NotificationManager.instance.badge = 0
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
        }
    }
}
