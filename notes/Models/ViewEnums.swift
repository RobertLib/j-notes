//
//  ViewEnums.swift
//  notes
//
//  Created by Robert Libšanský on 13.10.2025.
//

import SwiftUI

enum NoteSortOption: String, CaseIterable, Identifiable {
    case dateNewest = "dateNewest"
    case dateOldest = "dateOldest"
    case titleAZ = "titleAZ"
    case titleZA = "titleZA"

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

enum NoteDisplayStyle: String, CaseIterable, Identifiable {
    case compact = "compact"
    case standard = "standard"
    case detailed = "detailed"

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }

    var icon: String {
        switch self {
        case .compact:
            return "list.bullet"
        case .standard:
            return "list.bullet.rectangle"
        case .detailed:
            return "list.bullet.rectangle.portrait"
        }
    }
}
