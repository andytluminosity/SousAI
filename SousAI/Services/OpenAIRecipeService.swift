//
//  OpenAIRecipeService.swift
//  SousAI
//
//  The domain layer that turns OpenAI calls into the three things the
//  post-ingredient half of SousAI needs:
//
//    1. generateRecipes(from:excluding:) → [Recipe]
//       Text-completion call. Builds a JSON-mode prompt from the active
//       ingredient list (plus an optional exclusion list of titles
//       we've already shown, for "Generate More") and decodes the
//       response straight into `[Recipe]`. UUIDs are minted on the
//       device — the model doesn't need to invent stable IDs.
//
//    2. generateImage(forPrompt:) → URL (local file)
//       Image-generation call. Asks `OpenAIClient.imageGeneration` for
//       the decoded PNG bytes (via `b64_json`), writes them to a
//       uniquely-named file in `FileManager.default.temporaryDirectory`,
//       and returns the local `file://` URL. The per-recipe image-
//       enrichment hook in RecipeCardsView fires one of these per
//       recipe in parallel, then writes the resolved local URL into
//       `recipes[i].imageURL` by id. `AsyncImage` renders local file
//       URLs reliably; the OpenAI temporary CDN URLs it would otherwise
//       hand us did not. See `Recipe.swift` for the seam diagram.
//
//    3. troubleshootStep(recipe:stepIndex:userIssue:) → TroubleshootResult
//       The in-kitchen co-pilot. When the user types "what went wrong"
//       on an active step in CookingModeView, this call sends the full
//       recipe context + the user's issue and returns:
//         • `message` — an upbeat, lightly humorous, resilience-first
//           remediation in 2–4 short sentences. Always present.
//         • `updatedSteps` / `updatedIngredients` — full replacement
//           arrays when the recipe genuinely needs to change (something
//           burned past saving, a swap is required, a recovery
//           ingredient must be added). `nil` otherwise — most issues
//           are fixed verbally, not by rewriting the recipe.
//       CookingModeView replaces the live arrays on its `@State recipe`
//       when these come back, scoped to that screen only — the
//       RecipeCardsView source of truth is never mutated.
//
//  All three methods route through `OpenAIClient` for the auth header,
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

// MARK: - Troubleshoot result

/// The decoded outcome of `OpenAIRecipeService.troubleshootStep`.
///
/// `message` is always present — the upbeat fix-it line the cooking
/// screen renders beneath the active step's input.
///
/// `updatedSteps` and `updatedIngredients` are optional and only
/// populated when the model decided the recipe genuinely needs to
/// change (something is unsalvageable, a swap is required, a recovery
/// ingredient must be added). When present, each is the **full
/// replacement array**, not a diff — the call site replaces the live
/// recipe's arrays wholesale and lets SwiftUI re-render. Defaulting
/// both to `nil` keeps "the recipe is fine, just do this differently"
/// the happy path.
struct TroubleshootResult {
    let message: String
    let updatedSteps: [String]?
    let updatedIngredients: [String]?
}

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
    /// the text call above, persists the bytes to a uniquely-named file
    /// in the app's temporary directory, and returns the local file URL.
    ///
    /// Why we persist instead of returning a remote URL:
    ///   • `OpenAIClient.imageGeneration` returns the decoded PNG bytes
    ///     directly (via the `b64_json` response format). The alternative
    ///     — having OpenAI hand back a temporary signed CDN URL —
    ///     consistently misbehaves under `AsyncImage`: depending on the
    ///     blob host the fetch either stalls forever or returns 403 once
    ///     the signature expires, leaving the dish preview stuck on its
    ///     emoji placeholder.
    ///   • A local file URL drops straight into `RecipeDishImage`'s
    ///     `AsyncImage` and renders deterministically on the first
    ///     attempt.
    ///   • Files live in `FileManager.default.temporaryDirectory`, which
    ///     iOS reclaims as it sees fit — perfectly fine for a session-
    ///     scoped dish preview that the user will never revisit after
    ///     the app is killed.
    func generateImage(forPrompt prompt: String) async throws -> URL {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIError.invalidPayload("Image prompt was empty.")
        }
        let imageData = try await client.imageGeneration(prompt: trimmed)
        return try Self.persistTemporary(imageData: imageData)
    }

    /// Writes `imageData` to a uniquely-named `.png` file inside a
    /// dedicated subdirectory of the system temporary directory.
    /// Creates the subdirectory on first use (idempotent — no-op on
    /// subsequent calls).
    ///
    /// Failures bubble as `OpenAIError.invalidPayload` so the call site
    /// can surface them through the same error taxonomy as transport
    /// errors — the user doesn't need to know the difference between
    /// "OpenAI failed" and "disk failed".
    private static func persistTemporary(imageData: Data) throws -> URL {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("SousAI-RecipeImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw OpenAIError.invalidPayload(
                "Could not create the image cache directory: \(error.localizedDescription)"
            )
        }
        let fileURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            throw OpenAIError.invalidPayload(
                "Could not write the image to disk: \(error.localizedDescription)"
            )
        }
        return fileURL
    }

    // MARK: - Troubleshoot: step issue → remediation (+ optional recipe rewrite)

    /// Asks the model to help the cook through an in-progress issue on
    /// a specific step of the recipe they're cooking. Returns an
    /// always-present remediation `message` plus optional full
    /// replacement `updatedSteps` / `updatedIngredients` arrays when
    /// the recipe needs to change.
    ///
    /// Prompt shape:
    ///   • System: identity + tone (warm, lightly humorous, resilience
    ///     first), and the strict rule that the recipe-rewrite fields
    ///     default to `null` and the dish should stay recognizable.
    ///   • User: the recipe title, current ingredients, the full step
    ///     list with the active step marked, and the user's typed
    ///     issue.
    ///
    /// Temperature is intentionally higher (0.85) than the recipe-
    /// generation call (0.8) — this surface lives or dies by
    /// personality. JSON mode keeps decoding deterministic.
    ///
    /// Failures route through the same `OpenAIError` taxonomy as the
    /// other calls in this service so the UI layer's
    /// `friendlyMessage(for:)` mapping covers them uniformly.
    func troubleshootStep(recipe: Recipe,
                          stepIndex: Int,
                          userIssue: String) async throws -> TroubleshootResult {

        let trimmedIssue = userIssue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIssue.isEmpty else {
            throw OpenAIError.invalidPayload("Cannot troubleshoot an empty issue.")
        }

        let steps = recipe.steps ?? []
        let safeIndex = max(0, min(stepIndex, max(0, steps.count - 1)))

        let system = """
        You are SousAI's in-kitchen co-pilot — the friend who's calmly \
        standing at the stove with the cook. Your job is to keep them \
        cooking and feeling good about it when something goes wrong.

        Voice and tone:
        - Warm, upbeat, lightly humorous. Address the cook directly ("you").
        - Resilience first: mistakes are normal, every save is a small win.
        - Concrete and actionable. 2 to 4 short sentences. No lists, no \
          markdown, no emoji, no preamble like "Don't worry!" — just lead \
          with the fix.

        Behavior:
        - Read the full recipe context and the active step the cook is on.
        - Give the single best next move tailored to THIS step and THIS issue.
        - Most of the time the recipe does NOT need to change — the cook \
          just needs a technique tip or a quick recovery. In that case, \
          return `updatedSteps: null` and `updatedIngredients: null`.
        - Only rewrite the recipe when the situation truly demands it: \
          something is unsalvageable, a technique swap is required, or a \
          recovery ingredient must be added. When you do rewrite, return \
          the FULL replacement array (not a diff), keep the dish \
          recognizably the same recipe, and keep step count between 4 and \
          8 imperative sentences in cooking order. If you add a new \
          ingredient, also reflect it in the updated steps.
        - Never invent allergens or radically new techniques. Stay within \
          the cook's likely pantry.

        Return ONLY a JSON object with this exact shape, no prose:
        {
          "message": "...",
          "updatedSteps": null,
          "updatedIngredients": null
        }
        """

        // Mark the active step inline so the model can't miscount when
        // we tell it "step N" — the marker is unambiguous in either
        // 0- or 1-based reading.
        let stepListing: String
        if steps.isEmpty {
            stepListing = "(no steps provided)"
        } else {
            stepListing = steps.enumerated().map { offset, text in
                let prefix = (offset == safeIndex)
                    ? ">> STEP \(offset + 1) <<"
                    : "Step \(offset + 1):"
                return "\(prefix) \(text)"
            }.joined(separator: "\n")
        }

        let userText = """
        Recipe: \(recipe.title)
        Ingredients: \(recipe.ingredients.joined(separator: ", "))

        Full steps (active step marked with >> <<):
        \(stepListing)

        The cook is on step \(safeIndex + 1) and says:
        "\(trimmedIssue)"

        Help them through it.
        """

        let messages: [OpenAIChatMessage] = [
            .system(system),
            .user(userText)
        ]

        let content = try await client.chatCompletion(messages: messages,
                                                     jsonMode: true,
                                                     temperature: 0.85)

        guard let jsonData = content.data(using: .utf8) else {
            throw OpenAIError.decoding(NSError(domain: "OpenAIRecipeService",
                                               code: -1,
                                               userInfo: [NSLocalizedDescriptionKey:
                                                            "Response was not UTF-8."]))
        }

        let envelope: TroubleshootEnvelope
        do {
            envelope = try JSONDecoder().decode(TroubleshootEnvelope.self,
                                                from: jsonData)
        } catch {
            throw OpenAIError.decoding(error)
        }

        let message = envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw OpenAIError.emptyResponse
        }

        // Treat empty arrays the same as `nil` so the call site has a
        // single "no change" signal to check. This is the same defensive
        // posture `RecipesEnvelope.Item.asRecipe` uses for `steps`.
        let normalizedSteps: [String]? = (envelope.updatedSteps?.isEmpty == false)
            ? envelope.updatedSteps
            : nil
        let normalizedIngredients: [String]? = (envelope.updatedIngredients?.isEmpty == false)
            ? envelope.updatedIngredients
            : nil

        return TroubleshootResult(
            message: message,
            updatedSteps: normalizedSteps,
            updatedIngredients: normalizedIngredients
        )
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

    /// Wire shape of the JSON returned by `troubleshootStep`. `message`
    /// is required; the two `updated*` arrays are optional and default
    /// to `nil` when the model returned `null` (the common case — most
    /// fixes are verbal, not structural).
    private struct TroubleshootEnvelope: Decodable {
        let message: String
        let updatedSteps: [String]?
        let updatedIngredients: [String]?
    }
}
