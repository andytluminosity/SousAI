//
//  ViewfinderFrame.swift
//  SousAI
//
//  The four L-shaped corner brackets that frame the camera composition area.
//
//  Design intent (document-scanner grammar):
//    • Four L-brackets at the corners — nothing else. No center reticle, no
//      rule-of-thirds grid, no rangefinder ticks.
//    • Strokes are quiet: bodyOnDark @ 0.35, 1.5pt — present but easy to
//      look past so the composition (not the chrome) holds the eye.
//    • Bracket arms are ~24pt long — short enough to feel like punctuation,
//      long enough to read as a frame.
//    • Pure `Shape`. No state, no animation, no interaction.
//

import SwiftUI

/// A `Shape` that draws four L-brackets at the corners of its bounding rect.
///
/// Use as an overlay on top of a photographic viewfinder area:
///
/// ```
/// ViewfinderPlaceholder()
///     .aspectRatio(3.0/4.0, contentMode: .fit)
///     .overlay(ViewfinderFrame(armLength: 28)
///         .stroke(AppColor.bodyOnDark.opacity(0.35), lineWidth: 1.5))
/// ```
struct ViewfinderFrame: Shape {

    /// Length of each arm of the L from the corner outward.
    var armLength: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let topLeft     = CGPoint(x: rect.minX, y: rect.minY)
        let topRight    = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomLeft  = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)

        // Top-left L: down then right.
        path.move(to: CGPoint(x: topLeft.x, y: topLeft.y + armLength))
        path.addLine(to: topLeft)
        path.addLine(to: CGPoint(x: topLeft.x + armLength, y: topLeft.y))

        // Top-right L: left then down.
        path.move(to: CGPoint(x: topRight.x - armLength, y: topRight.y))
        path.addLine(to: topRight)
        path.addLine(to: CGPoint(x: topRight.x, y: topRight.y + armLength))

        // Bottom-left L: up then right.
        path.move(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - armLength))
        path.addLine(to: bottomLeft)
        path.addLine(to: CGPoint(x: bottomLeft.x + armLength, y: bottomLeft.y))

        // Bottom-right L: left then up.
        path.move(to: CGPoint(x: bottomRight.x - armLength, y: bottomRight.y))
        path.addLine(to: bottomRight)
        path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - armLength))

        return path
    }
}

// MARK: - Previews

#Preview("ViewfinderFrame — dark") {
    ZStack {
        AppColor.surfaceBlack.ignoresSafeArea()
        ViewfinderFrame(armLength: 28)
            .stroke(AppColor.bodyOnDark.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .padding(AppSpacing.xl)
    }
    .preferredColorScheme(.dark)
}
