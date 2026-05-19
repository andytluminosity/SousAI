//
//  HomeView.swift
//  SousAI
//
//  The premium hero landing for SousAI.
//
//  Design intent (per the brief + DESIGN.md):
//    • Edge-to-edge dark hero on AppColor.surfaceTile1 — no chrome, no cards.
//    • Hero typography is the spine: SF Pro Display 600 with tight tracking,
//      followed by a single 19pt SF Pro Text lead and one Action-Blue pill.
//    • Ambient lighting (AmbientBackground) supplies the only depth.
//    • Staggered entrance: eyebrow → headline → tagline → CTA → fine-print.
//      Motion is calm easeOut + a soft spring on the CTA. No bounces.
//    • Press behavior on the CTA = scale(0.95) + medium haptic, per DESIGN.md.
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
        ZStack {
            AmbientBackground()

            content
        }
        .background(AppColor.surfaceTile1.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear(perform: animateEntrance)
    }

    // MARK: - Composition

    private var content: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, AppSpacing.xs)

            Spacer(minLength: AppSpacing.xl)

            heroStack
                .padding(.horizontal, AppSpacing.lg)

            Spacer(minLength: AppSpacing.section)

            ctaCluster
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
        }
    }

    // MARK: Top bar — quiet brand eyebrow only

    private var topBar: some View {
        HStack {
            Text("SOUSAI")
                .font(AppTypography.brandEyebrow)
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))

            Spacer()

            // A single quiet utility — kept as a circular chip the user can
            // grow into later (e.g. saved recipes, profile). 44×44 hit area
            // matches DESIGN.md's `button-icon-circular`.
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Profile")
        }
        .padding(.horizontal, AppSpacing.lg)
        .opacity(eyebrowVisible ? 1 : 0)
    }

    // MARK: Hero typography stack

    private var heroStack: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {

            Text("What are we\ncooking today?")
                .font(AppTypography.heroDisplay)
                .tracking(AppTypography.heroDisplayTracking)
                .lineSpacing(2)
                .foregroundColor(AppColor.bodyOnDark)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 18)

            Text("Turn leftovers into something amazing with your AI sous-chef.")
                .font(AppTypography.lead)
                .tracking(AppTypography.leadTracking)
                .lineSpacing(4)
                .foregroundColor(AppColor.bodyMuted)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(taglineVisible ? 1 : 0)
                .offset(y: taglineVisible ? 0 : 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: CTA cluster

    private var ctaCluster: some View {
        VStack(spacing: AppSpacing.sm) {
            PrimaryPillButton("Scan Your Fridge",
                              icon: "viewfinder",
                              action: onScanFridge)
                .frame(maxWidth: .infinity)
                .opacity(ctaVisible ? 1 : 0)
                .offset(y: ctaVisible ? 0 : 16)

            Text("Point your camera. We'll do the rest.")
                .font(AppTypography.finePrint)
                .tracking(AppTypography.finePrintTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.5))
                .opacity(ctaVisible ? 1 : 0)
        }
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

// MARK: - Previews

#Preview("HomeView — iPhone 15 Pro") {
    HomeView()
}

#Preview("HomeView — Accessibility XL") {
    HomeView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
