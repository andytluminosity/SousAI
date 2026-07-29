//
//  CameraView.swift
//  SousAI
//
//  The immersive capture screen.
//
//  Design intent (per the brief + DESIGN.md):
//    • Full-bleed AppColor.surfaceBlack canvas — the only place in the app
//      where pure black appears, per DESIGN.md's "edge-to-edge photographic
//      overlay" rule. Distinct from HomeView's surface-tile-1 hero.
//    • UI recedes: a single translucent close chip, a quiet eyebrow, a
//      one-line caption, three bottom controls. Nothing else.
//    • Motion is restrained: 0.5s ease-out fade on chrome only; the
//      viewfinder snaps in instantly so the user can compose.
//
//  Capture (live):
//    • `CameraController` owns the `AVCaptureSession`; this screen owns the
//      controller in `@State` and switches its viewfinder on
//      `controller.state`. The previous mock — a gradient rasterized by
//      `synthesizeCapture()` — is gone.
//    • The viewfinder slot renders `CameraPreviewView` when the session is
//      running and `ViewfinderPlaceholderCanvas` in every other state.
//      That keeps this screen's composition previewable on a Mac, where
//      no capture device exists, and gives permission-denied a home that
//      isn't a modal alert (consistent with AnalysisLoadingView, which
//      also keeps failure inside the composition the user is looking at).
//    • The shutter is armed only in `.running`. When there is no camera
//      the caption steers to the photo-library button instead, which
//      still feeds a real photo into the vision call — so the Simulator
//      can exercise the whole AI pipeline.
//
//  Lifecycle:
//    • `.task` prepares the session on appear. `prepare()` is idempotent,
//      so returning to this screen restarts rather than reconfigures.
//    • `.onDisappear` and a `scenePhase` watcher stop the session, so the
//      camera indicator goes out and the device stops burning power the
//      moment the screen is left or the app is backgrounded.
//
//  Orientation:
//    • Portrait-locked while on screen (see `PortraitLock` below). The
//      preview connection and the still capture are both hard-pinned to
//      `CameraController.portraitRotationAngle`, so letting the UI rotate
//      underneath them would show a sideways feed. The rest of the app
//      keeps its declared landscape support.
//

import SwiftUI
import PhotosUI
import UIKit

struct CameraView: View {

    // MARK: - Navigation

    @Binding var path: NavigationPath

    // MARK: - Capture

    @State private var controller = CameraController()

    // MARK: - Local state

    @Environment(\.scenePhase) private var scenePhase

    @State private var chromeVisible = false
    @State private var flashOpacity: Double = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var captureError: String?

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColor.surfaceBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .opacity(chromeVisible ? 1 : 0)

                Spacer(minLength: AppSpacing.lg)

                viewfinder

                Spacer(minLength: AppSpacing.lg)

                bottomControls
                    .opacity(chromeVisible ? 1 : 0)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.xl)

            // Shutter flash — sits above everything, briefly white.
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            PortraitLock.engage()
            withAnimation(.easeOut(duration: 0.5)) {
                chromeVisible = true
            }
        }
        .task {
            await controller.prepare()
        }
        .onDisappear {
            controller.stop()
            PortraitLock.release()
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding must release the camera; foregrounding brings
            // it back without re-prompting or reconfiguring.
            switch phase {
            case .active:   controller.start()
            case .inactive, .background: controller.stop()
            @unknown default: break
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedImage(from: newItem) }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            CircularIconButton(systemName: "xmark",
                               accessibilityLabel: "Close camera") {
                if !path.isEmpty { path.removeLast() }
            }

            Spacer()

            Text("SCAN")
                .font(AppTypography.brandEyebrow)
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyOnDark.opacity(0.35))

            Spacer()

            // Symmetry placeholder — keeps the eyebrow optically centered.
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                // The live feed when there is one; the placeholder wash
                // otherwise. Both sit under the same corner marks so the
                // frame reads identically in every state.
                if controller.state == .running {
                    CameraPreviewView(session: controller.session)
                        .clipped()
                        .transition(.opacity)
                } else {
                    ViewfinderPlaceholderCanvas()
                        .clipped()
                        .transition(.opacity)
                }

                ViewfinderFrame(armLength: 28)
                    .stroke(AppColor.bodyOnDark.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.35), value: controller.state)

            captionStack
        }
    }

    /// The single line beneath the frame, plus the one affordance that
    /// only permission-denied needs. Everything the user is told about
    /// camera state lives here — no alerts, no sheets.
    private var captionStack: some View {
        VStack(spacing: AppSpacing.sm) {
            Text(captionText)
                .font(AppTypography.caption)
                .tracking(AppTypography.captionTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if controller.state == .permissionDenied {
                SecondaryGhostButton("Open Settings") {
                    PortraitLock.openSettings()
                }
            }
        }
    }

    /// Caption copy per capture state. `captureError` takes precedence —
    /// a failed shutter is the most recent thing the user did, so it's
    /// the most relevant thing to tell them.
    private var captionText: String {
        if let captureError { return captureError }

        switch controller.state {
        case .running:
            return "Center your open fridge in the frame."
        case .idle, .preparing:
            return "Starting the camera…"
        case .unavailable:
            return "No camera here — pick a photo from your library instead."
        case .permissionDenied:
            return "SousAI needs camera access to scan your fridge. You can also pick a photo from your library."
        case .failed(let message):
            return message
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        HStack(alignment: .center) {
            PhotosPicker(selection: $pickerItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(AppColor.bodyOnDark)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .fill(AppColor.surfaceBlack.opacity(0.18))
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("Choose from library")

            Spacer()

            shutterButton

            Spacer()

            // Reserved — flash/flip will land here in a later pass.
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    /// Dims and disables itself outside `.running`, so the only tappable
    /// path when there is no camera is the library button.
    private var shutterButton: some View {
        Button(action: handleShutter) {
            ZStack {
                Circle()
                    .stroke(AppColor.bodyOnDark.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(AppColor.bodyOnDark)
                    .frame(width: 60, height: 60)
            }
            .contentShape(Circle())
        }
        .buttonStyle(AppPressStyle())
        .disabled(!controller.canCapture || isCapturing)
        .opacity(controller.canCapture ? 1 : 0.35)
        .animation(.easeOut(duration: 0.25), value: controller.canCapture)
        .accessibilityLabel("Capture photo")
    }

    // MARK: - Capture

    private func handleShutter() {
        guard controller.canCapture, !isCapturing else { return }
        isCapturing = true
        captureError = nil

        let feedback = UIImpactFeedbackGenerator(style: .heavy)
        feedback.impactOccurred()

        // Cinematic shutter flash. Fires immediately on tap rather than
        // on the photo callback — the flash is feedback for the *tap*,
        // and waiting for AVFoundation would make it feel laggy.
        withAnimation(.easeOut(duration: 0.08)) {
            flashOpacity = 0.6
        }
        withAnimation(.easeOut(duration: 0.18).delay(0.10)) {
            flashOpacity = 0
        }

        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let image = try await controller.capturePhoto()
                path.append(AppRoute.confirmation(CapturedPhoto(image: image)))
            } catch {
                captureError = "That shot didn't take. Try again."
                #if DEBUG
                print("SousAI: photo capture failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    @MainActor
    private func loadPickedImage(from item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else { return }
        path.append(AppRoute.confirmation(CapturedPhoto(image: image)))
    }
}

// MARK: - Portrait lock

/// Pins the interface to portrait for the lifetime of the capture screen.
///
/// Both the preview connection and the still capture are hard-pinned to
/// `CameraController.portraitRotationAngle`, so allowing the UI to rotate
/// underneath them would show a sideways feed. Locking the screen is the
/// cheap half of that trade — the alternative is tracking rotation with an
/// `AVCaptureDevice.RotationCoordinator` and reflowing a 3:4 viewfinder
/// into landscape.
///
/// `requestGeometryUpdate` is the supported iOS 16+ mechanism. The older
/// trick — setting `UIDevice.orientation` by KVC — is private API and gets
/// apps rejected. Requests are intersected with the Info.plist orientation
/// set, so `release()` can ask for `.all` and let the system clamp it back
/// to whatever the app actually declares.
private enum PortraitLock {

    static func engage() { request(.portrait) }

    static func release() { request(.all) }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func request(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
    }
}

// MARK: - Previews

#Preview("CameraView — iPhone 15 Pro") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        CameraView(path: path)
    }
}

/// Tiny helper that lets us hand a `Binding<NavigationPath>` to a `#Preview`.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value,
         @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
