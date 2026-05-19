//
//  HomeView.swift
//  SousAI
//
//  The premium hero landing for SousAI.
//
//  Design intent (per the brief + DESIGN.md):
//    • Edge-to-edge dark hero on AppColor.surfaceTile1 — no chrome, no cards.
//    • Hero typography is the spine: SF Pro Display 600 with tight tracking,
//      followed by a single SF Pro Text lead and one Action-Blue pill.
//    • Ambient lighting (AmbientBackground) supplies the only depth.
//    • Staggered entrance: eyebrow → headline → tagline → CTA → fine-print.
//      Motion is calm easeOut + a soft spring on the CTA. No bounces.
//    • Press behavior on the CTA = scale(0.95) + medium haptic, per DESIGN.md.
//
//  Responsive sizing strategy:
//    • A single `HeroMetrics` struct, computed from `GeometryReader`, owns
//      every dimension in the view: type sizes, tracking, gutter, gaps, AND
//      a single `contentWidth` budget that every text element is forced into
//      via an explicit `.frame(maxWidth: m.contentWidth, ...)`.
//    • Because each Text has a *concrete* maximum width, `minimumScaleFactor`
//      always has something to compete against and the layout cannot bleed
//      past the gutter on any device or Dynamic Type setting.
//

import SwiftUI

struct HomeView: View {

    // MARK: - Entrance state

    @State private var eyebrowVisible  = false
    @State private var headlineVisible = false
    @State private var taglineVisible  = false
    @State private var ctaVisible      = false

    // Hook the parent app can replace with a real router/coordinator later.
    var onScanFridge: () -> Void = {}

    // MARK: - Body

    var body: some View {
        // AmbientBackground is attached as a `.background(...)` of the
        // GeometryReader rather than a ZStack sibling. With this shape the
        // background view *inherits* the foreground's frame and physically
        // cannot push proxy.size around — so the responsive metrics always
        // see the true viewport width.
        GeometryReader { proxy in
            let m = HeroMetrics(width: proxy.size.width,
                                height: proxy.size.height)

            VStack(spacing: 0) {
                topBar(metrics: m)
                    .frame(width: m.contentWidth)
                    .padding(.top, AppSpacing.xs)

                Spacer(minLength: m.gapTop)

                heroStack(metrics: m)
                    .frame(width: m.contentWidth, alignment: .leading)

                Spacer(minLength: m.gapBottom)

                ctaCluster(metrics: m)
                    .frame(width: m.contentWidth)
                    .padding(.bottom, AppSpacing.lg)
            }
            .frame(width: proxy.size.width,
                   height: proxy.size.height)
        }
        .background(AmbientBackground())
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: animateEntrance)
    }

    // MARK: Top bar — quiet brand eyebrow only

    private func topBar(metrics m: HeroMetrics) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text("SOUSAI")
                .font(.system(size: m.eyebrowSize, weight: .semibold))
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: AppSpacing.xs)

            // A single quiet utility — kept as a circular chip the user can
            // grow into later (e.g. saved recipes, profile). 44×44 hit area
            // matches DESIGN.md's `button-icon-circular`.
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Profile")
        }
        .opacity(eyebrowVisible ? 1 : 0)
    }

    // MARK: Hero typography stack

    private func heroStack(metrics m: HeroMetrics) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {

            Text("What are we cooking today?")
                .font(.system(size: m.headlineSize, weight: .semibold))
                .tracking(m.headlineTracking)
                .lineSpacing(m.headlineSize * 0.04)
                .foregroundColor(AppColor.bodyOnDark)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: m.contentWidth, alignment: .leading)
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 18)

            Text("Turn leftovers into something amazing with your AI sous-chef.")
                .font(.system(size: m.subtitleSize, weight: .regular))
                .tracking(AppTypography.leadTracking)
                .lineSpacing(m.subtitleSize * 0.22)
                .foregroundColor(AppColor.bodyMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: m.contentWidth, alignment: .leading)
                .opacity(taglineVisible ? 1 : 0)
                .offset(y: taglineVisible ? 0 : 14)
        }
        .frame(maxWidth: m.contentWidth, alignment: .leading)
    }

    // MARK: CTA cluster

    private func ctaCluster(metrics m: HeroMetrics) -> some View {
        VStack(spacing: AppSpacing.sm) {
            // The pill hugs its content per DESIGN.md `button-store-hero`
            // grammar; the surrounding VStack centers it.
            PrimaryPillButton("Scan Your Fridge",
                              icon: "viewfinder",
                              action: onScanFridge)
                .opacity(ctaVisible ? 1 : 0)
                .offset(y: ctaVisible ? 0 : 16)

            Text("Point your camera. We'll do the rest.")
                .font(.system(size: m.finePrintSize, weight: .regular))
                .tracking(AppTypography.finePrintTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: m.contentWidth)
                .opacity(ctaVisible ? 1 : 0)
        }
        .frame(maxWidth: m.contentWidth)
    }

    // MARK: Entrance choreography

    private func animateEntrance() {
        // Tiny eyebrow first — sets the stage almost imperceptibly.
        withAnimation(.easeOut(duration: 0.7).delay(0.05)) {
            eyebrowVisible = true
        }
        // Headline carries the most weight — give it the longest read.
        withAnimation(.easeOut(duration: 0.95).delay(0.20)) {
            headlineVisible = true
        }
        // Tagline trails the headline by a single beat.
        withAnimation(.easeOut(duration: 0.85).delay(0.50)) {
            taglineVisible = true
        }
        // CTA arrives with a soft spring — the only "alive" motion in the view.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.78)) {
            ctaVisible = true
        }
    }
}

// MARK: - Responsive metrics

/// Derives every size in the hero from the live viewport.
/// Reference width = 393pt (iPhone 15 Pro).
private struct HeroMetrics {
    let width: CGFloat
    let height: CGFloat

    /// Linear width scale, clamped to a tasteful band:
    ///   • iPhone SE 3 (375pt)  → ~0.95
    ///   • iPhone 15 Pro (393pt) → 1.00
    ///   • iPhone 15 Pro Max (430pt) → ~1.09
    ///   • iPad-class widths     → caps at 1.15 (no headline blowups)
    var scale: CGFloat {
        let raw = width / 393
        return min(max(raw, 0.78), 1.15)
    }

    /// Horizontal gutter — 24pt minimum, expands gently on wider devices.
    var gutter: CGFloat {
        max(AppSpacing.lg, width * 0.06)
    }

    /// The single source of truth for "how wide a text block may be".
    /// Every Text in the view is constrained to this via `.frame(maxWidth:)`
    /// so nothing can extend past the gutter under any circumstances.
    var contentWidth: CGFloat {
        max(0, width - 2 * gutter)
    }

    /// Vertical breathing space above and below the hero stack.
    /// Floors at the design-system spacing tokens so very short viewports
    /// still respect the section rhythm.
    var gapTop: CGFloat    { max(AppSpacing.xl,      height * 0.06) }
    var gapBottom: CGFloat { max(AppSpacing.section, height * 0.14) }

    // MARK: Typography sizes (scale with viewport)

    /// 44pt at 1.0× → ~34pt at the 0.78 floor, ~51pt at the iPad cap.
    var headlineSize: CGFloat { 44 * scale }

    /// Tracking scales softly so the "Apple tight" cadence is preserved
    /// proportionally as the headline grows or shrinks.
    var headlineTracking: CGFloat { -1.0 * scale }

    var subtitleSize: CGFloat  { 19 * scale }
    var eyebrowSize: CGFloat   { 11 * scale }
    var finePrintSize: CGFloat { 12 * scale }
}

// MARK: - Previews

#Preview("HomeView — iPhone 15 Pro") {
    HomeView()
}

#Preview("HomeView — Compact (iPhone SE-class)") {
    HomeView()
        .frame(width: 375, height: 667)
}

#Preview("HomeView — Pro Max width") {
    HomeView()
        .frame(width: 430, height: 932)
}

#Preview("HomeView — Accessibility XL") {
    HomeView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
