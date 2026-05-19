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
//  AI seam (live):
//    • The send button forwards the typed string to the parent via
//      `onSubmitIssue`. The parent (CookingModeView) calls
//      `OpenAIRecipeService.troubleshootStep` and writes the lifecycle
//      of that call back into `CookingStepInteraction.assistantStatus`.
//    • This card renders the status directly:
//        - `.idle`     → nothing beneath the input row.
//        - `.loading`  → three pulsing dots, same cadence as
//          `RecipeGeneratingView`. Send button is disabled.
//        - `.response` → text on a `surfaceTile3` inner tile with a tiny
//          "SOUSAI" eyebrow. Fade+slide-up on entry.
//        - `.error`    → muted line + small inline Retry text-button
//          that fires `onRetry`.
//
//  Animation:
//    • Expand/collapse: `.spring(response: 0.42, dampingFraction: 0.82)`
//      — the same spring `RecipeCardsView` uses for its page indicator,
//      keeping the in-app motion vocabulary consistent.
//    • Input row reveal: gentle `.opacity` + `.move(edge: .top)`
//      transition driven by an `easeOut(0.28)` `withAnimation` in the
//      parent on `selectedStepIndex` change.
//    • Assistant block reveal: same fade + slide-up transition as the
//      input row, driven by the parent's status-change `withAnimation`.
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
    /// The lifecycle of the AI troubleshooting call for this step.
    /// The card renders directly off the case (see file header). The
    /// parent (`CookingModeView`) owns the state and flips it as the
    /// `OpenAIRecipeService.troubleshootStep` call moves forward.
    var assistantStatus: StepAssistantStatus = .idle
    /// Fired when the user taps the step (collapsed or expanded). The
    /// parent toggles `selectedStepIndex` from this — the card itself
    /// has no opinion on selection state.
    var onTap: () -> Void = {}
    /// Fired when the user presses return on the input or taps the
    /// send button. The parent calls the AI from this and updates
    /// `assistantStatus` as the call lands.
    var onSubmitIssue: () -> Void = {}
    /// Fired when the user taps Retry on an `.error` assistant block.
    /// The parent re-dispatches the same troubleshooting call.
    var onRetry: () -> Void = {}

    // MARK: - Local state

    @FocusState private var inputIsFocused: Bool

    /// Drives the three-dot pulse during `.loading`. Same cadence the
    /// `RecipeGeneratingView` loading state uses so the two surfaces
    /// share one loading vocabulary.
    @State private var loadingPulse = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tapTarget

            if isActive {
                divider
                    .padding(.horizontal, AppSpacing.lg)

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    inputRow

                    if hasAssistantBlock {
                        assistantBlock
                            .transition(
                                .opacity
                                    .combined(with: .move(edge: .top))
                            )
                    }
                }
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
        .onChange(of: assistantStatus) { _, newStatus in
            syncLoadingPulse(for: newStatus)
        }
        .onAppear {
            syncLoadingPulse(for: assistantStatus)
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

    // MARK: - Assistant block

    /// `true` when there's any AI state to render beneath the input
    /// row. `.idle` is intentionally absent so the expanded card looks
    /// identical to its old shape until the user actually engages.
    private var hasAssistantBlock: Bool {
        switch assistantStatus {
        case .idle:     return false
        case .loading,
             .response,
             .error:    return true
        }
    }

    @ViewBuilder
    private var assistantBlock: some View {
        switch assistantStatus {
        case .idle:
            EmptyView()
        case .loading:
            loadingDots
                .accessibilityLabel(Text("SousAI is thinking"))
        case .response(let text):
            responseTile(text: text)
        case .error(let message):
            errorRow(message: message)
        }
    }

    /// Three-dot pulse with the same cadence/spacing the
    /// `RecipeGeneratingView` uses. Sitting on its own row (rather
    /// than inside a tile) keeps the loading footprint quiet and the
    /// final response feel like the actual reveal.
    private var loadingDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppColor.primaryOnDark.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .scaleEffect(loadingPulse ? 1.0 : 0.55)
                    .opacity(loadingPulse ? 1.0 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: loadingPulse
                    )
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func responseTile(text: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("SOUSAI")
                .font(AppTypography.brandEyebrow)
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))

            Text(text)
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.bodyOnDark)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColor.surfaceTile3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("SousAI says: \(text)"))
    }

    private func errorRow(message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text(message)
                .font(AppTypography.caption)
                .tracking(AppTypography.captionTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.85))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: handleRetry) {
                Text("Retry")
                    .font(AppTypography.captionStrong)
                    .tracking(AppTypography.captionStrongTracking)
                    .foregroundColor(AppColor.primaryOnDark)
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel(Text("Retry asking SousAI"))
        }
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Helpers

    /// The user can only submit while there's text AND no call is
    /// already in flight. Without the `.loading` gate, a fast double-
    /// tap on send could stack two requests for the same step.
    private var isSubmittable: Bool {
        guard !userIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if case .loading = assistantStatus { return false }
        return true
    }

    private func handleTap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        onTap()
    }

    private func handleSubmit() {
        guard isSubmittable else { return }
        inputIsFocused = false
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        onSubmitIssue()
    }

    private func handleRetry() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        onRetry()
    }

    /// Starts or stops the loading-dot animation in lockstep with the
    /// status. Driven from `.onAppear` and `.onChange(of:assistantStatus)`
    /// so the dots don't keep pulsing after a response lands.
    private func syncLoadingPulse(for status: StepAssistantStatus) {
        switch status {
        case .loading:
            if !loadingPulse { loadingPulse = true }
        default:
            if loadingPulse { loadingPulse = false }
        }
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

#Preview("CookingStepCard — assistant loading") {
    StatefulPreview(initial: "The eggs are sticking to the pan.") { binding in
        ZStack {
            AppColor.surfaceTile1.ignoresSafeArea()
            CookingStepCard(
                stepIndex: 1,
                stepText: "Pour in the eggs and let them set around the edges for 30 seconds.",
                isActive: true,
                userIssue: binding,
                assistantStatus: .loading
            )
            .padding(AppSpacing.lg)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("CookingStepCard — assistant response") {
    StatefulPreview(initial: "The eggs are sticking to the pan.") { binding in
        ZStack {
            AppColor.surfaceTile1.ignoresSafeArea()
            CookingStepCard(
                stepIndex: 1,
                stepText: "Pour in the eggs and let them set around the edges for 30 seconds.",
                isActive: true,
                userIssue: binding,
                assistantStatus: .response(
                    "Totally fixable. Lift one edge with a spatula, add a small knob of butter, and tilt the pan so it slides under the eggs. They'll loosen in about ten seconds."
                )
            )
            .padding(AppSpacing.lg)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("CookingStepCard — assistant error") {
    StatefulPreview(initial: "The eggs are sticking to the pan.") { binding in
        ZStack {
            AppColor.surfaceTile1.ignoresSafeArea()
            CookingStepCard(
                stepIndex: 1,
                stepText: "Pour in the eggs and let them set around the edges for 30 seconds.",
                isActive: true,
                userIssue: binding,
                assistantStatus: .error("We couldn't reach SousAI. Check your connection and try again.")
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
