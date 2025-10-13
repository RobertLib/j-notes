//
//  NoteModel.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import CoreLocation
import SwiftUI

enum NoteType: String, Codable, Sendable {
    case text
    case drawing
}

struct NoteModel: Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let title: String
    let content: String
    let type: NoteType
    let drawingData: Data?
    let drawingCanvasSize: CGSize?
    let backgroundImageData: Data?
    let pinned: Bool
    let color: Color?
    let reminder: Date?
    let notificationIdentifiers: [String]?
    let location: [Double]?
    let isDeleted: Bool
    let deletedAt: Date?

    init(
        id: UUID? = nil,
        createdAt: Date? = nil,
        title: String,
        content: String,
        type: NoteType? = nil,
        drawingData: Data? = nil,
        drawingCanvasSize: CGSize? = nil,
        backgroundImageData: Data? = nil,
        pinned: Bool? = nil,
        color: Color? = nil,
        reminder: Date? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil,
        isDeleted: Bool? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id ?? UUID()
        self.createdAt = createdAt ?? .now
        self.title = title
        self.content = content
        self.type = type ?? .text
        self.drawingData = drawingData
        self.drawingCanvasSize = drawingCanvasSize
        self.backgroundImageData = backgroundImageData
        self.pinned = pinned ?? false
        self.color = color
        self.reminder = reminder
        self.notificationIdentifiers = notificationIdentifiers
        self.location = location
        self.isDeleted = isDeleted ?? false
        self.deletedAt = deletedAt
    }

    var coordinate: CLLocationCoordinate2D {
        if let location = location, location.count >= 2 {
            return CLLocationCoordinate2D(
                latitude: location[0], longitude: location[1]
            )
        }

        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}

// MARK: - Codable conformance with backward compatibility
extension NoteModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id, createdAt, title, content, type
        case drawingData, drawingCanvasSize, backgroundImageData
        case pinned, color, reminder, notificationIdentifiers, location
        case isDeleted, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(NoteType.self, forKey: .type)
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        drawingCanvasSize = try container.decodeIfPresent(CGSize.self, forKey: .drawingCanvasSize)
        backgroundImageData = try container.decodeIfPresent(Data.self, forKey: .backgroundImageData)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        color = try container.decodeIfPresent(Color.self, forKey: .color)
        reminder = try container.decodeIfPresent(Date.self, forKey: .reminder)
        notificationIdentifiers = try container.decodeIfPresent([String].self, forKey: .notificationIdentifiers)
        location = try container.decodeIfPresent([Double].self, forKey: .location)

        // New properties with default values for backward compatibility
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        try container.encodeIfPresent(drawingCanvasSize, forKey: .drawingCanvasSize)
        try container.encodeIfPresent(backgroundImageData, forKey: .backgroundImageData)
        try container.encode(pinned, forKey: .pinned)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(reminder, forKey: .reminder)
        try container.encodeIfPresent(notificationIdentifiers, forKey: .notificationIdentifiers)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}
