//
//  AppRadius.swift
//  SousAI
//
//  Border-radius scale from DESIGN.md.
//  The grammar is strict: `sm` for compact utility, `lg` for utility cards,
//  `pill` for primary actions and search inputs, `md` for Pearl Button only.
//

import CoreGraphics

enum AppRadius {
    static let none: CGFloat = 0
    static let xs: CGFloat   = 5
    static let sm: CGFloat   = 8
    static let md: CGFloat   = 11
    static let lg: CGFloat   = 18
    /// 9999 — treated as a full capsule via `Capsule()` shape in SwiftUI.
    static let pill: CGFloat = 9999
}
