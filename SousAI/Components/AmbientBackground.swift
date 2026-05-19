//
//  AmbientBackground.swift
//  SousAI
//
//  The hero's ambient backdrop.
//
//  Design intent:
//    • Honor DESIGN.md's "no decorative gradient" rule — these are not
//      decorative gradients painted across the canvas. They are *photographic
//      lighting cues* (a warm fill light, a cool rim light) that mimic the
//      studio lighting beneath a product photograph.
//    • Opacity stays in the 0.04–0.13 range. The orbs should be felt, not seen.
//    • Motion is a very slow breath (8s autoreverse) — calm, never playful.
//    • The canvas itself is AppColor.surfaceTile1 (#272729) — the primary
//      dark-tile token used on the homepage product grid.
//

import SwiftUI

struct AmbientBackground: View {

    @State private var breathing = false

    var body: some View {
        ZStack {

            // The dark canvas — #272729 from the design system.
            AppColor.surfaceTile1
                .ignoresSafeArea()

            // Warm fill light — upper-left. Reads as a soft kitchen-warm
            // highlight without ever crossing into "orange gradient".
            Circle()
                .fill(Color(red: 1.00, green: 0.78, blue: 0.55))
                .frame(width: 560, height: 560)
                .blur(radius: 140)
                .opacity(breathing ? 0.13 : 0.085)
                .offset(x: -170, y: -280)
                .blendMode(.screen)

            // Cool rim light — lower-right. Echoes a soft studio bounce.
            Circle()
                .fill(Color(red: 0.55, green: 0.72, blue: 1.00))
                .frame(width: 440, height: 440)
                .blur(radius: 130)
                .opacity(breathing ? 0.08 : 0.045)
                .offset(x: 190, y: 340)
                .blendMode(.screen)

            // Single quiet specular — anchors the eye toward the headline.
            Circle()
                .fill(Color.white)
                .frame(width: 220, height: 220)
                .blur(radius: 110)
                .opacity(breathing ? 0.045 : 0.025)
                .offset(x: 40, y: -80)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
        .onAppear { startBreathing() }
    }

    private func startBreathing() {
        // 8-second cycle — slow enough to feel ambient, never animated.
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

#Preview {
    AmbientBackground()
}
