//
//  OpenAIClient.swift
//  SousAI
//
//  Thin URLSession wrapper for the OpenAI Chat Completions API.
//
//  Scope:
//    • Two endpoints:
//        - POST https://api.openai.com/v1/chat/completions
//        - POST https://api.openai.com/v1/images/generations
//    • One text model: gpt-4o-mini (vision-capable, supports JSON-mode, cheap)
//    • One image model: dall-e-2 (cheapest URL-returning image model — the
//      response URL drops directly into RecipeDishImage's AsyncImage seam
//      with zero file-system plumbing).
//    • Two async helpers:
//        - `chatCompletion(messages:jsonMode:temperature:)` returns the raw
//          `content` string from the first choice.
//        - `imageGeneration(prompt:)` returns the generated image's URL.
//
//  Why this shape:
//    • All three call sites (fridge vision, single-emoji text, recipe-text
//      generation, dish-image generation) speak the OpenAI dialect.
//      Centralizing the auth header, request body shape, decoding, and
//      error mapping keeps the per-service methods small and unit-test-
//      friendly.
//    • `OpenAIError` is the single error type any service can surface to
//      the UI. The view never has to know the difference between a
//      transport failure and a 401.
//
//  Networking posture:
//    • 60 second timeout — vision calls on a fresh server can take ~10s.
//    • No retries (yet). Failures bubble; the AnalysisLoadingView has a
//      user-driven Retry button which is the right place for retry policy
//      in this UI.
//    • No streaming. Both call sites need the full payload before they
//      can act on it.
//

import Foundation

// MARK: - Errors

enum OpenAIError: Error, LocalizedError {
    case missingKey
    case transport(Error)
    case http(status: Int, body: String)
    case emptyResponse
    case decoding(Error)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "OpenAI API key is not configured. Add it to .env."
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .http(let status, _):
            return "OpenAI responded with status \(status)."
        case .emptyResponse:
            return "OpenAI returned an empty response."
        case .decoding(let error):
            return "Could not understand the response: \(error.localizedDescription)"
        case .invalidPayload(let detail):
            return detail
        }
    }
}

// MARK: - Message DSL

/// The subset of OpenAI's message schema we actually send. Lives here
/// because both services compose them; the wire shape is identical to
/// the public API.
struct OpenAIChatMessage: Encodable {
    let role: String
    let content: [Content]

    enum Content: Encodable {
        case text(String)
        case imageURL(url: String, detail: String?)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case image_url
        }
        private struct ImageURLPayload: Encodable {
            let url: String
            let detail: String?
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let s):
                try c.encode("text", forKey: .type)
                try c.encode(s, forKey: .text)
            case .imageURL(let url, let detail):
                try c.encode("image_url", forKey: .type)
                try c.encode(ImageURLPayload(url: url, detail: detail),
                             forKey: .image_url)
            }
        }
    }

    static func system(_ text: String) -> OpenAIChatMessage {
        .init(role: "system", content: [.text(text)])
    }

    static func user(_ text: String) -> OpenAIChatMessage {
        .init(role: "user", content: [.text(text)])
    }

    static func user(text: String,
                     imageURL: String,
                     detail: String = "low") -> OpenAIChatMessage {
        .init(role: "user", content: [
            .text(text),
            .imageURL(url: imageURL, detail: detail)
        ])
    }
}

// MARK: - Client

final class OpenAIClient {

    static let shared = OpenAIClient()

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let imageEndpoint = URL(string: "https://api.openai.com/v1/images/generations")!
    private let model = "gpt-4o-mini"
    /// Dall-E 2 is the cheapest URL-returning image model (~$0.02/image at
    /// 1024x1024) — its response URL lands directly in RecipeDishImage's
    /// AsyncImage seam, so we avoid the b64 → temp-file plumbing the
    /// gpt-image-1 / dall-e-3 (-b64) flow would require.
    private let imageModel = "dall-e-2"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends a Chat Completion request and returns the `content` of the
    /// first choice's message. `jsonMode == true` sets
    /// `response_format: { type: "json_object" }`, which constrains the
    /// model to emit valid JSON — the caller can then decode straight
    /// into a typed struct without prose-stripping.
    func chatCompletion(messages: [OpenAIChatMessage],
                        jsonMode: Bool = false,
                        temperature: Double = 0.2) async throws -> String {
        let key: String
        do {
            key = try Secrets.require("OPENAI_API_KEY")
        } catch {
            throw OpenAIError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body = RequestBody(
            model: model,
            messages: messages,
            temperature: temperature,
            response_format: jsonMode
                ? ResponseFormat(type: "json_object")
                : nil
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw OpenAIError.decoding(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidPayload("Non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(status: http.statusCode, body: bodyText)
        }

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAIError.decoding(error)
        }

        guard let content = decoded.choices.first?.message.content,
              !content.isEmpty else {
            throw OpenAIError.emptyResponse
        }
        return content
    }

    // MARK: - Image generation

    /// Generates a single 1024x1024 image for `prompt` and returns the
    /// hosted URL of the result. The URL is the OpenAI-issued temporary
    /// link in the response payload — short-lived (~hours) but plenty for
    /// our session: the AsyncImage in RecipeDishImage fetches it the
    /// moment it lands on `imageURL` and the user is already looking at
    /// the card.
    ///
    /// Failures route through the same `OpenAIError` taxonomy as
    /// `chatCompletion` so the UI layer has one error type to surface.
    func imageGeneration(prompt: String) async throws -> URL {
        let key: String
        do {
            key = try Secrets.require("OPENAI_API_KEY")
        } catch {
            throw OpenAIError.missingKey
        }

        var request = URLRequest(url: imageEndpoint)
        request.httpMethod = "POST"
        // Image generation is slower than chat — 30s budgets feel tight in
        // practice; 60s is the same as `chatCompletion` for one stable
        // ceiling across the client.
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body = ImageRequestBody(
            model: imageModel,
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            response_format: "url"
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw OpenAIError.decoding(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidPayload("Non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(status: http.statusCode, body: bodyText)
        }

        let decoded: ImageResponse
        do {
            decoded = try JSONDecoder().decode(ImageResponse.self, from: data)
        } catch {
            throw OpenAIError.decoding(error)
        }

        guard let urlString = decoded.data.first?.url,
              let url = URL(string: urlString) else {
            throw OpenAIError.emptyResponse
        }
        return url
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable {
        let model: String
        let messages: [OpenAIChatMessage]
        let temperature: Double
        let response_format: ResponseFormat?
    }

    private struct ResponseFormat: Encodable {
        let type: String
    }

    private struct ChatCompletionResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
        }
        struct Message: Decodable {
            let content: String
        }
    }

    private struct ImageRequestBody: Encodable {
        let model: String
        let prompt: String
        let n: Int
        let size: String
        let response_format: String
    }

    private struct ImageResponse: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let url: String?
        }
    }
}
