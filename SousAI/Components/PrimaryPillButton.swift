//
//  PrimaryPillButton.swift
//  SousAI
//
//  The single primary action component for SousAI.
//
//  Implements the DESIGN.md `button-store-hero` spec:
//    • Background: AppColor.primary (Action Blue, #0066cc)
//    • Label:      AppColor.bodyOnDark in `buttonLarge` (18pt / weight 300)
//    • Shape:      Capsule (rounded.pill — the brand action signal)
//    • Padding:    14pt × 28pt
//    • Pressed:    transform: scale(0.95) — the system-wide micro-interaction
//
//  Haptic feedback is fired on tap to honor the brief's "tactile and native"
//  interaction requirement.
//

import SwiftUI
import UIKit

struct PrimaryPillButton: View {

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
                        .font(.system(size: 17, weight: .regular))
                }
                Text(title)
                    .font(AppTypography.buttonLarge)
            }
            .foregroundColor(AppColor.bodyOnDark)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(minHeight: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColor.primary)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(Text(title))
    }

    private func handleTap() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        action()
    }
}

// MARK: - Previews

#Preview("Primary Pill — dark") {
    ZStack {
        AppColor.surfaceTile1.ignoresSafeArea()
        PrimaryPillButton("Scan Your Fridge", icon: "viewfinder") { }
    }
    .preferredColorScheme(.dark)
}

#Preview("Primary Pill — light") {
    ZStack {
        AppColor.canvasParchment.ignoresSafeArea()
        PrimaryPillButton("Get Started") { }
    }
}
