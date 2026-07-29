//
//  SecretsParseTests.swift
//  SousAITests
//
//  Covers the hand-rolled `.env` parser in `Secrets`.
//
//  Worth testing despite being ~15 lines: it is the single point of failure
//  for the app's only secret. A parse bug doesn't fail loudly — it yields a
//  subtly wrong key, and the first symptom is an HTTP 401 three screens into
//  the flow, which reads like an API problem rather than a parsing one.
//

import XCTest

@testable import SousAI

final class SecretsParseTests: XCTestCase {

    func testParsesASimpleKeyValuePair() {
        let values = Secrets.parse("OPENAI_API_KEY=sk-abc123")
        XCTAssertEqual(values["OPENAI_API_KEY"], "sk-abc123")
    }

    func testIgnoresCommentsAndBlankLines() {
        let source = """
        # This is a comment
        OPENAI_API_KEY=sk-abc123

           # An indented comment
        OTHER=value
        """
        let values = Secrets.parse(source)

        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values["OPENAI_API_KEY"], "sk-abc123")
        XCTAssertEqual(values["OTHER"], "value")
    }

    func testStripsSurroundingDoubleQuotes() {
        let values = Secrets.parse(#"OPENAI_API_KEY="sk-abc123""#)
        XCTAssertEqual(values["OPENAI_API_KEY"], "sk-abc123")
    }

    func testStripsSurroundingSingleQuotes() {
        let values = Secrets.parse("OPENAI_API_KEY='sk-abc123'")
        XCTAssertEqual(values["OPENAI_API_KEY"], "sk-abc123")
    }

    func testTrimsWhitespaceAroundKeyAndValue() {
        let values = Secrets.parse("  OPENAI_API_KEY   =   sk-abc123   ")
        XCTAssertEqual(values["OPENAI_API_KEY"], "sk-abc123")
    }

    func testPreservesEqualsSignsInsideTheValue() {
        // Base64-ish and JWT-ish secrets routinely contain '='. Splitting on
        // every '=' instead of the first would silently truncate the key.
        let values = Secrets.parse("TOKEN=abc=def==")
        XCTAssertEqual(values["TOKEN"], "abc=def==")
    }

    func testSkipsLinesWithNoAssignment() {
        let values = Secrets.parse("JUST_A_WORD\nREAL=1")
        XCTAssertNil(values["JUST_A_WORD"])
        XCTAssertEqual(values["REAL"], "1")
    }

    func testSkipsEntriesWithAnEmptyKey() {
        let values = Secrets.parse("=orphaned\nREAL=1")
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values["REAL"], "1")
    }

    func testHandlesCarriageReturnLineEndings() {
        // A .env authored on Windows, or pasted from one, arrives with \r\n.
        let values = Secrets.parse("A=1\r\nB=2\r\n")
        XCTAssertEqual(values["A"], "1")
        XCTAssertEqual(values["B"], "2")
    }

    func testRetainsAnEmptyValueAsEmptyRatherThanDropping() {
        // `require(_:)` is what rejects empty values, not the parser. Keeping
        // the key here means the error says "not defined" for a truly absent
        // key and nothing misleading for a present-but-blank one.
        let values = Secrets.parse("EMPTY=")
        XCTAssertEqual(values["EMPTY"], "")
    }

    func testLaterDuplicateKeyWins() {
        let values = Secrets.parse("KEY=first\nKEY=second")
        XCTAssertEqual(values["KEY"], "second")
    }
}
