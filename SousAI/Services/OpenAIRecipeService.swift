//
//  OpenAIRecipeService.swift
//  SousAI
//
//  The domain layer that turns OpenAI calls into the two things the
//  post-ingredient half of SousAI needs:
//
//    1. generateRecipes(from:excluding:) → [Recipe]
//       Text-completion call. Builds a JSON-mode prompt from the active
//       ingredient list (plus an optional exclusion list of titles
//       we've already shown, for "Generate More") and decodes the
//       response straight into `[Recipe]`. UUIDs are minted on the
//       device — the model doesn't need to invent stable IDs.
//
//    2. generateImage(forPrompt:) → URL
//       Image-generation call. Thin delegate to
//       `OpenAIClient.imageGeneration` — the per-recipe image-enrichment
//       hook in RecipeCardsView fires one of these per recipe in
//       parallel, then writes the resolved URL into
//       `recipes[i].imageURL` by id. See `Recipe.swift` for the seam
//       diagram.
//
//  Both methods route through `OpenAIClient` for the auth header,
//  request shape, and error mapping — this file only owns the prompts
//  and the JSON-decoding into our domain types.
//
//  Dedupe posture (Generate More):
//    • The exclusion list is sent to the model in the prompt — it's the
//      first defence against duplicates.
//    • Defensive title-level dedupe lives at the call site, not in this
//      service: even with the exclusion prompt the model can echo a
//      restatement. `RecipeCardsView.handleGenerateMore` filters by
//      lowercased title against the current array before appending.
//

import Foundation

final class OpenAIRecipeService {

    static let shared = OpenAIRecipeService()

    private let client: OpenAIClient

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    // MARK: - Text: ingredients → recipes

    /// Generates 4 distinct recipes from the active ingredient list.
    /// When `existingTitles` is non-empty (the "Generate More" path),
    /// the model is asked to be substantively different from those.
    /// Throws `OpenAIError` on failure; the caller (RecipeGeneratingView
    /// for the initial call, RecipeCardsView for Generate More) surfaces
    /// these via inline error + Retry affordances.
    func generateRecipes(from activeIngredients: [DetectedIngredient],
                         excluding existingTitles: [String] = []) async throws -> [Recipe] {

        let ingredientList = activeIngredients
            .map(\.name)
            .joined(separator: ", ")

        guard !ingredientList.isEmpty else {
            throw OpenAIError.invalidPayload("Cannot generate recipes from an empty ingredient list.")
        }

        let system = """
        You are SousAI's recipe generator. Given a list of ingredients a \
        cook has on hand, propose exactly 4 distinct, achievable home \
        recipes that primarily use those ingredients. Each recipe must be \
        meaningfully different from the others in technique or cuisine — \
        not four variations of the same dish.

        For each recipe, return:
        - title: a short, common, title-cased English name (e.g. \
          "Lemon Chicken Skillet"). No brand names.
        - summary: one sensory sentence describing the finished dish.
        - cookTimeMinutes: an integer between 5 and 60.
        - ingredients: a JSON array of short ingredient name strings the \
          recipe uses. Draw primarily from the provided list; reasonable \
          pantry staples (salt, pepper, olive oil, water) are OK to add.
        - emoji: a single Unicode emoji glyph that best represents the \
          dish. Exactly one glyph, no text, no spaces.
        - imagePrompt: a short photography brief (one or two sentences) \
          describing what the finished dish looks like — overhead or \
          three-quarter angle, natural light, ceramic or stone surface, \
          editorial food photography. This is fed to an image model so \
          be specific about plating and lighting.
        - steps: a JSON array of 4 to 8 imperative cooking instructions, \
          one short sentence each, in cooking order.

        Return ONLY a JSON object with this exact shape, no prose:
        {
          "recipes": [
            {
              "title": "...",
              "summary": "...",
              "cookTimeMinutes": 0,
              "ingredients": ["..."],
              "emoji": "...",
              "imagePrompt": "...",
              "steps": ["..."]
            }
          ]
        }
        """

        var userText = "Available ingredients: \(ingredientList)"
        if !existingTitles.isEmpty {
            let exclusion = existingTitles.joined(separator: ", ")
            userText += "\nDo not propose any of these existing recipes "
                     + "(be substantively different, not just a renaming): \(exclusion)"
        }

        let messages: [OpenAIChatMessage] = [
            .system(system),
            .user(userText)
        ]

        let content = try await client.chatCompletion(messages: messages,
                                                     jsonMode: true,
                                                     temperature: 0.8)

        guard let jsonData = content.data(using: .utf8) else {
            throw OpenAIError.decoding(NSError(domain: "OpenAIRecipeService",
                                               code: -1,
                                               userInfo: [NSLocalizedDescriptionKey:
                                                            "Response was not UTF-8."]))
        }

        do {
            let envelope = try JSONDecoder().decode(RecipesEnvelope.self,
                                                    from: jsonData)
            return envelope.recipes.map(\.asRecipe)
        } catch {
            throw OpenAIError.decoding(error)
        }
    }

    // MARK: - Image: prompt → URL

    /// Generates the dish-preview image for an `imagePrompt` returned by
    /// the text call above. Returns the hosted URL. Thin delegate — the
    /// real work lives in `OpenAIClient.imageGeneration`.
    func generateImage(forPrompt prompt: String) async throws -> URL {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIError.invalidPayload("Image prompt was empty.")
        }
        return try await client.imageGeneration(prompt: trimmed)
    }

    // MARK: - Wire types (private)

    private struct RecipesEnvelope: Decodable {
        let recipes: [Item]

        struct Item: Decodable {
            let title: String
            let summary: String
            let cookTimeMinutes: Int
            let ingredients: [String]
            let emoji: String?
            let imagePrompt: String?
            let steps: [String]?

            /// Mints a fresh UUID on the device — the model doesn't need
            /// to invent stable IDs. Same posture as
            /// `OpenAIIngredientService.IngredientsEnvelope.Item.asDetected`.
            var asRecipe: Recipe {
                Recipe(
                    title: title,
                    summary: summary,
                    cookTimeMinutes: cookTimeMinutes,
                    ingredients: ingredients,
                    emoji: emoji?.isEmpty == true ? nil : emoji,
                    imagePrompt: imagePrompt?.isEmpty == true ? nil : imagePrompt,
                    imageURL: nil,
                    steps: (steps?.isEmpty == true) ? nil : steps
                )
            }
        }
    }
}
