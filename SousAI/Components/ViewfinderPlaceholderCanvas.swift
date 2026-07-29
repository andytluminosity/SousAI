//
//  ViewfinderPlaceholderCanvas.swift
//  SousAI
//
//  The visual stand-in for a live camera feed.
//
//  A warm fill light and a cool rim light wash over `surfaceTile1` to
//  mimic the soft, photographic feel of an out-of-focus frame.
//
//  Originally this was also rasterized into the "captured" UIImage by
//  `CameraView.synthesizeCapture()`, back when the camera was mocked.
//  That function is gone — capture is real now (`CameraController`) — so
//  this canvas has one job left: fill the viewfinder frame whenever there
//  is no live feed to show. That happens in four situations:
//
//    • The Simulator and SwiftUI Previews, which have no capture device.
//    • Before permission resolves, on first launch.
//    • After the user denies camera access.
//    • After a session configuration failure.
//
//  Keeping it means `#Preview` still renders CameraView's full
//  composition without hardware, which is the only way to iterate on that
//  screen's layout on a Mac. It moved out of CameraView.swift when the
//  real capture states pushed that file past 400 lines; it lives here
//  next to `ViewfinderFrame`, the corner-mark shape it renders beneath.
//

import SwiftUI

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

#Preview("ViewfinderPlaceholderCanvas") {
    ViewfinderPlaceholderCanvas()
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .padding()
        .background(AppColor.surfaceBlack)
}
