//
//  StubURLProtocol.swift
//  SousAITests
//
//  Intercepts URLSession traffic so the OpenAI services can be tested
//  against canned responses.
//
//  Why this and not a fake client: `OpenAIRecipeService.init(client:)` takes
//  a concrete `OpenAIClient`, and `OpenAIClient.init(session:)` takes a
//  `URLSession`. Injecting at the session layer means the tests exercise
//  the REAL request encoding, status-code branching, JSON decoding, and
//  `OpenAIError` mapping — everything except the socket. Substituting a
//  fake client instead would skip all of that and assert only that a stub
//  returns what it was told to return.
//

import Foundation

final class StubURLProtocol: URLProtocol {

    /// What the next request should resolve to. Set per-test.
    /// `nonisolated(unsafe)` because `URLProtocol` hands us no context to
    /// thread state through, and the tests that use it are serial.
    nonisolated(unsafe) static var stub: Stub?

    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        /// When set, the request fails at the transport layer instead of
        /// returning a response — the `OpenAIError.transport` path.
        var error: Error?

        static func json(_ string: String, statusCode: Int = 200) -> Stub {
            Stub(statusCode: statusCode, body: Data(string.utf8))
        }
    }

    static func reset() { stub = nil }

    /// Builds a session wired to this protocol. `.ephemeral` so no cache or
    /// cookie state leaks between tests.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub else {
            client?.urlProtocol(self,
                                didFailWithError: URLError(.resourceUnavailable))
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: stub.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self,
                            didReceive: response,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
