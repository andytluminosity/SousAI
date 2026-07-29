//
//  OpenAIServiceDecodingTests.swift
//  SousAITests
//
//  Covers the model-response → domain-type boundary, which is where this
//  app is most exposed: the OpenAI response is JSON authored by a language
//  model, so every field is a thing that can arrive missing, empty, or
//  shaped slightly differently than the prompt asked for.
//
//  These run through the real `OpenAIClient` against a stubbed
//  `URLSession` (see `StubURLProtocol`), so the assertions cover the
//  genuine request path — status-code branching, `OpenAIError` mapping,
//  envelope decoding, and the optional-normalization rules the services
//  apply — rather than a hand-rolled fake of it.
//

import XCTest

@testable import SousAI

final class OpenAIServiceDecodingTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    /// A client wired to the stub protocol with a dummy key, so no `.env`
    /// needs to exist on the machine running the tests.
    private func makeClient() -> OpenAIClient {
        OpenAIClient(session: StubURLProtocol.makeSession(),
                     apiKeyProvider: { "sk-test-key" })
    }

    private func makeRecipeService() -> OpenAIRecipeService {
        OpenAIRecipeService(client: makeClient())
    }

    /// Wraps a payload in the Chat Completions envelope the client unwraps
    /// before handing the inner JSON to a service.
    private func chatCompletionResponse(containing payload: String) -> String {
        let escaped = payload
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return #"{"choices":[{"message":{"content":"\#(escaped)"}}]}"#
    }

    private let sampleIngredients = [
        DetectedIngredient(name: "Egg", confidence: 0.9, emoji: "🥚"),
        DetectedIngredient(name: "Spinach", confidence: 0.8, emoji: "🥬")
    ]

    // MARK: - Recipe generation

    func testGenerateRecipesDecodesAllFields() async throws {
        let payload = """
        {"recipes":[{"title":"Spinach Frittata","summary":"Golden and set.",\
        "cookTimeMinutes":18,"ingredients":["Egg","Spinach"],"emoji":"🍳",\
        "imagePrompt":"Overhead, natural light.","steps":["Beat eggs.","Bake."]}]}
        """
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let recipes = try await makeRecipeService()
            .generateRecipes(from: sampleIngredients)

        XCTAssertEqual(recipes.count, 1)
        let recipe = try XCTUnwrap(recipes.first)
        XCTAssertEqual(recipe.title, "Spinach Frittata")
        XCTAssertEqual(recipe.summary, "Golden and set.")
        XCTAssertEqual(recipe.cookTimeMinutes, 18)
        XCTAssertEqual(recipe.ingredients, ["Egg", "Spinach"])
        XCTAssertEqual(recipe.emoji, "🍳")
        XCTAssertEqual(recipe.imagePrompt, "Overhead, natural light.")
        XCTAssertEqual(recipe.steps, ["Beat eggs.", "Bake."])
        XCTAssertNil(recipe.imageURL,
                     "The text call must leave imageURL nil — it's filled in later by the image-enrichment pass.")
    }

    func testGenerateRecipesMintsDistinctIDsPerRecipe() async throws {
        let payload = """
        {"recipes":[\
        {"title":"A","summary":"s","cookTimeMinutes":5,"ingredients":["Egg"],"emoji":"🍳","imagePrompt":"p","steps":["x"]},\
        {"title":"B","summary":"s","cookTimeMinutes":5,"ingredients":["Egg"],"emoji":"🥗","imagePrompt":"p","steps":["x"]}]}
        """
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let recipes = try await makeRecipeService()
            .generateRecipes(from: sampleIngredients)

        // IDs are minted on-device, not supplied by the model. The image
        // enrichment pass matches results back by id, so collisions would
        // write a dish photo onto the wrong card.
        XCTAssertEqual(Set(recipes.map(\.id)).count, 2)
    }

    func testGenerateRecipesTreatsEmptyOptionalArraysAsNil() async throws {
        let payload = """
        {"recipes":[{"title":"Plain Toast","summary":"s","cookTimeMinutes":3,\
        "ingredients":["Bread"],"emoji":"","imagePrompt":"","steps":[]}]}
        """
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let recipes = try await makeRecipeService()
            .generateRecipes(from: sampleIngredients)
        let recipe = try XCTUnwrap(recipes.first)

        // Empty string / empty array must normalize to nil so the views can
        // use a single `if let` to pick their placeholder state.
        XCTAssertNil(recipe.emoji)
        XCTAssertNil(recipe.imagePrompt)
        XCTAssertNil(recipe.steps)
    }

    func testGenerateRecipesRejectsAnEmptyIngredientListWithoutCallingTheAPI() async {
        // No stub is set — if a request were made, StubURLProtocol fails it
        // with a transport error, which would surface as a different case.
        do {
            _ = try await makeRecipeService().generateRecipes(from: [])
            XCTFail("An empty ingredient list must be rejected locally.")
        } catch let error as OpenAIError {
            guard case .invalidPayload = error else {
                return XCTFail("Expected .invalidPayload, got \(error).")
            }
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    // MARK: - Troubleshooting

    func testTroubleshootStepDefaultsRewriteFieldsToNil() async throws {
        let payload = """
        {"message":"Turn the heat down and keep going.","updatedSteps":null,"updatedIngredients":null}
        """
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let result = try await makeRecipeService().troubleshootStep(
            recipe: Self.sampleRecipe,
            stepIndex: 0,
            userIssue: "It's smoking."
        )

        XCTAssertEqual(result.message, "Turn the heat down and keep going.")
        XCTAssertNil(result.updatedSteps)
        XCTAssertNil(result.updatedIngredients)
    }

    func testTroubleshootStepNormalizesEmptyArraysToNil() async throws {
        let payload = """
        {"message":"You're fine.","updatedSteps":[],"updatedIngredients":[]}
        """
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let result = try await makeRecipeService().troubleshootStep(
            recipe: Self.sampleRecipe,
            stepIndex: 0,
            userIssue: "Runny."
        )

        // CookingModeView replaces its live arrays whenever these are
        // non-nil. An empty array would blank the recipe on screen.
        XCTAssertNil(result.updatedSteps)
        XCTAssertNil(result.updatedIngredients)
    }

    func testTroubleshootStepReturnsRewrittenArraysWhenPresent() async throws {
        let payload = """
        {"message":"Add stock to loosen it.","updatedSteps":["Add stock.","Simmer 5 minutes."],\
        "updatedIngredients":["Rice","Stock"]}
        """
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let result = try await makeRecipeService().troubleshootStep(
            recipe: Self.sampleRecipe,
            stepIndex: 1,
            userIssue: "Too dry."
        )

        XCTAssertEqual(result.updatedSteps, ["Add stock.", "Simmer 5 minutes."])
        XCTAssertEqual(result.updatedIngredients, ["Rice", "Stock"])
    }

    func testTroubleshootStepClampsAnOutOfRangeStepIndex() async throws {
        // The view passes a step index; a stale index must not trap.
        let payload = #"{"message":"All good.","updatedSteps":null,"updatedIngredients":null}"#
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: payload))

        let result = try await makeRecipeService().troubleshootStep(
            recipe: Self.sampleRecipe,
            stepIndex: 999,
            userIssue: "Confused."
        )

        XCTAssertEqual(result.message, "All good.")
    }

    func testTroubleshootStepRejectsAnEmptyIssue() async {
        do {
            _ = try await makeRecipeService().troubleshootStep(
                recipe: Self.sampleRecipe,
                stepIndex: 0,
                userIssue: "   \n "
            )
            XCTFail("A whitespace-only issue must be rejected locally.")
        } catch let error as OpenAIError {
            guard case .invalidPayload = error else {
                return XCTFail("Expected .invalidPayload, got \(error).")
            }
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    // MARK: - Error mapping

    func testNonSuccessStatusMapsToHTTPErrorCarryingTheBody() async {
        StubURLProtocol.stub = .json(#"{"error":{"message":"Invalid API key"}}"#,
                                     statusCode: 401)

        do {
            _ = try await makeRecipeService().generateRecipes(from: sampleIngredients)
            XCTFail("A 401 must throw.")
        } catch let error as OpenAIError {
            guard case .http(let status, let body) = error else {
                return XCTFail("Expected .http, got \(error).")
            }
            XCTAssertEqual(status, 401)
            // The body is retained on the error even though
            // `errorDescription` hides it — that's what makes a 4xx
            // diagnosable in the DEBUG logs.
            XCTAssertTrue(body.contains("Invalid API key"))
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    func testTransportFailureMapsToTransportError() async {
        StubURLProtocol.stub = StubURLProtocol.Stub(error: URLError(.notConnectedToInternet))

        do {
            _ = try await makeRecipeService().generateRecipes(from: sampleIngredients)
            XCTFail("A transport failure must throw.")
        } catch let error as OpenAIError {
            guard case .transport = error else {
                return XCTFail("Expected .transport, got \(error).")
            }
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    func testMalformedInnerJSONMapsToDecodingError() async {
        // Valid Chat Completions envelope, but the model's `content` is not
        // the shape the prompt demanded. JSON mode makes this rare, not
        // impossible.
        StubURLProtocol.stub = .json(chatCompletionResponse(containing: #"{"recipes":"not-an-array"}"#))

        do {
            _ = try await makeRecipeService().generateRecipes(from: sampleIngredients)
            XCTFail("A malformed payload must throw.")
        } catch let error as OpenAIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error).")
            }
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    func testMissingAPIKeyMapsToMissingKeyWithoutARequest() async {
        struct NoKey: Error {}
        let client = OpenAIClient(session: StubURLProtocol.makeSession(),
                                  apiKeyProvider: { throw NoKey() })

        do {
            _ = try await OpenAIRecipeService(client: client)
                .generateRecipes(from: sampleIngredients)
            XCTFail("A missing key must throw before any request.")
        } catch let error as OpenAIError {
            guard case .missingKey = error else {
                return XCTFail("Expected .missingKey, got \(error).")
            }
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    func testEmptyChoicesMapsToEmptyResponse() async {
        StubURLProtocol.stub = .json(#"{"choices":[]}"#)

        do {
            _ = try await makeRecipeService().generateRecipes(from: sampleIngredients)
            XCTFail("An empty choices array must throw.")
        } catch let error as OpenAIError {
            guard case .emptyResponse = error else {
                return XCTFail("Expected .emptyResponse, got \(error).")
            }
        } catch {
            XCTFail("Expected OpenAIError, got \(error).")
        }
    }

    // MARK: - Fixtures

    private static let sampleRecipe = Recipe(
        title: "Risotto",
        summary: "Creamy.",
        cookTimeMinutes: 30,
        ingredients: ["Rice", "Stock"],
        emoji: "🍚",
        imagePrompt: nil,
        imageURL: nil,
        steps: ["Toast the rice.", "Add stock slowly."]
    )
}
