//
//  CameraEnvironment.swift
//  SousAI
//
//  The three facts `CameraController` needs to learn from the outside
//  world before it can show a viewfinder:
//
//      1. Has the user granted camera access?
//      2. If they haven't been asked yet, ask them.
//      3. Is there actually a capture device on this hardware?
//
//  All three are static-global reads on `AVCaptureDevice` in production,
//  which makes the controller's state machine untestable if it calls them
//  directly. Wrapping them in one protocol is the entire test seam: a
//  fake can report `.denied`, or report `.authorized` with no device
//  (exactly the Simulator's situation), and the controller's transitions
//  can be asserted without any hardware.
//
//  Why one protocol and not three:
//    • All three answers come from the same source (the device
//      environment) and are needed at the same moment (`prepare()`).
//      Splitting them would mean three injection points on the
//      initializer for one conceptual dependency.
//    • `makeVideoDevice()` returns the real `AVCaptureDevice?` rather
//      than a Bool because the authorized-with-hardware path genuinely
//      needs the object. Fakes return `nil`, which is why the
//      no-camera branch is the one that's unit-testable and the
//      happy path is device-only. See `CameraControllerTests`.
//

import AVFoundation

/// The camera-permission and hardware-availability facts
/// `CameraController` depends on. Injected so tests can drive the state
/// machine without a real capture device.
protocol CameraEnvironment {

    /// The current camera authorization status for video capture.
    var authorizationStatus: AVAuthorizationStatus { get }

    /// Prompts the user for camera access. Returns whether it was
    /// granted. Only meaningful when `authorizationStatus` is
    /// `.notDetermined` — the system shows the prompt at most once per
    /// install.
    func requestAccess() async -> Bool

    /// The device to capture with, or `nil` when this hardware has none
    /// (the Simulator, or an iPad with the rear camera disabled by
    /// policy).
    func makeVideoDevice() -> AVCaptureDevice?
}

/// The production implementation — thin pass-throughs to `AVCaptureDevice`.
///
/// Prefers the rear wide-angle camera, which is the right lens for a
/// fridge interior: `.builtInWideAngleCamera` exists on every iPhone and
/// iPad that has a rear camera, where `.builtInUltraWideCamera` and the
/// telephoto do not.
struct SystemCameraEnvironment: CameraEnvironment {

    var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func makeVideoDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera,
                                for: .video,
                                position: .back)
            // Fall back to any video device rather than failing outright
            // — a front-only configuration is still better than a dead
            // viewfinder.
            ?? AVCaptureDevice.default(for: .video)
    }
}
