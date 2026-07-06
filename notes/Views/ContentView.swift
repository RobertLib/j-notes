//
//  ContentView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("list", systemImage: "list.bullet") {
                NotesView()
            }

            Tab("calendar", systemImage: "calendar") {
                CalendarView()
            }

            Tab("map", systemImage: "map") {
                MapView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(LocationManager())
        .environment(NotesStore())
}
