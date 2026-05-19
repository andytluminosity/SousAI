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

    init(id: UUID = UUID(),
         name: String,
         confidence: Double? = nil) {
        self.id = id
        self.name = name
        self.confidence = confidence
    }
}

// MARK: - Sample data

extension DetectedIngredient {

    /// A realistic 12-item fridge inventory used by previews and as the stub
    /// payload that `AnalysisLoadingView` hands forward to the ingredient
    /// screen until the real vision call is wired in.
    ///
    /// Names are deliberately ordinary — the screen should look like the
    /// inside of a real fridge, not a curated grocery shoot.
    static let sampleFridge: [DetectedIngredient] = [
        .init(name: "Eggs",          confidence: 0.97),
        .init(name: "Greek Yogurt",  confidence: 0.94),
        .init(name: "Butter",        confidence: 0.92),
        .init(name: "Spinach",       confidence: 0.91),
        .init(name: "Cherry Tomato", confidence: 0.88),
        .init(name: "Red Onion",     confidence: 0.86),
        .init(name: "Garlic",        confidence: 0.84),
        .init(name: "Parmesan",      confidence: 0.83),
        .init(name: "Lemon",         confidence: 0.79),
        .init(name: "Olive Oil",     confidence: 0.77),
        .init(name: "Chicken Thigh", confidence: 0.74),
        .init(name: "Sourdough",     confidence: 0.69)
    ]
}
