//
//  AppRoute.swift
//  SousAI
//
//  The single navigation contract for the SousAI capture flow.
//
//  Design intent:
//    • Every screen the user can land on after Home is one case of `AppRoute`,
//      so the NavigationStack path stays inspectable, reversible, and trivial
//      to reason about. No coordinators, no environment-injected stores.
//    • The captured photo rides along as the associated value of the route
//      that needs it — it only exists for as long as it's on the stack.
//    • `CapturedPhoto` Hashes by identity (UUID), not by image pixels. Two
//      navigations of the same photo will produce two distinct stack entries
//      — which is what we want for stack semantics.
//
//  This file is also the future-proof seam: when the mock `ImageRenderer`
//  capture is swapped for real AVFoundation, the `CapturedPhoto` value
//  doesn't change — only its producer does.
//

import UIKit

/// Routes pushable onto the app's `NavigationStack` after `HomeView`.
enum AppRoute: Hashable {
    /// The immersive viewfinder screen.
    case camera

    /// The cinematic full-bleed confirmation screen for a freshly captured photo.
    case confirmation(CapturedPhoto)

    /// The stub "Analyzing your fridge…" loading screen that will host the
    /// future OpenAI vision call.
    case analyzing(CapturedPhoto)

    /// The interactive refinement screen — the user reviews, toggles, and
    /// edits the detected ingredient list before recipe generation.
    /// Rides the original `CapturedPhoto` so a "Retake" pop can reuse it,
    /// and the AI's `[DetectedIngredient]` payload as the initial list.
    case ingredients(CapturedPhoto, [DetectedIngredient])

    /// The "Generating recipes…" loading screen that will host the future
    /// OpenAI text-completion call. Rides the *active* ingredient list —
    /// the user's `excluded` selections have already been filtered out by
    /// `IngredientSelectionView`, so the route payload is exactly what the
    /// real text model will eventually receive.
    case generatingRecipes([DetectedIngredient])

    /// The swipeable recipe cards screen — the first "wow moment". Rides
    /// the original `[DetectedIngredient]` (the active list used to seed
    /// the text-completion call) alongside the `[Recipe]` produced by the
    /// loading screen. The active list rides along because the cards
    /// screen offers a "Generate More" affordance that re-calls the text
    /// model with the original ingredients plus an exclusion list of
    /// already-shown titles — see `RecipeCardsView.handleGenerateMore`.
    /// Each `Recipe` carries its `imagePrompt` and an `imageURL` mutated
    /// in place by id once the image-gen hook resolves. See `Recipe.swift`
    /// for the seam.
    case recipeCards([DetectedIngredient], [Recipe])

    /// The guided step-by-step cooking screen. Rides the *single* `Recipe`
    /// the user committed to when they tapped "Start Cooking" on its card
    /// — passed by value, not looked up by id. The screen is a pure
    /// projection of this payload, so popping the stack returns the user
    /// to the same page in the pager with no state to reconcile.
    case cookingMode(Recipe)
}

/// A captured `UIImage` paired with a stable identity.
///
/// `UIImage` itself is not `Hashable`, and even if it were, hashing by pixel
/// content would defeat NavigationStack's identity model. We hash by `id`
/// so each captured photo is its own distinct stack entry.
struct CapturedPhoto: Hashable, Identifiable {

    let id: UUID
    let image: UIImage

    init(image: UIImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
    }

    static func == (lhs: CapturedPhoto, rhs: CapturedPhoto) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
