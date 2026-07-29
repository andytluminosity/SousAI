//
//  CameraPreviewView.swift
//  SousAI
//
//  The live camera feed, as a SwiftUI view.
//
//  This is the 1:1 replacement for `ViewfinderPlaceholderCanvas` inside
//  CameraView's viewfinder frame — same slot, same 3:4 aspect ratio, same
//  `ViewfinderFrame` corner marks drawn on top. The placeholder canvas
//  still exists and still renders whenever there is no camera to show
//  (Simulator, Previews, permission denied).
//
//  Why the layer is the view:
//    `layerClass` is overridden so the backing layer of `PreviewUIView`
//    *is* an `AVCaptureVideoPreviewLayer`. UIKit then resizes it with the
//    view for free. The common alternative — adding the preview layer as
//    a sublayer — means mirroring every bounds change by hand in
//    `layoutSubviews`, which is where the "preview is the wrong size on
//    rotation / on first layout" class of bug comes from.
//
//  This type deliberately knows nothing about permission, capture, or
//  state. It takes a session and shows it. Everything else lives in
//  `CameraController`.
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {

    /// The session to display. Owned by `CameraController`; this view
    /// only attaches it.
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        // `.resizeAspectFill` so the feed fills the 3:4 frame with no
        // letterboxing — the sensor is 4:3, so this crops the long edge
        // rather than distorting. What the user frames is what they get.
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        applyPortraitRotation(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        // The connection does not exist until the session has an input,
        // which happens asynchronously on the controller's session queue.
        // Re-applying on update is what catches that.
        applyPortraitRotation(to: uiView)
    }

    /// Pins the preview to portrait, matching the angle the controller
    /// pins the still capture to. CameraView is portrait-locked, so this
    /// is set once rather than tracked with an
    /// `AVCaptureDevice.RotationCoordinator`.
    private func applyPortraitRotation(to view: PreviewUIView) {
        guard let connection = view.previewLayer.connection else { return }
        let angle = CameraController.portraitRotationAngle
        guard connection.isVideoRotationAngleSupported(angle),
              connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }

    /// A `UIView` whose backing layer is the preview layer itself.
    final class PreviewUIView: UIView {

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` above guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
