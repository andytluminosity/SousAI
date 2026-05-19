//
//  AppColor.swift
//  SousAI
//
//  Color tokens mirrored from DESIGN.md.
//  Action Blue is the sole interactive accent; every "tap me" signal uses it.
//  Surfaces are warm-neutral whites, parchment, and a curated near-black ladder.
//

import SwiftUI

enum AppColor {

    // MARK: Brand & Accent
    /// #0066cc — the only brand-level interactive color.
    static let primary = Color(red: 0.0,        green: 0.40,       blue: 0.80)
    /// #0071e3 — used for the keyboard focus ring on buttons.
    static let primaryFocus = Color(red: 0.0,   green: 0.443,      blue: 0.890)
    /// #2997ff — brighter blue reserved for links on dark surfaces.
    static let primaryOnDark = Color(red: 0.161, green: 0.592,     blue: 1.0)

    // MARK: Text
    /// #1d1d1f — the voice of every headline and body line on light surfaces.
    static let ink = Color(red: 0.114,           green: 0.114,     blue: 0.122)
    static let body = ink
    /// White text used on dark tiles and global nav.
    static let bodyOnDark = Color.white
    /// #cccccc — secondary copy on dark tiles.
    static let bodyMuted = Color(red: 0.800,     green: 0.800,     blue: 0.800)
    /// #333333 — body text on near-white Pearl Button surfaces.
    static let inkMuted80 = Color(red: 0.200,    green: 0.200,     blue: 0.200)
    /// #7a7a7a — disabled state, fine-print legal.
    static let inkMuted48 = Color(red: 0.478,    green: 0.478,     blue: 0.478)

    // MARK: Surfaces
    /// Pure white canvas.
    static let canvas = Color.white
    /// #f5f5f7 — the signature Apple off-white "parchment".
    static let canvasParchment = Color(red: 0.961, green: 0.961,   blue: 0.969)
    /// #fafafc — fill for secondary ghost buttons.
    static let surfacePearl = Color(red: 0.980,    green: 0.980,   blue: 0.988)
    /// #272729 — primary dark-tile surface (used for the hero canvas here).
    static let surfaceTile1 = Color(red: 0.153,    green: 0.153,   blue: 0.161)
    /// #2a2a2c — micro-step lighter, used for adjacency separation.
    static let surfaceTile2 = Color(red: 0.165,    green: 0.165,   blue: 0.173)
    /// #252527 — micro-step darker, used at the foot of dark stacks.
    static let surfaceTile3 = Color(red: 0.145,    green: 0.145,   blue: 0.153)
    /// True void — used only for the global nav, video, edge-to-edge overlays.
    static let surfaceBlack = Color.black

    // MARK: Hairlines
    /// #f0f0f0 — soft ring shadow on secondary buttons.
    static let dividerSoft = Color(red: 0.941,     green: 0.941,   blue: 0.941)
    /// #e0e0e0 — 1px hairline border on utility cards and configurator chips.
    static let hairline = Color(red: 0.878,        green: 0.878,   blue: 0.878)
}
