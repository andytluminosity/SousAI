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

import SwiftUI

struct AnalysisLoadingView: View {

    let photo: CapturedPhoto
    @Binding var path: NavigationPath

    @State private var pulse = false

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
