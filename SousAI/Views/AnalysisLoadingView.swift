//
//  AnalysisLoadingView.swift
//  SousAI
//
//  The stub "Analyzing your fridge…" screen.
//
//  This is the future home of the OpenAI vision call. For now it exists so
//  the navigation flow is wired end-to-end and the user lands somewhere
//  honest after tapping "Use This Photo".
//
//  Design intent:
//    • Re-uses the hero's `AmbientBackground` — keeps brand continuity with
//      Home rather than the black canvas of CameraView/Confirmation, because
//      we're no longer in the "photographic capture" context.
//    • A single quiet question in `displayMedium`, then three pulsing dots
//      instead of a spinner. Spinners feel transactional; dots feel patient.
//    • A single quiet "Cancel" affordance — restrained ghost capsule in the
//      same bottom CTA zone the confirmation view uses, so the layout rhythm
//      across the flow stays consistent. Tapping it pops the stack one step
//      back to PhotoConfirmationView (not all the way home), so the user
//      keeps their captured photo and can simply re-confirm or retake.
//
//  Stubbed handoff:
//    • After ~2.4s of "thinking", the screen pushes `.ingredients(...)` onto
//      the path with the `DetectedIngredient.sampleFridge` fixture. This is
//      the exact site the real OpenAI vision call will replace — destination
//      and payload shape stay identical; only the source flips from fixture
//      to network. The advance Task is cancelled on `.onDisappear` so a
//      mid-flight Cancel tap never re-pushes us into Ingredients.
//

import SwiftUI

struct AnalysisLoadingView: View {

    let photo: CapturedPhoto
    @Binding var path: NavigationPath

    @State private var pulse = false
    @State private var advanceTask: Task<Void, Never>?

    /// Stub latency before we land on the ingredient screen. Replace by the
    /// real OpenAI vision call's resolution time when wired in.
    private let stubAnalysisDuration: Duration = .milliseconds(2400)

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: AppSpacing.xl) {
                    Text("Analyzing your fridge…")
                        .font(AppTypography.displayMedium)
                        .tracking(AppTypography.displayMediumTracking)
                        .foregroundColor(AppColor.bodyOnDark)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, AppSpacing.lg)

                    pulsingDots
                }

                Spacer()

                SecondaryGhostButton("Cancel") {
                    advanceTask?.cancel()
                    if !path.isEmpty { path.removeLast() }
                }
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

    // MARK: - Stubbed handoff

    private func scheduleAdvance() {
        // Guard against `.onAppear` re-fires (e.g. returning to this screen
        // from a downstream pop). The Task is the single source of truth for
        // "an advance is pending".
        guard advanceTask == nil else { return }

        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: stubAnalysisDuration)
            guard !Task.isCancelled else { return }
            path.append(
                AppRoute.ingredients(photo, DetectedIngredient.sampleFridge)
            )
        }
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
