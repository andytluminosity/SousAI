//
//  CameraController.swift
//  SousAI
//
//  Owns the live capture session behind CameraView.
//
//  This is the type that replaced the mocked `synthesizeCapture()`. The
//  screen used to rasterize a gradient into a `UIImage`; it now drives a
//  real `AVCaptureSession` and hands `AVCapturePhotoOutput`'s result
//  straight into `CapturedPhoto` — the same value the rest of the flow
//  already carried, so nothing downstream of `AppRoute.confirmation`
//  changed.
//
//  Shape:
//    • One `State` enum the view switches on. This is the whole public
//      surface besides `prepare/start/stop/capturePhoto` — the view never
//      touches an AVFoundation type except `session`, which it hands to
//      `CameraPreviewView` unread.
//    • `@Observable` (iOS 17+) so state changes re-render the viewfinder
//      without an `ObservableObject` + `@Published` ceremony. This is the
//      first observation-based type in the app; every other screen's
//      state is plain `@State`, which stays true — `CameraView` holds
//      this controller in a `@State` of its own.
//    • `@MainActor` on the class, because every state mutation feeds
//      SwiftUI. All AVFoundation work is pushed to `sessionQueue`.
//
//  Threading, which AVFoundation is strict about:
//    • `startRunning()` BLOCKS — commonly 100-400ms while the camera
//      warms up. Calling it on the main thread hitches the entrance
//      animation the screen plays on appear. Every session mutation
//      (configure / start / stop / capture) therefore goes through one
//      private serial queue.
//    • State is written back on the main actor via `await`, so the view
//      only ever observes a settled value.
//    • `AVCaptureVideoPreviewLayer` is the exception: it is UIKit and
//      must be created and attached on the main thread. That is why it
//      lives in `CameraPreviewView` rather than in here — this type
//      never touches the layer.
//
//  Orientation:
//    • CameraView is portrait-locked (see `PortraitLock` in that file),
//      so both the preview connection and the photo connection are
//      pinned to `portraitRotationAngle` once at configuration time
//      rather than tracked with an `AVCaptureDevice.RotationCoordinator`.
//      One constant, no observation.
//    • Capture requests JPEG so `UIImage(data:)` reads the EXIF
//      orientation tag AVFoundation writes and hands back an upright
//      image. `OpenAIIngredientService.downscale` redraws through
//      `UIGraphicsImageRenderer`, which bakes that orientation in — so
//      the vision call receives an upright photo with no extra work.
//

// `@preconcurrency` because AVFoundation predates `Sendable` annotation:
// `AVCaptureSession`, `AVCaptureDevice`, and `AVCapturePhotoOutput` are all
// unannotated, so handing them to `sessionQueue.async` warns even though
// serial-queue confinement is precisely the usage Apple documents for
// them. The confinement invariant is enforced here by never touching those
// objects outside `sessionQueue` (the sole exception is `session`, which is
// handed to `CameraPreviewView` for main-thread layer attachment — a read
// of object identity, not a mutation).
@preconcurrency import AVFoundation
import UIKit

// MARK: - Errors

enum CameraError: Error, LocalizedError {
    case sessionNotRunning
    case noDevice
    case configurationFailed(String)
    case captureFailed(String)
    case noImageData

    var errorDescription: String? {
        switch self {
        case .sessionNotRunning:
            return "The camera isn't running."
        case .noDevice:
            return "No camera is available on this device."
        case .configurationFailed(let detail):
            return "Could not start the camera: \(detail)"
        case .captureFailed(let detail):
            return "Could not take the photo: \(detail)"
        case .noImageData:
            return "The camera returned an empty photo."
        }
    }
}

// MARK: - Controller

@Observable
@MainActor
final class CameraController {

    /// What the viewfinder should be showing. `CameraView` switches on
    /// this and nothing else.
    enum State: Equatable {
        /// Nothing attempted yet — the initial value.
        case idle
        /// Asking for permission, or configuring the session.
        case preparing
        /// Live preview is up; the shutter is armed.
        case running
        /// The user declined, or an MDM policy forbids the camera.
        /// Terminal for this launch — the system prompt only appears
        /// once per install, so the only way forward is Settings.
        case permissionDenied
        /// This hardware has no capture device. The Simulator always
        /// lands here, which is why the screen keeps its placeholder
        /// canvas and steers to the photo library.
        case unavailable
        /// Configuration or a runtime failure. Carries user-facing copy.
        case failed(String)
    }

    // MARK: Observable state

    private(set) var state: State = .idle

    /// Whether the shutter should accept a tap.
    var canCapture: Bool { state == .running }

    // MARK: Collaborators

    /// Handed to `CameraPreviewView`, which attaches it to its layer.
    /// Not observed — the session object identity never changes, only
    /// its running state, which `state` already describes.
    @ObservationIgnored
    let session = AVCaptureSession()

    @ObservationIgnored
    private let environment: CameraEnvironment

    @ObservationIgnored
    private let photoOutput = AVCapturePhotoOutput()

    /// Serialises every session mutation off the main thread.
    @ObservationIgnored
    private let sessionQueue = DispatchQueue(label: "vc.axl.SousAI.camera.session")

    /// `AVCapturePhotoOutput` does not retain its delegate, so we hold it
    /// for the lifetime of the capture and release it in the callback.
    @ObservationIgnored
    private var captureDelegate: PhotoCaptureDelegate?

    @ObservationIgnored
    private var isConfigured = false

    /// Portrait. `AVCaptureConnection.videoRotationAngle` (iOS 17+) is
    /// degrees clockwise from the sensor's native landscape orientation,
    /// so 90 is portrait for a rear camera. Applied to the photo
    /// connection here and to the preview connection in
    /// `CameraPreviewView`.
    static let portraitRotationAngle: CGFloat = 90

    init(environment: CameraEnvironment = SystemCameraEnvironment()) {
        self.environment = environment
    }

    // MARK: - Lifecycle

    /// Resolves permission, then configures and starts the session.
    /// Idempotent: safe to call from `.task` on every appearance — an
    /// already-running session is left alone and an already-configured
    /// one is only restarted.
    func prepare() async {
        switch state {
        case .running, .preparing:
            return
        case .idle, .permissionDenied, .unavailable, .failed:
            break
        }

        // A denied/restricted status can't be recovered in-process, so
        // re-entering the screen shouldn't re-prompt.
        switch environment.authorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            state = .preparing
            guard await environment.requestAccess() else {
                state = .permissionDenied
                return
            }
        case .denied, .restricted:
            state = .permissionDenied
            return
        @unknown default:
            state = .permissionDenied
            return
        }

        state = .preparing

        // Already wired up from a previous visit — just spin it back up.
        if isConfigured {
            startRunningSession()
            state = .running
            return
        }

        guard let device = environment.makeVideoDevice() else {
            state = .unavailable
            return
        }

        do {
            try await configureSession(with: device)
            isConfigured = true
            startRunningSession()
            state = .running
        } catch let error as CameraError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Restarts a session that was stopped by backgrounding. No-op unless
    /// the session was fully configured first.
    func start() {
        guard isConfigured, state != .running else { return }
        startRunningSession()
        state = .running
    }

    /// Stops the session so the camera indicator goes out and the device
    /// stops burning power the moment the screen is left or the app is
    /// backgrounded. Configuration is retained for a cheap restart.
    func stop() {
        guard isConfigured else { return }
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        if state == .running { state = .preparing }
    }

    // MARK: - Capture

    /// Takes a photo and returns it upright.
    ///
    /// Bridges `AVCapturePhotoCaptureDelegate` to `async` so the call site
    /// in `CameraView.handleShutter` reads as one `await` instead of a
    /// completion handler that has to hop back to the main actor itself.
    func capturePhoto() async throws -> UIImage {
        guard state == .running else { throw CameraError.sessionNotRunning }

        let output = photoOutput
        let queue = sessionQueue

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                // Release the retained delegate now the capture is over.
                Task { @MainActor in self?.captureDelegate = nil }
                continuation.resume(with: result)
            }
            captureDelegate = delegate

            queue.async {
                output.capturePhoto(with: Self.makeSettings(for: output),
                                    delegate: delegate)
            }
        }
    }

    /// Requests JPEG when the output offers it.
    ///
    /// The downstream vision call re-encodes to JPEG at quality 0.8
    /// anyway (`OpenAIIngredientService.encodeAsJPEGDataURL`), so asking
    /// for JPEG here costs nothing and sidesteps the HEIC path entirely
    /// — one fewer container for `UIImage(data:)` to interpret.
    ///
    /// `flashMode` is deliberately left at its default (`.auto`): a
    /// fridge interior is usually dim enough to want it, and setting the
    /// property to a value outside `supportedFlashModes` raises an
    /// exception on devices with no flash.
    /// `nonisolated` because it is called from `sessionQueue`, not the main
    /// actor. It reads only its parameter, so there is no isolated state to
    /// protect — without this it would inherit the class's `@MainActor` and
    /// become an actor-hop (or, in Swift 5 mode, a silent violation).
    nonisolated private static func makeSettings(for output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        guard output.availablePhotoCodecTypes.contains(.jpeg) else {
            return AVCapturePhotoSettings()
        }
        return AVCapturePhotoSettings(
            format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
        )
    }

    // MARK: - Session plumbing

    /// Builds the session on `sessionQueue` and resumes on the main actor.
    /// Wrapped in `begin/commitConfiguration` so the session applies the
    /// input and output as one atomic change.
    private func configureSession(with device: AVCaptureDevice) async throws {
        let session = session
        let photoOutput = photoOutput
        let rotation = Self.portraitRotationAngle

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                session.beginConfiguration()

                // `.photo` gives the full-resolution still the vision
                // call wants, and lets AVFoundation pick the best
                // preview format for the device.
                if session.canSetSessionPreset(.photo) {
                    session.sessionPreset = .photo
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        continuation.resume(
                            throwing: CameraError.configurationFailed("the camera input was rejected")
                        )
                        return
                    }
                    session.addInput(input)
                } catch {
                    session.commitConfiguration()
                    continuation.resume(
                        throwing: CameraError.configurationFailed(error.localizedDescription)
                    )
                    return
                }

                guard session.canAddOutput(photoOutput) else {
                    session.commitConfiguration()
                    continuation.resume(
                        throwing: CameraError.configurationFailed("the photo output was rejected")
                    )
                    return
                }
                session.addOutput(photoOutput)

                // Pin the still to portrait. The connection only exists
                // once the output is attached, which is why this sits
                // after `addOutput`.
                if let connection = photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotation) {
                    connection.videoRotationAngle = rotation
                }

                session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    private func startRunningSession() {
        let session = session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }
}

// MARK: - Photo delegate bridge

/// Adapts the one `AVCapturePhotoCaptureDelegate` callback we need into a
/// `Result` handoff, so `capturePhoto()` can stay a single `await`.
///
/// Decodes through `fileDataRepresentation()` rather than
/// `cgImageRepresentation()` on purpose: the file representation carries
/// the EXIF orientation tag, and `UIImage(data:)` applies it. Going
/// through the raw `CGImage` would hand back a sideways photo that we'd
/// then have to rotate by hand.
///
/// `@unchecked Sendable` is sound here by construction: the only stored
/// property is an immutable closure, nothing mutates after `init`, and
/// AVFoundation invokes the callback exactly once on its own queue. The
/// alternative — leaving it non-Sendable — warns at the `sessionQueue.async`
/// that hands it to `capturePhoto(with:delegate:)`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let completion: (Result<UIImage, Error>) -> Void

    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            completion(.failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(.failure(CameraError.noImageData))
            return
        }
        completion(.success(image))
    }
}
