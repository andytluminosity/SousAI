//
//  AnalysisLoadingView.swift
//  SousAI
//
//  The "Analyzing your fridge…" screen.
//
//  This is the host of the OpenAI vision call. The screen owns the
//  in-flight Task, the cancel/retry affordances, and the error surface.
//  Successful completion pushes `.ingredients(photo, detected)` and pops
//  itself out of the user's mental model — the path is what survives.
//
//  Design intent:
//    • Re-uses the hero's `AmbientBackground` — keeps brand continuity with
//      Home rather than the black canvas of CameraView/Confirmation, because
//      we're no longer in the "photographic capture" context.
//    • A single quiet question in `displayMedium`, then three pulsing dots
//      instead of a spinner. Spinners feel transactional; dots feel patient.
//    • When the network call fails the dots are swapped for a short,
//      humane error line and the CTA cluster becomes Retry + Cancel.
//      No alert sheets, no scary modal — failure stays inside the same
//      composition the user is already looking at.
//
//  Cancel semantics: pops one entry off the stack — back to
//  PhotoConfirmationView, with the captured photo intact, so the user
//  can simply re-confirm or retake without losing their photo.
//

import SwiftUI

struct AnalysisLoadingView: View {

    let photo: CapturedPhoto
    @Binding var path: NavigationPath

    @State private var pulse = false
    @State private var advanceTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: AppSpacing.xl) {
                    Text(headlineText)
                        .font(AppTypography.displayMedium)
                        .tracking(AppTypography.displayMediumTracking)
                        .foregroundColor(AppColor.bodyOnDark)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, AppSpacing.lg)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.body)
                            .tracking(AppTypography.bodyTracking)
                            .foregroundColor(AppColor.bodyMuted.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppSpacing.lg)
                    } else {
                        pulsingDots
                    }
                }

                Spacer()

                ctaCluster
                    .padding(.bottom, AppSpacing.xl)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            scheduleAdvance()
        }
        .onDisappear {
            advanceTask?.cancel()
            advanceTask = nil
        }
    }

    // MARK: - Headline + CTA

    private var headlineText: String {
        errorMessage == nil ? "Analyzing your fridge…" : "Something went wrong"
    }

    @ViewBuilder
    private var ctaCluster: some View {
        if errorMessage != nil {
            VStack(spacing: AppSpacing.sm) {
                PrimaryPillButton("Try Again",
                                  icon: "arrow.clockwise",
                                  action: retry)
                SecondaryGhostButton("Cancel", action: cancel)
            }
        } else {
            SecondaryGhostButton("Cancel", action: cancel)
        }
    }

    // MARK: - Real handoff

    private func scheduleAdvance() {
        // Guard against `.onAppear` re-fires (e.g. returning to this screen
        // from a downstream pop). The Task is the single source of truth for
        // "an analysis is pending".
        guard advanceTask == nil else { return }

        advanceTask = Task { @MainActor in
            do {
                let detected = try await OpenAIIngredientService.shared
                    .analyzeFridge(photo: photo.image)
                guard !Task.isCancelled else { return }
                path.append(AppRoute.ingredients(photo, detected))
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = Self.friendlyMessage(for: error)
                advanceTask = nil
            }
        }
    }

    private func retry() {
        errorMessage = nil
        advanceTask?.cancel()
        advanceTask = nil
        scheduleAdvance()
    }

    private func cancel() {
        advanceTask?.cancel()
        advanceTask = nil
        if !path.isEmpty { path.removeLast() }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let openAI = error as? OpenAIError {
            switch openAI {
            case .missingKey:
                return "OpenAI API key isn't set. Add it to .env and try again."
            case .transport:
                return "We couldn't reach OpenAI. Check your connection and try again."
            case .http(let status, _):
                return "OpenAI returned an error (status \(status)). Please try again."
            case .emptyResponse, .decoding, .invalidPayload:
                return "We couldn't read the response. Please try again."
            }
        }
        return "Something went wrong. Please try again."
    }

    private var pulsingDots: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppColor.bodyMuted.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.0 : 0.55)
                    .opacity(pulse ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: pulse
                    )
            }
        }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Previews

#Preview("AnalysisLoadingView") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        AnalysisLoadingView(photo: CapturedPhoto(image: UIImage()),
                            path: path)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value,
         @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
