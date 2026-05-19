//
//  RecipeCardsView.swift
//  SousAI
//
//  The first reward moment in SousAI — a swipeable pager of AI-suggested
//  recipes. Each card shows the dish preview, title, description, cook
//  time, ingredient highlights, and a primary "Start Cooking" CTA.
//
//  Design intent (per DESIGN.md + the brief):
//    • Calm, premium, Apple-like. The cards ARE the page; everything
//      else recedes.
//    • Canvas: AmbientBackground over AppColor.surfaceTile1 — same dark
//      hero canvas used by Home / AnalysisLoading / IngredientSelection
//      / RecipeGenerating, so the post-capture branch reads as one room.
//    • Top bar: small `CircularIconButton` back chevron + centered
//      "RECIPES" eyebrow + symmetry placeholder — identical rhythm to
//      IngredientSelectionView so the user feels the same chrome
//      treatment as they swipe through the flow.
//    • Hero stack: "Your recipes" in `displayMedium`, sub-line "Based on
//      what's in your fridge" in `body` / `bodyMuted` — left-aligned to
//      read like an editorial spread.
//    • Pager: native SwiftUI `TabView` in `.page` mode (`indexDisplayMode:
//      .never`), so the iOS-native swipe physics carry the interaction.
//      A custom indicator below the pager keeps the page-dot dots on-
//      brand (the default white dots feel generic; ours use a widening
//      capsule on the active page in `primaryOnDark`).
//    • Motion: same staggered easeOut cascade as the other screens in
//      the flow (eyebrow → headline → cards → indicator). The cards
//      themselves fade in with a 14pt upward slide.
//
//  Image-enrichment (live):
//    • `recipes` is `@State` so `enrichImages()` can write each resolved
//      URL into `recipes[i].imageURL` (matched by `id`). One DALL-E 2
//      call per recipe fires in parallel from `onAppear`; SwiftUI re-
//      renders just the affected card via `RecipeDishImage`'s state
//      switch — no plumbing through `RecipeCardsView` or `RecipeCard`.
//    • Failures are intentionally swallowed: the per-card placeholder
//      (emoji on `surfaceTile3`) is a perfectly good ship state — see
//      `RecipeDishImage`'s file header.
//
//  Generate More (live):
//    • A trailing card in the pager invites the user to keep ideas
//      coming. Its content is state-driven (idle → loading → error).
//    • On tap, `handleGenerateMore` re-calls
//      `OpenAIRecipeService.generateRecipes(from:excluding:)` with the
//      original active ingredients plus the current recipes' titles as
//      the exclusion list — the model is asked to be substantively
//      different. A defensive lowercased-title filter runs at the call
//      site before appending, in case the model echoes a restatement.
//    • After append, `selection` jumps to the index of the first new
//      recipe so the user lands on the freshly-arrived card rather
//      than being stranded on the (now-shifted) extension card.
//      `enrichImages()` is then re-run so the new entries' previews
//      develop in too.
//
//  Start Cooking is the live CookingModeView seam — `handleStartCooking`
//  pushes `AppRoute.cookingMode(recipe)` onto the path, carrying the
//  exact `Recipe` instance the tapped card was bound to (the per-card
//  closure captures the recipe out of the enumerated ForEach, so it's
//  always the page the user is currently viewing). The medium impact
//  haptic comes from PrimaryPillButton itself; we don't double-fire.
//

import SwiftUI

struct RecipeCardsView: View {

    // MARK: - Inputs

    /// The original active ingredient list used to seed the text-completion
    /// call. Carried on this screen so the trailing "Generate More" card
    /// can re-call the recipe service with the same ingredients plus an
    /// exclusion list of titles we've already shown. See
    /// `handleGenerateMore`.
    let activeIngredients: [DetectedIngredient]

    @Binding var path: NavigationPath

    // MARK: - State

    /// Mutable so the image-enrichment hook can write URLs in place by id
    /// (see `enrichImages`), and so "Generate More" can append fresh
    /// non-duplicate recipes (see `handleGenerateMore`).
    @State private var recipes: [Recipe]
    @State private var selection: Int = 0

    /// One outstanding image-generation Task per recipe id. Keyed by id
    /// so the gate `imageTasks[recipe.id] == nil` makes `enrichImages()`
    /// idempotent — it can be safely re-run after a Generate More append.
    @State private var imageTasks: [UUID: Task<Void, Never>] = [:]

    /// State for the trailing "Generate More" card.
    @State private var moreState: GenerateMoreState = .idle
    @State private var moreTask: Task<Void, Never>?

    // Note: there is intentionally no `eyebrowVisible` state. The topBar
    // renders statically at full opacity from the first frame and is
    // explicitly opted out of every inherited animation context via
    // `.transaction { $0.animation = nil }` on its instance below. This
    // is the bulletproof answer to a "topBar bobs up and down" report:
    // even if an upstream view (e.g. `AmbientBackground`'s 8s
    // `repeatForever` breathing) leaks an implicit animation into our
    // render transaction, the topBar cannot inherit it.
    @State private var headlineVisible = false
    @State private var cardsVisible    = false
    @State private var indicatorVisible = false

    // MARK: - Init

    init(activeIngredients: [DetectedIngredient],
         recipes: [Recipe],
         path: Binding<NavigationPath>) {
        self.activeIngredients = activeIngredients
        self._recipes = State(initialValue: recipes)
        self._path = path
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let m = ScreenMetrics(width: proxy.size.width,
                                  height: proxy.size.height)

            VStack(spacing: 0) {
                // The topBar is the literal first child of the VStack
                // with NO Spacer above it. Its vertical position is
                // determined only by `.padding(.top, AppSpacing.xs)`
                // plus the safe-area inset — nothing in the layout
                // below can push it. (An earlier version sandwiched
                // the hero and pager between two `Spacer(minLength:)`
                // blocks; that upper Spacer let the topBar drift up
                // and down whenever TabView re-queried its preferred
                // height during swipe gestures or the entrance tick.)
                //
                // The topBar is also explicitly opted out of EVERY
                // inherited animation via `.transaction { $0.animation
                // = nil }`. This bulletproofs it against `AmbientBackground`'s
                // 8s `repeatForever` breathing transaction (and any
                // other implicit animation context) leaking in and
                // causing perceived motion. Static. From frame 1.
                topBar
                    .frame(width: m.contentWidth)
                    .padding(.top, AppSpacing.xs)
                    .transaction { $0.animation = nil }

                heroStack(metrics: m)
                    .frame(width: m.contentWidth, alignment: .leading)
                    .padding(.top, AppSpacing.xl)
                    .opacity(headlineVisible ? 1 : 0)
                    .offset(y: headlineVisible ? 0 : 14)

                // The pager fills all remaining vertical space between
                // the hero and the bottom safe-area inset that holds
                // the indicator (see `.safeAreaInset` below). We
                // deliberately do NOT pin a fixed `.frame(height:)`
                // here: an earlier `max(420, height * 0.62)` budget was
                // shorter than the recipe card's natural content
                // (~590pt on a typical iPhone), so the card's own
                // `clipShape` was chopping the bottom of the
                // Start Cooking button. With `maxHeight: .infinity`,
                // the pager receives a single, deterministic height
                // from the VStack layout pass (total − topBar − hero −
                // indicator inset), giving the card room to render in
                // full while still handing TabView a stable proposed
                // height (no Spacer in the flow → no bobbing).
                pager(metrics: m)
                    .padding(.top, AppSpacing.lg)
                    .frame(maxHeight: .infinity)
                    .opacity(cardsVisible ? 1 : 0)
                    .offset(y: cardsVisible ? 0 : 14)
            }
            .frame(width: proxy.size.width,
                   height: proxy.size.height,
                   alignment: .top)
            // The indicator is rendered in the bottom safe-area inset —
            // NOT as the last child of the VStack — for two reasons:
            //   1. It removes the indicator from the VStack's vertical
            //      layout flow, so its position no longer depends on a
            //      `Spacer` whose length can be perturbed by
            //      `TabView`'s preferred-height re-queries during swipe
            //      gestures (the classic SwiftUI "page dots bobbing"
            //      symptom — same failure mode the topBar comment
            //      above already calls out).
            //   2. `safeAreaInset` reserves its own space above the
            //      home indicator, which is exactly what we want: the
            //      pager above is sized into the remaining area
            //      automatically, with no Spacer plumbing required.
            // The `.transaction { $0.animation = nil }` is belt-and-
            // braces against any inherited animation context (e.g.
            // AmbientBackground's 8s breathing) leaking into a
            // hypothetical inset-height tween.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                indicator
                    .frame(width: m.contentWidth)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.lg)
                    .opacity(indicatorVisible ? 1 : 0)
                    .transaction { $0.animation = nil }
            }
        }
        .background(AmbientBackground())
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            animateEntrance()
            enrichImages()
        }
        .onDisappear {
            for task in imageTasks.values { task.cancel() }
            imageTasks.removeAll()
            moreTask?.cancel()
            moreTask = nil
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            CircularIconButton(systemName: "chevron.left",
                               accessibilityLabel: "Back to ingredients") {
                if !path.isEmpty { path.removeLast(); path.removeLast() }
            }

            Text("RECIPES")
                .font(AppTypography.brandEyebrow)
                .tracking(AppTypography.brandEyebrowTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.55))

            Spacer()

            // Symmetry placeholder so the eyebrow stays optically centered.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Hero text stack

    private func heroStack(metrics m: ScreenMetrics) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Your recipes")
                .font(.system(size: m.headlineSize, weight: .semibold))
                .tracking(AppTypography.displayMediumTracking)
                .foregroundColor(AppColor.bodyOnDark)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: m.contentWidth, alignment: .leading)

            Text("Based on what's in your fridge")
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.78))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: m.contentWidth, alignment: .leading)
        }
        .frame(maxWidth: m.contentWidth, alignment: .leading)
    }

    // MARK: - Pager

    private func pager(metrics m: ScreenMetrics) -> some View {
        // Insetting each card by half a gutter lets the neighbour peek
        // through optically while the TabView swipe still feels edge-
        // to-edge. We use horizontal padding inside each tab page rather
        // than on the TabView itself so the gesture catchment stays full
        // width.
        //
        // The trailing `GenerateMoreCard` lives inside the same TabView
        // so the user reaches it with the same swipe gesture they're
        // already using. Its tag is `recipes.count` — when more recipes
        // are appended, the extension card's tag naturally moves
        // forward and `handleGenerateMore` re-aims `selection` at the
        // first new recipe.
        TabView(selection: $selection) {
            ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                RecipeCard(recipe: recipe) { _ in
                    handleStartCooking(recipe)
                }
                .padding(.horizontal, m.gutter * 0.6)
                .padding(.vertical, AppSpacing.xxs)
                .tag(index)
            }

            GenerateMoreCard(state: moreState, onGenerate: handleGenerateMore)
                .padding(.horizontal, m.gutter * 0.6)
                .padding(.vertical, AppSpacing.xxs)
                .tag(recipes.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // No `.frame(height:)` — the parent VStack hands the TabView a
        // definite height via `.frame(maxHeight: .infinity)` (see body),
        // so the page-style pager still gets a stable proposed height
        // without the card overflow we saw under a fixed pagerHeight.
    }

    // MARK: - Indicator

    private var indicator: some View {
        // Total page count includes the trailing Generate More card.
        // We treat that card as a real page in the indicator — it IS a
        // page the user can land on — so the rightmost dot tracks the
        // extension card with the same active treatment as the recipe
        // dots.
        let totalPages = recipes.count + 1
        return HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { index in
                let isActive = index == selection
                Capsule(style: .continuous)
                    .fill(isActive
                          ? AppColor.primaryOnDark
                          : AppColor.bodyMuted.opacity(0.35))
                    .frame(width: isActive ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.42, dampingFraction: 0.82),
                               value: selection)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(selection + 1) of \(totalPages)"))
    }

    // MARK: - Actions

    private func handleStartCooking(_ recipe: Recipe) {
        // Pushes the cooking mode screen with the exact recipe the user
        // tapped. The per-card closure in `pager(_:)` captures `recipe`
        // out of the enumerated ForEach, so this is always the page the
        // user is currently viewing — no `selection` lookup needed.
        // PrimaryPillButton already fires a medium impact haptic on tap,
        // so we don't fire another here.
        path.append(AppRoute.cookingMode(recipe))
    }

    // MARK: - Image enrichment

    /// Fires one DALL-E 2 image-generation Task per recipe that has an
    /// `imagePrompt` and no `imageURL` yet. The Tasks run in parallel;
    /// each writes its result into `recipes[i].imageURL` (matched by id)
    /// so SwiftUI re-renders only the affected card via the AsyncImage
    /// in `RecipeDishImage`. The placeholder underneath fades out as
    /// the image fades in (see `RecipeDishImage.body`).
    ///
    /// Idempotent: the `imageTasks[recipe.id] == nil` gate means this
    /// can be safely re-run after a Generate More append — only the
    /// new recipes get fresh tasks.
    ///
    /// Errors are intentionally swallowed: the per-card placeholder is
    /// a perfectly good ship state.
    private func enrichImages() {
        for recipe in recipes {
            guard let prompt = recipe.imagePrompt,
                  recipe.imageURL == nil,
                  imageTasks[recipe.id] == nil else { continue }
            let recipeId = recipe.id
            imageTasks[recipeId] = Task { @MainActor in
                guard let url = try? await OpenAIRecipeService.shared
                    .generateImage(forPrompt: prompt) else { return }
                guard !Task.isCancelled else { return }
                guard let idx = recipes.firstIndex(where: { $0.id == recipeId }) else {
                    return
                }
                withAnimation(.easeOut(duration: 0.45)) {
                    recipes[idx].imageURL = url
                }
            }
        }
    }

    // MARK: - Generate More

    /// Asks the recipe service for 4 more recipes, passing the current
    /// titles as the exclusion list so the model is steered away from
    /// duplicates. A defensive lowercased-title dedupe runs on the
    /// response before appending (the prompt is the first defence; this
    /// is the second). On success, `selection` jumps to the index of
    /// the first new recipe and `enrichImages()` is re-run so the new
    /// previews develop in.
    private func handleGenerateMore() {
        guard moreTask == nil else { return }
        moreState = .loading
        moreTask = Task { @MainActor in
            do {
                let new = try await OpenAIRecipeService.shared.generateRecipes(
                    from: activeIngredients,
                    excluding: recipes.map(\.title)
                )
                guard !Task.isCancelled else { return }

                let existingLower = Set(recipes.map { $0.title.lowercased() })
                let deduped = new.filter {
                    !existingLower.contains($0.title.lowercased())
                }

                guard !deduped.isEmpty else {
                    // Every returned recipe was a restatement of something
                    // we already showed. We don't auto-retry (keeps cost
                    // predictable) — instead, be honest that the well is
                    // dry and nudge toward changing the ingredient list.
                    moreState = .error(
                        "We're out of fresh ideas for this list. Try going back and adjusting your ingredients."
                    )
                    moreTask = nil
                    return
                }

                let firstNewIndex = recipes.count
                withAnimation(.easeOut(duration: 0.45)) {
                    recipes.append(contentsOf: deduped)
                }
                moreState = .idle
                moreTask = nil

                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    selection = firstNewIndex
                }
                enrichImages()
            } catch {
                guard !Task.isCancelled else { return }
                moreState = .error(Self.friendlyMessage(for: error))
                moreTask = nil
            }
        }
    }

    /// Mirrors `RecipeGeneratingView.friendlyMessage(for:)` so the error
    /// vocabulary stays consistent across the post-capture flow.
    private static func friendlyMessage(for error: Error) -> String {
        if let openAI = error as? OpenAIError {
            switch openAI {
            case .missingKey:
                return "OpenAI API key isn't set. Add it to .env and try again."
            case .transport:
                return "We couldn't reach OpenAI. Check your connection and try again."
            case .http(let status, _):
                return "OpenAI returned an error (status \(status)). Please try again."
            case .emptyResponse, .decoding, .invalidPayload:
                return "We couldn't read the response. Please try again."
            }
        }
        return "Something went wrong. Please try again."
    }

    // MARK: - Entrance

    private func animateEntrance() {
        // The topBar is intentionally absent from this cascade — it
        // renders statically from frame 1 (see the `transaction`
        // modifier on its instance above and the comment block on the
        // state declarations).
        withAnimation(.easeOut(duration: 0.85).delay(0.18)) {
            headlineVisible = true
        }
        withAnimation(.easeOut(duration: 0.85).delay(0.34)) {
            cardsVisible = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.55)) {
            indicatorVisible = true
        }
    }
}

// MARK: - Responsive metrics

/// Derives every horizontal dimension on the page from the live viewport.
/// Same shape as `IngredientSelectionView`'s `ScreenMetrics` so the two
/// screens scale identically across devices.
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

    var headlineSize: CGFloat { 28 * scale }

    // Note: there is intentionally no `pagerHeight`. An earlier version
    // pinned the pager to `max(420, height * 0.62)`, which was shorter
    // than the recipe card's natural content (~590pt for a typical
    // recipe) on a stock iPhone 14 Pro — the card's clipShape then
    // chopped the bottom of the Start Cooking button. The pager now
    // takes the remaining vertical space via `.frame(maxHeight: .infinity)`
    // in the body, with the indicator anchored in a bottom
    // `.safeAreaInset` so the pager's height stays deterministic.
}

// MARK: - Generate More card

/// The three render states of the trailing extension card. Kept at file
/// scope (rather than nested in `RecipeCardsView`) so `GenerateMoreCard`
/// — which is a sibling private struct — can name the type directly.
private enum GenerateMoreState: Equatable {
    case idle
    case loading
    case error(String)
}

/// The trailing card in the pager that invites the user to keep ideas
/// coming. Same `surfaceTile2` chassis as `RecipeCard` so the two
/// belong to the same family; no `RecipeDishImage` because there is
/// no dish yet — the centered `sparkles` glyph is the placeholder
/// treatment.
private struct GenerateMoreCard: View {

    let state: GenerateMoreState
    let onGenerate: () -> Void

    /// Drives the three-dot pulse during `.loading`. Same cadence as
    /// `RecipeGeneratingView` so the two surfaces share a loading
    /// vocabulary.
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: AppSpacing.xl) {
                glyph

                VStack(spacing: AppSpacing.sm) {
                    Text(headline)
                        .font(AppTypography.displayMedium)
                        .tracking(AppTypography.displayMediumTracking)
                        .foregroundColor(AppColor.bodyOnDark)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subline)
                        .font(AppTypography.body)
                        .tracking(AppTypography.bodyTracking)
                        .foregroundColor(AppColor.bodyMuted.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.lg)
            }

            Spacer(minLength: 0)

            cta
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .accessibilityLabel(Text(accessibilityLabel))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - State-driven slots

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .idle, .error:
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(AppColor.primaryOnDark.opacity(0.85))
                .accessibilityHidden(true)
        case .loading:
            pulsingDots
        }
    }

    private var headline: String {
        switch state {
        case .idle:    return "More recipes?"
        case .loading: return "Composing more recipes…"
        case .error:   return "Something went wrong"
        }
    }

    private var subline: String {
        switch state {
        case .idle:
            return "Tap to keep ideas coming — we'll skip what's already here."
        case .loading:
            return "Crafting fresh dishes from the same ingredients."
        case .error(let message):
            return message
        }
    }

    @ViewBuilder
    private var cta: some View {
        switch state {
        case .idle:
            PrimaryPillButton("Generate More",
                              icon: "sparkles",
                              action: onGenerate)
        case .loading:
            // No button while a request is in flight — the pulsing dots
            // above are the affordance. Reserving the CTA height keeps
            // the card from jumping between states.
            Color.clear.frame(height: 52)
        case .error:
            PrimaryPillButton("Try Again",
                              icon: "arrow.clockwise",
                              action: onGenerate)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:    return "More recipes. Tap Generate More to add."
        case .loading: return "Composing more recipes."
        case .error(let message): return "Generate more failed. \(message)"
        }
    }

    // MARK: - Pulsing dots

    private var pulsingDots: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppColor.bodyMuted.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.0 : 0.55)
                    .opacity(pulse ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: pulse
                    )
            }
        }
        .frame(height: 56)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Previews

#Preview("RecipeCardsView — default") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        RecipeCardsView(activeIngredients: DetectedIngredient.sampleFridge,
                        recipes: Recipe.mocks,
                        path: path)
    }
}

#Preview("RecipeCardsView — single recipe") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        RecipeCardsView(activeIngredients: DetectedIngredient.sampleFridge,
                        recipes: Array(Recipe.mocks.prefix(1)),
                        path: path)
    }
}

#Preview("RecipeCardsView — Accessibility XL") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        RecipeCardsView(activeIngredients: DetectedIngredient.sampleFridge,
                        recipes: Recipe.mocks,
                        path: path)
    }
    .environment(\.dynamicTypeSize, .accessibility2)
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
