//
//  RecipeGeneratingView.swift
//  SousAI
//
//  The "AI is composing your recipes" screen.
//
//  This is the calm pause between IngredientSelectionView's commitment
//  ("Generate Recipes") and the reward moment in RecipeCardsView. It
//  honors the same motion vocabulary as AnalysisLoadingView so the post-
//  capture branch of the app feels like one continuous experience —
//  AmbientBackground canvas, displayMedium headline, three pulsing dots,
//  and a graceful failure mode (Try Again + Cancel).
//
//  Host of the OpenAI text-completion call:
//    • The active ingredient list arrives on the route payload — see
//      IngredientSelectionView.generateRecipes(), which filters the
//      user's `excluded` selections off before pushing this route.
//    • `scheduleAdvance` fires `OpenAIRecipeService.generateRecipes`,
//      which returns `[Recipe]` with `title`, `summary`, `cookTimeMinutes`,
//      `ingredients`, `emoji`, `imagePrompt`, AND `steps` already
//      populated. The image-gen call does NOT run here — it runs in
//      parallel from `RecipeCardsView.onAppear`, so the cards land
//      immediately with placeholders and the previews develop in.
//      See the seam diagram in `Recipe.swift`.
//
//  Error posture: matches AnalysisLoadingView. The dots are swapped for
//  a humane error line; the CTA cluster becomes Try Again + Cancel; the
//  headline flips to "Something went wrong". No alert sheets. Failure
//  stays inside the same composition the user is already looking at.
//
//  Cancel semantics: pops one entry off the stack — back to
//  IngredientSelectionView, with `excluded` selections intact, so the
//  user can adjust the ingredient list and retry without losing their
//  pruning.
//

import SwiftUI

struct RecipeGeneratingView: View {

    let activeIngredients: [DetectedIngredient]
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
        errorMessage == nil ? "Generating recipes…" : "Something went wrong"
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
        // from a downstream pop). The Task is the single source of truth
        // for "a generation is pending".
        guard advanceTask == nil else { return }

        advanceTask = Task { @MainActor in
            do {
                let recipes = try await OpenAIRecipeService.shared
                    .generateRecipes(from: activeIngredients)
                guard !Task.isCancelled else { return }
                path.append(AppRoute.recipeCards(activeIngredients, recipes))
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

    /// Mirrors `AnalysisLoadingView.friendlyMessage(for:)` so the error
    /// vocabulary stays consistent across the post-capture flow.
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
