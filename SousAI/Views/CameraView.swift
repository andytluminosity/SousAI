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
//    • The "live feed" is mocked by `ViewfinderPlaceholderCanvas` — a soft
//      warm/cool radial wash that reads as a photographic frame. It will be
//      replaced 1:1 by an AVCaptureVideoPreviewLayer in a later pass.
//    • The shutter tap rasterizes that same canvas via SwiftUI's
//      `ImageRenderer` into a real UIImage, so what the user "captured" is
//      visually identical to what they were composing.
//    • Motion is restrained: 0.5s ease-out fade on chrome only; the
//      viewfinder snaps in instantly so the user can compose.
//
//  Future-proofing seams:
//    • Replace `ViewfinderPlaceholderCanvas` with a UIViewRepresentable that
//      hosts an AVCaptureVideoPreviewLayer.
//    • Replace `synthesizeCapture()` with an AVCapturePhotoOutput delegate
//      callback that hands back a UIImage.
//

import SwiftUI
import PhotosUI
import UIKit

struct CameraView: View {

    // MARK: - Navigation

    @Binding var path: NavigationPath

    // MARK: - Local state

    @State private var chromeVisible = false
    @State private var flashOpacity: Double = 0
    @State private var pickerItem: PhotosPickerItem?

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
            withAnimation(.easeOut(duration: 0.5)) {
                chromeVisible = true
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
                ViewfinderPlaceholderCanvas()
                    .clipped()

                ViewfinderFrame(armLength: 28)
                    .stroke(AppColor.bodyOnDark.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            Text("Center your open fridge in the frame.")
                .font(AppTypography.caption)
                .tracking(AppTypography.captionTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
        .accessibilityLabel("Capture photo")
    }

    // MARK: - Capture

    private func handleShutter() {
        let feedback = UIImpactFeedbackGenerator(style: .heavy)
        feedback.impactOccurred()

        // Cinematic shutter flash.
        withAnimation(.easeOut(duration: 0.08)) {
            flashOpacity = 0.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.18)) {
                flashOpacity = 0
            }
        }

        // Rasterize the placeholder canvas into a real UIImage. This is the
        // exact site that swaps for AVCapturePhotoOutput later.
        guard let captured = synthesizeCapture() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            path.append(AppRoute.confirmation(CapturedPhoto(image: captured)))
        }
    }

    private func synthesizeCapture() -> UIImage? {
        let canvas = ViewfinderPlaceholderCanvas()
            .frame(width: 1024, height: 1365)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
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

// MARK: - Viewfinder placeholder canvas

/// The visual stand-in for a live camera feed.
///
/// A warm fill light and a cool rim light wash over `surfaceTile1` to mimic
/// the soft, photographic feel of an out-of-focus frame. Used both inside
/// the live viewfinder *and* rasterized into the captured `UIImage` — so the
/// captured "photo" matches what the user composed.
struct ViewfinderPlaceholderCanvas: View {
    var body: some View {
        ZStack {
            AppColor.surfaceTile1

            Circle()
                .fill(Color(red: 1.00, green: 0.78, blue: 0.55))
                .blur(radius: 140)
                .opacity(0.18)
                .scaleEffect(1.4)
                .offset(x: -120, y: -180)
                .blendMode(.screen)

            Circle()
                .fill(Color(red: 0.55, green: 0.72, blue: 1.00))
                .blur(radius: 130)
                .opacity(0.12)
                .scaleEffect(1.2)
                .offset(x: 140, y: 220)
                .blendMode(.screen)

            Circle()
                .fill(Color.white)
                .blur(radius: 110)
                .opacity(0.05)
                .scaleEffect(0.6)
                .offset(x: 30, y: -60)
                .blendMode(.screen)
        }
        .clipped()
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
