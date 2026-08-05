//
//  NotificationManager.swift
//  notes
//
//  Created by Robert Libšanský on 24.07.2022.
//

import OSLog
import SwiftUI
import UserNotifications

@MainActor
final class NotificationManager {
    static let instance = NotificationManager()

    /// iOS keeps only the soonest 64 pending notification requests per app and
    /// discards the rest without telling anyone — `add(_:)` reports success
    /// either way. Held a little under the real ceiling to leave room for
    /// requests this process did not schedule itself.
    ///
    /// The single source of truth for the limit; `NotesStore` re-arms a restore
    /// against the same number.
    static let maxPendingReminders = 60

    private init() {}

    /// Whether the system will keep one more reminder without quietly discarding
    /// one that is already waiting.
    ///
    /// The question used to be how many reminders were due *ahead* of the new one,
    /// which answers something narrower: whether the new request itself survives.
    /// It does not follow that the others do. iOS keeps the *soonest* 64, so a
    /// reminder set for this afternoon joins a full queue at the front, is kept —
    /// and pushes the latest one out. That displaced reminder is one the user set
    /// earlier and has no reason to look at again, and nothing anywhere said it had
    /// stopped existing. The check protected the reminder being written at the
    /// expense of one already written.
    ///
    /// Counting the whole queue is the only form of the question that protects
    /// both. Past the limit the new reminder is refused instead, which routes the
    /// form to its "will not fire" alert and keeps the date the user picked —
    /// the same treatment a denied permission gets, and for the same reason.
    ///
    /// Split out of `scheduleNotification` so it can be exercised at all: a test
    /// process cannot be granted notification authorization, so its pending
    /// queue is always empty and the limit would never be reached there.
    static func canSchedule(pendingReminders count: Int) -> Bool {
        count < maxPendingReminders
    }

    /// Whether the permission the user has granted lets a reminder be delivered
    /// at all.
    ///
    /// `add(_:)` reports no error when authorization is missing — it accepts the
    /// request, files it in the pending queue and simply never delivers it — so
    /// this is the only thing standing between a denied permission and a note
    /// that claims a reminder which cannot fire.
    ///
    /// `.notDetermined` counts as no for the same reason: nothing arrives until
    /// the prompt is answered. The form asks for authorization the moment the
    /// toggle goes on, and that prompt is modal, so by the time a save reaches
    /// here the answer is in.
    ///
    /// Split out for the same reason as `canSchedule(remindersDueEarlier:)`: a
    /// test process is never granted authorization, so an end-to-end check could
    /// not tell a refused request from an accepted one.
    static func canSchedule(authorizationStatus status: UNAuthorizationStatus) -> Bool {
        switch status {
        // `.provisional` delivers quietly to Notification Centre and
        // `.ephemeral` is an App Clip's grant — both still arrive.
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    /// The trigger a reminder for `date` needs, or `nil` when that reminder
    /// would never arrive.
    ///
    /// A non-repeating calendar trigger whose components are all specified and
    /// already in the past has no next fire date, and `add(_:)` accepts the
    /// request anyway — so the notification is simply never delivered. The form
    /// reads its date when it opens and the trigger matches whole minutes, so an
    /// edit that outlasts the reminder lands here even though the picker will
    /// not let a past date be selected.
    ///
    /// Split out for the same reason as `canSchedule`: a test process cannot be
    /// granted notification authorization, but this is calendar arithmetic and
    /// needs none.
    static func trigger(for date: Date) -> UNCalendarNotificationTrigger? {
        let dateMatching = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateMatching,
            repeats: false
        )

        return trigger.nextTriggerDate() == nil ? nil : trigger
    }

    func requestAuthorization() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: options)
            if granted {
                Log.notifications.info("Notification authorization granted")
            } else {
                Log.notifications.notice("Notification authorization denied")
            }
            return granted
        } catch {
            Log.notifications.error("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// What the pending queue holds, as the two numbers scheduling a reminder for
    /// `date` needs: how many reminders are waiting in total, which decides whether
    /// the system has room for another at all, and how many of those fire no later
    /// than `date`, which decides the badge this one should carry.
    ///
    /// Both counted from a single fetch. They used to be one number doing both
    /// jobs — see `canSchedule(pendingReminders:)` — and asking twice would mean
    /// two round trips to the notification centre for one save.
    private func pendingReminders(dueNoLaterThan date: Date) async -> (total: Int, dueEarlier: Int) {
        var total = 0
        var dueEarlier = 0

        for request in await UNUserNotificationCenter.current().pendingNotificationRequests() {
            // Only this app's reminders: everything it schedules carries a
            // calendar trigger, and one whose date has gone by will not fire, so
            // it takes up no room in the queue. The same filter `rebalanceBadges`
            // applies.
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fireDate = trigger.nextTriggerDate()
            else { continue }

            total += 1

            if fireDate <= date { dueEarlier += 1 }
        }

        return (total, dueEarlier)
    }

    /// Where the line between seen and unseen sits: the moment the app was last
    /// on screen.
    ///
    /// Kept in `UserDefaults` rather than in memory because the badge a reminder
    /// carries is fixed when it is scheduled, and the process that schedules it
    /// need not be the one that was last active — the app can be killed in
    /// between, and a Siri shortcut can schedule a reminder having never shown a
    /// screen at all.
    private static let deliveredSeenKey = "deliveredRemindersSeenAt"

    /// When the user was last handed everything the notification centre held.
    /// `nil` until the app has been on screen once. Written only by
    /// `resetBadgeCount()`.
    var deliveredSeenUpTo: Date? {
        UserDefaults.standard.object(forKey: Self.deliveredSeenKey) as? Date
    }

    /// How many delivered reminders the user has not been handed yet.
    ///
    /// Everything the notification centre still holds, minus what it was already
    /// holding the last time the app was on screen. Counting the lot — as this
    /// used to — meant a reminder read last week went on being counted into the
    /// badge baked onto every reminder scheduled after it: three read yesterday
    /// and one set today arrived showing 4. The app clears the icon on every
    /// `.active` but deliberately leaves the notifications themselves in place,
    /// since the notification centre is where a missed reminder stays
    /// reviewable — so the count needs a watermark of its own rather than the
    /// icon being the only record.
    ///
    /// Compared by delivery date rather than kept as a running total, so the
    /// tally cannot drift: clearing part of the notification centre by hand, or
    /// the app dropping a delivered reminder along with the note that owned it,
    /// each simply take a date out of the list.
    ///
    /// Split out for the same reason as `canSchedule`: a test process is never
    /// granted authorization, so nothing is ever delivered to it and the rule
    /// would not be reachable end to end.
    static func unseenCount(deliveryDates: [Date], seenUpTo: Date?) -> Int {
        guard let seenUpTo else { return deliveryDates.count }

        return deliveryDates.filter { $0 > seenUpTo }.count
    }

    /// `unseenCount` against the live notification centre.
    private func unseenDeliveredCount() async -> Int {
        Self.unseenCount(
            deliveryDates: await UNUserNotificationCenter.current()
                .deliveredNotifications()
                .map(\.date),
            seenUpTo: deliveredSeenUpTo
        )
    }

    /// Badge value a reminder should carry when it fires: every delivered
    /// reminder the user has not seen yet, plus every reminder scheduled to
    /// arrive no later than this one. Counting all pending requests instead — as
    /// this used to — gave the same number to every reminder regardless of when
    /// it was due.
    private func badgeCount(remindersDueEarlier count: Int) async -> Int {
        await unseenDeliveredCount() + count + 1
    }

    /// A reminder the notification centre is still holding, reduced to what
    /// deciding its badge actually needs.
    struct PendingReminder: Sendable {
        let identifier: String
        let fireDate: Date

        /// The badge the request currently carries, or `nil` when it carries none.
        let badge: Int?
    }

    /// The badge each pending reminder ought to carry, keyed by identifier —
    /// containing only the ones that carry something else today.
    ///
    /// A badge is baked into the notification when it is scheduled, so the number
    /// is only ever right for the queue as it stood at that moment. Add a reminder
    /// that fires *before* one already scheduled and the later one is now second
    /// in line while still carrying the badge of the first: set a reminder for
    /// tonight, then one for this afternoon, and tonight's arrives showing 1 when
    /// two reminders are waiting. Cancelling the earliest of several leaves the
    /// rest counting one too many for the same reason.
    ///
    /// Reminders are numbered in fire order, which is the order the user meets
    /// them in — matching what `badgeCount(remindersDueEarlier:)` computes for a
    /// single new request. Ties break on identifier, so the result is stable
    /// rather than dependent on the order the notification centre listed them in.
    ///
    /// Split out as a pure function for the same reason as `canSchedule`: a test
    /// process cannot be granted notification authorization, so its pending queue
    /// is always empty and none of this would be reachable end to end.
    static func rebalancedBadges(
        unseenDelivered: Int,
        reminders: [PendingReminder]
    ) -> [String: Int] {
        let ordered = reminders.sorted { lhs, rhs in
            lhs.fireDate == rhs.fireDate
                ? lhs.identifier < rhs.identifier
                : lhs.fireDate < rhs.fireDate
        }

        var corrections: [String: Int] = [:]

        for (index, reminder) in ordered.enumerated() {
            let expected = unseenDelivered + index + 1

            // Only what actually differs: re-adding a request is a write to the
            // notification centre, and the common case — a new reminder that is
            // simply the latest — leaves every existing badge already correct.
            if reminder.badge != expected {
                corrections[reminder.identifier] = expected
            }
        }

        return corrections
    }

    /// Brings every pending reminder's badge back in line with its place in the
    /// queue. Call it after anything that changes what is pending.
    func rebalanceBadges() async {
        let center = UNUserNotificationCenter.current()

        var reminders: [PendingReminder] = []
        var requestsByIdentifier: [String: UNNotificationRequest] = [:]

        for request in await center.pendingNotificationRequests() {
            // Only this app's reminders: everything it schedules carries a
            // calendar trigger, and one whose date has gone by will not fire at
            // all, so it takes no place in the queue.
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fireDate = trigger.nextTriggerDate()
            else { continue }

            reminders.append(
                PendingReminder(
                    identifier: request.identifier,
                    fireDate: fireDate,
                    badge: request.content.badge?.intValue
                )
            )
            requestsByIdentifier[request.identifier] = request
        }

        guard !reminders.isEmpty else { return }

        let corrections = Self.rebalancedBadges(
            unseenDelivered: await unseenDeliveredCount(),
            reminders: reminders
        )

        guard !corrections.isEmpty else { return }

        for (identifier, badge) in corrections {
            guard let request = requestsByIdentifier[identifier],
                  let content = request.content.mutableCopy()
                      as? UNMutableNotificationContent
            else { continue }

            content.badge = NSNumber(value: badge)

            // Re-added under the identifier it already has, which replaces the
            // pending request rather than queueing a second one — so the
            // identifier the note stores stays the one that will be delivered,
            // and `NotificationRouter` can still route a tap back to it.
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: request.trigger
                    )
                )
            } catch {
                Log.notifications.error("Failed to re-badge a pending reminder: \(error.localizedDescription)")
            }
        }

        Log.notifications.info("Re-badged \(corrections.count) pending reminder(s)")
    }

    /// Schedules a reminder.
    /// - Returns: The notification identifier, or `nil` when the reminder will
    ///   not fire — either because the system refused the request or because it
    ///   is already past the pending limit. Callers must not store an identifier
    ///   for a notification that will never arrive.
    func scheduleNotification(
        title: String,
        subtitle: String,
        date: Date
    ) async -> String? {
        // Checked before anything else: an identifier must never be handed back
        // for a reminder that cannot fire, and a date that has already gone by
        // is as unschedulable as a full queue. Refusing routes the caller down
        // the same path — the note keeps its date, and the user is told.
        guard let trigger = Self.trigger(for: date) else {
            Log.notifications.notice("Refusing to schedule: the reminder date has already passed")
            return nil
        }

        // A denied permission is as unschedulable as a past date, and the system
        // will not say so: it accepts the request and never delivers it. Without
        // this the note stored an identifier for a reminder that could not fire,
        // and the form's "will not fire" alert never appeared — the one case the
        // alert exists for that was going unreported.
        let status = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus

        guard Self.canSchedule(authorizationStatus: status) else {
            Log.notifications.notice("Refusing to schedule: notification authorization is \(status.rawValue), nothing would be delivered")
            return nil
        }

        let pending = await pendingReminders(dueNoLaterThan: date)

        // Past the limit the system accepts the request and then drops one, so
        // `add(_:)` succeeding would be no evidence anything will fire — neither
        // this reminder nor whichever one it displaced. Refusing here routes the
        // caller down the same path as a denied permission: the note keeps the
        // date the user picked, no identifier is stored, and they are told it will
        // not fire.
        guard Self.canSchedule(pendingReminders: pending.total) else {
            Log.notifications.notice("Refusing to schedule: \(pending.total) reminders are already pending, at this app's limit - adding another would silently drop one of them")
            return nil
        }

        let content = UNMutableNotificationContent()

        content.title = title
        content.subtitle = subtitle
        content.sound = .default
        content.badge = NSNumber(value: await badgeCount(remindersDueEarlier: pending.dueEarlier))

        let identifier = UUID().uuidString

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Log.notifications.info("Notification scheduled")

            // The badge above is right for the queue as it stands, but this
            // request may have landed ahead of reminders that were scheduled
            // earlier — and their badges were fixed when they were added.
            await rebalanceBadges()

            return identifier
        } catch {
            Log.notifications.error("Failed to schedule notification: \(error.localizedDescription)")
            return nil
        }
    }

    func removeNotifications(identifiers: [String]?) async {
        guard let identifiers = identifiers, !identifiers.isEmpty else {
            return
        }

        let center = UNUserNotificationCenter.current()

        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        // Whatever is left has moved up the queue. Dropping the earliest of
        // several reminders otherwise left the rest carrying a badge that counted
        // the one that is no longer coming.
        //
        // Editing a note that carries a reminder removes and then re-schedules it,
        // so this runs twice for one save and the second pass undoes some of the
        // first pass's writes. Left as is on purpose: the queue is capped at
        // `maxPendingReminders`, and `rebalancedBadges` returns nothing at all
        // once the numbering already agrees, so the redundant work is bounded and
        // usually zero.
        await rebalanceBadges()

        // Update badge count after removal
        await updateBadgeCount()

        Log.notifications.info("Removed \(identifiers.count) notification(s)")
    }

    /// The badge the icon should carry right now, given what the notification
    /// centre holds and whether the app is on screen.
    ///
    /// Only delivered reminders the user has not seen yet count. `pending` is
    /// taken as an argument rather than ignored silently, because counting it is
    /// exactly the bug this rule exists to prevent: pending requests are
    /// reminders that have not fired yet, and `removeNotifications` calls this —
    /// so merely editing or deleting a note that carried a reminder used to badge
    /// the app out of nowhere with a count of the user's future reminders.
    ///
    /// `isActive` closes the other half of the same bug. The app clears its badge
    /// every time it becomes active, but the reminders themselves stay in the
    /// notification centre — and `removeNotifications` recounted those, so
    /// editing or deleting a note that carried a reminder put the number straight
    /// back on the icon of an app the user was looking at. While the app is on
    /// screen the user is being handed their reminders directly, so the icon stays
    /// bare; the notification centre keeps its copies, which is where a missed
    /// reminder should still be reviewable.
    ///
    /// Keeping those copies is why the count is of *unseen* reminders rather than
    /// delivered ones — see `unseenCount`. Going bare while the app is open said
    /// the user had seen them; nothing recorded it, so the next time the icon was
    /// counted they were all back.
    ///
    /// Split out of `updateBadgeCount()` so it can be exercised at all: a test
    /// process cannot be granted notification authorization, so its pending queue
    /// is always empty and the distinction would be invisible there.
    static func badgeCount(unseenDelivered: Int, pending: Int, isActive: Bool) -> Int {
        isActive ? 0 : unseenDelivered
    }

    /// Puts the number of reminders the user has actually been handed on the icon.
    /// - Returns: The badge value this call asked for, whether or not the system
    ///   accepted it.
    @discardableResult
    func updateBadgeCount() async -> Int {
        let center = UNUserNotificationCenter.current()

        let badge = Self.badgeCount(
            unseenDelivered: await unseenDeliveredCount(),
            // Deliberately not counted. The rule above ignores `pending`, and the
            // parameter is kept precisely so that ignoring it is written down and
            // tested — but this asked the notification centre for the number
            // anyway and then threw it away. That is a round trip to another
            // process, on a path `removeNotifications` walks for every edit or
            // deletion of a note that carried a reminder.
            pending: 0,
            isActive: UIApplication.shared.applicationState == .active
        )

        do {
            try await center.setBadgeCount(badge)
            Log.notifications.info("Badge count updated to \(badge)")
        } catch {
            Log.notifications.error("Failed to update badge count: \(error.localizedDescription)")
        }

        return badge
    }

    /// Clears the icon and records that everything delivered so far has been seen.
    /// Call it whenever the app becomes active.
    ///
    /// The record is the half that used to be missing. Clearing the badge does
    /// not clear the notifications — deliberately, since the notification centre
    /// is where a missed reminder stays reviewable — so with nothing marking them
    /// as read they went on being counted into the badge fixed onto every
    /// reminder scheduled afterwards. See `unseenCount`.
    func resetBadgeCount() async {
        // Stamped before the badge is written rather than after: a reminder
        // delivered while this runs is then counted as unseen, which is the safe
        // way round. Writing it off would hide a reminder the user may not have
        // looked at, and the next trip through here picks it up anyway.
        UserDefaults.standard.set(Date(), forKey: Self.deliveredSeenKey)

        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
        } catch {
            Log.notifications.error("Failed to reset badge count: \(error.localizedDescription)")
        }
    }
}

/// Presents reminders that fire while the app is on screen, and routes whatever
/// asks for a particular note — a tapped reminder, a widget's deep link — to the
/// note it names.
///
/// Without a delegate iOS suppresses a notification that arrives in the
/// foreground entirely — no banner, no sound, nothing — and the reminder defaults
/// to five minutes out, so a user who stays in the app to finish writing the note
/// simply never heard about it. A tap had nowhere to go either: it opened the list
/// and left the user to find the note themselves.
///
/// The widget's links arrive by a different door and want the same thing, so they
/// go through the same one queue rather than a second copy of it. Everything the
/// notification path needed is what they need too: the note resolved against the
/// store as it is *now* rather than as the payload described it, and a request
/// that lands before the notes are readable kept for another attempt instead of
/// dropped. Keeping the name: this is still the notification centre's delegate,
/// and that is what decides where it lives.
///
/// Lives beside `NotificationManager` rather than in a file of its own because it
/// is the other half of the same subject: the manager schedules a reminder, this
/// decides what happens when one arrives.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Shared because the delegate has to be installed during launch, before any
    /// view exists that could own it.
    static let shared = NotificationRouter()

    /// The note that has been asked for, cleared once the navigation has consumed
    /// it.
    ///
    /// An id rather than a `NoteModel`: the store is the only thing that knows the
    /// current state of a note, and a note can have been edited — or trashed —
    /// since its reminder was scheduled or the widget last drew it.
    var noteToOpen: UUID?

    /// What was asked for, in the two forms it can arrive in.
    ///
    /// One enum rather than a stored property per door, so the keeping and the
    /// retrying below are written once. A second copy of that logic for the widget
    /// is how one of them comes to be missing the `storeIsLoaded` distinction the
    /// other was fixed to make.
    enum Request: Equatable {
        /// A reminder was tapped, named by its notification request identifier.
        case notification(String)

        /// A widget's link was followed, naming the note directly.
        case note(UUID)
    }

    /// A request whose note could not be resolved when it arrived, kept so it can
    /// be tried once more.
    ///
    /// A tap is delivered as soon as launch finishes, which can be before the
    /// store has managed to read its notes: the file is written with
    /// `.completeFileProtection`, so a launch that races the device handing over
    /// protected data starts a store that knows about no notes at all. Every tap
    /// then named "no note that is still there" and was dropped — the reminder the
    /// user actually pressed opened nothing, and nothing ever asked again. A
    /// widget link followed from a locked home screen lands in exactly the same
    /// place.
    ///
    /// Observed rather than `@ObservationIgnored`, which is what it used to be:
    /// `hasPendingDestination` reads it, and the splash screen reads that in order
    /// to get out of the way of a launch that already has somewhere to go.
    private(set) var pendingRequest: Request?

    /// Whether this launch already has a note to go to — either resolved, or
    /// waiting on a store that has not read its notes yet.
    ///
    /// Read by `LaunchScreenView`, which otherwise holds the app behind its splash
    /// for six tenths of a second on every launch, including the ones that were
    /// started *by* a tapped reminder or a widget link. The user pressed the note
    /// they wanted; making them watch an intro animation first is the one case
    /// where the splash costs something.
    var hasPendingDestination: Bool {
        noteToOpen != nil || pendingRequest != nil
    }

    /// Installs this router as the notification centre's delegate.
    ///
    /// Called from the app's initialiser, not from a view: iOS hands a tap that
    /// launched the app to a delegate that was already in place when launch
    /// finished, so `.task` or `.onAppear` would both be too late and the tap
    /// would be dropped on exactly the cold-launch path it matters most on.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows a reminder that fires while the app is on screen.
    ///
    /// Deliberately without `.badge`: the user is looking at the app, so a number
    /// on its icon is noise — the same rule `NotificationManager.badgeCount`
    /// applies while the app is active, for the same reason.
    ///
    /// Main-actor isolated for the reason spelled out on `didReceive` below.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Opens the note whose reminder was tapped.
    ///
    /// The request identifier is what the note stores in
    /// `notificationIdentifiers`, so the note is looked up through the store
    /// rather than through anything carried in the notification itself — a
    /// protected note's reminder deliberately carries neither its title nor its
    /// body, so there is nothing in the payload to route on.
    ///
    /// Runs on the main actor, and the whole method has to. It used to be
    /// `nonisolated`, hopping to the main actor for the routing alone — and that
    /// crashed the app on every tapped reminder.
    ///
    /// The ObjC entry point behind this is
    /// `…didReceiveNotificationResponse:withCompletionHandler:`, and the compiler
    /// calls that completion handler wherever the async body happens to finish. A
    /// `nonisolated` body that suspends — which `MainActor.run` is — resumes on
    /// the cooperative pool, so the handler ran off the main thread. The handler
    /// UIKit passes in is
    /// `-[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]`,
    /// which asserts it is on the main thread and aborts the process when it is
    /// not: `NSInternalInconsistencyException`, on the one path the user reaches
    /// by pressing the reminder they asked for.
    ///
    /// Isolating the whole method is what puts the completion handler back where
    /// UIKit requires it, and it costs nothing — UserNotifications already
    /// delivers these callbacks on the main thread, so there is no hop to pay for
    /// on the way in either.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let store = NotesStore.shared

        open(
            .notification(response.notification.request.identifier),
            in: store.notes,
            storeIsLoaded: store.isLoaded
        )
    }

    // MARK: - Opening a note

    /// Opens the note `request` names, or keeps the request for another attempt
    /// when the store cannot yet answer for it.
    ///
    /// The one way in, for both doors — `notesApp` hands widget links here from
    /// `onOpenURL`, and the delegate above hands tapped reminders here.
    func open(_ request: Request, in notes: [NoteModel], storeIsLoaded: Bool) {
        apply(
            Self.outcome(for: request, in: notes, storeIsLoaded: storeIsLoaded),
            for: request
        )
    }

    /// Tries again to open the note behind a request that arrived before the store
    /// could answer for it. Call it once the store has reloaded — `notesApp` does,
    /// on every `.active`. A no-op when nothing is waiting.
    func retryPendingRequest(in notes: [NoteModel], storeIsLoaded: Bool) {
        guard let pendingRequest else { return }

        open(pendingRequest, in: notes, storeIsLoaded: storeIsLoaded)
    }

    /// What becomes of a tapped reminder.
    enum TapOutcome: Equatable {
        /// The note is there — open it.
        case route(UUID)

        /// The store cannot answer for this tap yet, so it is kept for the next
        /// attempt rather than dropped.
        case keepWaiting

        /// The store holds its notes and none of them is this one, so the note
        /// really is gone.
        case giveUp
    }

    /// What to do with a request, given what the store currently knows.
    ///
    /// The `storeIsLoaded` distinction is the whole point. A store that never read
    /// its notes answers "no such note" to everything, and that used to end the
    /// matter — so a tap delivered before the file came within reach opened
    /// nothing, and nothing asked again. It is not an answer; it is the absence of
    /// one, and `refresh()` supplies the real one later.
    ///
    /// Giving up once the store *is* loaded is equally deliberate. Carrying the
    /// request on indefinitely would mean a reminder tapped for a trashed note
    /// springing open the moment the user restored it, long after they had
    /// forgotten pressing anything.
    ///
    /// Split out as a pure function for the same reason as `noteIdentifier` — a
    /// test process cannot be handed a real `UNNotificationResponse`, and it can
    /// no more be handed a widget tap.
    static func outcome(
        for request: Request,
        in notes: [NoteModel],
        storeIsLoaded: Bool
    ) -> TapOutcome {
        let id: UUID?

        switch request {
        case .notification(let identifier):
            id = noteIdentifier(forNotification: identifier, in: notes)
        case .note(let noteID):
            // Matched against the live note rather than taken at face value: the
            // widget's payload can be minutes old, and a note that has since gone
            // to the trash must not be sprung open by a link drawn before it went
            // — the same rule `noteIdentifier` applies to a notification that
            // outlived its note.
            id = notes.first { $0.id == noteID && !$0.isDeleted }?.id
        }

        if let id { return .route(id) }

        return storeIsLoaded ? .giveUp : .keepWaiting
    }

    private func apply(_ outcome: TapOutcome, for request: Request) {
        switch outcome {
        case .route(let id):
            pendingRequest = nil
            noteToOpen = id

        case .keepWaiting:
            pendingRequest = request
            Log.notifications.notice("A request to open a note arrived before the notes were readable - keeping it for the next attempt")

        case .giveUp:
            pendingRequest = nil
            Log.notifications.notice("A request to open a note names none that is still there")
        }
    }

    /// The note a delivered notification belongs to, or `nil` when it no longer
    /// has one.
    ///
    /// A trashed note is deliberately not matched: its reminder was cancelled on
    /// the way into the trash, so a tap can only be a notification that outlived
    /// it, and pushing a note the user deleted would be worse than doing nothing.
    ///
    /// Split out as a pure function so the rule can be exercised at all — a test
    /// process cannot be handed a real `UNNotificationResponse`.
    static func noteIdentifier(
        forNotification identifier: String,
        in notes: [NoteModel]
    ) -> UUID? {
        notes.first { note in
            !note.isDeleted
                && (note.notificationIdentifiers?.contains(identifier) ?? false)
        }?.id
    }
}
