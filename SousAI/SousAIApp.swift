//
//  SousAIApp.swift
//  SousAI
//
//  App entry point.
//
//  The root view is a single `NavigationStack` that owns the navigation path
//  for the entire capture flow:
//
//      HomeView ─► CameraView ─► PhotoConfirmationView ─► AnalysisLoadingView
//
//  All push/pop happens through `AppRoute` cases so the path stays
//  inspectable and reversible. The path itself lives here so children can
//  reset it (e.g. PhotoConfirmationView's close X clears back to Home).
//

import SwiftUI

@main
struct SousAIApp: App {

    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(onScanFridge: {
                    path.append(AppRoute.camera)
                })
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .camera:
                        CameraView(path: $path)
                    case .confirmation(let photo):
                        PhotoConfirmationView(photo: photo, path: $path)
                    case .analyzing(let photo):
                        AnalysisLoadingView(photo: photo, path: $path)
                    }
                }
            }
            .tint(AppColor.primaryOnDark)
            .preferredColorScheme(.dark)
        }
    }
}
