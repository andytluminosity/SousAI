//
//  RecipeGeneratingView.swift
//  SousAI
//
//  The transitional "AI is composing your recipes" screen.
//
//  This is the calm pause between IngredientSelectionView's commitment
//  ("Generate Recipes") and the reward moment in RecipeCardsView. It
//  honors the same motion vocabulary as AnalysisLoadingView so the post-
//  capture branch of the app feels like one continuous experience —
//  AmbientBackground canvas, displayMedium headline, three pulsing dots,
//  a single quiet "Cancel" ghost. The only differences from
//  AnalysisLoadingView are the copy and the advance destination.
//
//  Future OpenAI seam:
//    • This screen is where the text-completion call will live. The
//      active ingredient list rides in on the route payload — no extra
//      plumbing needed. The future implementation will replace the
//      `advanceTask` body with the real call and push
//      `.recipeCards(decodedRecipes)` when it resolves.
//    • Image generation does NOT happen here. The text call returns
//      each `Recipe.imagePrompt` already populated; RecipeCardsView
//      fires the per-recipe image calls in parallel as soon as it
//      mounts, so the user is already swiping while images develop in.
//      See the seam diagram in `Recipe.swift`.
//
//  Cancel behavior: pops one entry off the stack — back to
//  IngredientSelectionView, with `excluded` selections intact, so the
//  user can adjust and retry without losing their pruning.
//

import SwiftUI

struct RecipeGeneratingView: View {

    let activeIngredients: [DetectedIngredient]
    @Binding var path: NavigationPath

    @State private var pulse = false
    @State private var advanceTask: Task<Void, Never>?

    /// Stub latency before we land on the cards. Replace with the real
    /// OpenAI text-completion call's resolution time when wired in.
    private let stubGenerationDuration: Duration = .milliseconds(2800)

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: AppSpacing.xl) {
                    Text("Generating recipes…")
                        .font(AppTypography.displayMedium)
                        .tracking(AppTypography.displayMediumTracking)
                        .foregroundColor(AppColor.bodyOnDark)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, AppSpacing.lg)

                    pulsingDots

                    Text("Crafting personalized meals from your ingredients")
                        .font(AppTypography.body)
                        .tracking(AppTypography.bodyTracking)
                        .foregroundColor(AppColor.bodyMuted.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppSpacing.lg)
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
        // from a downstream pop). The Task is the single source of truth
        // for "an advance is pending".
        guard advanceTask == nil else { return }

        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: stubGenerationDuration)
            guard !Task.isCancelled else { return }
            // The real implementation will pass the decoded recipes
            // produced from `activeIngredients`. For now we hand the
            // fixture forward so the downstream cards screen has data.
            path.append(AppRoute.recipeCards(Recipe.mocks))
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

#Preview("RecipeGeneratingView") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        RecipeGeneratingView(
            activeIngredients: DetectedIngredient.sampleFridge,
            path: path
        )
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
