//
//  PressStyle.swift
//  SousAI
//
//  The system-wide press signal for every interactive surface in SousAI.
//
//  DESIGN.md mandates `transform: scale(0.95)` as the universal pressed-state
//  micro-interaction — applied identically to the primary pill, the secondary
//  ghost pill, and the circular icon chip. Centralizing it here guarantees
//  every button feels exactly the same under the finger.
//
//  Timing is a short, crisp spring (response 0.28, damping 0.7) — long enough
//  to register, short enough to never feel playful or bouncy.
//

import SwiftUI

/// The single press style used by every tactile control in the app.
///
/// Combines DESIGN.md's `scale(0.95)` press transform with a subtle opacity
/// dip so the button reads as "engaged" on both bright and translucent
/// surfaces.
struct AppPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
