//
//  PhotoConfirmationView.swift
//  SousAI
//
//  The cinematic confirmation screen for a freshly captured fridge photo.
//
//  Design intent (per the brief + DESIGN.md):
//    • Photography-first composition: the photo is the hero, edge-to-edge,
//      no rounding (DESIGN.md `rounded.none` for full-bleed tiles), no
//      shadow, no decorative frame. The image speaks; the UI recedes.
//    • Pure black `surface-black` canvas — so nothing competes with the
//      photograph. DESIGN.md reserves this hex for edge-to-edge photographic
//      overlays, which is exactly what this screen is.
//    • Two CTAs only:
//        – Primary: "Use This Photo"  — Action Blue pill (`PrimaryPillButton`)
//        – Secondary: "Retake"        — ghost capsule in Sky Link Blue
//      Vertical stack. Primary above secondary. No third option.
//    • Caption: a single quiet line ("Looks good?") in `displayMedium`.
//      Sets the question, then steps out of the way.
//    • Motion: 0.4s ease-out fade + 1.02 → 1.0 scale on the image only.
//      Cinematic, restrained. No springs, no rotations.
//

import SwiftUI

struct PhotoConfirmationView: View {

    // MARK: - Inputs

    let photo: CapturedPhoto
    @Binding var path: NavigationPath

    // MARK: - Local state

    @State private var imageVisible = false
    @State private var chromeVisible = false

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColor.surfaceBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xs)
                    .opacity(chromeVisible ? 1 : 0)

                Spacer(minLength: AppSpacing.lg)

                heroImage

                Spacer(minLength: AppSpacing.lg)

                caption
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
                    .opacity(chromeVisible ? 1 : 0)

                ctaCluster
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
                    .opacity(chromeVisible ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: animateEntrance)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            CircularIconButton(systemName: "xmark",
                               accessibilityLabel: "Discard and go home") {
                path = NavigationPath()
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Hero image

    private var heroImage: some View {
        Image(uiImage: photo.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .opacity(imageVisible ? 1 : 0)
            .scaleEffect(imageVisible ? 1.0 : 1.02)
    }

    // MARK: - Caption

    private var caption: some View {
        Text("Looks good?")
            .font(AppTypography.displayMedium)
            .tracking(AppTypography.displayMediumTracking)
            .foregroundColor(AppColor.bodyOnDark)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }

    // MARK: - CTA cluster

    private var ctaCluster: some View {
        VStack(spacing: AppSpacing.sm) {
            PrimaryPillButton("Use This Photo",
                              icon: "sparkles") {
                path.append(AppRoute.analyzing(photo))
            }

            SecondaryGhostButton("Retake",
                                 icon: "arrow.counterclockwise") {
                if !path.isEmpty { path.removeLast() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entrance

    private func animateEntrance() {
        withAnimation(.easeOut(duration: 0.4)) {
            imageVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.18)) {
            chromeVisible = true
        }
    }
}

// MARK: - Previews

#Preview("PhotoConfirmationView") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        PhotoConfirmationView(
            photo: CapturedPhoto(image: previewImage()),
            path: path
        )
    }
}

/// Produces a real photographic-feeling UIImage for SwiftUI previews by
/// rasterizing the same canvas the CameraView uses for its mock feed.
@MainActor
private func previewImage() -> UIImage {
    let renderer = ImageRenderer(content:
        ViewfinderPlaceholderCanvas()
            .frame(width: 1024, height: 1365)
    )
    renderer.scale = 2
    return renderer.uiImage ?? UIImage()
}

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
