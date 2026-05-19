//
//  OpenAIClient.swift
//  SousAI
//
//  Thin URLSession wrapper for the OpenAI Chat Completions API.
//
//  Scope:
//    • One endpoint: POST https://api.openai.com/v1/chat/completions
//    • One model: gpt-4o-mini (vision-capable, supports JSON-mode, cheap)
//    • One async helper: `chatCompletion(messages:jsonMode:)` that returns
//      the raw `content` string from the first choice.
//
//  Why this shape:
//    • Both call sites (fridge vision, single-emoji text) speak the same
//      Chat Completions dialect. Centralizing the auth header, request
//      body shape, decoding, and error mapping keeps the two service
//      methods small and unit-test-friendly.
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
    private let model = "gpt-4o-mini"
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
}
