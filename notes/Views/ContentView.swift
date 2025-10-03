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
            NotesView()
                .tabItem {
                    Label("list", systemImage: "list.bullet")
                }
                .tag(0)

            CalendarView()
                .tabItem {
                    Label("calendar", systemImage: "calendar")
                }
                .tag(1)

            MapView()
                .tabItem {
                    Label("map", systemImage: "map")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(NotesStore())
}
