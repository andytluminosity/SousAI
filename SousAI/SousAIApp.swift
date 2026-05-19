//
//  SousAIApp.swift
//  SousAI
//
//  App entry point. The hero is shown immediately — no splash, no chrome.
//

import SwiftUI

@main
struct SousAIApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView(onScanFridge: {
                // TODO: route into the camera / scan flow when implemented.
                #if DEBUG
                print("SousAI · Scan Your Fridge tapped")
                #endif
            })
            .preferredColorScheme(.dark)
        }
    }
}
