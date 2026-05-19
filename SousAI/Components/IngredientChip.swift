//
//  IngredientChip.swift
//  SousAI
//
//  The configurator-option-chip in dark mode.
//
//  DESIGN.md spec (configurator-option-chip):
//    • backgroundColor: canvas (white)
//    • textColor:       ink (#1d1d1f)
//    • typography:      caption (14pt) — promoted here to body (17pt) because
//                       ingredient names ARE the primary content of this
//                       screen, and DESIGN.md's body (17pt / 400 / -0.374
//                       tracking) is the brand's defining reading size.
//                       Padding compensates so the chip remains compact.
//    • rounded:         pill
//    • padding:         12 × 16  (DESIGN.md token)
//
//  Selected state (configurator-option-chip-selected):
//    • 2pt border in `primary-focus` (#0071e3) — the literal DESIGN.md
//      selected-ring, rendered here as a `Capsule().strokeBorder(...)`.
//
//  Dark-canvas semantics:
//    • The chip itself stays light — a white pill on the dark surfaceTile1
//      canvas reads as a tactile object lifting off the page. This mirrors
//      the iPhone 17 Pro configurator chip on parchment.
//    • Excluded chips collapse to a transparent ghost with a thin hairline
//      border, muted text, and a quiet strikethrough — visible enough to
//      tap-restore, faint enough to read as "off."
//
//  Motion:
//    • Toggle: `.spring(response: 0.42, dampingFraction: 0.82)` — short,
//      crisp, never bouncy.
//    • Press:  shared `AppPressStyle` (scale 0.95 + 0.92 opacity).
//    • Long-press: success-style notification haptic, then `onRemove` so the
//      parent can animate the full removal.
//

import SwiftUI
import UIKit

struct IngredientChip: View {

    // MARK: - Inputs

    let name: String
    let isSelected: Bool
    var onToggle: () -> Void
    var onRemove: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: handleTap) {
            Text(name)
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(labelColor)
                .strikethrough(!isSelected, color: AppColor.bodyMuted.opacity(0.7))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(fillColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: strokeWidth)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(AppPressStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in handleLongPress() }
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.82),
                   value: isSelected)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(isSelected ? "Included" : "Excluded"))
        .accessibilityHint(Text("Double tap to toggle. Long press to remove."))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Styling tokens (state-driven)

    private var fillColor: Color {
        isSelected ? AppColor.bodyOnDark : Color.clear
    }

    private var labelColor: Color {
        isSelected ? AppColor.ink : AppColor.bodyMuted.opacity(0.6)
    }

    private var strokeColor: Color {
        isSelected
            ? AppColor.primaryFocus
            : AppColor.bodyMuted.opacity(0.35)
    }

    private var strokeWidth: CGFloat {
        isSelected ? 2 : 1
    }

    // MARK: - Interaction handlers

    private func handleTap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        onToggle()
    }

    private func handleLongPress() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        onRemove()
    }
}

// MARK: - Previews

#Preview("IngredientChip — states") {
    ZStack {
        AppColor.surfaceTile1.ignoresSafeArea()

        VStack(spacing: AppSpacing.lg) {
            IngredientChip(name: "Cherry Tomato",
                           isSelected: true,
                           onToggle: {},
                           onRemove: {})

            IngredientChip(name: "Greek Yogurt",
                           isSelected: false,
                           onToggle: {},
                           onRemove: {})

            // A long name to verify wrap behavior in the flow layout.
            IngredientChip(name: "Aged Sharp Cheddar",
                           isSelected: true,
                           onToggle: {},
                           onRemove: {})
        }
        .padding(AppSpacing.lg)
    }
    .preferredColorScheme(.dark)
}
