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
//    • No CTA, no close chip. The user is committed; this screen waits.
//

import SwiftUI

struct AnalysisLoadingView: View {

    let photo: CapturedPhoto

    @State private var pulse = false

    var body: some View {
        ZStack {
            AmbientBackground()

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
    AnalysisLoadingView(photo: CapturedPhoto(image: UIImage()))
}
