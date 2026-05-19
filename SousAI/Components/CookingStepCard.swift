//
//  CookingStepCard.swift
//  SousAI
//
//  A single step row inside CookingModeView's vertical step list.
//
//  Two render states, driven entirely by the parent's `selectedStepIndex`:
//
//    • Collapsed (inactive)
//        A compact tile with a "STEP N" eyebrow above the step text.
//        Body copy at 17pt — readable but quiet so the active step
//        reads as the focal point of the page.
//
//    • Expanded (active)
//        Same eyebrow, same tile, but the step text upgrades to
//        `displayMedium` (28pt semibold) so the eye locks onto it. A
//        thin hairline separates the step text from the contextual
//        input row beneath — a single-line TextField on a `surfaceTile3`
//        capsule with a trailing send button.
//
//  Surface grammar (per DESIGN.md):
//    • Container: `surfaceTile2` (#2a2a2c), `AppRadius.lg` (18pt),
//      `bodyOnDark.opacity(0.06)` hairline — identical to `RecipeCard`
//      so the two card surfaces feel like the same family of object.
//    • Inner input chip: `surfaceTile3` (#252527) — DESIGN.md's
//      micro-step darker tone, used for the page → card → inner-chip
//      ladder.
//
//  Future AI seam:
//    • The send button does not call any backend. It commits the typed
//      string into `CookingStepInteraction.userIssue` via the
//      `onCommit` binding, where the future AI hook will pick it up
//      and write its response into `assistantResponse`. That field
//      already exists on the interaction value type (see
//      `CookingModeView.swift`); when wired, this card will render the
//      response beneath the input row with the same fade+slide-up
//      transition the input itself uses today.
//
//  Animation:
//    • Expand/collapse: `.spring(response: 0.42, dampingFraction: 0.82)`
//      — the same spring `RecipeCardsView` uses for its page indicator,
//      keeping the in-app motion vocabulary consistent.
//    • Input row reveal: gentle `.opacity` + `.move(edge: .top)`
//      transition driven by an `easeOut(0.28)` `withAnimation` in the
//      parent on `selectedStepIndex` change.
//

import SwiftUI
import UIKit

struct CookingStepCard: View {

    // MARK: - Inputs

    let stepIndex: Int
    let stepText: String
    let isActive: Bool
    /// Two-way binding into the parent's per-step `userIssue` slot.
    /// The card never owns the issue string — it only edits the
    /// parent's `CookingStepInteraction.userIssue`.
    @Binding var userIssue: String
    /// Fired when the user taps the step (collapsed or expanded). The
    /// parent toggles `selectedStepIndex` from this — the card itself
    /// has no opinion on selection state.
    var onTap: () -> Void = {}
    /// Fired when the user presses return on the input or taps the
    /// send button. The future AI hook lands here; today it just
    /// resigns focus.
    var onSubmitIssue: () -> Void = {}

    // MARK: - Local state

    @FocusState private var inputIsFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tapTarget

            if isActive {
                divider
                    .padding(.horizontal, AppSpacing.lg)

                inputRow
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.lg)
                    .transition(
                        .opacity
                            .combined(with: .move(edge: .top))
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColor.surfaceTile2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppColor.bodyOnDark.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(stepIndex + 1). \(stepText)"))
        .accessibilityHint(Text(isActive
                                ? "Active step. Describe an issue, or tap another step to switch."
                                : "Double tap to focus this step."))
        .onChange(of: isActive) { _, nowActive in
            if !nowActive { inputIsFocused = false }
        }
    }

    // MARK: - Tap target (the always-visible step body)

    private var tapTarget: some View {
        Button(action: handleTap) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("STEP \(stepIndex + 1)")
                    .font(AppTypography.brandEyebrow)
                    .tracking(AppTypography.brandEyebrowTracking)
                    .foregroundColor(AppColor.bodyMuted.opacity(0.55))

                Text(stepText)
                    .font(isActive
                          ? AppTypography.displayMedium
                          : AppTypography.body)
                    .tracking(isActive
                              ? AppTypography.displayMediumTracking
                              : AppTypography.bodyTracking)
                    .foregroundColor(AppColor.bodyOnDark)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle())
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(AppColor.bodyOnDark.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: AppSpacing.sm) {
            TextField("", text: $userIssue, prompt: Text("Tell me what went wrong…")
                .foregroundColor(AppColor.bodyMuted.opacity(0.55)))
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.bodyOnDark)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .focused($inputIsFocused)
                .onSubmit(handleSubmit)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColor.surfaceTile3)
                )
                .accessibilityLabel(Text("Describe an issue with step \(stepIndex + 1)"))

            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: handleSubmit) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(isSubmittable
                                 ? AppColor.primaryOnDark
                                 : AppColor.bodyMuted.opacity(0.35))
        }
        .buttonStyle(AppPressStyle())
        .disabled(!isSubmittable)
        .accessibilityLabel(Text("Send"))
    }

    // MARK: - Helpers

    private var isSubmittable: Bool {
        !userIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleTap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        onTap()
    }

    private func handleSubmit() {
        guard isSubmittable else { return }
        // The future AI hook lands here. Today: resign focus so the
        // keyboard tucks away cleanly, and notify the parent that the
        // user committed their issue (parent can persist, log, etc.).
        inputIsFocused = false
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        onSubmitIssue()
    }
}

// MARK: - Previews

#Preview("CookingStepCard — collapsed") {
    StatefulPreview(initial: "") { binding in
        ZStack {
            AppColor.surfaceTile1.ignoresSafeArea()
            CookingStepCard(
                stepIndex: 0,
                stepText: "Heat a knob of butter in a non-stick pan over medium heat.",
                isActive: false,
                userIssue: binding
            )
            .padding(AppSpacing.lg)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("CookingStepCard — expanded, empty input") {
    StatefulPreview(initial: "") { binding in
        ZStack {
            AppColor.surfaceTile1.ignoresSafeArea()
            CookingStepCard(
                stepIndex: 1,
                stepText: "Pour in the eggs and let them set around the edges for 30 seconds.",
                isActive: true,
                userIssue: binding
            )
            .padding(AppSpacing.lg)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("CookingStepCard — expanded, with text") {
    StatefulPreview(initial: "I burned the butter and now it smells bitter.") { binding in
        ZStack {
            AppColor.surfaceTile1.ignoresSafeArea()
            CookingStepCard(
                stepIndex: 2,
                stepText: "Scatter the parmesan and wilted spinach across one half.",
                isActive: true,
                userIssue: binding
            )
            .padding(AppSpacing.lg)
        }
        .preferredColorScheme(.dark)
    }
}

private struct StatefulPreview<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(initial: Value,
         @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
