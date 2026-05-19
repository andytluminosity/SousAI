//
//  Ingredient.swift
//  SousAI
//
//  The AI-domain representation of an ingredient detected in a fridge photo.
//
//  Two-layer contract:
//    • `DetectedIngredient` is the pure wire format. `Codable` so the future
//      OpenAI vision response can be decoded straight into `[DetectedIngredient]`
//      without an intermediate adapter.
//    • Selection state (which detected items the user excluded from the
//      recipe pool) deliberately lives in the *view*, not on the model —
//      keeping the wire shape clean and the decoder dumb.
//
//  Hashable conformance is required by `AppRoute.ingredients(_,_)` so the
//  route can ride a `[DetectedIngredient]` payload through `NavigationStack`.
//
//  Emoji enrichment seam:
//    • AI-detected items receive `emoji` directly from the model — the
//      vision/text response is asked to return a single glyph per item
//      alongside the name, decoded straight into this struct.
//    • User-added items are minted with `emoji = nil` in the view layer
//      and remain that way until enrichment runs. We deliberately do NOT
//      guess emojis on-device: a keyword lookup falls apart on typos
//      ("chickn"), composed phrases ("chicken olive oil sauce"), brand
//      names, and non-English input — exactly the inputs that need it
//      most. The same AI that names ingredients picks their glyphs.
//    • When the OpenAI client lands, the enrichment hook will mutate the
//      user-added DetectedIngredient in place (matched by `id`) to attach
//      the returned emoji. The view binds to the array, so the chip just
//      re-renders when the emoji appears.
//

import Foundation

/// A single ingredient the vision model believes it saw in the photo.
///
/// `id` is a UUID minted on the device so we have a stable identity for
/// SwiftUI's `ForEach` and for the view's selection set. When the OpenAI
/// response lands, the decoder can either accept an `id` from the JSON or
/// synthesize one at decode time — either path keeps the rest of the app
/// unchanged.
struct DetectedIngredient: Codable, Identifiable, Hashable {

    let id: UUID
    var name: String
    /// 0.0 – 1.0. `nil` for user-added items where no model confidence exists.
    var confidence: Double?
    /// A single emoji glyph chosen by the AI to represent this ingredient.
    /// `nil` for user-added items until the OpenAI enrichment call populates
    /// it. Never guessed locally — see the file header for rationale.
    var emoji: String?

    init(id: UUID = UUID(),
         name: String,
         confidence: Double? = nil,
         emoji: String? = nil) {
        self.id = id
        self.name = name
        self.confidence = confidence
        self.emoji = emoji
    }
}

// MARK: - Sample data

extension DetectedIngredient {

    /// A realistic 12-item fridge inventory used by previews and as the stub
    /// payload that `AnalysisLoadingView` hands forward to the ingredient
    /// screen until the real vision call is wired in.
    ///
    /// Names are deliberately ordinary — the screen should look like the
    /// inside of a real fridge, not a curated grocery shoot. Emojis are
    /// hard-coded here to stand in for what the OpenAI response will return
    /// in production, so the demo flow looks alive from the first push.
    static let sampleFridge: [DetectedIngredient] = [
        .init(name: "Eggs",          confidence: 0.97, emoji: "🥚"),
        .init(name: "Greek Yogurt",  confidence: 0.94, emoji: "🥛"),
        .init(name: "Butter",        confidence: 0.92, emoji: "🧈"),
        .init(name: "Spinach",       confidence: 0.91, emoji: "🥬"),
        .init(name: "Cherry Tomato", confidence: 0.88, emoji: "🍅"),
        .init(name: "Red Onion",     confidence: 0.86, emoji: "🧅"),
        .init(name: "Garlic",        confidence: 0.84, emoji: "🧄"),
        .init(name: "Parmesan",      confidence: 0.83, emoji: "🧀"),
        .init(name: "Lemon",         confidence: 0.79, emoji: "🍋"),
        .init(name: "Olive Oil",     confidence: 0.77, emoji: "🫒"),
        .init(name: "Chicken Thigh", confidence: 0.74, emoji: "🍗"),
        .init(name: "Sourdough",     confidence: 0.69, emoji: "🍞")
    ]
}
