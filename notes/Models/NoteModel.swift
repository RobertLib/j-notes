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

struct NoteModel: Identifiable, Codable, Sendable {
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
        location: [Double]? = nil
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
    }

    var coordinate: CLLocationCoordinate2D {
        if let location = location {
            return CLLocationCoordinate2D(
                latitude: location[0], longitude: location[1]
            )
        }

        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}
