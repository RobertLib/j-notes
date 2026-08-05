//
//  PrivacyCover.swift
//  notes
//

import SwiftUI

/// What covers a protected note while the scene is not active.
///
/// Opaque rather than blurred: a blur still leaks the shape of the text.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)

            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}

/// Hides a protected note's text before iOS takes its app-switcher snapshot.
///
/// Shared by the detail view and the form. It used to live only in the detail
/// view, so a locked note being *edited* went into the snapshot in full — the
/// one screen that shows its body in an editable text view.
private struct PrivacyCoverModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    /// Whether this note is protected at all. An unprotected note is never
    /// covered, so the handler stays out of the way entirely.
    let isProtected: Bool

    /// Whether the text is on screen right now and therefore worth hiding.
    /// The detail view passes its unlocked state; the form passes `true`, since
    /// reaching it at all means the note was already unlocked.
    let isRevealed: Bool

    @State private var isObscured = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isObscured {
                    PrivacyCover()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard isProtected else {
                    isObscured = false
                    return
                }

                switch newPhase {
                case .active:
                    isObscured = false
                case .background:
                    isObscured = true
                default:
                    // iOS grabs the app-switcher snapshot while the scene is
                    // `.inactive`, which arrives before `.background` — covering
                    // the note only on `.background` let an unlocked one show up
                    // in the switcher. Keyed on `isRevealed` because the Face ID
                    // prompt deactivates the scene too, and covering a note that
                    // is still locked would flash over the unlock button.
                    isObscured = isRevealed
                }
            }
    }
}

extension View {
    /// Covers this view while the scene is not active, so a protected note's text
    /// does not reach the app-switcher snapshot.
    func privacyCover(isProtected: Bool, isRevealed: Bool = true) -> some View {
        modifier(
            PrivacyCoverModifier(isProtected: isProtected, isRevealed: isRevealed)
        )
    }
}
