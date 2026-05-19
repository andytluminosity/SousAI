//
//  AppTypography.swift
//  SousAI
//
//  Typography tokens mirrored from DESIGN.md.
//
//  Principles enforced here:
//    • Display sizes use SF Pro Display, weight 600 — never weight 500 or 700.
//    • Body sits at 17pt / 400 / -0.374 tracking — not 16pt.
//    • Weight 300 is real and rare — reserved for `buttonLarge` and `leadAiry`.
//    • Negative tracking at display sizes produces the "Apple tight" cadence.
//
//  Web pixel sizes from the design system are translated to iPhone-natural
//  point sizes for the hero context (e.g. 56px hero → 44pt on a 393pt-wide
//  iPhone 15 Pro), preserving the typographic *spirit* without overflowing
//  the device. The weight, tracking, and family rules remain literal.
//

import SwiftUI

enum AppTypography {

    // MARK: Display family

    /// Hero headline. SF Pro Display 600 with the signature negative tracking.
    /// DESIGN.md token: `hero-display` (56px / 600 / -0.28px) — point-scaled for iPhone.
    static let heroDisplay: Font   = .system(size: 44, weight: .semibold, design: .default)
    static let heroDisplayTracking: CGFloat = -1.0

    /// `display-lg` — 40px / 600. Used for section tile heads.
    static let displayLarge: Font  = .system(size: 34, weight: .semibold, design: .default)
    static let displayLargeTracking: CGFloat = 0

    /// `display-md` — SF Pro Text at display proportions, 34px / 600 / -0.374px.
    static let displayMedium: Font = .system(size: 28, weight: .semibold, design: .default)
    static let displayMediumTracking: CGFloat = -0.374

    /// `lead` — 28px / 400 / +0.196px. Product tile subcopy.
    static let lead: Font          = .system(size: 22, weight: .regular,  design: .default)
    static let leadTracking: CGFloat = 0.196

    /// `lead-airy` — the rare weight 300 used on environment-page leads.
    static let leadAiry: Font      = .system(size: 20, weight: .light,    design: .default)

    /// `tagline` — 21px / 600 / +0.231px. Sub-nav category names.
    static let tagline: Font       = .system(size: 19, weight: .semibold, design: .default)
    static let taglineTracking: CGFloat = 0.231

    // MARK: Body family (SF Pro Text)

    /// `body-strong` — 17pt / 600 / -0.374px tracking.
    static let bodyStrong: Font    = .system(size: 17, weight: .semibold, design: .default)
    static let bodyStrongTracking: CGFloat = -0.374

    /// `body` — the default paragraph. 17pt / 400 / -0.374px tracking.
    /// Apple breaks the SaaS convention: body is 17pt, not 16pt.
    static let body: Font          = .system(size: 17, weight: .regular,  design: .default)
    static let bodyTracking: CGFloat = -0.374

    /// `caption` — 14pt / 400.
    static let caption: Font       = .system(size: 14, weight: .regular,  design: .default)
    static let captionTracking: CGFloat = -0.224

    /// `caption-strong` — 14pt / 600.
    static let captionStrong: Font = .system(size: 14, weight: .semibold, design: .default)
    static let captionStrongTracking: CGFloat = -0.224

    // MARK: Buttons & micro

    /// `button-large` — 18pt / 300. The rare light weight used on store hero CTAs.
    static let buttonLarge: Font   = .system(size: 18, weight: .light,    design: .default)

    /// `button-utility` — 14pt / 400 / -0.224px.
    static let buttonUtility: Font = .system(size: 14, weight: .regular,  design: .default)
    static let buttonUtilityTracking: CGFloat = -0.224

    /// `fine-print` — 12pt / 400.
    static let finePrint: Font     = .system(size: 12, weight: .regular,  design: .default)
    static let finePrintTracking: CGFloat = -0.12

    /// `micro-legal` — 10pt / 400.
    static let microLegal: Font    = .system(size: 10, weight: .regular,  design: .default)

    /// `nav-link` — 12pt / 400 / -0.12px. Global nav menu items.
    static let navLink: Font       = .system(size: 12, weight: .regular,  design: .default)
    static let navLinkTracking: CGFloat = -0.12

    // MARK: Custom — used for the brand overline on the home hero.
    /// 11pt / 600 with wide tracking — a quiet eyebrow above the headline.
    static let brandEyebrow: Font  = .system(size: 11, weight: .semibold, design: .default)
    static let brandEyebrowTracking: CGFloat = 3.0
}
