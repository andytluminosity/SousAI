//
//  SecondaryGhostButton.swift
//  SousAI
//
//  The secondary action used alongside `PrimaryPillButton` on dark surfaces.
//
//  Adapts DESIGN.md `button-secondary-pill` for the dark canvas:
//    • Background: transparent (no fill, no border) — true ghost capsule
//    • Label:      AppColor.primaryOnDark (#2997ff — "Sky Link Blue")
//                  DESIGN.md mandates this brighter blue on dark surfaces
//                  because Action Blue (#0066cc) disappears against tile-1.
//    • Typography: buttonLarge (18pt / 300) — matches PrimaryPillButton so
//                  the two CTAs read as a balanced pair.
//    • Shape:      Capsule (rounded.pill grammar)
//    • Padding:    14pt × 28pt — identical to PrimaryPillButton
//    • Press:      shared AppPressStyle (scale 0.95 + 0.92 opacity)
//
//  Light haptic on tap — softer than the primary's medium impact, so the
//  secondary feels less committal.
//

import SwiftUI
import UIKit

struct SecondaryGhostButton: View {

    private let title: String
    private let icon: String?
    private let action: () -> Void

    init(_ title: String,
         icon: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: AppSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .regular))
                }
                Text(title)
                    .font(AppTypography.buttonLarge)
            }
            .foregroundColor(AppColor.primaryOnDark)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(minHeight: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(Text(title))
    }

    private func handleTap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        action()
    }
}

// MARK: - Previews

#Preview("SecondaryGhostButton — dark") {
    ZStack {
        AppColor.surfaceBlack.ignoresSafeArea()
        SecondaryGhostButton("Retake", icon: "arrow.counterclockwise") { }
    }
    .preferredColorScheme(.dark)
}
