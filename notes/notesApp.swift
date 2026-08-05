//
//  notesApp.swift
//  notes
//
//  Created by Robert Libšanský on 05.07.2022.
//

import OSLog
import SwiftUI
import UserNotifications

extension Date {
    /// Built once rather than per call. This runs for every visible row on every
    /// redraw — once per keystroke in the search field, over the whole list — and
    /// a `Formatter` is expensive to construct, which made it the last per-body
    /// allocation of the kind `NotesView.startExport` and `LazyNoteForm` already
    /// pulled out of their own hot paths.
    ///
    /// Pinned to the main actor because that is where every caller is: a view's
    /// `body`. `RelativeDateTimeFormatter` is not `Sendable`, so sharing it
    /// needs an isolation to share it *within*, and this is the honest one.
    ///
    /// The locale is set explicitly to the autoupdating one, so the shared
    /// instance still follows a language changed under the app rather than
    /// keeping whatever was current when it was first asked for.
    @MainActor
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    @MainActor
    func timeAgoDisplay() -> String {
        let now = Date()

        if (self + 60) > now {
            return String(localized: "new")
        } else {
            return Self.relativeFormatter.localizedString(for: self, relativeTo: now)
        }
    }
}

/// Keeps the process alive long enough for a save that starts on the way to the
/// background to finish.
///
/// `flushPendingSave` is asynchronous, and iOS suspends a backgrounding app
/// without waiting for a `Task` — so the very edit the flush exists to rescue
/// could still be lost partway through the write. The assertion is what asks for
/// the time instead of assuming it.
@MainActor
final class BackgroundSaveAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    /// Takes the assertion. Call it synchronously as the scene leaves the
    /// foreground, before the task that does the writing — an assertion taken
    /// inside that task would be too late to protect its own scheduling.
    func begin() {
        guard identifier == .invalid else { return }

        identifier = UIApplication.shared.beginBackgroundTask(withName: "flushPendingSave") {
            // Out of time. Releasing it is not optional: an assertion still held
            // when the system loses patience terminates the app.
            Log.store.notice("Background time expired before the pending save finished")
            self.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }

        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

@main
struct notesApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var locationManager = LocationManager()
    @State private var notesStore = NotesStore.shared
    @State private var notificationRouter = NotificationRouter.shared
    @State private var saveAssertion = BackgroundSaveAssertion()

    init() {
        // Installed here rather than from a view: a tap that launched the app is
        // delivered only to a delegate that was in place before launch finished,
        // so `.onAppear` would drop it on the cold-launch path — and without any
        // delegate at all iOS shows nothing for a reminder that fires while the
        // app is already on screen.
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            LaunchScreenView()
                .environment(locationManager)
                .environment(notesStore)
                .environment(notificationRouter)
                // Where a widget's link lands. Routed through the same queue as a
                // tapped reminder — see `NotificationRouter` — so a link followed
                // from a locked home screen, before the notes file is readable, is
                // kept and retried below rather than opening nothing.
                .onOpenURL { url in
                    guard let id = NoteDeepLink.noteID(from: url) else { return }

                    notificationRouter.open(
                        .note(id),
                        in: notesStore.notes,
                        storeIsLoaded: notesStore.isLoaded
                    )
                }
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // Picks up a file that was unreadable at launch (device
                        // locked) and sweeps trash that expired while the process
                        // was alive but in the background.
                        Task {
                            await notesStore.refresh()

                            // A reminder tapped — or a widget link followed — on
                            // the way in is delivered before the store has
                            // necessarily read anything, and a note it could not
                            // find then may well be there now. Asked after the
                            // refresh for exactly that reason.
                            notificationRouter.retryPendingRequest(
                                in: notesStore.notes,
                                storeIsLoaded: notesStore.isLoaded
                            )
                        }

                        // Every time the app is opened, not just the first: this
                        // used to sit in a `.task`, which does not run again when
                        // the process is merely brought back to the foreground —
                        // so a reminder that fired while the app was backgrounded
                        // left its badge on the icon until the next cold launch.
                        Task { await NotificationManager.instance.resetBadgeCount() }
                    case .background:
                        // A debounced save may still be sleeping, and iOS
                        // suspends the process without waiting for it. The
                        // assertion is taken here rather than inside the task,
                        // so the write is covered from before it is scheduled —
                        // and only when there is one, so an idle trip to the
                        // background does not ask for time it will not use.
                        if notesStore.isSavePending {
                            saveAssertion.begin()
                            Task {
                                await notesStore.flushPendingSave()
                                saveAssertion.end()
                            }
                        }
                    default:
                        break
                    }
                }
        }
    }
}
