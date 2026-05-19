//
//  CookingModeView.swift
//  SousAI
//
//  The final, most important stage of the SousAI flow:
//
//      Home → Camera → Confirmation → Analysis → Ingredients →
//      RecipeGenerating → RecipeCards → CookingModeView
//
//  The guided cooking experience. Inspired by Apple Fitness's "in-
//  workout" detail screen: a rich top header that anchors the user in
//  what they're making, a vertical step list that becomes the focus as
//  the user engages, and one expandable step at a time with an
//  inline contextual input for asking "what went wrong" — scaffolded
//  for the future AI hook, no backend wired today.
//
//  Design intent (per DESIGN.md + the brief):
//    • Same dark chassis as every other post-capture screen:
//      AmbientBackground over `surfaceTile1`. The user feels the same
//      room they've been in since the Camera screen.
//    • Top bar grammar identical to RecipeCardsView: `CircularIconButton`
//      back chevron · "COOKING" eyebrow · 44pt symmetry placeholder.
//      Pinned. Never animates after frame 1.
//    • Recipe header is a *tile* — `surfaceTile2` rounded container
//      with `bodyOnDark.opacity(0.06)` hairline, top-flush
//      `RecipeDishImage` in 4:3, then title / summary / meta beneath.
//      Same family of object as RecipeCard, minus the "Start Cooking"
//      CTA (the user is already cooking). The tile scrolls *with* the
//      step list — as the user engages, the header naturally moves
//      out of the way.
//    • Step list lives below in its own section, marked by a small
//      "STEPS" eyebrow. Each step is a `CookingStepCard`; tapping
//      activates it, switching active state is a single spring
//      transaction.
//    • Footer hint sits quietly at the bottom of the scroll content,
//      teaching the per-step input pattern without occupying any
//      chrome.
//    • Entrance cascade identical to RecipeCardsView's:
//        - topBar: static from frame 1, opted out of every inherited
//          animation via `.transaction { $0.animation = nil }`.
//        - recipeHeaderTile: easeOut(0.85).delay(0.18) — opacity + 14pt up.
//        - stepsSection: easeOut(0.85).delay(0.34) — opacity + 14pt up.
//        - footerHint: easeOut(0.7).delay(0.55) — opacity.
//
//  State model:
//    • `selectedStepIndex: Int?` — one active step at a time. `nil`
//      = collapsed list (the screen's initial state).
//    • `interactions: [Int: CookingStepInteraction]` — per-step
//      user-issue text + future `assistantResponse` slot. Lazily
//      created on first edit; never mutated for unedited steps.
//
//  Future AI seam:
//    • `CookingStepInteraction.assistantResponse` is the field the
//      future AI call writes into. When wired, the response renders
//      beneath the per-step input row with the same fade+slide-up
//      transition the input itself uses today.
//
//  No networking. No API calls. The send button on each step's input
//  only commits the typed string into the local interaction map.
//

import SwiftUI

// MARK: - Per-step interaction value

/// The lightweight per-step interaction record. Both fields are
/// designed for the future AI hook:
///   • `userIssue` is what the user types into the step's input.
///   • `assistantResponse` is what the AI will write back. Today it
///     stays `nil`; the type exists so the cooking screen's data flow
///     is the right shape from the start.
struct CookingStepInteraction: Hashable {
    let stepIndex: Int
    var userIssue: String = ""
    var assistantResponse: String? = nil
}

// MARK: - Screen

struct CookingModeView: View {

    // MARK: - Inputs

    let recipe: Recipe
    @Binding var path: NavigationPath

    // MARK: - State

    /// Index into the resolved `steps` list of the currently expanded
    /// step. `nil` = no step is active (initial render).
    @State private var selectedStepIndex: Int? = nil

    /// Per-step interaction map, keyed by step index. Lazily created
    /// in `binding(for:)` on first edit so unedited steps don't
    /// pollute the map.
    @State private var interactions: [Int: CookingStepInteraction] = [:]

    // Entrance cascade. Same posture as RecipeCardsView — see that
    // file's header for the rationale on topBar being static from
    // frame 1.
    @State private var headerVisible = false
    @State private var stepsVisible  = false
    @State private var hintVisible   = false

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let m = ScreenMetrics(width: proxy.size.width,
                                  height: proxy.size.height)

            VStack(spacing: 0) {
                // Same bulletproofing as RecipeCardsView: the topBar
                // is the literal first child with NO Spacer above it,
                // and is explicitly opted out of every inherited
                // animation via `.transaction { $0.animation = nil }`.
                // This prevents AmbientBackground's 8s repeatForever
                // breathing transaction (or any other implicit
                // animation context) from leaking in and causing the
                // bar to bob. Static. From frame 1.
                topBar
                    .frame(width: m.contentWidth)
                    .padding(.top, AppSpacing.xs)
                    .transaction { $0.animation = nil }

                bodyScroll(metrics: m)
            }
            .frame(width: proxy.size.width,
                   height: proxy.size.height,
                   alignment: .top)
        }
        .background(AmbientBackground())
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: animateEntrance)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            CircularIconButton(systemName: "chevron.left",
                               accessibilityLabel: "Back to recipes") {
                if !path.isEmpty { path.removeLast() }
            }

            Text("COOKING")
                .font(AppTypography.brandEyebrow)
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))

            Spacer()

            // Symmetry placeholder so the eyebrow stays optically centered.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Scrollable body

    private func bodyScroll(metrics m: ScreenMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    recipeHeaderTile(metrics: m)
                        .padding(.top, AppSpacing.lg)
                        .opacity(headerVisible ? 1 : 0)
                        .offset(y: headerVisible ? 0 : 14)

                    stepsSection(metrics: m)
                        .padding(.top, AppSpacing.xl)
                        .opacity(stepsVisible ? 1 : 0)
                        .offset(y: stepsVisible ? 0 : 14)

                    footerHint
                        .padding(.top, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.xxl)
                        .opacity(hintVisible ? 1 : 0)
                }
                .frame(width: m.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: selectedStepIndex) { _, newValue in
                guard let index = newValue else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    proxy.scrollTo(stepAnchor(for: index), anchor: .top)
                }
            }
        }
    }

    // MARK: - Recipe header tile

    private func recipeHeaderTile(metrics m: ScreenMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeDishImage(recipe: recipe)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                titleBlock
                metaRow
                ingredientLine
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColor.surfaceTile2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(AppColor.bodyOnDark.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(recipe.title))
        .accessibilityHint(Text("\(recipe.cookTimeMinutes) minutes. \(recipe.summary)"))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(recipe.title)
                .font(AppTypography.displayMedium)
                .tracking(AppTypography.displayMediumTracking)
                .foregroundColor(AppColor.bodyOnDark)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(recipe.summary)
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.bodyMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .regular))
            Text("\(recipe.cookTimeMinutes) min")
                .font(AppTypography.captionStrong)
                .tracking(AppTypography.captionStrongTracking)
        }
        .foregroundColor(AppColor.bodyOnDark.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(AppColor.surfaceTile3)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cook time \(recipe.cookTimeMinutes) minutes"))
    }

    /// Inline (no chips) ingredient list — keeps the header tile
    /// visually distinct from the full RecipeCard the user just
    /// tapped, and honors the brief's "key ingredients (small chips
    /// OR inline text)" alternative.
    private var ingredientLine: some View {
        Text(recipe.ingredients.joined(separator: " · "))
            .font(AppTypography.caption)
            .tracking(AppTypography.captionTracking)
            .foregroundColor(AppColor.bodyMuted.opacity(0.85))
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Ingredients: \(recipe.ingredients.joined(separator: ", "))"))
    }

    // MARK: - Steps section

    private func stepsSection(metrics m: ScreenMetrics) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("STEPS")
                .font(AppTypography.brandEyebrow)
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))
                .padding(.horizontal, AppSpacing.xs)

            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(resolvedSteps.enumerated()), id: \.offset) { index, text in
                    CookingStepCard(
                        stepIndex: index,
                        stepText: text,
                        isActive: selectedStepIndex == index,
                        userIssue: binding(for: index),
                        onTap: { toggleStep(index) },
                        onSubmitIssue: { handleSubmit(index) }
                    )
                    .id(stepAnchor(for: index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer hint

    private var footerHint: some View {
        Text("Need help? Tap a step and describe the issue.")
            .font(AppTypography.caption)
            .tracking(AppTypography.captionTracking)
            .foregroundColor(AppColor.bodyMuted.opacity(0.6))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func toggleStep(_ index: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            if selectedStepIndex == index {
                selectedStepIndex = nil
            } else {
                selectedStepIndex = index
            }
        }
    }

    private func handleSubmit(_ index: Int) {
        // The future AI hook lands here. Today: the value is already
        // in `interactions[index].userIssue` via the two-way binding,
        // so there's nothing else to commit. The card's `handleSubmit`
        // resigns focus and fires a haptic; we just no-op.
        _ = index
    }

    // MARK: - Derived data

    /// Resolves `recipe.steps` to a non-empty list. When the model
    /// didn't return steps (the offline-fallback state), we surface
    /// a single quiet line rather than blocking the flow.
    private var resolvedSteps: [String] {
        if let steps = recipe.steps, !steps.isEmpty {
            return steps
        }
        return ["Cook to your taste."]
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding<String>(
            get: { interactions[index]?.userIssue ?? "" },
            set: { newValue in
                if var existing = interactions[index] {
                    existing.userIssue = newValue
                    interactions[index] = existing
                } else {
                    interactions[index] = CookingStepInteraction(
                        stepIndex: index,
                        userIssue: newValue
                    )
                }
            }
        )
    }

    private func stepAnchor(for index: Int) -> String {
        "cooking-step-\(index)"
    }

    // MARK: - Entrance

    private func animateEntrance() {
        // The topBar is intentionally absent from this cascade — it
        // renders statically from frame 1 (see the `transaction`
        // modifier on its instance above and the comment block on the
        // state declarations).
        withAnimation(.easeOut(duration: 0.85).delay(0.18)) {
            headerVisible = true
        }
        withAnimation(.easeOut(duration: 0.85).delay(0.34)) {
            stepsVisible = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.55)) {
            hintVisible = true
        }
    }
}

// MARK: - Responsive metrics

/// Mirrors `RecipeCardsView.ScreenMetrics` so the cooking screen scales
/// identically to the cards screen across devices.
private struct ScreenMetrics {
    let width: CGFloat
    let height: CGFloat

    var scale: CGFloat {
        let raw = width / 393
        return min(max(raw, 0.78), 1.15)
    }

    var gutter: CGFloat {
        max(AppSpacing.lg, width * 0.06)
    }

    var contentWidth: CGFloat {
        max(0, width - 2 * gutter)
    }
}

// MARK: - Previews

#Preview("CookingModeView — default") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        CookingModeView(recipe: Recipe.mocks[0], path: path)
    }
}

#Preview("CookingModeView — longer recipe") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        CookingModeView(recipe: Recipe.mocks[1], path: path)
    }
}

#Preview("CookingModeView — Accessibility XL") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        CookingModeView(recipe: Recipe.mocks[3], path: path)
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("CookingModeView — no steps fallback") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        CookingModeView(
            recipe: Recipe(
                title: "Mystery Dish",
                summary: "A recipe whose steps haven't been generated yet.",
                cookTimeMinutes: 8,
                ingredients: ["Eggs", "Butter"],
                emoji: "❓",
                steps: nil
            ),
            path: path
        )
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value,
         @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
