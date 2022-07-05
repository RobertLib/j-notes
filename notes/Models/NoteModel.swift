//
//  NoteModel.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import CoreLocation
import SwiftUI

struct NoteModel: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    let content: String
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

//let mockNotes = [
//    NoteModel(
//        title: "How to Be More Productive",
//        content: "In order to be more productive, you need to have a clear goal in mind. Break down that goal into smaller steps that you can complete. Make a schedule and stick to it.",
//        title: "Jak být produktivnější",
//        content: "Abyste byli produktivnější, musíte mít v hlavě jasný cíl. Rozdělte tento cíl na menší kroky, které můžete splnit. Udělejte si rozvrh a držte se ho.",
//        pinned: true,
//        color: .red,
//        reminder: Date(),
//        location: [50.04, 14.41]
//    ),
//    NoteModel(
//        title: "The Benefits of a Plant-Based Diet",
//        content: "A plant-based diet has many benefits, including reducing the risk of chronic diseases, such as heart disease, stroke, and cancer. Plants are a good source of fiber, vitamins, and minerals.",
//        title: "Výhody rostlinné stravy",
//        content: "Rostlinná strava má mnoho výhod, včetně snížení rizika chronických onemocnění, jako jsou srdeční choroby, mrtvice a rakovina. Rostliny jsou dobrým zdrojem vlákniny, vitamínů a minerálů.",
//        pinned: false,
//        color: .blue,
//        reminder: Date().addingTimeInterval(15 * 60),
//        location: [50.06, 14.45]
//    ),
//    NoteModel(
//        title: "How to be a better person",
//        content: "In order to be a better person, it is important to be mindful of your own actions and words. Make an effort to be kind, patient, and helpful to others, and try to avoid speaking or acting.",
//        title: "Jak být lepším člověkem",
//        content: "Abyste byli lepším člověkem, je důležité mít na paměti své vlastní činy a slova. Snažte se být laskaví, trpěliví a nápomocní ostatním a snažte se vyhnout mluvení nebo jednání.",
//        pinned: false,
//        color: .green,
//        reminder: Date().addingTimeInterval(30 * 60),
//        location: [50.02, 14.49]
//    ),
//]
