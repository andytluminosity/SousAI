//
//  OpenAIIngredientService.swift
//  SousAI
//
//  The domain layer that turns OpenAI Chat Completions into the two
//  things SousAI actually needs:
//
//    1. analyzeFridge(photo:) → [DetectedIngredient]
//       Vision call. Downscales + JPEG-encodes the captured UIImage,
//       sends it as a base64 data URL, asks the model for a strict
//       JSON object, decodes straight into the DetectedIngredient
//       shape declared in Models/Ingredient.swift. UUIDs are minted
//       on the device — the model doesn't need to invent stable IDs.
//
//    2. emoji(for:) → String
//       Text-only call. Returns a single emoji glyph for one ingredient
//       name. Used by IngredientSelectionView to enrich user-added
//       chips that arrive with `emoji == nil`.
//
//  Both methods route through `OpenAIClient` for the auth header,
//  request shape, and error mapping — this file only owns the prompts,
//  the image pre-processing, and the JSON-decoding into our domain
//  types.
//

import UIKit

final class OpenAIIngredientService {

    static let shared = OpenAIIngredientService()

    private let client: OpenAIClient

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    // MARK: - Vision: photo → ingredients

    /// Analyzes a fridge photo and returns the visible ingredients with
    /// AI-supplied emoji + confidence. Throws `OpenAIError` on failure;
    /// the caller (AnalysisLoadingView) surfaces these via an inline
    /// error + Retry affordance.
    func analyzeFridge(photo image: UIImage) async throws -> [DetectedIngredient] {
        guard let dataURL = Self.encodeAsJPEGDataURL(image,
                                                     maxEdge: 1024,
                                                     quality: 0.8) else {
            throw OpenAIError.invalidPayload("Could not encode the captured photo.")
        }

        let system = """
        You analyze a single photograph of the inside of a refrigerator \
        (or a kitchen counter) and identify the visible food ingredients. \
        For each distinct ingredient you can see, return:
        - name: a short, common, title-cased English name (e.g. "Cherry Tomato", \
          "Greek Yogurt", "Chicken Thigh"). Prefer the most-recognizable \
          name over a brand name.
        - emoji: a single Unicode emoji glyph that best represents the \
          ingredient. Exactly one glyph, no text, no spaces.
        - confidence: your confidence the ingredient is present, as a \
          float between 0.0 and 1.0.
        Return ONLY a JSON object with this exact shape, no prose:
        { "ingredients": [ { "name": "...", "emoji": "...", "confidence": 0.0 } ] }
        If you cannot see any food ingredients at all, return:
        { "ingredients": [] }
        Do not invent ingredients you cannot actually see.
        """

        let messages: [OpenAIChatMessage] = [
            .system(system),
            .user(text: "Identify the ingredients in this photo.",
                  imageURL: dataURL,
                  detail: "low")
        ]

        let content = try await client.chatCompletion(messages: messages,
                                                     jsonMode: true,
                                                     temperature: 0.1)

        guard let jsonData = content.data(using: .utf8) else {
            throw OpenAIError.decoding(NSError(domain: "OpenAIIngredientService",
                                               code: -1,
                                               userInfo: [NSLocalizedDescriptionKey:
                                                            "Response was not UTF-8."]))
        }

        do {
            let envelope = try JSONDecoder().decode(IngredientsEnvelope.self,
                                                    from: jsonData)
            return envelope.ingredients.map(\.asDetected)
        } catch {
            throw OpenAIError.decoding(error)
        }
    }

    // MARK: - Text: name → emoji

    /// Returns a single emoji glyph for the given ingredient name.
    /// Used to enrich user-added chips. Throws on transport / parsing
    /// failure; the call site swallows the error and leaves the chip
    /// name-only (the existing "never guess locally" posture).
    func emoji(for name: String) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIError.invalidPayload("Ingredient name was empty.")
        }

        let system = """
        Given a single food ingredient name, respond with exactly one \
        Unicode emoji glyph that best represents it. The emoji must be \
        a single grapheme cluster, with no surrounding text, spaces, \
        punctuation, or quotation marks. Return ONLY a JSON object with \
        this exact shape: { "emoji": "..." }
        """

        let messages: [OpenAIChatMessage] = [
            .system(system),
            .user("Ingredient: \(trimmed)")
        ]

        let content = try await client.chatCompletion(messages: messages,
                                                     jsonMode: true,
                                                     temperature: 0.2)

        guard let data = content.data(using: .utf8) else {
            throw OpenAIError.decoding(NSError(domain: "OpenAIIngredientService",
                                               code: -1,
                                               userInfo: [NSLocalizedDescriptionKey:
                                                            "Response was not UTF-8."]))
        }

        let envelope: EmojiEnvelope
        do {
            envelope = try JSONDecoder().decode(EmojiEnvelope.self, from: data)
        } catch {
            throw OpenAIError.decoding(error)
        }

        let glyph = envelope.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !glyph.isEmpty else {
            throw OpenAIError.invalidPayload("Empty emoji from model.")
        }
        // Best-effort single-grapheme check. We don't reject multi-char
        // ZWJ sequences (👩‍🍳) because those ARE single grapheme clusters
        // in Swift's `String` — count of `1` covers them.
        guard glyph.count == 1 else {
            throw OpenAIError.invalidPayload("Model returned more than one glyph: \(glyph)")
        }
        return glyph
    }

    // MARK: - Image pre-processing

    /// Downscales `image` so its longest edge is `maxEdge` points, then
    /// JPEG-encodes it and returns a `data:image/jpeg;base64,...` URL
    /// suitable for the Chat Completions `image_url` content part.
    ///
    /// Why downscale: a raw 12MP fridge photo is ~3-5 MB and adds
    /// real latency for no recognition benefit at `detail: "low"`,
    /// which the vision model bins to a 512px tile regardless.
    static func encodeAsJPEGDataURL(_ image: UIImage,
                                    maxEdge: CGFloat,
                                    quality: CGFloat) -> String? {
        let resized = downscale(image, maxEdge: maxEdge)
        guard let data = resized.jpegData(compressionQuality: quality) else {
            return nil
        }
        let base64 = data.base64EncodedString()
        return "data:image/jpeg;base64,\(base64)"
    }

    private static func downscale(_ image: UIImage,
                                  maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: floor(size.width * scale),
                             height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Wire types (private)

    private struct IngredientsEnvelope: Decodable {
        let ingredients: [Item]

        struct Item: Decodable {
            let name: String
            let emoji: String?
            let confidence: Double?

            var asDetected: DetectedIngredient {
                DetectedIngredient(
                    name: name,
                    confidence: confidence,
                    emoji: emoji?.isEmpty == true ? nil : emoji
                )
            }
        }
    }

    private struct EmojiEnvelope: Decodable {
        let emoji: String
    }
}
