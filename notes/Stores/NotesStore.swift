//
//  NotesStore.swift
//  notes
//
//  Created by Robert Libšanský on 06.07.2022.
//

import OSLog
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// How the notes file and a backup are encoded and decoded.
///
/// A `nonisolated` type of its own so one spelling of each format serves both the
/// debounced save — which runs it off the main actor through `NotesFileCoder` —
/// and the legacy `UserDefaults` migration, which happens inside `load()` and so
/// cannot await anything. Two spellings of a storage format is how the on-disk
/// shape drifts apart from the one that reads it.
enum NotesCodec {
    /// The on-disk format: compact on purpose, since the file holds base64
    /// drawing and image blobs where the extra whitespace is pure overhead.
    static func encode(_ notes: [NoteModel]) throws -> Data {
        try JSONEncoder().encode(notes)
    }

    static func write(_ notes: [NoteModel], to url: URL) throws {
        try encode(notes).write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// The backup format: pretty-printed with ISO-8601 dates, so the file a user
    /// keeps is readable. Export stays readable where the store's own file does
    /// not need to be.
    static func encodeBackup(_ notes: [NoteModel]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(notes)
    }

    /// Reads the store's own file, in exactly the format `encode` writes.
    ///
    /// Separate from `decode`, and deliberately stricter. A backup may have been
    /// written by any version of the app, so restoring one accepts either date
    /// encoding; the store's file is only ever written by `write` above, so it
    /// has one format — and reading it with the looser rule would paper over a
    /// drift between the two halves rather than surface it.
    ///
    /// Spelled here rather than at the call site so that `encode` and the thing
    /// that reads it back cannot part company, which is the whole reason this
    /// type exists. `load()` used to construct a `JSONDecoder` of its own, so a
    /// date strategy added to `encode` would have gone unnoticed until a user's
    /// notes failed to load.
    static func decodeStored(_ data: Data) throws -> [NoteModel] {
        try JSONDecoder().decode([NoteModel].self, from: data)
    }

    /// A restore accepts either date encoding, so a file copied straight out of
    /// the app container imports just as a written backup does.
    static func decode(_ data: Data) throws -> [NoteModel] {
        let iso8601 = JSONDecoder()
        iso8601.dateDecodingStrategy = .iso8601

        do {
            return try iso8601.decode([NoteModel].self, from: data)
        } catch let iso8601Error {
            do {
                return try JSONDecoder().decode([NoteModel].self, from: data)
            } catch {
                // Report against the documented backup format.
                throw iso8601Error
            }
        }
    }
}

/// Runs a store's encoding, decoding and file I/O off the main actor.
///
/// A note's `drawingData` and `backgroundImageData` are base64 inside the JSON, so
/// encoding the list is work proportional to the whole library — megabytes once a
/// handful of drawings carry a photo. All of it used to run on the main actor,
/// where every debounced save paid for a full re-encode of every blob before the
/// UI could move again: a checkbox tick, a pin, a swipe to the trash.
///
/// An actor rather than a bare `Task.detached`, because the serialisation is the
/// point. Two writes in flight at once could otherwise finish in either order and
/// leave the *older* snapshot on the disk. It also means an export or an import
/// queues behind a save in progress, which is the right way round: they are all
/// the same file's worth of work, and none of them is on a hot path.
private actor NotesFileCoder {
    func write(_ notes: [NoteModel], to url: URL) throws {
        try NotesCodec.write(notes, to: url)
    }

    func encodeBackup(_ notes: [NoteModel]) throws -> Data {
        try NotesCodec.encodeBackup(notes)
    }

    func decode(_ data: Data) throws -> [NoteModel] {
        try NotesCodec.decode(data)
    }

    func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}

@MainActor
@Observable
final class NotesStore {
    /// Shared instance used by the app and App Intents so they operate on the same data
    static let shared = NotesStore()

    /// Deleted notes are purged from storage once they have been in the trash this long.
    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    /// A large restore re-arms only the soonest reminders instead of letting the
    /// system silently drop an arbitrary subset. Takes the number from
    /// `NotificationManager`, which refuses anything past the same limit
    /// one-at-a-time, so the two cannot drift apart.
    static let maxScheduledReminders = NotificationManager.maxPendingReminders

    private(set) var notes: [NoteModel] = []
    private(set) var saveError: String?

    /// Whether the message currently in `saveError` describes the *load* rather
    /// than a save.
    ///
    /// A successful save used to clear `saveError` outright. That is right for
    /// what `save()` sets itself — "saving is blocked", "could not be written",
    /// both of which a write going through disproves — and wrong for what
    /// `load()` sets. A file that had to be set aside is the one moment the user
    /// has to be pointed at Restore from Backup, and nothing about a later write
    /// makes it untrue.
    ///
    /// `refresh()` is where the two meet, and it is the compound case that used
    /// to go unreported: a store that could not read its file at launch, notes
    /// created in the meantime, and bytes that turn out not to decode once the
    /// device is unlocked. The refresh writes those rescued notes out
    /// immediately — so the very save that saved them wrote off the explanation
    /// for the emptied list they landed in. The trash sweep at the end of the
    /// same function schedules a save of its own, so even a refresh with nothing
    /// to merge could lose the message.
    ///
    /// Set through `report(_:isAboutLoading:)` so no call site has to remember,
    /// and cleared by `clearError()` — the alert's OK button, by which point the
    /// user has read it.
    @ObservationIgnored
    private var isLoadError = false

    /// Sets the message the user is shown, and records whether a save going
    /// through is allowed to write it off. See `isLoadError`.
    private func report(_ message: String?, isAboutLoading: Bool = false) {
        saveError = message
        isLoadError = message != nil && isAboutLoading
    }

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    /// Does this store's encoding and file I/O, off the main actor and one write
    /// at a time. See `NotesFileCoder`.
    @ObservationIgnored
    private let coder = NotesFileCoder()

    /// `true` while a debounced save is still waiting to be written. Read by
    /// `flushPendingSave()`, so leaving the foreground does not pay for a full
    /// re-encode of every drawing blob when nothing has changed.
    @ObservationIgnored
    private var hasPendingSave = false

    /// Bumped by every `scheduleSave()`, so a write can tell whether the bytes it
    /// is carrying are still the latest by the time they are down.
    ///
    /// Needed because the write now suspends: an edit made while it was in flight
    /// has already queued a save of its own, and clearing `hasPendingSave` on the
    /// older write's behalf would tell the scene there is nothing left to flush.
    /// See `save()`.
    @ObservationIgnored
    private var saveRevision = 0

    /// Whether a debounced save is still waiting to be written. Let the scene ask
    /// iOS for background time only when there is a write to protect, rather than
    /// on every trip to the background.
    var isSavePending: Bool { hasPendingSave }

    /// Whether `notes` is the stored list rather than whatever little a blocked
    /// store holds in memory. Read by `NotificationRouter`, which has to tell "the
    /// note this reminder names is gone" from "this store never read its notes" —
    /// the second is not an answer, and giving up on it lost the tap. See
    /// `isStorageLoaded`.
    var isLoaded: Bool { isStorageLoaded }

    /// `false` when the notes file is there but its bytes could not be read —
    /// most likely because it is still protected while the device is locked.
    /// Saving in that state would replace the user's real notes with whatever
    /// little is in memory, so writes are refused until a load succeeds. See
    /// `refresh()`.
    ///
    /// Deliberately *not* set for a file whose bytes were read but did not
    /// decode. See `LoadFailure`.
    @ObservationIgnored
    private var isStorageLoaded = true

    /// Why a load did not produce the stored notes.
    ///
    /// The two cases used to be one, and the difference decides whether waiting
    /// helps. Everything but "no such file" was treated as "unreadable, retry
    /// later", which is right for a locked device and wrong for a file that will
    /// never decode: writes stayed blocked for ever, `importNotes` refuses while
    /// they are, and so the one action that would have fixed it — restoring a
    /// backup — was the one action ruled out. The app was left unusable with no
    /// way back that did not involve deleting it.
    private enum LoadFailure {
        /// The bytes could not be read. The notes are still in there, so a later
        /// attempt gets them; nothing may be written until it does.
        case unreadable

        /// The bytes were read but are not notes. No later attempt will decode
        /// them either, so the file is moved aside instead of blocking the app
        /// for ever — see `setAsideUnreadableFile()`. Nothing is destroyed.
        case undecodable
    }

    // Exposed for test teardown; production code always uses the default.
    let fileURL: URL

    /// `URL.documentsDirectory` rather than the first element of
    /// `FileManager.urls(for:in:)`, which is an array and so had to be force
    /// unwrapped. The unwrap could not actually fail — an iOS app always has a
    /// Documents directory — but "safe because of something you have to know about
    /// the platform" is the kind of claim a reader has to stop and verify, and it
    /// was the only `!` left in either target. Foundation spells the same directory
    /// as a non-optional; this is that spelling.
    private static let defaultFileURL = URL.documentsDirectory
        .appendingPathComponent("notes.json")

    /// Moves a notes file whose contents could not be decoded out of the way.
    ///
    /// The bytes are kept — renamed, not deleted. They are all that is left of
    /// whatever was in there, and a copy pulled off the device later may still be
    /// worth something. What this buys is a store that reads as empty rather than
    /// as blocked, so the app works and a backup has somewhere to land.
    ///
    /// - Returns: `true` when the file is no longer where the store reads from.
    private func setAsideUnreadableFile() -> Bool {
        // A UUID rather than a timestamp: unique without needing a second
        // attempt, and the file's own creation date already says when.
        let destination = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(fileURL.deletingPathExtension().lastPathComponent)-unreadable-\(UUID().uuidString).json"
            )

        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            Log.store.error("Notes file could not be decoded; set aside as \(destination.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Log.store.error("Could not set the undecodable notes file aside: \(error.localizedDescription)")
            return false
        }
    }

    private func load() {
        var failure: LoadFailure?
        var failureError: Error?

        // Try to load from file first (current storage)
        do {
            let data = try Data(contentsOf: fileURL)

            do {
                notes = try NotesCodec.decodeStored(data)
                isStorageLoaded = true
                Log.store.info("Loaded \(self.notes.count) notes from file storage")

                // Clean up old UserDefaults if they exist (migration already completed)
                if UserDefaults.standard.data(forKey: "notes") != nil {
                    UserDefaults.standard.removeObject(forKey: "notes")
                    Log.store.info("Cleaned up old UserDefaults data")
                }
                return
            } catch {
                // The bytes are there and they are not notes. Waiting changes
                // nothing; try the UserDefaults backup.
                Log.store.error("Notes file did not decode, trying UserDefaults fallback: \(error.localizedDescription)")
                failure = .undecodable
                failureError = error
            }
        } catch CocoaError.fileReadNoSuchFile {
            // File doesn't exist - check for migration from UserDefaults.
            // Nothing to lose here, so writing stays allowed.
            isStorageLoaded = true
            Log.store.info("No notes file found - checking for UserDefaults migration")
        } catch {
            // The file is there but its bytes are out of reach — the device is
            // locked, most likely. The notes are intact, so nothing may be
            // written over them; `refresh()` retries.
            Log.store.error("Notes file could not be read, trying UserDefaults fallback: \(error.localizedDescription)")
            failure = .unreadable
            failureError = error
        }

        // A file that will never decode goes aside here rather than at the end of
        // this function. Waiting cannot help it, so there is nothing to gain by
        // leaving it — and the recovery below writes to exactly this path, so
        // leaving it meant that write destroyed the one copy of whatever was in
        // there. Keeping those bytes is the whole point of setting the file aside.
        let isSetAside = failure == .undecodable ? setAsideUnreadableFile() : false

        // Whether the recovery below has anywhere safe to write.
        //
        // An unreadable file must never be written over — its notes are intact
        // and merely out of reach, and a stale UserDefaults copy is not a reason
        // to replace them. An undecodable one that could not even be renamed is
        // still what the store reads from, so it is just as untouchable. Both are
        // the same rule `save()` and `importNotes` already enforce; this is the
        // one write that used to sidestep it.
        let canWrite: Bool
        switch failure {
        case nil: canWrite = true
        case .unreadable: canWrite = false
        case .undecodable: canWrite = isSetAside
        }

        // Migration: Load from UserDefaults if the file is missing, unreadable
        // or undecodable
        // The legacy copy was written by a build that encoded exactly as
        // `NotesCodec.encode` does, so it is read back through the same rule as
        // the file — see `decodeStored`.
        if let data = UserDefaults.standard.data(forKey: "notes"),
           let decoded = try? NotesCodec.decodeStored(data) {
            notes = decoded

            if failure != nil {
                Log.store.info("Recovered \(self.notes.count) notes from UserDefaults backup after the file failed to load")
            } else {
                Log.store.info("Found \(self.notes.count) notes in UserDefaults, migrating to file storage")
            }

            guard canWrite else {
                // The notes are on board and stay in UserDefaults as their only
                // durable copy. Writes remain blocked until a load succeeds, so
                // nothing can land on the file still in the way.
                isStorageLoaded = false
                Log.store.error("Recovered notes from UserDefaults, but the notes file cannot be written over - saving is blocked")
                report(String(localized: "errorSaveBlocked"))
                return
            }

            isStorageLoaded = true

            // Perform SYNCHRONOUS migration/recovery to file.
            //
            // The one write in the app that is still paid for on the main actor,
            // and it has to be: `load()` is called from `init`, so it cannot
            // await, and the `UserDefaults` copy below must not be removed until
            // these bytes are confirmed down. It runs once in a device's lifetime,
            // for a legacy store, where the debounced save it bypasses runs on
            // every edit — see `NotesFileCoder`.
            do {
                try NotesCodec.write(notes, to: fileURL)

                // Only remove from UserDefaults AFTER confirmed successful save
                UserDefaults.standard.removeObject(forKey: "notes")
                Log.store.info("Successfully saved \(self.notes.count) notes to file storage")

                // A file that had to be set aside is news the user has to have,
                // and this was the one branch that set one aside and said nothing
                // — it cleared the error outright. The recovery going well is not
                // the same as nothing having happened: these notes come from a
                // UserDefaults copy left behind by a migration that never
                // finished, so they can be older than what the file held, and
                // that file is now sitting in the container under another name.
                report(
                    isSetAside ? String(localized: "errorLoadCorruptRecovered") : nil,
                    isAboutLoading: true
                )
            } catch {
                Log.store.error("Failed to save to file, notes remain in UserDefaults as backup: \(error.localizedDescription)")
                report(String(localized: "errorSaveFailed"))
            }
            return
        }

        // No data anywhere - either first launch or both sources failed
        guard let failure, let failureError else {
            Log.store.info("Starting fresh - no existing notes found")
            return
        }

        switch failure {
        case .unreadable:
            // Keep writes blocked so a save cannot overwrite the notes with an
            // empty list; `refresh()` retries once the device is unlocked.
            isStorageLoaded = false
            Log.store.error("Notes file unreadable and no UserDefaults backup - saving is blocked until a load succeeds")
            report(
                String(localized: "errorLoadFailed \(failureError.localizedDescription)"),
                isAboutLoading: true
            )

        case .undecodable:
            // Blocking writes would block them for ever, restoring a backup
            // included. The file went aside instead — kept, not dropped — and the
            // store carries on as an empty one, which is what it now truthfully is.
            if isSetAside {
                isStorageLoaded = true
                report(String(localized: "errorLoadCorrupt"), isAboutLoading: true)
            } else {
                // It could not even be renamed, so it is still what the store
                // reads from. Treat it as unreadable rather than write over it.
                isStorageLoaded = false
                Log.store.error("The undecodable notes file is still in place - saving stays blocked")
                report(
                    String(localized: "errorLoadFailed \(failureError.localizedDescription)"),
                    isAboutLoading: true
                )
            }
        }
    }

    /// Retries a load that previously failed and purges expired trash.
    /// Call it whenever the app becomes active: a store created while the device
    /// was locked starts out unable to read its own file, and the trash of a
    /// long-lived process would otherwise never be swept again after launch.
    func refresh() async {
        if !isStorageLoaded {
            // Anything created while storage was unreadable exists only in
            // memory. Load the real file, then fold those notes back in.
            let pending = notes

            // Cleared *before* the load, not after it. `load()` has its own things
            // to say — above all that it had to set a file aside, which is the one
            // moment the user has to be told to restore from a backup — and
            // clearing afterwards threw that message away along with the stale
            // "could not be read" this is here to drop. What was left was an
            // emptied store, no explanation on screen, and no pointer at the one
            // action that would fix it.
            //
            // What `load()` then has to say survives the save below as well —
            // clearing it before was only half the fix, because the write that
            // rescues the notes made while storage was blocked used to clear
            // `saveError` on its way through. See `isLoadError`.
            report(nil)
            notes = []
            load()

            if isStorageLoaded {
                let known = Set(notes.map(\.id))
                let recovered = pending.filter { !known.contains($0.id) }
                notes.append(contentsOf: recovered)
                Log.store.info("Storage became readable again, merged \(recovered.count) note(s) created while it was locked")

                if !recovered.isEmpty {
                    _ = await save()
                } else {
                    // A save is what normally republishes the widget's payload,
                    // and there is nothing here to save. This is the one moment
                    // the store's contents change without an edit, so it is the
                    // only chance to bring the shared container back in line with
                    // a file it may well be out of step with — it was last
                    // written by whatever ran before this process.
                    syncWidgetData()
                }
            } else {
                // Still unreadable - keep the in-memory notes for a later retry.
                notes = pending
                return
            }
        }

        let before = notes
        if purgeExpiredTrash() {
            let orphans = orphanedIdentifiers(comparedTo: before)
            scheduleSave()
            await NotificationManager.instance.removeNotifications(identifiers: orphans)
        }
    }

    /// Drops notes that have been in the trash longer than `trashRetention`.
    /// - Returns: `true` when anything was purged.
    @discardableResult
    private func purgeExpiredTrash() -> Bool {
        let cutoff = Date().addingTimeInterval(-Self.trashRetention)
        let remaining = notes.filter { note in
            guard note.isDeleted, let deletedAt = note.deletedAt else { return true }
            return deletedAt > cutoff
        }

        guard remaining.count != notes.count else { return false }

        Log.store.info("Purged \(self.notes.count - remaining.count) expired notes from trash")
        notes = remaining
        return true
    }

    private func save() async -> Bool {
        // Never write over a file that was never read - see `isStorageLoaded`.
        guard isStorageLoaded else {
            Log.store.error("Refusing to save: notes were never loaded, writing now would destroy the stored data")
            report(String(localized: "errorSaveBlocked"))
            return false
        }

        // Both taken before the suspension below. The encode runs off the main
        // actor now, so `notes` can be edited again while these bytes are still
        // on their way to the disk — the snapshot is what is actually being
        // written, and the revision is how this write recognises itself as stale.
        let snapshot = notes
        let revision = saveRevision

        do {
            try await coder.write(snapshot, to: fileURL)

            // Cleared once the bytes are actually down, not on the way in.
            // Clearing it up front left a refused or failed write reading as
            // "nothing pending", so the flush on the way to the background —
            // the retry this flag exists to trigger — was skipped for exactly
            // the case that needed it.
            //
            // And only while these are still the newest bytes. The write suspends,
            // so an edit made while it was in flight has already scheduled a save
            // of its own; clearing the flag on this older write's behalf would
            // tell the scene there is nothing to protect and lose that edit if the
            // app went to the background in the gap.
            if revision == saveRevision {
                hasPendingSave = false
            }

            // Only a message about saving, which this write has just disproved.
            // What `load()` had to say outlives it — see `isLoadError`.
            if !isLoadError { report(nil) }

            Log.store.info("Successfully saved \(snapshot.count) notes")
            syncWidgetData()
            return true
        } catch {
            Log.store.error("Failed to save notes: \(error.localizedDescription)")
            report(String(localized: "errorSaveFailedDetail \(error.localizedDescription)"))
            return false
        }
    }

    /// How many notes the widget payload carries. The widget only ever shows a
    /// handful; the rest is headroom so it has something to fall back on.
    static let widgetPayloadLimit = 20

    /// The truncated, ordered payload the widget reads.
    ///
    /// Split out of `syncWidgetData` so it can be exercised without an App
    /// Group container, which a test process does not have.
    static func widgetPayload(for activeNotes: [NoteModel]) -> [WidgetNoteEntry] {
        activeNotes
            // Pinned first, then newest. Fixed on purpose rather than following
            // the list's `sortOption`, which is a view preference the widget
            // cannot read — and "newest pinned note" is what a glanceable
            // widget wants regardless of how the user sorts the full list.
            .sorted { lhs, rhs in
                lhs.pinned == rhs.pinned
                    ? lhs.createdAt > rhs.createdAt
                    : lhs.pinned
            }
            .prefix(widgetPayloadLimit)
            .map { WidgetNoteEntry(from: $0) }
    }

    private func syncWidgetData() {
        // Refused while the stored notes are unread, for the same reason `save()`
        // and `importNotes` refuse: an unreadable store must not be mistaken for
        // an empty one. `notes` then holds whatever little is in memory — usually
        // nothing at all — and the shared container is what the home screen
        // renders, so publishing from it replaced the user's widget with "No
        // notes". Unlike the file, that copy has no protection to hide behind,
        // and the very case this happens in is a process that started while the
        // device was locked: a Siri shortcut, a background launch.
        guard isStorageLoaded else {
            Log.store.error("Refusing to publish the widget payload: the stored notes were never read")
            return
        }

        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return }
        let active = activeNotes
        if let data = try? JSONEncoder().encode(Self.widgetPayload(for: active)) {
            defaults.set(data, forKey: AppGroup.widgetDataKey)
        }
        defaults.set(active.count, forKey: AppGroup.widgetTotalKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Re-arms a reminder whose notification was never scheduled on this device.
    /// Imported notes carry identifiers minted on another device, and a note
    /// coming back from the trash had its notifications cancelled when it went
    /// in — in both cases the note would otherwise show a reminder that can
    /// never fire.
    ///
    /// Deliberately does not save. `rescheduleReminders` re-arms a whole restore
    /// in a loop and every iteration awaits the notification centre, so a save
    /// in here had its debounce elapse between two awaits — rewriting the entire
    /// file, base64 drawing and photo blobs included, once per reminder instead
    /// of once for the batch. Callers persist what changed.
    ///
    /// - Returns: `true` when the note's identifiers actually changed.
    @discardableResult
    private func rescheduleReminder(for id: UUID) async -> Bool {
        guard let note = notes.first(where: { $0.id == id }),
              !note.isDeleted,
              let reminder = note.reminder,
              reminder > Date()
        else { return false }

        // Stale identifiers are usually unknown to this device, but dropping
        // them keeps a re-import from leaving duplicates behind.
        await NotificationManager.instance.removeNotifications(identifiers: note.notificationIdentifiers)

        let identifier = await NotificationManager.instance.scheduleNotification(
            title: note.notificationTitle,
            subtitle: note.notificationSubtitle,
            date: reminder
        )

        // The array may have changed while awaiting, so look the note up again.
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }

        // The reminder date itself is kept even when scheduling fails (for
        // example with notifications denied): it is user data from the backup
        // and the calendar view lists notes by it. Only the identifiers are
        // dropped, so nothing points at a notification that does not exist.
        let updated = identifier.map { [$0] }

        // A note whose identifiers come back the same — nil in, nil out when
        // scheduling was refused — owes no write and no observation.
        guard notes[index].notificationIdentifiers != updated else { return false }

        notes[index].notificationIdentifiers = updated
        return true
    }

    private func rescheduleReminders(for ids: [UUID]) async {
        let now = Date()
        // Indexed by a `Set` rather than looking each id up in `notes`, which was
        // quadratic — and this runs on the main actor immediately after a
        // restore, the one moment both sides are as large as the library ever
        // gets. `importNotes` fixed the same shape in its own merge; this was the
        // other half of it, reached from that very call.
        let wanted = Set(ids)
        let candidates = notes
            .filter {
                wanted.contains($0.id)
                    && !$0.isDeleted
                    && ($0.reminder ?? .distantPast) > now
            }
            .sorted { ($0.reminder ?? .distantPast) < ($1.reminder ?? .distantPast) }

        let arming = candidates.prefix(Self.maxScheduledReminders)

        if candidates.count > arming.count {
            Log.notifications.notice("Re-arming \(arming.count) reminders; \(candidates.count - arming.count) beyond the system limit were left unscheduled")
        }

        // One save for the whole batch — see `rescheduleReminder`.
        var changed = false

        for note in arming {
            if await rescheduleReminder(for: note.id) { changed = true }
        }

        if changed { scheduleSave() }
    }

    /// Identifiers of notifications belonging to notes that no longer exist or
    /// no longer carry a reminder. Used to reconcile after a purge.
    private func orphanedIdentifiers(comparedTo previous: [NoteModel]) -> [String] {
        let liveIdentifiers = Set(notes.flatMap { $0.notificationIdentifiers ?? [] })
        return previous
            .flatMap { $0.notificationIdentifiers ?? [] }
            .filter { !liveIdentifiers.contains($0) }
    }

    private func scheduleSave() {
        // Cancel previous save task if still running
        saveTask?.cancel()
        hasPendingSave = true

        // Marks everything already in flight as superseded — see `saveRevision`.
        saveRevision &+= 1

        // Schedule new save task with debouncing
        saveTask = Task {
            // Small delay to debounce rapid changes
            try? await Task.sleep(for: .milliseconds(100))

            guard !Task.isCancelled else { return }
            _ = await save()
        }
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()

        // Expired trash is dropped at launch; persist only if something changed.
        let before = notes
        if purgeExpiredTrash() {
            let orphans = orphanedIdentifiers(comparedTo: before)
            scheduleSave()
            Task { await NotificationManager.instance.removeNotifications(identifiers: orphans) }
        } else {
            // Keep the widget in sync even when nothing was written this launch,
            // otherwise a fresh install shows an empty widget until the first edit.
            syncWidgetData()
        }
    }

    /// Saves immediately, cancelling any pending debounced save.
    /// Use when the caller needs a guarantee that data hit the disk (e.g. App Intents).
    @discardableResult
    func saveNow() async -> Bool {
        saveTask?.cancel()
        return await save()
    }

    /// Writes a debounced save out now instead of waiting for its delay to
    /// elapse. Call it when the scene leaves the foreground: `scheduleSave`
    /// sleeps before it writes and iOS suspends the process without waiting, so
    /// the last pin, checkbox or delete would simply never reach the disk.
    /// A no-op when nothing is pending.
    func flushPendingSave() async {
        guard hasPendingSave else { return }
        Log.store.info("Flushing a pending save before leaving the foreground")
        await saveNow()
    }

    func setError(_ message: String) {
        report(message)
    }

    /// Clears the current error. Views must call this when the user dismisses
    /// the alert — otherwise `saveError` keeps its old value and an identical
    /// second failure would not register as a change, so no alert would appear.
    func clearError() {
        report(nil)
    }

    func add(
        title: String,
        content: String,
        type: NoteType? = nil,
        drawingData: Data? = nil,
        drawingCanvasSize: CGSize? = nil,
        backgroundImageData: Data? = nil,
        color: Color? = nil,
        isColorOn: Bool? = nil,
        reminder: Date? = nil,
        isReminderOn: Bool? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil,
        tags: [String]? = nil,
        isProtected: Bool? = nil
    ) {
        notes.append(
            NoteModel(
                title: title,
                content: content,
                type: type ?? .text,
                drawingData: drawingData,
                drawingCanvasSize: drawingCanvasSize,
                backgroundImageData: backgroundImageData,
                color: isColorOn == false ? nil : color,
                reminder: isReminderOn == false ? nil : reminder,
                notificationIdentifiers: notificationIdentifiers?.isEmpty == true
                    ? nil
                    : notificationIdentifiers,
                location: location,
                tags: tags,
                isProtected: isProtected
            )
        )
        scheduleSave()
    }

    func update(
        note: NoteModel,
        title: String? = nil,
        content: String? = nil,
        type: NoteType? = nil,
        drawingData: Data?? = nil,
        drawingCanvasSize: CGSize?? = nil,
        backgroundImageData: Data?? = nil,
        pinned: Bool? = nil,
        color: Color? = nil,
        isColorOn: Bool? = nil,
        reminder: Date? = nil,
        isReminderOn: Bool? = nil,
        notificationIdentifiers: [String]? = nil,
        location: [Double]? = nil,
        tags: [String]? = nil,
        isProtected: Bool? = nil
    ) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }

        // Copy-and-tweak: every field the caller did not name keeps its stored
        // value, so a partial update cannot drop state such as `isDeleted`.
        var updated = notes[index]

        if let title { updated.title = title }
        if let content { updated.content = content }
        if let type { updated.type = type }
        if let drawingData { updated.drawingData = drawingData }
        if let drawingCanvasSize { updated.drawingCanvasSize = drawingCanvasSize }
        if let backgroundImageData { updated.backgroundImageData = backgroundImageData }
        if let pinned { updated.pinned = pinned }
        if let location { updated.location = location }
        if let tags { updated.tags = tags }
        if let isProtected { updated.isProtected = isProtected }

        // Switching the toggle off clears the value; otherwise a passed value
        // wins and omitting it keeps what is already there.
        if isColorOn == false {
            updated.color = nil
        } else if let color {
            updated.color = color
        }

        if isReminderOn == false {
            updated.reminder = nil
        } else if let reminder {
            updated.reminder = reminder
        }

        // Not passing the parameter keeps the existing identifiers; passing an
        // empty array clears them. Without that distinction a partial update
        // (e.g. toggling `pinned`) would orphan the note's scheduled
        // notifications.
        if let notificationIdentifiers {
            updated.notificationIdentifiers =
                notificationIdentifiers.isEmpty ? nil : notificationIdentifiers
        }

        notes[index] = updated
        scheduleSave()
    }

    /// Stores `note` verbatim, replacing every field of the stored copy.
    ///
    /// Deliberately not another `update` overload. It used to be one, which meant
    /// `update(note: x)` and `update(note: x, title: y)` — the same call spelled
    /// with one argument fewer — had opposite semantics: a wholesale replace
    /// against a patch that leaves unnamed fields alone. Overload resolution
    /// picked the replace silently, so a caller who meant to patch would have
    /// written back whatever their copy of the note happened to hold.
    ///
    /// Use it only with a note derived from the current stored one by
    /// copy-and-tweak (`var updated = note`); use `update(note:…)` to change
    /// named fields.
    func replace(note: NoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            scheduleSave()
        }
    }

    // Soft delete - move to trash
    func moveToTrash(note: NoteModel) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }

        // Cancelled here rather than by each caller. `restoreFromTrash` re-arms
        // the reminder inside the store, so the other half of the same rule
        // belongs here too — it used to be spelled out in every view that
        // deletes a note, and a caller that forgot would leave a note firing a
        // reminder from inside the trash.
        let identifiers = notes[index].notificationIdentifiers

        notes[index].isDeleted = true
        notes[index].deletedAt = Date()
        // Dropped along with the notifications they name: nothing may point at a
        // request that no longer exists. `restoreFromTrash` mints fresh ones.
        notes[index].notificationIdentifiers = nil
        scheduleSave()

        Task {
            await NotificationManager.instance.removeNotifications(identifiers: identifiers)
        }
    }

    // Restore from trash
    func restoreFromTrash(note: NoteModel) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }

        notes[index].isDeleted = false
        notes[index].deletedAt = nil
        scheduleSave()

        // The note's notifications were cancelled on the way into the trash, so
        // a reminder still in the future has to be armed again. The identifier
        // that produces is persisted here: `rescheduleReminder` no longer saves,
        // and the debounced save above may well have fired while it awaited.
        let id = note.id
        Task {
            if await rescheduleReminder(for: id) { scheduleSave() }
        }
    }

    /// Drops a note for good.
    ///
    /// Cancels its notifications here rather than leaving that to each caller, the
    /// same arrangement — and for the same reason — as `moveToTrash`. Both call
    /// sites did spell it out, so nothing was firing for a note that no longer
    /// existed; what the asymmetry cost was that the rule had to be remembered. A
    /// note normally reaches this having been through the trash, where its
    /// identifiers were already dropped, but one restored from a backup can still
    /// carry them — so the caller that forgot would leave exactly the orphan
    /// `emptyTrash` and `purgeExpiredTrash` reconcile against.
    func remove(note: NoteModel) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }

        let identifiers = notes[index].notificationIdentifiers

        notes.remove(at: index)
        scheduleSave()

        Task {
            await NotificationManager.instance.removeNotifications(identifiers: identifiers)
        }
    }

    /// Drops everything in the trash for good.
    ///
    /// The same thing `purgeExpiredTrash` does when the retention period runs out,
    /// asked for rather than waited for — so it reconciles notifications the same
    /// way. A note's reminder is cancelled on the way *into* the trash, so there is
    /// usually nothing left to remove; a note restored and re-trashed by an older
    /// build, or one that arrived already deleted from a backup, can still carry
    /// identifiers, and an orphaned one would go on firing for a note that no
    /// longer exists anywhere.
    ///
    /// - Returns: `true` when anything was dropped.
    @discardableResult
    func emptyTrash() -> Bool {
        let before = notes
        let remaining = notes.filter { !$0.isDeleted }

        guard remaining.count != notes.count else { return false }

        notes = remaining
        Log.store.info("Emptied the trash, dropping \(before.count - remaining.count) note(s)")

        let orphans = orphanedIdentifiers(comparedTo: before)
        scheduleSave()
        Task { await NotificationManager.instance.removeNotifications(identifiers: orphans) }

        return true
    }

    /// Encodes a backup, off the main actor.
    ///
    /// Pretty-printed and larger than the store's own file, so the encode is the
    /// heaviest one in the app — and the user is watching a menu when it runs. See
    /// `NotesFileCoder`.
    func exportNotes() async -> Data? {
        let snapshot = notes

        do {
            let data = try await coder.encodeBackup(snapshot)
            Log.store.info("Exported \(snapshot.count) notes")
            return data
        } catch {
            Log.store.error("Failed to export notes: \(error.localizedDescription)")
            report(String(localized: "errorExportFailed \(error.localizedDescription)"))
            return nil
        }
    }

    /// The bytes of a backup file the user picked, or `nil` when they cannot be
    /// read.
    ///
    /// Lives here rather than in the view for two reasons. The read runs off the
    /// main actor — a backup with drawings in it is megabytes, and this is the one
    /// read the user waits on — so the file's security scope has to be held across
    /// a suspension, which a `defer` in a synchronous `fileImporter` callback
    /// cannot do: it would release the scope while the read was still in flight.
    /// And the failure has a message to set, which is the store's to own.
    func readBackup(at url: URL) async -> Data? {
        guard url.startAccessingSecurityScopedResource() else {
            Log.files.error("Failed to access security-scoped resource")
            report(String(localized: "errorFileAccess"))
            return nil
        }

        defer { url.stopAccessingSecurityScopedResource() }

        do {
            return try await coder.read(url)
        } catch {
            Log.files.error("Failed to read file: \(error.localizedDescription)")
            report(String(localized: "errorFileRead \(error.localizedDescription)"))
            return nil
        }
    }

    // Import notes from JSON data
    func importNotes(from data: Data, replaceExisting: Bool = false) async -> Bool {
        // Nothing that follows can reach the disk while the stored notes are out
        // of reach, and `refresh()` folds the in-memory notes back into whatever
        // it later manages to load — so a "replace" would quietly come back as a
        // merge. Better to say so than to report a success that did not happen.
        //
        // This is the locked-device case only, and it clears itself the moment the
        // device is unlocked. A file that will never decode is set aside at load
        // instead of blocking, precisely so a restore is still possible — see
        // `LoadFailure`.
        guard isStorageLoaded else {
            Log.store.error("Refusing to import: notes were never loaded")
            report(String(localized: "errorSaveBlocked"))
            return false
        }

        // Decoded off the main actor: a backup is pretty-printed and carries every
        // drawing and background photo base64'd, so this is the heaviest decode in
        // the app. Nothing here touches the store, and `isStorageLoaded` cannot go
        // back to `false` once it is `true`, so the guard above still holds.
        let importedNotes: [NoteModel]

        do {
            importedNotes = try await coder.decode(data)
        } catch {
            Log.store.error("Failed to import notes: \(error.localizedDescription)")
            report(String(localized: "errorImportFailed \(error.localizedDescription)"))
            return false
        }

        let previous = notes
        let restored: [UUID]

        if replaceExisting {
            // Deduplicated by id rather than stored verbatim. The file is whatever
            // the user handed over — hand-edited, or two backups concatenated — so
            // it can carry the same note twice, and `notes` is what every `ForEach`
            // and every `firstIndex(where: { $0.id == … })` in the app indexes by.
            // Two rows sharing one id leaves SwiftUI's list ill-defined and makes
            // the second copy impossible to edit or delete, since the lookup can
            // only ever reach the first. The merge path below never had the
            // problem: it checks each note against what it has already appended.
            var unique: [NoteModel] = []
            var seen = Set<UUID>()

            for note in importedNotes where seen.insert(note.id).inserted {
                unique.append(note)
            }

            if unique.count != importedNotes.count {
                Log.store.notice("Dropped \(importedNotes.count - unique.count) note(s) from the backup that repeated an id already in it")
            }

            notes = unique
            restored = unique.map(\.id)
            Log.store.info("Replaced all notes with \(unique.count) imported notes")

            // The replaced notes' reminders would otherwise keep firing.
            let orphans = orphanedIdentifiers(comparedTo: previous)
            Task { await NotificationManager.instance.removeNotifications(identifiers: orphans) }
        } else {
            // Merge - add only notes with IDs that don't exist.
            //
            // Indexed by a `Set` rather than rescanning `notes` for each imported
            // note, which was quadratic — and a restore is the one moment both
            // lists are as large as the library ever gets. The replace branch
            // above already deduplicates this way; this is the same rule, and it
            // keeps the property that branch's comment describes: inserting as we
            // go means a backup carrying the same new id twice still lands once,
            // because the second copy meets the first in `known`.
            var known = Set(notes.map(\.id))
            var added: [UUID] = []

            for importedNote in importedNotes where known.insert(importedNote.id).inserted {
                notes.append(importedNote)
                added.append(importedNote.id)
            }

            restored = added
            Log.store.info("Imported \(added.count) new notes, skipped \(importedNotes.count - added.count) duplicates")
        }

        scheduleSave()

        // Imported identifiers were minted on the device that made the backup, so
        // the reminders have to be scheduled again here.
        Task { await rescheduleReminders(for: restored) }

        return true
    }

    // Computed properties for filtered notes
    var activeNotes: [NoteModel] {
        notes.filter { !$0.isDeleted }
    }

    var deletedNotes: [NoteModel] {
        notes.filter { $0.isDeleted }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// Whether anything is in the trash.
    ///
    /// Exists because that is all the list's toolbar needs in order to decide
    /// whether to offer the "Deleted" button, and it asks on every pass through
    /// `body` — where `deletedNotes` allocated a filtered array and sorted it by
    /// deletion date to answer a question that stops at the first match.
    var hasDeletedNotes: Bool {
        notes.contains { $0.isDeleted }
    }

    /// Every tag in use, one entry per tag, sorted.
    ///
    /// Deduplicated through `NoteModel.tagKey` rather than by exact text, so two
    /// notes tagged "Práce" and "práce" produce one chip instead of two — one of
    /// which would then filter the other's notes out. `uniqueTags` applies the
    /// same rule one level down, within a single note.
    ///
    /// Sorted *before* the duplicates are dropped rather than after, so which of
    /// two spellings survives is decided by the ordering and not by whichever note
    /// happens to come first in the file: the chip row must not rename itself when
    /// an unrelated note is added.
    ///
    /// Ordered the way the reader's language orders words rather than by Unicode
    /// scalar, which is what a bare `sorted()` gave. That put every capitalised tag
    /// ahead of every lowercase one and dropped the whole Czech alphabet past "z":
    /// "Byt", "Zebra", "auto", "dům", "čas", "řeka", "škola", where the row should
    /// read "auto", "Byt", "čas", "dům", "řeka", "škola", "Zebra". The list's own
    /// title sort has gone through `localizedCaseInsensitiveCompare` all along, so
    /// this was the one place left in the app that ordered user text by code point.
    ///
    /// Deliberately locale-aware where `NoteModel.tagKey` deliberately is not. That
    /// rule decides which tags are the *same* tag, and so what a backup round-trips
    /// to; this only decides the order they are drawn in. Nothing here is stored,
    /// and the ordering is still fixed for a given language — which is all the
    /// paragraph above asks of it. `localizedStandardCompare` separates two
    /// spellings that differ only in case as a tertiary difference ("práce" before
    /// "Práce"), so a total order survives and the surviving spelling stays
    /// decidable rather than resting on a sort that is not stable.
    var allTags: [String] {
        var seen = Set<String>()

        return activeNotes
            .flatMap { $0.tags }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .filter { seen.insert(NoteModel.tagKey($0)).inserted }
    }
}
