//
//  CircularIconButton.swift
//  SousAI
//
//  The translucent circular chip that floats over photographic surfaces.
//
//  Implements the DESIGN.md `button-icon-circular` spec:
//    • 44×44 — also the iOS minimum touch target
//    • Background: surface-chip-translucent (#d2d2d7) at ~64% alpha — applied
//      via .ultraThinMaterial on dark surfaces so it reads as glass, not paint
//    • Icon: bodyOnDark, system symbol, weight regular
//    • Press: shared AppPressStyle (scale 0.95 + 0.92 opacity)
//
//  Used exclusively for navigation chrome that floats over photography
//  (close X on CameraView and PhotoConfirmationView, optional PhotosPicker
//  entry on CameraView). Never sits on a plain canvas — the glass material
//  needs something photographic behind it to read correctly.
//

import SwiftUI
import UIKit

struct CircularIconButton: View {

    private let systemName: String
    private let accessibilityLabel: String
    private let action: () -> Void

    init(systemName: String,
         accessibilityLabel: String,
         action: @escaping () -> Void) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: handleTap) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AppColor.bodyOnDark)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(AppColor.surfaceBlack.opacity(0.18))
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func handleTap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        action()
    }
}

// MARK: - Previews

#Preview("CircularIconButton — dark") {
    ZStack {
        AppColor.surfaceBlack.ignoresSafeArea()
        HStack(spacing: AppSpacing.lg) {
            CircularIconButton(systemName: "xmark",
                               accessibilityLabel: "Close") { }
            CircularIconButton(systemName: "photo.on.rectangle",
                               accessibilityLabel: "Choose from library") { }
        }
    }
    .preferredColorScheme(.dark)
}
