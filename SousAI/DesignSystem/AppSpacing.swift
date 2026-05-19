//
//  AppSpacing.swift
//  SousAI
//
//  Spacing tokens from DESIGN.md. 8pt base unit; sub-base values used only for
//  tight typographic adjustments. Structural layout snaps to the named tokens.
//

import CoreGraphics

enum AppSpacing {
    static let xxs: CGFloat     = 4
    static let xs: CGFloat      = 8
    static let sm: CGFloat      = 12
    static let md: CGFloat      = 17
    static let lg: CGFloat      = 24
    static let xl: CGFloat      = 32
    static let xxl: CGFloat     = 48
    /// 80pt — the section rhythm constant. Vertical padding inside product tiles.
    static let section: CGFloat = 80
}
