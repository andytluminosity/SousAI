//
//  RecipeDishImage.swift
//  SousAI
//
//  The "dish preview" surface that sits at the top of every RecipeCard.
//
//  Why a dedicated component:
//    • Isolates the three render states of an AI-generated image so
//      RecipeCard can stay flat and declarative.
//    • Lets the OpenAI image-enrichment hook mutate `Recipe.imageURL`
//      in place without RecipeCard needing to know — when `imageURL`
//      flips from `nil → URL`, only this sub-tree re-renders.
//
//  Three render states (driven entirely by `recipe.imageURL`):
//
//    • Pre-generation (`imageURL == nil`)
//        A `surfaceTile3` panel with the recipe's emoji centered at
//        64pt and a very subtle ambient breathing (opacity 0.85 ↔ 1.0,
//        1.6s autoreverse). Calm, never spinner-y. This is what users
//        see in the first ~second on production and 100% of the time
//        in mocks.
//
//    • Loading (URL present, `AsyncImage` `.empty` phase)
//        Same placeholder underneath. AsyncImage's content fades in
//        on top when it arrives, so the transition reads as a
//        "develop-in" rather than a swap.
//
//    • Loaded (URL present, `.success`)
//        The image fills the 4:3 surface, clipped to match the card's
//        top-corner radius. Cross-fades in over 0.45s easeOut.
//
//  Failure (`.failure`) silently falls back to the placeholder — no
//  error chrome on a delight surface.
//
//  Surface treatment (per DESIGN.md):
//    • 4:3 aspect — editorial food-photography proportions.
//    • Top corners rounded to `AppRadius.lg` (matched to the card's
//      outer corners via `UnevenRoundedRectangle`), bottom corners
//      square — the image bleeds to the card's left/right/top edges
//      and the title block sits flush beneath it.
//    • No drop-shadow. DESIGN.md sanctions one shadow for "product
//      imagery resting on a surface", but the dish image IS the card's
//      top surface here, not a render floating above one — so the
//      shadow rule doesn't apply. Keeps the page consistently flat.
//

import SwiftUI

struct RecipeDishImage: View {

    let recipe: Recipe

    /// Drives the placeholder's slow ambient breath.
    @State private var breathing = false

    /// Top-corner radius — matched to the card's outer radius so the
    /// two surfaces share an edge perfectly.
    private let topCornerRadius: CGFloat = AppRadius.lg

    var body: some View {
        ZStack {
            // The placeholder sits behind everything so the loaded
            // image cross-fades in on top of it (develop-in feel).
            placeholder

            if let url = recipe.imageURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.45))) { phase in
                    switch phase {
                    case .empty:
                        // Placeholder already underneath; render nothing.
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        // Quiet fallback — no error chrome.
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(topRoundedShape)
        .contentShape(topRoundedShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of \(recipe.title)"))
        .onAppear { startBreathing() }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        ZStack {
            AppColor.surfaceTile3

            if let emoji = recipe.emoji {
                Text(emoji)
                    .font(.system(size: 64))
                    .opacity(breathing ? 1.0 : 0.85)
                    .scaleEffect(breathing ? 1.0 : 0.985)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Shapes

    private var topRoundedShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: topCornerRadius
            ),
            style: .continuous
        )
    }

    // MARK: - Motion

    private func startBreathing() {
        guard !breathing else { return }
        // 1.6s slow autoreverse — calm, never animated. Matches the
        // ambient-light cadence in AmbientBackground without copying it.
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

// MARK: - Previews

#Preview("RecipeDishImage — pre-generation (mock)") {
    ZStack {
        AppColor.surfaceTile2.ignoresSafeArea()
        RecipeDishImage(recipe: Recipe.mocks[0])
            .padding(AppSpacing.lg)
    }
    .preferredColorScheme(.dark)
}

#Preview("RecipeDishImage — no emoji") {
    ZStack {
        AppColor.surfaceTile2.ignoresSafeArea()
        RecipeDishImage(recipe: Recipe(
            title: "No Emoji Test",
            summary: "—",
            cookTimeMinutes: 10,
            ingredients: [],
            emoji: nil
        ))
        .padding(AppSpacing.lg)
    }
    .preferredColorScheme(.dark)
}
