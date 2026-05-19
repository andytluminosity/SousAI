//
//  Recipe.swift
//  SousAI
//
//  The AI-domain representation of a single recipe suggestion.
//
//  Two-call AI architecture seam:
//
//      ┌──────────────────────────────┐
//      │ RecipeGeneratingView         │
//      └──────────────────────────────┘
//         │
//         │ 1. ingredients ──▶ OpenAI text model
//         │                       returns [Recipe] with `imagePrompt`
//         │                       populated and `imageURL == nil`.
//         │
//         ▼
//      path.append(.recipeCards(recipes))
//         │
//         │ 2. RecipeCardsView appears immediately with placeholders.
//         │    In parallel — one image generation call per recipe —
//         │    OpenAI image model resolves each `imagePrompt` to a URL.
//         │    Each URL is written back to `recipes[i].imageURL`
//         │    (matched by `id`); SwiftUI re-renders just the affected
//         │    card. The user is already swiping; images develop in.
//
//  Why this shape:
//    • `imagePrompt` is persisted on the model so an image-gen retry
//      doesn't require another (expensive, slow) text round-trip.
//    • `imageURL` is `var` so the future image-enrichment hook can
//      mutate it in place — the same posture the codebase already uses
//      for `DetectedIngredient.emoji` enrichment (see Ingredient.swift).
//    • Both new fields are optional so today's mock flow ships with
//      `imageURL == nil` end-to-end and the view shows its elegant
//      placeholder state — an honest preview of what users will see in
//      the first ~second after the cards land in production.
//
//  `Codable` so the future OpenAI text response decodes straight into
//  `[Recipe]` without an intermediate adapter. `Hashable` so the model
//  can ride `AppRoute.recipeCards([Recipe])` through `NavigationStack`.
//

import Foundation

/// A single AI-suggested recipe.
struct Recipe: Codable, Identifiable, Hashable {

    let id: UUID
    var title: String
    var summary: String
    var cookTimeMinutes: Int
    var ingredients: [String]
    /// A single emoji glyph that stands in for the dish on the chip
    /// surface and inside `RecipeDishImage`'s pre-generation placeholder.
    /// AI-supplied — we never guess locally; same rationale as in
    /// `Ingredient.swift`.
    var emoji: String?
    /// The natural-language prompt the text model returns alongside the
    /// recipe. Fed back into OpenAI's image model to produce the dish
    /// preview. Persisted on the model so retries don't require another
    /// text round-trip.
    var imagePrompt: String?
    /// The image-generation result. `nil` while the image call is
    /// pre-flight, in-flight, or has failed. Mutated in place by the
    /// future enrichment hook, matched by `id`. The view treats `nil`
    /// as the placeholder state — there is no separate "loading" flag.
    var imageURL: URL?

    init(id: UUID = UUID(),
         title: String,
         summary: String,
         cookTimeMinutes: Int,
         ingredients: [String],
         emoji: String? = nil,
         imagePrompt: String? = nil,
         imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.cookTimeMinutes = cookTimeMinutes
        self.ingredients = ingredients
        self.emoji = emoji
        self.imagePrompt = imagePrompt
        self.imageURL = imageURL
    }
}

// MARK: - Sample data

extension Recipe {

    /// The fixture handed forward by `RecipeGeneratingView` until the
    /// real OpenAI text call is wired in.
    ///
    /// Each mock sets `imagePrompt` to a representative food-photography
    /// brief — visible at a glance so the field's purpose is obvious —
    /// and intentionally leaves `imageURL = nil`. That `nil` is the
    /// production "image not back yet" state, so the demo ships with
    /// the exact same placeholder treatment users will see in the first
    /// ~second of a real generation.
    static let mocks: [Recipe] = [
        .init(
            title: "High-Protein Omelette",
            summary: "A fluffy three-egg omelette folded around melted parmesan and wilted spinach.",
            cookTimeMinutes: 10,
            ingredients: ["Eggs", "Parmesan", "Spinach", "Butter"],
            emoji: "🍳",
            imagePrompt: "A golden three-egg omelette on a white ceramic plate, melted cheese visible, soft window light, overhead food photography, shallow depth of field."
        ),
        .init(
            title: "Quick Cheese Pasta",
            summary: "Al dente pasta tossed in butter, garlic, and a generous shower of aged parmesan.",
            cookTimeMinutes: 15,
            ingredients: ["Pasta", "Butter", "Garlic", "Parmesan", "Olive Oil"],
            emoji: "🧀",
            imagePrompt: "A bowl of buttery pasta with grated parmesan and a swirl of olive oil, rustic wooden table, warm natural light, editorial food photography."
        ),
        .init(
            title: "Veggie Scramble Bowl",
            summary: "Soft-scrambled eggs over greens with cherry tomatoes, red onion, and crusty sourdough.",
            cookTimeMinutes: 12,
            ingredients: ["Eggs", "Spinach", "Cherry Tomato", "Red Onion", "Sourdough"],
            emoji: "🥗",
            imagePrompt: "A breakfast bowl of soft scrambled eggs with sautéed spinach, halved cherry tomatoes, and toasted sourdough, on a stone surface, morning light."
        ),
        .init(
            title: "Lemon Chicken Skillet",
            summary: "Seared chicken thigh finished with garlic, lemon, and a glossy pan sauce.",
            cookTimeMinutes: 22,
            ingredients: ["Chicken Thigh", "Lemon", "Garlic", "Butter", "Olive Oil"],
            emoji: "🍗",
            imagePrompt: "Golden-seared chicken thighs in a cast iron skillet with lemon slices and garlic, glossy pan sauce, dark moody food photography."
        )
    ]
}
