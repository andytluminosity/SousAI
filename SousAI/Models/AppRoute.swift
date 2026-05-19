//
//  AppRoute.swift
//  SousAI
//
//  The single navigation contract for the SousAI capture flow.
//
//  Design intent:
//    • Every screen the user can land on after Home is one case of `AppRoute`,
//      so the NavigationStack path stays inspectable, reversible, and trivial
//      to reason about. No coordinators, no environment-injected stores.
//    • The captured photo rides along as the associated value of the route
//      that needs it — it only exists for as long as it's on the stack.
//    • `CapturedPhoto` Hashes by identity (UUID), not by image pixels. Two
//      navigations of the same photo will produce two distinct stack entries
//      — which is what we want for stack semantics.
//
//  This file is also the future-proof seam: when the mock `ImageRenderer`
//  capture is swapped for real AVFoundation, the `CapturedPhoto` value
//  doesn't change — only its producer does.
//

import UIKit

/// Routes pushable onto the app's `NavigationStack` after `HomeView`.
enum AppRoute: Hashable {
    /// The immersive viewfinder screen.
    case camera

    /// The cinematic full-bleed confirmation screen for a freshly captured photo.
    case confirmation(CapturedPhoto)

    /// The stub "Analyzing your fridge…" loading screen that will host the
    /// future OpenAI vision call.
    case analyzing(CapturedPhoto)
}

/// A captured `UIImage` paired with a stable identity.
///
/// `UIImage` itself is not `Hashable`, and even if it were, hashing by pixel
/// content would defeat NavigationStack's identity model. We hash by `id`
/// so each captured photo is its own distinct stack entry.
struct CapturedPhoto: Hashable, Identifiable {

    let id: UUID
    let image: UIImage

    init(image: UIImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
    }

    static func == (lhs: CapturedPhoto, rhs: CapturedPhoto) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
