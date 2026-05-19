//
//  RecipeCard.swift
//  SousAI
//
//  A single recipe card inside the RecipeCardsView pager.
//
//  Design intent (per DESIGN.md + the brief):
//    • Background: AppColor.surfaceTile2 (#2a2a2c) — DESIGN.md's
//      micro-step lighter tile, used to separate adjacency on the
//      surfaceTile1 page canvas without resorting to a forbidden card
//      shadow. Depth comes from the tile-color step alone:
//        page (surfaceTile1) → card (surfaceTile2) → inner chips
//        (surfaceTile3).
//    • Corners: AppRadius.lg (18pt) — the `store-utility-card` grammar.
//    • Hairline: 1pt bodyOnDark @ 6% — the "soft hairline" depth
//      treatment DESIGN.md prescribes for utility cards.
//    • Layout (top → bottom):
//        - RecipeDishImage — flush to the top edge, 4:3 aspect. Its
//          top corners are pre-matched to AppRadius.lg via
//          UnevenRoundedRectangle, so the card's clip and the image's
//          clip share an edge perfectly.
//        - Title — displayMedium with tight tracking, bodyOnDark.
//        - Description — body (17pt), bodyMuted.
//        - Meta capsule — clock symbol + "X min" on surfaceTile3.
//        - Ingredient chips — ChipFlowLayout of small surfaceTile3
//          pills (reuses the existing flow primitive from the
//          IngredientSelectionView screen).
//        - Spacer, then PrimaryPillButton("Start Cooking").
//
//  No drop-shadow on the card. DESIGN.md's single sanctioned shadow is
//  reserved for product imagery, not card chrome.
//
//  Start Cooking is the future CookingModeView seam — for now it fires
//  a medium haptic via PrimaryPillButton and otherwise no-ops, mirroring
//  the posture IngredientSelectionView.generateRecipes() had before it
//  was wired through.
//

import SwiftUI

struct RecipeCard: View {

    let recipe: Recipe
    var onStartCooking: (Recipe) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeDishImage(recipe: recipe)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                titleBlock
                metaRow
                ingredientChips
                Spacer(minLength: AppSpacing.sm)
                startCookingButton
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(recipe.title))
        .accessibilityHint(Text("\(recipe.cookTimeMinutes) minutes. \(recipe.summary)"))
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(recipe.title)
                .font(AppTypography.displayMedium)
                .tracking(AppTypography.displayMediumTracking)
                .foregroundColor(AppColor.bodyOnDark)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(recipe.summary)
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.bodyMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meta row

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .regular))
            Text("\(recipe.cookTimeMinutes) min")
                .font(AppTypography.captionStrong)
                .tracking(AppTypography.captionStrongTracking)
        }
        .foregroundColor(AppColor.bodyOnDark.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(AppColor.surfaceTile3)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cook time \(recipe.cookTimeMinutes) minutes"))
    }

    // MARK: - Ingredient chips

    private var ingredientChips: some View {
        ChipFlowLayout(horizontalSpacing: AppSpacing.xxs,
                       verticalSpacing: AppSpacing.xxs) {
            ForEach(recipe.ingredients, id: \.self) { name in
                Text(name)
                    .font(AppTypography.caption)
                    .tracking(AppTypography.captionTracking)
                    .foregroundColor(AppColor.bodyMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColor.surfaceTile3)
                    )
                    .accessibilityLabel(Text(name))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA

    private var startCookingButton: some View {
        HStack {
            PrimaryPillButton("Start Cooking",
                              icon: "flame.fill") {
                onStartCooking(recipe)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

#Preview("RecipeCard — pre-generation (mock)") {
    ZStack {
        AppColor.surfaceTile1.ignoresSafeArea()
        RecipeCard(recipe: Recipe.mocks[0])
            .padding(AppSpacing.lg)
    }
    .preferredColorScheme(.dark)
}

#Preview("RecipeCard — long title") {
    ZStack {
        AppColor.surfaceTile1.ignoresSafeArea()
        RecipeCard(recipe: Recipe(
            title: "Slow-Roasted Garlic Butter Chicken Thighs",
            summary: "Pan-seared and oven-finished, with a glossy lemon-garlic pan sauce.",
            cookTimeMinutes: 45,
            ingredients: ["Chicken Thigh", "Butter", "Garlic", "Lemon", "Olive Oil", "Spinach"],
            emoji: "🍗"
        ))
        .padding(AppSpacing.lg)
    }
    .preferredColorScheme(.dark)
}
