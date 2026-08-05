//
//  NoteLockTests.swift
//  notesTests
//

import XCTest
@testable import J_Notes

/// The rule deciding whether a protected note is shown behind its lock.
///
/// Regression cover for a one-way door. `evaluatePolicy` fails with
/// `.passcodeNotSet` on a device with no passcode — for biometry *and* for the
/// passcode fallback — so a note marked protected could not be opened, and
/// therefore could not be edited or un-protected either, since both live in the
/// toolbar behind the lock. The only thing left to do with it was delete it from
/// the list unread.
final class NoteLockTests: XCTestCase {

    // MARK: - The ordinary case

    func testAnUnprotectedNoteIsNeverLocked() {
        XCTAssertFalse(
            NoteLock.requiresAuthentication(isProtected: false, canAuthenticate: true)
        )
    }

    func testAProtectedNoteIsLockedWhereTheDeviceCanAuthenticate() {
        XCTAssertTrue(
            NoteLock.requiresAuthentication(isProtected: true, canAuthenticate: true)
        )
    }

    // MARK: - The device that can authenticate nobody

    /// The fix: no passcode, no biometry, so nothing could ever satisfy the
    /// prompt. Locking here only ever locked the owner out.
    func testAProtectedNoteOpensWhereTheDeviceCannotAuthenticate() {
        XCTAssertFalse(
            NoteLock.requiresAuthentication(isProtected: true, canAuthenticate: false)
        )
    }

    /// And an unprotected note is unaffected either way — the rule must not start
    /// gating notes that were never marked protected in the first place.
    func testAnUnprotectedNoteOpensWhereTheDeviceCannotAuthenticate() {
        XCTAssertFalse(
            NoteLock.requiresAuthentication(isProtected: false, canAuthenticate: false)
        )
    }

    // MARK: - The whole table

    /// Written out in full because this is the rule `NoteDetailView` reads in
    /// four places — the initial `isAuthenticated`, the branch between the locked
    /// screen and the note, the re-lock on `.background` and the re-lock when the
    /// note is protected from the edit form. Exactly one of the four combinations
    /// hides the text, and it is the only one where hiding it is reversible.
    func testOnlyAProtectedNoteOnAnAuthenticatingDeviceIsLocked() {
        let table: [(isProtected: Bool, canAuthenticate: Bool, isLocked: Bool)] = [
            (true, true, true),
            (true, false, false),
            (false, true, false),
            (false, false, false)
        ]

        for row in table {
            XCTAssertEqual(
                NoteLock.requiresAuthentication(
                    isProtected: row.isProtected,
                    canAuthenticate: row.canAuthenticate
                ),
                row.isLocked,
                "protected: \(row.isProtected), canAuthenticate: \(row.canAuthenticate)"
            )
        }
    }

    /// The device query itself has no business trapping or throwing, whatever the
    /// process it is asked in — a test process has neither biometry nor a
    /// passcode, which is precisely the configuration that used to strand a note.
    func testTheDeviceQueryAnswersWithoutTrapping() {
        _ = NoteLock.deviceCanAuthenticate()
    }
}
