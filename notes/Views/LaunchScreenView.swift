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
                withAnimation(
                    .spring(response: 1, dampingFraction: 0.5)
                ) {
                    scaleEffect = 1.4
                    opacity = 1
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
    }
}

struct LaunchScreenView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreenView()
            .environmentObject(LocationManager())
            .environmentObject(NotesStore())
    }
}
