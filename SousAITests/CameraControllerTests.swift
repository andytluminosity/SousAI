//
//  CameraControllerTests.swift
//  SousAITests
//
//  Covers `CameraController`'s permission and availability state machine.
//
//  What is and isn't testable here, stated plainly:
//    • Every path that ends WITHOUT a live session is covered — denied,
//      restricted, declined-at-prompt, and authorized-but-no-hardware.
//      Those are the paths a fake `CameraEnvironment` can drive, and
//      they're also the paths a user is most likely to hit and most
//      likely to be stranded by.
//    • The authorized-WITH-hardware path is deliberately not covered.
//      `AVCaptureDevice` cannot be constructed or subclassed, so there is
//      no honest way to fake one; reaching `.running` requires a physical
//      device. Asserting it here would mean testing a mock instead of the
//      code, which is worse than an acknowledged gap.
//
//  The re-prompt test is the one with real teeth: iOS shows the camera
//  permission alert at most once per install, so a controller that asks
//  again after a denial silently does nothing and leaves the user on a
//  dead screen with no way forward.
//

import AVFoundation
import XCTest

@testable import SousAI

@MainActor
final class CameraControllerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsIdle() {
        let controller = CameraController(environment: FakeCameraEnvironment(status: .notDetermined))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.canCapture)
    }

    // MARK: - Permission already resolved

    func testDeniedStatusResolvesToPermissionDeniedWithoutPrompting() async {
        let environment = FakeCameraEnvironment(status: .denied)
        let controller = CameraController(environment: environment)

        await controller.prepare()

        XCTAssertEqual(controller.state, .permissionDenied)
        XCTAssertEqual(environment.requestAccessCallCount, 0,
                       "A denied status must not trigger another system prompt.")
        XCTAssertFalse(controller.canCapture)
    }

    func testRestrictedStatusResolvesToPermissionDenied() async {
        let environment = FakeCameraEnvironment(status: .restricted)
        let controller = CameraController(environment: environment)

        await controller.prepare()

        // Restricted means an MDM policy forbids the camera. There is no
        // prompt that can change it, so it collapses into the same state.
        XCTAssertEqual(controller.state, .permissionDenied)
        XCTAssertEqual(environment.requestAccessCallCount, 0)
    }

    // MARK: - Permission prompt

    func testDecliningThePromptResolvesToPermissionDenied() async {
        let environment = FakeCameraEnvironment(status: .notDetermined,
                                                grantsAccess: false)
        let controller = CameraController(environment: environment)

        await controller.prepare()

        XCTAssertEqual(controller.state, .permissionDenied)
        XCTAssertEqual(environment.requestAccessCallCount, 1)
    }

    func testDecliningThePromptDoesNotRePromptOnSecondPrepare() async {
        let environment = FakeCameraEnvironment(status: .notDetermined,
                                                grantsAccess: false)
        let controller = CameraController(environment: environment)

        // Simulates leaving the screen and coming back — `.task` fires
        // `prepare()` again on every appearance.
        await controller.prepare()
        await controller.prepare()

        XCTAssertEqual(controller.state, .permissionDenied)
        XCTAssertEqual(environment.requestAccessCallCount, 1,
                       "iOS only shows the permission alert once per install; asking again is a silent no-op that strands the user.")
    }

    func testGrantingThePromptWithNoHardwareResolvesToUnavailable() async {
        let environment = FakeCameraEnvironment(status: .notDetermined,
                                                grantsAccess: true)
        let controller = CameraController(environment: environment)

        await controller.prepare()

        // Permission was granted, but there is no capture device — the
        // Simulator's exact situation.
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertEqual(environment.requestAccessCallCount, 1)
        XCTAssertFalse(controller.canCapture)
    }

    // MARK: - Hardware availability

    func testAuthorizedWithNoHardwareResolvesToUnavailable() async {
        let environment = FakeCameraEnvironment(status: .authorized)
        let controller = CameraController(environment: environment)

        await controller.prepare()

        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertEqual(environment.requestAccessCallCount, 0,
                       "An already-authorized status needs no prompt.")
    }

    // MARK: - Capture guards

    func testCapturePhotoThrowsWhenSessionIsNotRunning() async {
        let controller = CameraController(environment: FakeCameraEnvironment(status: .denied))
        await controller.prepare()

        do {
            _ = try await controller.capturePhoto()
            XCTFail("Capturing without a running session must throw.")
        } catch let error as CameraError {
            guard case .sessionNotRunning = error else {
                return XCTFail("Expected .sessionNotRunning, got \(error).")
            }
        } catch {
            XCTFail("Expected CameraError, got \(error).")
        }
    }

    // MARK: - Lifecycle guards

    func testStopLeavesStateUntouchedWhenNeverConfigured() async {
        let environment = FakeCameraEnvironment(status: .authorized)
        let controller = CameraController(environment: environment)
        await controller.prepare()
        XCTAssertEqual(controller.state, .unavailable)

        // `onDisappear` calls this unconditionally, including on a screen
        // that never got a session. It must not rewrite the state the
        // caption is driven from.
        controller.stop()

        XCTAssertEqual(controller.state, .unavailable)
    }

    func testStartIsIgnoredWhenNeverConfigured() async {
        let controller = CameraController(environment: FakeCameraEnvironment(status: .denied))
        await controller.prepare()

        // The `scenePhase` watcher calls `start()` on every foreground,
        // including when permission was denied.
        controller.start()

        XCTAssertEqual(controller.state, .permissionDenied,
                       "Foregrounding must not promote a denied screen to running.")
        XCTAssertFalse(controller.canCapture)
    }
}

// MARK: - Fake environment

/// Drives `CameraController` without hardware.
///
/// `makeVideoDevice()` always returns `nil` because `AVCaptureDevice` has
/// no public initializer and is not subclassable — see the file header for
/// why that bounds this suite rather than being papered over.
private final class FakeCameraEnvironment: CameraEnvironment {

    private(set) var requestAccessCallCount = 0

    var authorizationStatus: AVAuthorizationStatus
    private let grantsAccess: Bool

    init(status: AVAuthorizationStatus, grantsAccess: Bool = false) {
        self.authorizationStatus = status
        self.grantsAccess = grantsAccess
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        // Mirror the real system: once the user answers, the status is no
        // longer `.notDetermined`. Without this the re-prompt test would
        // pass for the wrong reason.
        authorizationStatus = grantsAccess ? .authorized : .denied
        return grantsAccess
    }

    func makeVideoDevice() -> AVCaptureDevice? { nil }
}
