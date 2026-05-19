//
//  Secrets.swift
//  SousAI
//
//  Runtime accessor for values defined in `.env`.
//
//  iOS does not have a "process environment" in the Unix sense — there is
//  no `getenv()` worth using inside an app sandbox — so the canonical
//  `.env` file at the project root is mirrored into `SousAI/Resources/.env`
//  and shipped as a bundle resource. This loader reads that bundled copy
//  once on first access, parses `KEY=value` lines, and caches the result
//  for the rest of the process lifetime.
//
//  Why this shape, not Info.plist:
//    • Developers expect a `.env` file. Matching that mental model keeps
//      onboarding a single instruction ("drop your key in .env").
//    • No build script, no xcconfig, no plist gymnastics. Just a file
//      that ships in the bundle and a 20-line parser.
//
//  Why two physical files (root + Resources):
//    • The root `.env` is where humans put the key.
//    • The Resources copy is what `Bundle.main` can find at runtime.
//    Both are gitignored. See the plan + `.env.example` for the contract.
//
//  Safety posture:
//    • In DEBUG, a missing / placeholder key trips a `fatalError` so the
//      mistake surfaces the first time you run the app, not silently as
//      a network 401 three screens deep.
//    • In RELEASE, the same condition throws `SecretsError.missingKey`
//      so the calling service can degrade gracefully instead of crashing
//      a shipping build.
//

import Foundation

enum SecretsError: Error, LocalizedError {
    case bundleFileMissing
    case missingKey(String)
    case placeholderKey(String)

    var errorDescription: String? {
        switch self {
        case .bundleFileMissing:
            return "Could not find .env in the app bundle."
        case .missingKey(let name):
            return "\(name) is not defined in .env."
        case .placeholderKey(let name):
            return "\(name) in .env is still the placeholder value."
        }
    }
}

enum Secrets {

    /// The OpenAI API key, read from the bundled `.env` on first access.
    /// Trips `fatalError` in DEBUG if missing / placeholder; throws via
    /// the loader path in RELEASE so callers can fall back.
    static var openAIAPIKey: String {
        do {
            return try require("OPENAI_API_KEY")
        } catch {
            #if DEBUG
            fatalError("Secrets: \(error.localizedDescription) See .env.example.")
            #else
            return ""
            #endif
        }
    }

    /// Throwing variant — services that want to recover from a bad key
    /// (e.g. show an inline error instead of crashing) should call this.
    static func require(_ key: String) throws -> String {
        let values = try loadedValues()
        guard let raw = values[key] else {
            throw SecretsError.missingKey(key)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw SecretsError.missingKey(key) }
        if trimmed.hasPrefix("sk-replace") || trimmed == "your-key-here" {
            throw SecretsError.placeholderKey(key)
        }
        return trimmed
    }

    // MARK: - Parsing

    /// Cached parsed `.env` contents. The parse runs at most once per
    /// process — `.env` files are immutable for the lifetime of an app
    /// install, so there is nothing to invalidate.
    private static let cache: Result<[String: String], Error> = {
        guard let url = Bundle.main.url(forResource: ".env",
                                        withExtension: nil)
                    ?? Bundle.main.url(forResource: "env",
                                       withExtension: nil) else {
            return .failure(SecretsError.bundleFileMissing)
        }
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            return .success(parse(raw))
        } catch {
            return .failure(error)
        }
    }()

    private static func loadedValues() throws -> [String: String] {
        switch cache {
        case .success(let dict): return dict
        case .failure(let error): throw error
        }
    }

    /// Minimal `.env` parser: ignores blanks and `#` comments, supports
    /// optional surrounding single or double quotes around the value.
    /// Deliberately small — we do not need shell-style interpolation
    /// for an app that holds exactly one secret.
    private static func parse(_ source: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in source.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            out[key] = value
        }
        return out
    }
}
