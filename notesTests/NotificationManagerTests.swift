//
//  NotificationManagerTests.swift
//  notesTests
//
//  Created by Robert Libšanský on 04.10.2025.
//

import XCTest
import UIKit
import UserNotifications
@testable import J_Notes

@MainActor
final class NotificationManagerTests: XCTestCase {

    func testSingleton() {
        let instance1 = NotificationManager.instance
        let instance2 = NotificationManager.instance
        XCTAssertTrue(instance1 === instance2)
    }

    /// Only a granted permission delivers anything, so only a granted permission
    /// may yield an identifier.
    ///
    /// This is the rule that closed a silent failure: `add(_:)` reports no error
    /// when authorization is missing — it files the request and never delivers it
    /// — so a denied permission handed back an identifier, the note recorded a
    /// reminder that could not fire, and the form's "will not fire" alert stayed
    /// silent for the very case it was written for.
    ///
    /// Asserted against the rule rather than the live notification centre: a test
    /// process is normally never granted authorization, so an end-to-end check
    /// could not tell a refused request from an accepted one.
    func testOnlyGrantedAuthorizationCanSchedule() {
        XCTAssertTrue(NotificationManager.canSchedule(authorizationStatus: .authorized))
        // Delivered quietly to Notification Centre, but delivered.
        XCTAssertTrue(NotificationManager.canSchedule(authorizationStatus: .provisional))
        XCTAssertTrue(NotificationManager.canSchedule(authorizationStatus: .ephemeral))

        XCTAssertFalse(
            NotificationManager.canSchedule(authorizationStatus: .denied),
            "A denied permission delivers nothing, so no identifier may be stored"
        )
        XCTAssertFalse(
            NotificationManager.canSchedule(authorizationStatus: .notDetermined),
            "Nothing is delivered until the prompt has been answered"
        )
    }

    /// The live path agrees with the rule, whatever this process happens to hold:
    /// a simulator the app has already been run and allowed on carries a real
    /// grant, a fresh one carries none.
    func testSchedulingFollowsTheAuthorizationRule() async {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus

        let scheduled = await NotificationManager.instance.scheduleNotification(
            title: "Test",
            subtitle: "Test",
            date: Date().addingTimeInterval(3600)
        )

        if NotificationManager.canSchedule(authorizationStatus: status) {
            XCTAssertNotNil(scheduled, "An authorized process must get an identifier back")
            await NotificationManager.instance.removeNotifications(
                identifiers: scheduled.map { [$0] }
            )
        } else {
            XCTAssertNil(
                scheduled,
                "Without authorization the reminder cannot fire, so nothing may be stored for it"
            )
        }
    }

    func testRemoveNotificationsLeavesNoPendingRequest() async throws {
        // Added straight through the notification centre rather than through
        // `scheduleNotification`, which now refuses without authorization — and a
        // test process normally has none. `try?` because the point of the case
        // above is precisely that this call does not fail when it cannot deliver.
        let identifier = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "Test"
        let trigger = try XCTUnwrap(
            NotificationManager.trigger(for: Date().addingTimeInterval(3600))
        )

        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )

        await NotificationManager.instance.removeNotifications(identifiers: [identifier])

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertFalse(pending.contains { $0.identifier == identifier })
    }

    /// The badge must count only what the user has actually been handed. Pending
    /// requests were counted too, which put a number on the icon for reminders
    /// that had not fired yet — and `removeNotifications` calls this, so editing
    /// or deleting a note that carried a reminder badged the app out of nowhere.
    ///
    /// Asserted against the rule rather than the live notification centre: a test
    /// process gets no notification authorization, so its pending queue stays
    /// empty and an end-to-end check would pass either way.
    func testBadgeCountIgnoresPendingReminders() {
        XCTAssertEqual(
            NotificationManager.badgeCount(unseenDelivered: 0, pending: 7, isActive: false),
            0,
            "Seven reminders scheduled for the future must leave the icon bare"
        )

        XCTAssertEqual(
            NotificationManager.badgeCount(unseenDelivered: 2, pending: 7, isActive: false),
            2,
            "Only the two the user has actually been handed belong on the badge"
        )
    }

    /// The other half of the same bug. The app clears its badge whenever it
    /// becomes active, but the reminders stay in the notification centre — and
    /// `removeNotifications` recounts those, so editing or deleting a note that
    /// carried a reminder put the number straight back on the icon of an app the
    /// user was looking at.
    func testBadgeStaysBareWhileTheAppIsOnScreen() {
        XCTAssertEqual(
            NotificationManager.badgeCount(unseenDelivered: 3, pending: 0, isActive: true),
            0,
            "Three reminders already handed over must not badge an app the user is in"
        )

        XCTAssertEqual(
            NotificationManager.badgeCount(unseenDelivered: 3, pending: 0, isActive: false),
            3,
            "Once the app is off screen the delivered reminders count again"
        )
    }

    // MARK: - Telling seen reminders from unseen ones

    /// Going bare while the app is open is a claim that the user has seen those
    /// reminders, and nothing used to record it. The notifications themselves stay
    /// in the notification centre on purpose — that is where a missed one remains
    /// reviewable — so with no watermark they were counted all over again into the
    /// badge fixed onto the next reminder scheduled: three read yesterday and one
    /// set today arrived showing 4.
    func testRemindersSeenInAnEarlierSessionAreNotCountedAgain() {
        let yesterday = Date().addingTimeInterval(-24 * 3600)
        let lastOpened = Date().addingTimeInterval(-3600)

        XCTAssertEqual(
            NotificationManager.unseenCount(
                deliveryDates: [yesterday, yesterday, yesterday],
                seenUpTo: lastOpened
            ),
            0,
            "Every one of them was already in the notification centre when the app was last open"
        )
    }

    /// The reminders that arrived since count, and only those.
    func testOnlyRemindersDeliveredSinceTheAppWasLastOpenCount() {
        let lastOpened = Date().addingTimeInterval(-3600)

        XCTAssertEqual(
            NotificationManager.unseenCount(
                deliveryDates: [
                    lastOpened.addingTimeInterval(-600),
                    lastOpened.addingTimeInterval(600),
                    lastOpened.addingTimeInterval(1200)
                ],
                seenUpTo: lastOpened
            ),
            2
        )
    }

    /// Before the app has ever been on screen there is nothing to have seen them
    /// by, so everything the notification centre holds still counts.
    func testEverythingCountsUntilTheAppHasBeenOpenedOnce() {
        XCTAssertEqual(
            NotificationManager.unseenCount(
                deliveryDates: [Date(), Date()],
                seenUpTo: nil
            ),
            2
        )
    }

    /// Counted from the delivery dates rather than kept as a running total, so
    /// nothing has to be decremented and the tally cannot drift: a reminder
    /// cleared by hand, or dropped by the app along with the note that owned it,
    /// simply stops being in the list.
    func testDroppingADeliveredReminderLeavesTheRestCountedRight() {
        let lastOpened = Date().addingTimeInterval(-3600)
        let seen = lastOpened.addingTimeInterval(-600)
        let unseen = [lastOpened.addingTimeInterval(600), lastOpened.addingTimeInterval(1200)]

        XCTAssertEqual(
            NotificationManager.unseenCount(
                deliveryDates: [seen] + unseen,
                seenUpTo: lastOpened
            ),
            2
        )

        XCTAssertEqual(
            NotificationManager.unseenCount(deliveryDates: unseen, seenUpTo: lastOpened),
            2,
            "Removing one the user had already seen must not take an unseen one with it"
        )
    }

    /// The live path agrees with the rule, whichever state this process is in.
    func testUpdateBadgeCountReportsWhatItSet() async {
        let badge = await NotificationManager.instance.updateBadgeCount()
        let expected = NotificationManager.badgeCount(
            unseenDelivered: NotificationManager.unseenCount(
                deliveryDates: await UNUserNotificationCenter.current()
                    .deliveredNotifications()
                    .map(\.date),
                seenUpTo: NotificationManager.instance.deliveredSeenUpTo
            ),
            pending: await UNUserNotificationCenter.current().pendingNotificationRequests().count,
            isActive: UIApplication.shared.applicationState == .active
        )

        XCTAssertEqual(badge, expected)
    }

    // MARK: - Keeping pending badges in fire order

    private func reminder(
        _ identifier: String,
        inHours hours: Double,
        badge: Int?
    ) -> NotificationManager.PendingReminder {
        NotificationManager.PendingReminder(
            identifier: identifier,
            fireDate: Date().addingTimeInterval(hours * 3600),
            badge: badge
        )
    }

    /// A badge is fixed when the reminder is scheduled, so a reminder inserted
    /// ahead of one already in the queue leaves that one counting too few. Set a
    /// reminder for tonight, then one for this afternoon, and tonight's used to
    /// arrive showing 1 while two reminders were waiting.
    func testABadgeIsRaisedForAReminderOvertakenByANewerOne() {
        let corrections = NotificationManager.rebalancedBadges(
            unseenDelivered: 0,
            reminders: [
                // Scheduled first, so it was numbered as if it were alone.
                reminder("tonight", inHours: 6, badge: 1),
                // Added afterwards but fires sooner, which pushes the other back.
                reminder("afternoon", inHours: 2, badge: 1)
            ]
        )

        XCTAssertEqual(
            corrections,
            ["tonight": 2],
            "The later reminder is now second in line and must say so"
        )
    }

    /// The mirror image: dropping the earliest of several reminders moves the rest
    /// up, and they were carrying a number that counted the one no longer coming.
    func testABadgeIsLoweredWhenAnEarlierReminderIsCancelled() {
        let corrections = NotificationManager.rebalancedBadges(
            unseenDelivered: 0,
            reminders: [
                reminder("afternoon", inHours: 2, badge: 2),
                reminder("tonight", inHours: 6, badge: 3)
            ]
        )

        XCTAssertEqual(
            corrections,
            ["afternoon": 1, "tonight": 2],
            "Both moved up a place when the reminder ahead of them went away"
        )
    }

    /// Re-adding a request is a write to the notification centre, and the ordinary
    /// case — a new reminder that is simply the latest — leaves every existing
    /// badge already right. Nothing may be rewritten for it.
    func testNothingIsRewrittenWhenEveryBadgeIsAlreadyRight() {
        let corrections = NotificationManager.rebalancedBadges(
            unseenDelivered: 0,
            reminders: [
                reminder("afternoon", inHours: 2, badge: 1),
                reminder("tonight", inHours: 6, badge: 2)
            ]
        )

        XCTAssertTrue(corrections.isEmpty)
    }

    /// Reminders are numbered on top of what has already been handed over, the
    /// same base `badgeCount(remindersDueEarlier:)` counts a single request from.
    func testDeliveredRemindersAreCountedBeneathThePendingOnes() {
        let corrections = NotificationManager.rebalancedBadges(
            unseenDelivered: 3,
            reminders: [
                reminder("afternoon", inHours: 2, badge: 1),
                reminder("tonight", inHours: 6, badge: 2)
            ]
        )

        XCTAssertEqual(corrections, ["afternoon": 4, "tonight": 5])
    }

    /// A reminder that carries no badge at all still needs one.
    func testAReminderWithoutABadgeGetsOne() {
        let corrections = NotificationManager.rebalancedBadges(
            unseenDelivered: 0,
            reminders: [reminder("lonely", inHours: 1, badge: nil)]
        )

        XCTAssertEqual(corrections, ["lonely": 1])
    }

    /// Two reminders due at the very same moment have no fire order to sort by, so
    /// the tie breaks on identifier — otherwise the numbering would depend on
    /// whatever order the notification centre happened to list them in, and the
    /// pair would be rewritten on every pass.
    func testRemindersDueAtTheSameMomentAreNumberedStably() {
        let due = Date().addingTimeInterval(3600)
        let makeReminders = { (identifiers: [String]) in
            identifiers.map {
                NotificationManager.PendingReminder(
                    identifier: $0, fireDate: due, badge: nil
                )
            }
        }

        let ascending = NotificationManager.rebalancedBadges(
            unseenDelivered: 0,
            reminders: makeReminders(["a", "b"])
        )
        let descending = NotificationManager.rebalancedBadges(
            unseenDelivered: 0,
            reminders: makeReminders(["b", "a"])
        )

        XCTAssertEqual(ascending, ["a": 1, "b": 2])
        XCTAssertEqual(descending, ascending)
    }

    /// An empty queue is not a queue that needs fixing.
    func testAnEmptyQueueNeedsNoCorrections() {
        XCTAssertTrue(
            NotificationManager.rebalancedBadges(unseenDelivered: 4, reminders: []).isEmpty
        )
    }

    /// The live path holds together whatever this process is authorized for: with
    /// no grant the pending queue is empty and it is a no-op, with one it must
    /// leave every pending badge agreeing with the rule.
    func testRebalanceLeavesEveryPendingBadgeAgreeingWithTheRule() async {
        await NotificationManager.instance.rebalanceBadges()

        let center = UNUserNotificationCenter.current()
        let reminders = await center.pendingNotificationRequests().compactMap {
            request -> NotificationManager.PendingReminder? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fireDate = trigger.nextTriggerDate()
            else { return nil }

            return NotificationManager.PendingReminder(
                identifier: request.identifier,
                fireDate: fireDate,
                badge: request.content.badge?.intValue
            )
        }

        let remaining = NotificationManager.rebalancedBadges(
            unseenDelivered: NotificationManager.unseenCount(
                deliveryDates: await center.deliveredNotifications().map(\.date),
                seenUpTo: NotificationManager.instance.deliveredSeenUpTo
            ),
            reminders: reminders
        )

        XCTAssertTrue(
            remaining.isEmpty,
            "A rebalance must leave nothing left to correct"
        )
    }

    // MARK: - Routing a tapped reminder

    /// A tapped reminder has to reach the note it belongs to. The lookup goes
    /// through the stored identifiers rather than through anything in the
    /// notification's payload, because a protected note's reminder deliberately
    /// carries neither its title nor its body.
    func testATappedReminderFindsItsNote() {
        let wanted = NoteModel(
            title: "Milk",
            content: "Content",
            notificationIdentifiers: ["reminder-1"]
        )
        let other = NoteModel(
            title: "Other",
            content: "Content",
            notificationIdentifiers: ["reminder-2"]
        )

        XCTAssertEqual(
            NotificationRouter.noteIdentifier(
                forNotification: "reminder-1",
                in: [other, wanted]
            ),
            wanted.id
        )
    }

    /// A notification that outlived the note it named must route nowhere rather
    /// than to whatever happens to be first in the list.
    func testATappedReminderForAnUnknownNoteRoutesNowhere() {
        let note = NoteModel(
            title: "Milk",
            content: "Content",
            notificationIdentifiers: ["reminder-1"]
        )

        XCTAssertNil(
            NotificationRouter.noteIdentifier(forNotification: "reminder-gone", in: [note])
        )
    }

    /// A trashed note's reminder was cancelled on the way into the trash, so a tap
    /// can only be a notification that outlived it — pushing a note the user
    /// deleted would be worse than doing nothing.
    func testATappedReminderSkipsATrashedNote() {
        let trashed = NoteModel(
            title: "Doomed",
            content: "Content",
            notificationIdentifiers: ["reminder-1"],
            isDeleted: true,
            deletedAt: Date()
        )

        XCTAssertNil(
            NotificationRouter.noteIdentifier(forNotification: "reminder-1", in: [trashed])
        )
    }

    /// A note without a reminder carries no identifiers at all, which must not be
    /// mistaken for a match.
    func testATappedReminderIgnoresNotesWithoutIdentifiers() {
        let plain = NoteModel(title: "Plain", content: "Content")

        XCTAssertNil(
            NotificationRouter.noteIdentifier(forNotification: "reminder-1", in: [plain])
        )
    }

    // MARK: - A tap that arrives before the notes do

    /// The ordinary case: the store knows the note, so the tap opens it.
    func testATapIsRoutedWhenTheStoreKnowsTheNote() {
        let note = NoteModel(
            title: "Milk",
            content: "Content",
            notificationIdentifiers: ["reminder-1"]
        )

        XCTAssertEqual(
            NotificationRouter.outcome(
                for: .notification("reminder-1"),
                in: [note],
                storeIsLoaded: true
            ),
            .route(note.id)
        )
    }

    /// A store that never read its notes answers "no such note" to everything, and
    /// that used to end the matter — so a reminder tapped while the file was still
    /// behind `.completeFileProtection` opened nothing and nothing asked again. It
    /// is not an answer, it is the absence of one, so the tap is kept.
    func testATapIsKeptWhileTheStoreCannotAnswerForIt() {
        XCTAssertEqual(
            NotificationRouter.outcome(
                for: .notification("reminder-1"),
                in: [],
                storeIsLoaded: false
            ),
            .keepWaiting
        )
    }

    /// And once the notes are readable the kept tap opens its note, which is the
    /// whole point of keeping it.
    func testAKeptTapIsRoutedOnceTheNotesAreReadable() {
        let note = NoteModel(
            title: "Milk",
            content: "Content",
            notificationIdentifiers: ["reminder-1"]
        )

        XCTAssertEqual(
            NotificationRouter.outcome(for: .notification("reminder-1"), in: [], storeIsLoaded: false),
            .keepWaiting
        )
        XCTAssertEqual(
            NotificationRouter.outcome(for: .notification("reminder-1"), in: [note], storeIsLoaded: true),
            .route(note.id)
        )
    }

    /// A loaded store that does not know the identifier is a real answer: the note
    /// is gone. Carrying the tap on would spring a note open the moment the user
    /// restored it from the trash, long after they had forgotten pressing anything.
    func testATapIsGivenUpOnOnceTheStoreCanAnswerAndDoesNotKnowTheNote() {
        let other = NoteModel(
            title: "Other",
            content: "Content",
            notificationIdentifiers: ["reminder-2"]
        )

        XCTAssertEqual(
            NotificationRouter.outcome(
                for: .notification("reminder-1"),
                in: [other],
                storeIsLoaded: true
            ),
            .giveUp
        )
    }

    /// A trashed note is still not a match, loaded store or not — the tap is a
    /// notification that outlived it.
    func testATapForATrashedNoteIsGivenUpOnRatherThanKept() {
        let trashed = NoteModel(
            title: "Doomed",
            content: "Content",
            notificationIdentifiers: ["reminder-1"],
            isDeleted: true,
            deletedAt: Date()
        )

        XCTAssertEqual(
            NotificationRouter.outcome(
                for: .notification("reminder-1"),
                in: [trashed],
                storeIsLoaded: true
            ),
            .giveUp
        )
    }

    /// Nothing waiting, nothing to do — the common path on every trip to the
    /// foreground.
    func testRetryingWithNoTapWaitingDoesNothing() {
        let router = NotificationRouter.shared
        router.noteToOpen = nil

        router.retryPendingRequest(in: [], storeIsLoaded: true)

        XCTAssertNil(router.noteToOpen)
    }

    // MARK: - Opening a note from the widget

    /// A widget link names its note directly, where a reminder names a
    /// notification request — but everything after that is the same question, and
    /// it goes through the same rule so the two cannot answer it differently.
    func testAWidgetLinkOpensItsNote() {
        let note = NoteModel(title: "Milk", content: "Content")
        let other = NoteModel(title: "Other", content: "Content")

        XCTAssertEqual(
            NotificationRouter.outcome(
                for: .note(note.id),
                in: [other, note],
                storeIsLoaded: true
            ),
            .route(note.id)
        )
    }

    /// The widget's payload can be minutes old, so the note it drew may since have
    /// gone to the trash. Springing a deleted note open would be worse than doing
    /// nothing — the same rule a notification that outlived its note meets.
    func testAWidgetLinkToATrashedNoteOpensNothing() {
        let trashed = NoteModel(
            title: "Doomed",
            content: "Content",
            isDeleted: true,
            deletedAt: Date()
        )

        XCTAssertEqual(
            NotificationRouter.outcome(
                for: .note(trashed.id),
                in: [trashed],
                storeIsLoaded: true
            ),
            .giveUp
        )
    }

    /// A link followed from a locked home screen reaches a store that has read
    /// nothing, which is not the same as the note being gone — so it is kept and
    /// tried again, exactly as a tapped reminder is.
    func testAWidgetLinkIsKeptWhileTheStoreCannotAnswerForIt() {
        let note = NoteModel(title: "Milk", content: "Content")

        XCTAssertEqual(
            NotificationRouter.outcome(for: .note(note.id), in: [], storeIsLoaded: false),
            .keepWaiting
        )
        XCTAssertEqual(
            NotificationRouter.outcome(for: .note(note.id), in: [note], storeIsLoaded: true),
            .route(note.id)
        )
    }

    /// The splash screen reads this to get out of the way of a launch that already
    /// has somewhere to go — otherwise the user who pressed the note they wanted
    /// waits six tenths of a second for an intro animation first.
    func testAKeptRequestCountsAsADestinationForTheSplashScreen() {
        let router = NotificationRouter.shared
        let note = NoteModel(title: "Milk", content: "Content")

        router.noteToOpen = nil
        router.open(.note(note.id), in: [], storeIsLoaded: true)
        XCTAssertFalse(
            router.hasPendingDestination,
            "A request given up on is not a destination"
        )

        // Kept rather than resolved: the store cannot answer yet.
        router.open(.note(note.id), in: [], storeIsLoaded: false)
        XCTAssertTrue(router.hasPendingDestination)

        router.open(.note(note.id), in: [note], storeIsLoaded: true)
        XCTAssertEqual(router.noteToOpen, note.id)
        XCTAssertTrue(router.hasPendingDestination)

        // Left as the rest of the suite expects to find it.
        router.noteToOpen = nil
    }

    /// Past the pending limit iOS accepts a request and then discards one, so a
    /// reminder scheduled into a full queue would be stored as scheduled and never
    /// fire — or would fire at the cost of one that was already waiting. The rule
    /// refuses it instead, which is what routes the form to its "will not fire"
    /// alert and keeps the date the user picked.
    ///
    /// Asserted against the rule rather than the live notification centre: a test
    /// process gets no authorization, so its pending queue never fills up and an
    /// end-to-end check would pass either way.
    func testSchedulingIsRefusedPastThePendingLimit() {
        let limit = NotificationManager.maxPendingReminders

        XCTAssertTrue(
            NotificationManager.canSchedule(pendingReminders: 0),
            "The first reminder must always be schedulable"
        )

        XCTAssertTrue(
            NotificationManager.canSchedule(pendingReminders: limit - 1),
            "The last slot under the limit is still usable"
        )

        XCTAssertFalse(
            NotificationManager.canSchedule(pendingReminders: limit),
            "A reminder added to a full queue would cost the system one of them"
        )

        XCTAssertFalse(
            NotificationManager.canSchedule(pendingReminders: limit + 40),
            "Being further past the limit does not make it schedulable again"
        )
    }

    /// The whole queue is counted, not just the part of it due ahead of the new
    /// reminder.
    ///
    /// That narrower question — how many fire *before* this one — answers only
    /// whether the new request survives, and iOS keeps the soonest 64: a reminder
    /// set for this afternoon joins a full queue at the front, is kept, and pushes
    /// the latest one out. The displaced reminder was set earlier and the user has
    /// no reason to look at it again, so nothing anywhere would have said it had
    /// stopped existing. The new reminder used to be protected at its expense.
    func testAReminderAtTheFrontOfAFullQueueIsStillRefused() {
        XCTAssertFalse(
            NotificationManager.canSchedule(
                pendingReminders: NotificationManager.maxPendingReminders
            ),
            "Nothing is due ahead of it, but keeping it would cost one already waiting"
        )
    }

    /// A date that has already gone by produces a request iOS accepts and never
    /// delivers, so storing an identifier for it would leave the note claiming a
    /// reminder that cannot fire. The form's picker refuses to select a past
    /// date, but it reads that date when it opens — an edit that outlasts the
    /// reminder gets here anyway.
    ///
    /// Asserted against the rule rather than the live notification centre: a
    /// test process gets no authorization, so an end-to-end check could not tell
    /// a refused request from an accepted one.
    func testATriggerIsRefusedForAPastDate() {
        XCTAssertNil(
            NotificationManager.trigger(for: Date().addingTimeInterval(-3600)),
            "An hour ago can never fire"
        )

        XCTAssertNotNil(
            NotificationManager.trigger(for: Date().addingTimeInterval(3600)),
            "An hour from now is perfectly schedulable"
        )
    }

    /// The trigger matches whole minutes, so a date still technically in the
    /// future can already have missed its slot. `Date()...` on the picker does
    /// not cover this, and it is the common case: the reminder defaults to five
    /// minutes out, and the fifth minute is spent finishing the note.
    func testATriggerIsRefusedWithinTheMinuteItHasMissed() throws {
        let calendar = Calendar.current
        let now = Date()

        // Truncated with `dateComponents`, not `date(bySetting:)` — the latter
        // returns the *next* time the component takes that value, so asking it
        // for second zero lands on the next minute rather than the start of this
        // one.
        let startOfMinute = try XCTUnwrap(
            calendar.date(
                from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            )
        )

        // The last instant of the minute now falls in: still ahead of `now` —
        // and so accepted by the picker's `Date()...` bound and by any check
        // that only compares against the present — yet its trigger fires at the
        // top of that minute, which has already gone.
        let lastInstant = startOfMinute.addingTimeInterval(59.999)

        XCTAssertNil(
            NotificationManager.trigger(for: lastInstant),
            "The trigger fires on the minute, and this minute's moment is gone"
        )
    }

    /// The refusal has to reach the caller as a missing identifier — that is what
    /// routes the form to its "will not fire" alert while keeping the date.
    func testSchedulingAPastReminderReturnsNoIdentifier() async {
        let scheduled = await NotificationManager.instance.scheduleNotification(
            title: "Test",
            subtitle: "Test",
            date: Date().addingTimeInterval(-3600)
        )

        XCTAssertNil(scheduled)
    }

    /// The bulk re-arm and the one-at-a-time path must not drift apart, or an
    /// import would stop exactly where single scheduling still says yes.
    func testStoreReArmsAgainstTheSameLimit() {
        XCTAssertEqual(
            NotesStore.maxScheduledReminders,
            NotificationManager.maxPendingReminders
        )
    }

    /// Staying under the real ceiling leaves room for requests this app did not
    /// schedule, so its own accounting cannot be the thing that overruns it.
    func testPendingLimitStaysUnderTheSystemCeiling() {
        XCTAssertLessThan(NotificationManager.maxPendingReminders, 64)
    }

    func testRemoveNotificationsIgnoresEmptyInput() async {
        // Must be a no-op rather than a crash: notes without a reminder carry
        // no identifiers at all.
        await NotificationManager.instance.removeNotifications(identifiers: nil)
        await NotificationManager.instance.removeNotifications(identifiers: [])
    }
}
