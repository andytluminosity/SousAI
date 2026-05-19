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
//    • `recipe: Recipe` — @State, seeded from the route value via
//      `init`. Mutated in place when the AI troubleshooting call
//      returns updated steps / ingredients. Screen-scoped — see
//      "Screen-scoped mutations" below.
//    • `selectedStepIndex: Int?` — one active step at a time. `nil`
//      = collapsed list (the screen's initial state).
//    • `interactions: [Int: CookingStepInteraction]` — per-step
//      user-issue text + assistant-call status. Lazily created on
//      first edit; never mutated for unedited steps.
//    • `assistantTasks: [Int: Task<Void, Never>]` — one in-flight
//      troubleshooting task per step, keyed by step index.
//    • `recipeUpdateBadge: Bool` — drives the brief "Recipe updated"
//      chip that surfaces after the AI mutates the recipe.
//
//  Live AI seam (per-step troubleshooting):
//    • `handleSubmit(_ index:)` calls
//      `OpenAIRecipeService.troubleshootStep(recipe:stepIndex:userIssue:)`
//      with the current `recipe`, the active step's 0-based index, and
//      the user's typed issue. The call returns an always-present
//      remediation `message` plus optional full-replacement
//      `updatedSteps` / `updatedIngredients` arrays.
//    • One in-flight `Task` per step is tracked in `assistantTasks`,
//      keyed by step index. Re-submitting on a step cancels any
//      existing task for that index before starting a new one.
//    • Status writes back into `interactions[index].assistantStatus`
//      so the card renders idle → loading → response | error in place
//      with the fade+slide-up transitions defined on the card.
//
//  Screen-scoped mutations:
//    • `recipe` is `@State`, seeded once from the route value via
//      `init`. When the model returns `updatedSteps` / `updatedIngredients`
//      we mutate `recipe.steps` / `recipe.ingredients` in place inside
//      a `withAnimation(.easeOut(0.45))`, then surface a brief
//      "Recipe updated" chip so the user notices.
//    • `AppRoute.cookingMode(Recipe)` carries the recipe by value, so
//      the route payload is never mutated. `RecipeCardsView.recipes`
//      is never touched. Popping back and re-entering re-seeds
//      `CookingModeView` from the original recipe — any AI rewrites
//      from the previous visit are intentionally gone. This is the
//      desired behavior: experiment freely, walk away, come back to a
//      clean recipe.
//

import SwiftUI

// MARK: - Per-step interaction value

/// The lightweight per-step interaction record. Two fields, one for
/// each direction of the conversation:
///   • `userIssue` — what the user typed into the step's input.
///   • `assistantStatus` — the lifecycle of the AI troubleshooting
///     call for this step. The card renders directly off the case:
///     `.idle` shows nothing, `.loading` shows pulsing dots,
///     `.response` shows the remediation tile, `.error` shows an
///     inline message + Retry affordance.
///
/// Per-step (not per-screen) so the user can engage multiple steps
/// over a cooking session and each step preserves its own answer.
struct CookingStepInteraction: Hashable {
    let stepIndex: Int
    var userIssue: String = ""
    var assistantStatus: StepAssistantStatus = .idle
}

/// Lifecycle of the OpenAI troubleshooting call for a single step.
///
/// Modeled as a single enum (rather than separate `isLoading` /
/// `responseText` / `errorMessage` fields) so the UI can `switch`
/// on it and a transition to a new state automatically clears the
/// previous one — no risk of showing stale response text while a
/// fresh call is in flight.
enum StepAssistantStatus: Hashable {
    case idle
    case loading
    case response(String)
    case error(String)
}

// MARK: - Screen

struct CookingModeView: View {

    // MARK: - Inputs

    @Binding var path: NavigationPath

    // MARK: - State

    /// The cooking-session-scoped copy of the recipe. Seeded once from
    /// the route value in `init`. The AI troubleshooting hook mutates
    /// `recipe.steps` and `recipe.ingredients` in place — see the
    /// file header for why those mutations are screen-scoped.
    @State private var recipe: Recipe

    /// Index into the resolved `steps` list of the currently expanded
    /// step. `nil` = no step is active (initial render).
    @State private var selectedStepIndex: Int? = nil

    /// Per-step interaction map, keyed by step index. Lazily created
    /// in `binding(for:)` on first edit so unedited steps don't
    /// pollute the map.
    @State private var interactions: [Int: CookingStepInteraction] = [:]

    /// One outstanding troubleshooting `Task` per step, keyed by step
    /// index. Submitting on a step cancels its existing task (if any)
    /// before starting a new one so the user can't stack requests.
    /// Stays untyped (`Task<Void, Never>`) because we never read the
    /// task's value — we only need its cancel handle and lifetime.
    @State private var assistantTasks: [Int: Task<Void, Never>] = [:]

    /// Drives the brief "Recipe updated" chip that fades in above the
    /// steps section right after the AI mutates `recipe.steps` /
    /// `recipe.ingredients`. Bumped on every successful mutation.
    @State private var recipeUpdateBadge: Bool = false

    // Entrance cascade. Same posture as RecipeCardsView — see that
    // file's header for the rationale on topBar being static from
    // frame 1.
    @State private var headerVisible = false
    @State private var stepsVisible  = false
    @State private var hintVisible   = false

    // MARK: - Init

    /// Seeds the screen's `@State recipe` from the route value once.
    /// SwiftUI ignores the wrapped value on re-init, so subsequent
    /// renders of this same `CookingModeView` instance preserve any
    /// AI-driven step / ingredient mutations. Popping and re-pushing
    /// the route creates a *new* `CookingModeView` (new stack entry),
    /// which re-seeds from the original recipe — exactly the
    /// "experiment freely, walk away, come back clean" semantic the
    /// file header describes.
    init(recipe: Recipe, path: Binding<NavigationPath>) {
        self._recipe = State(initialValue: recipe)
        self._path = path
    }

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
            HStack(spacing: AppSpacing.sm) {
                Text("STEPS")
                    .font(AppTypography.brandEyebrow)
                    .tracking(AppTypography.brandEyebrowTracking)
                    .foregroundColor(AppColor.bodyMuted.opacity(0.55))

                Spacer(minLength: 0)

                if recipeUpdateBadge {
                    recipeUpdatedChip
                        .transition(
                            .opacity.combined(with: .move(edge: .trailing))
                        )
                }
            }
            .padding(.horizontal, AppSpacing.xs)

            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(resolvedSteps.enumerated()), id: \.offset) { index, text in
                    CookingStepCard(
                        stepIndex: index,
                        stepText: text,
                        isActive: selectedStepIndex == index,
                        userIssue: binding(for: index),
                        assistantStatus: interactions[index]?.assistantStatus ?? .idle,
                        onTap: { toggleStep(index) },
                        onSubmitIssue: { handleSubmit(index) },
                        onRetry: { handleSubmit(index) }
                    )
                    .id(stepAnchor(for: index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The brief affordance that surfaces when the AI mutated the live
    /// recipe. Sits in the "STEPS" header row, fades in for ~2.5s, and
    /// disappears — the recipe-data refresh itself is the durable
    /// signal, this is just the moment of acknowledgement.
    private var recipeUpdatedChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Recipe updated")
                .font(AppTypography.captionStrong)
                .tracking(AppTypography.captionStrongTracking)
        }
        .foregroundColor(AppColor.bodyOnDark.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(AppColor.surfaceTile3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Recipe updated"))
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

    /// Dispatches the AI troubleshooting call for `index`.
    ///
    /// Steps:
    ///   1. Trim the user's typed issue; bail if empty (a no-op send
    ///      shouldn't show a loading state).
    ///   2. Cancel any existing task for this step so a rapid re-submit
    ///      or a Retry tap from `.error` can't stack two requests.
    ///   3. Flip the step's `assistantStatus` to `.loading` inside a
    ///      gentle animation so the previous response/error fades out
    ///      smoothly.
    ///   4. Call `OpenAIRecipeService.troubleshootStep(...)`. On
    ///      success, write `.response(message)` and apply any
    ///      `updatedSteps` / `updatedIngredients` to the live `recipe`
    ///      via `applyRecipeUpdates(...)`. On failure, write
    ///      `.error(friendlyMessage)`.
    private func handleSubmit(_ index: Int) {
        let raw = interactions[index]?.userIssue ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        assistantTasks[index]?.cancel()
        assistantTasks[index] = nil

        withAnimation(.easeOut(duration: 0.28)) {
            setStatus(.loading, for: index)
        }

        let snapshot = recipe
        let task = Task { @MainActor in
            do {
                let result = try await OpenAIRecipeService.shared.troubleshootStep(
                    recipe: snapshot,
                    stepIndex: index,
                    userIssue: trimmed
                )
                guard !Task.isCancelled else { return }

                if result.updatedSteps != nil || result.updatedIngredients != nil {
                    applyRecipeUpdates(
                        newSteps: result.updatedSteps,
                        newIngredients: result.updatedIngredients
                    )
                }

                withAnimation(.easeOut(duration: 0.35)) {
                    setStatus(.response(result.message), for: index)
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    setStatus(.error(Self.friendlyMessage(for: error)),
                              for: index)
                }
            }
            assistantTasks[index] = nil
        }
        assistantTasks[index] = task
    }

    /// Replaces the live `recipe.steps` / `recipe.ingredients` with
    /// the AI's full replacement arrays when provided, clamps the
    /// active selection if the new step count is shorter, and surfaces
    /// the "Recipe updated" chip for ~2.5s.
    ///
    /// Empty arrays from the model are ignored — the service layer
    /// already normalizes those to `nil`, this is a defensive belt-
    /// and-suspenders check so we never blank out the recipe.
    private func applyRecipeUpdates(newSteps: [String]?,
                                    newIngredients: [String]?) {
        var changed = false
        withAnimation(.easeOut(duration: 0.45)) {
            if let newSteps, !newSteps.isEmpty, newSteps != recipe.steps {
                recipe.steps = newSteps
                changed = true
                if let active = selectedStepIndex, active >= newSteps.count {
                    selectedStepIndex = newSteps.indices.last
                }
            }
            if let newIngredients,
               !newIngredients.isEmpty,
               newIngredients != recipe.ingredients {
                recipe.ingredients = newIngredients
                changed = true
            }
        }
        guard changed else { return }

        withAnimation(.easeOut(duration: 0.35)) {
            recipeUpdateBadge = true
        }
        // Dismiss the chip after a short read window. The recipe data
        // itself is the durable signal; this is just the in-the-moment
        // acknowledgement.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.45)) {
                recipeUpdateBadge = false
            }
        }
    }

    /// Writes a new `assistantStatus` into `interactions[index]`,
    /// lazily creating the record on first edit (same posture as
    /// `binding(for:)`). Centralized so all status writes go through
    /// one shape and the SwiftUI animation transactions wrap the
    /// dictionary write cleanly.
    private func setStatus(_ status: StepAssistantStatus, for index: Int) {
        if var existing = interactions[index] {
            existing.assistantStatus = status
            interactions[index] = existing
        } else {
            interactions[index] = CookingStepInteraction(
                stepIndex: index,
                assistantStatus: status
            )
        }
    }

    /// Mirrors `RecipeCardsView.friendlyMessage(for:)` so the
    /// post-capture flow keeps one error voice. Copied (not extracted)
    /// to keep both screens self-contained — the helper is small and
    /// the duplication is intentional.
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
