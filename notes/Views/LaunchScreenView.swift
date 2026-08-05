//
//  LaunchScreenView.swift
//  notes
//
//  Created by Robert Libšanský on 15.07.2022.
//

import SwiftUI

struct AnimatedBackgroundView: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [.accentColor, .yellow],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
            ) {
                animateGradient.toggle()
            }
        }
    }
}

struct LaunchScreenView: View {
    @Environment(NotificationRouter.self) private var notificationRouter

    @State private var isActive = false
    @State private var scaleEffect = 0.5
    @State private var opacity = 0.5

    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                AnimatedBackgroundView()

                Text("notes")
                    .font(.title)
                    .scaleEffect(scaleEffect)
                    .opacity(opacity)
            }
            .onAppear {
                // A launch that already has somewhere to go skips the splash
                // entirely. The user tapped a reminder, or the note they could see
                // on the home screen — they asked for that note, not for an intro
                // animation, and six tenths of a second is exactly long enough to
                // notice. This is the one case where the splash costs something,
                // and it is also the case it used to be paid in.
                guard !notificationRouter.hasPendingDestination else {
                    isActive = true
                    return
                }

                withAnimation(
                    .spring(response: 1, dampingFraction: 0.5)
                ) {
                    scaleEffect = 1.4
                    opacity = 1
                }

                Task {
                    // Just long enough for the intro animation to land — the
                    // splash should not hold the app back on every launch.
                    try? await Task.sleep(for: .seconds(0.6))
                    withAnimation {
                        isActive = true
                    }
                }
            }
            // A cold launch delivers the tap or the link once the scene is up,
            // which can be after `onAppear` has already started the wait above.
            // Both orderings have to get out of the way.
            .onChange(of: notificationRouter.hasPendingDestination) { _, hasDestination in
                if hasDestination { isActive = true }
            }
        }
    }
}

#Preview {
    LaunchScreenView()
        .environment(LocationManager())
        .environment(NotesStore())
        .environment(NotificationRouter.shared)
}
