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
            NotesView().tabItem {
                Label("list", systemImage: "list.bullet")
            }
            
            CalendarView().tabItem {
                Label("calendar", systemImage: "calendar")
            }
            
            MapView().tabItem {
                Label("map", systemImage: "map")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LocationManager())
            .environmentObject(NotesStore())
    }
}
