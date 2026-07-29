//
//  ImageEncodingTests.swift
//  SousAITests
//
//  Covers `OpenAIIngredientService.encodeAsJPEGDataURL`, the on-device
//  pre-processing step that every vision request goes through.
//
//  This is the cost-and-latency control for the whole feature: a raw
//  capture off a modern iPhone is multi-megabyte, and the vision model bins
//  the image to a 512px tile at `detail: "low"` regardless. Every byte
//  above the cap is upload latency and request size the user pays for and
//  gets nothing back for. A regression here would be invisible in the UI —
//  the app would keep working, just slower and more expensive — which is
//  exactly the kind of thing that needs a test rather than a code review.
//
//  All fixtures are rendered at `scale = 1` so points and pixels are the
//  same number. `downscale` reasons in points (`UIImage.size`) while the
//  encoded JPEG is measured in pixels, and a scale-3 fixture would make
//  every assertion here off by 3x for reasons unrelated to the code.
//

import UIKit
import XCTest

@testable import SousAI

final class ImageEncodingTests: XCTestCase {

    // MARK: - Downscaling

    func testDownscalesLongestEdgeToTheCap() throws {
        let source = makeImage(width: 2048, height: 1024)

        let encoded = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.8)
        )
        let decoded = try decodeImage(from: encoded)

        XCTAssertEqual(decoded.size.width, 1024)
        XCTAssertEqual(decoded.size.height, 512)
    }

    func testDownscalesPortraitImagesByHeight() throws {
        let source = makeImage(width: 1024, height: 2048)

        let encoded = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.8)
        )
        let decoded = try decodeImage(from: encoded)

        // A fridge photo is portrait, so this is the orientation that
        // actually ships.
        XCTAssertEqual(decoded.size.width, 512)
        XCTAssertEqual(decoded.size.height, 1024)
    }

    func testPreservesAspectRatioOnNonIntegerScales() throws {
        let source = makeImage(width: 1500, height: 500)

        let encoded = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.8)
        )
        let decoded = try decodeImage(from: encoded)

        XCTAssertEqual(max(decoded.size.width, decoded.size.height), 1024,
                       "The longest edge must land exactly on the cap.")
        // 3:1 in, 3:1 out — within a pixel, since the implementation floors
        // both dimensions independently.
        let ratio = decoded.size.width / decoded.size.height
        XCTAssertEqual(ratio, 3.0, accuracy: 0.02)
    }

    func testDoesNotUpscaleImagesSmallerThanTheCap() throws {
        let source = makeImage(width: 400, height: 300)

        let encoded = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.8)
        )
        let decoded = try decodeImage(from: encoded)

        // Upscaling would add bytes and zero recognition detail.
        XCTAssertEqual(decoded.size.width, 400)
        XCTAssertEqual(decoded.size.height, 300)
    }

    func testLeavesImagesExactlyAtTheCapUntouched() throws {
        let source = makeImage(width: 1024, height: 768)

        let encoded = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.8)
        )
        let decoded = try decodeImage(from: encoded)

        XCTAssertEqual(decoded.size.width, 1024)
        XCTAssertEqual(decoded.size.height, 768)
    }

    // MARK: - Data URL shape

    func testProducesADataURLTheChatCompletionsAPIAccepts() throws {
        let source = makeImage(width: 800, height: 600)

        let encoded = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.8)
        )

        // The `image_url` content part requires this exact prefix form.
        XCTAssertTrue(encoded.hasPrefix("data:image/jpeg;base64,"))
        let base64 = String(encoded.dropFirst("data:image/jpeg;base64,".count))
        XCTAssertFalse(base64.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: base64),
                        "The payload must be decodable base64, not a raw byte string.")
    }

    // MARK: - Quality

    func testLowerQualityProducesASmallerPayload() throws {
        let source = makeDetailedImage(width: 1024, height: 1024)

        let low = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.1)
        )
        let high = try XCTUnwrap(
            OpenAIIngredientService.encodeAsJPEGDataURL(source, maxEdge: 1024, quality: 0.9)
        )

        // Guards the assumption behind shipping at 0.8 rather than 1.0.
        XCTAssertLessThan(low.count, high.count)
    }

    // MARK: - Fixtures

    /// A flat-colour image at `scale = 1`, so `size` is in pixels.
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        return renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero,
                                size: CGSize(width: width, height: height)))
        }
    }

    /// A noisy image, so JPEG quality actually changes the encoded size.
    /// A flat fill compresses to nearly the same bytes at any quality, which
    /// would make the quality assertion pass or fail by luck.
    private func makeDetailedImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        return renderer.image { context in
            for row in stride(from: 0, to: Int(height), by: 4) {
                for column in stride(from: 0, to: Int(width), by: 4) {
                    // Deterministic pseudo-noise — no RNG, so payload sizes
                    // are stable across runs.
                    let shade = CGFloat((row * 7 + column * 13) % 255) / 255
                    UIColor(red: shade, green: 1 - shade, blue: shade, alpha: 1).setFill()
                    context.fill(CGRect(x: column, y: row, width: 4, height: 4))
                }
            }
        }
    }

    private func decodeImage(from dataURL: String) throws -> UIImage {
        let prefix = "data:image/jpeg;base64,"
        XCTAssertTrue(dataURL.hasPrefix(prefix))
        let base64 = String(dataURL.dropFirst(prefix.count))
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        return try XCTUnwrap(UIImage(data: data))
    }
}
