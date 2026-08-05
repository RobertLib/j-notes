//
//  ContentView.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import SwiftUI

/// The three top-level tabs, as a value the selection can be driven from.
///
/// The tabs used to carry no value at all, which is fine while only the user
/// switches them — but a tapped reminder has to bring the list forward from
/// wherever the app was left, and that needs something to select.
enum AppTab: Hashable {
    case list
    case calendar
    case map
}

struct ContentView: View {
    @Environment(NotesStore.self) private var notesStore
    @Environment(NotificationRouter.self) private var notificationRouter

    @State private var selectedTab: AppTab = .list

    @State private var showErrorAlert = false

    /// The message the alert is showing, taken from `saveError` at the moment the
    /// alert is raised.
    ///
    /// Read from the store directly before, which meant the message was whatever
    /// `saveError` happened to be while the alert was on screen rather than what
    /// raised it — and a save that succeeds clears `saveError`. A debounced write
    /// landing under an open alert therefore emptied it, leaving "Error" and a
    /// blank body. Latching it here also outlives `clearError()`, which the OK
    /// button calls.
    @State private var errorMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("list", systemImage: "list.bullet", value: AppTab.list) {
                NotesView()
            }

            Tab("calendar", systemImage: "calendar", value: AppTab.calendar) {
                CalendarView()
            }

            Tab("map", systemImage: "map", value: AppTab.map) {
                MapView()
            }
        }
        // A reminder can be tapped while the calendar or the map is on screen, and
        // the note is pushed onto the list's navigation stack — so the list has to
        // come forward first or the push would happen out of sight.
        .onChange(of: notificationRouter.noteToOpen) { _, id in
            if id != nil {
                selectedTab = .list
            }
        }
        // Raised here rather than inside the list, which is where it used to live.
        // A store error is not about the tab the user happens to be on — a save can
        // fail, or a load can be reported, while the calendar or the map is in
        // front — and an alert attached to a view in an unselected tab is not
        // presented. The flag stayed set, so it appeared on the next trip back to
        // the list instead: right message, arbitrary moment, long after whatever
        // caused it. `TabView` is the first thing above all three tabs, so this is
        // where an alert that belongs to the app rather than to a screen goes.
        .alert("error", isPresented: $showErrorAlert) {
            // Clearing the error matters: without it an identical second failure
            // would not change `saveError`, so `onChange` would not fire and the
            // alert would stay silent.
            Button("ok") {
                notesStore.clearError()
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        // `initial: true` is what makes a load failure visible at all: the store
        // reads its file in `init`, long before this view exists, so a plain
        // `onChange` never fired for the error that was already there — and the two
        // worst cases, an unreadable file and a failed migration, are set exactly
        // there. The user saw an empty list and no reason.
        .onChange(of: notesStore.saveError, initial: true) { _, newValue in
            if let newValue {
                // Copied rather than read back out of the store while the alert is
                // up — see `errorMessage`.
                errorMessage = newValue
                showErrorAlert = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(LocationManager())
        .environment(NotesStore())
        .environment(NotificationRouter.shared)
}
