//
//  IngredientSelectionView.swift
//  SousAI
//
//  The interactive refinement screen between AI scan and recipe generation.
//
//  Design intent (per the brief + DESIGN.md):
//    • Calm, tactile, minimal. The UI recedes; the chips ARE the page.
//    • Canvas: AppColor.surfaceTile1 via AmbientBackground() — the same
//      brand canvas used by HomeView and AnalysisLoadingView so the post-
//      capture branch reads as one room.
//    • Hero: "Your Ingredients" in displayMedium with tight tracking, left-
//      aligned to read like an editorial spread, not a dashboard heading.
//    • Body of the screen: a `ChipFlowLayout` of `IngredientChip` views,
//      followed by a trailing add-pill that, on tap, transforms in place
//      into a TextField for lightweight in-line entry (no modal screen).
//    • CTA cluster: one Action Blue PrimaryPillButton ("Generate Recipes")
//      and one quiet ghost link ("Retake Photo"). Nothing else competes.
//    • Motion: scaled-and-faded chip transitions, easeOut entrance, a soft
//      spring on the CTA. No bouncing. No gamified flourishes.
//
//  State seams:
//    • `ingredients` is the visible list. Removing a chip removes from this.
//    • `excluded` is the set of IDs the user toggled off (still visible,
//      but ghosted with strikethrough). They're skipped when recipes are
//      generated. Kept off the model so OpenAI decoding stays trivial.
//    • `isAddingIngredient` + `newIngredientText` drive the inline add-pill.
//
//  Responsive sizing strategy (mirrors HomeView):
//    • A single `ScreenMetrics` struct, computed from `GeometryReader`,
//      owns every horizontal dimension: gutter, `contentWidth`, and the
//      vertical breathing values.
//    • Every child of the page VStack is wrapped in an explicit
//      `.frame(width: m.contentWidth)`. This is the difference between a
//      bullet-proof layout and one that broadcasts giant widths under the
//      `.unspecified` proposal pass (which was clipping the headline and
//      the chip flow off the left edge).
//    • `AmbientBackground` is attached as `.background(...)` of the
//      `GeometryReader`, NOT as a ZStack sibling — so the background view
//      inherits the foreground's frame and physically cannot push
//      `proxy.size` around. Same trick HomeView uses.
//

import SwiftUI
import UIKit

struct IngredientSelectionView: View {

    // MARK: - Inputs

    let photo: CapturedPhoto
    @Binding var path: NavigationPath

    // MARK: - State

    @State private var ingredients: [DetectedIngredient]
    @State private var excluded: Set<UUID> = []

    @State private var isAddingIngredient = false
    @State private var newIngredientText = ""
    @FocusState private var addFieldFocused: Bool

    @State private var eyebrowVisible  = false
    @State private var headlineVisible = false
    @State private var chipsVisible    = false
    @State private var ctaVisible      = false

    // MARK: - Init

    init(photo: CapturedPhoto,
         detected: [DetectedIngredient],
         path: Binding<NavigationPath>) {
        self.photo = photo
        self._path = path
        self._ingredients = State(initialValue: detected)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let m = ScreenMetrics(width: proxy.size.width,
                                  height: proxy.size.height)

            VStack(spacing: 0) {
                topBar
                    .frame(width: m.contentWidth)
                    .padding(.top, AppSpacing.xs)
                    .opacity(eyebrowVisible ? 1 : 0)

                Spacer(minLength: AppSpacing.lg)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        heroStack(metrics: m)
                            .frame(width: m.contentWidth, alignment: .leading)
                            .opacity(headlineVisible ? 1 : 0)
                            .offset(y: headlineVisible ? 0 : 14)

                        chipCluster
                            .frame(width: m.contentWidth, alignment: .leading)
                            .opacity(chipsVisible ? 1 : 0)
                            .offset(y: chipsVisible ? 0 : 12)
                    }
                    .frame(width: m.contentWidth, alignment: .leading)
                    .padding(.bottom, AppSpacing.xl)
                }
                .frame(width: m.contentWidth)
                .scrollDismissesKeyboard(.interactively)

                ctaCluster
                    .frame(width: m.contentWidth)
                    .padding(.bottom, AppSpacing.lg)
                    .opacity(ctaVisible ? 1 : 0)
                    .offset(y: ctaVisible ? 0 : 16)
            }
            .frame(width: proxy.size.width,
                   height: proxy.size.height)
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
                               accessibilityLabel: "Back to camera") {
                retakePhoto()
            }

            Spacer()

            Text("REVIEW")
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
            Text("Your Ingredients")
                .font(.system(size: m.headlineSize, weight: .semibold))
                .tracking(AppTypography.displayMediumTracking)
                .foregroundColor(AppColor.bodyOnDark)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: m.contentWidth, alignment: .leading)

            Text("Review and adjust what we found.")
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.bodyMuted.opacity(0.78))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: m.contentWidth, alignment: .leading)
        }
        .frame(maxWidth: m.contentWidth, alignment: .leading)
    }

    // MARK: - Chip cluster

    private var chipCluster: some View {
        ChipFlowLayout(horizontalSpacing: AppSpacing.xs,
                       verticalSpacing: AppSpacing.xs) {
            ForEach(ingredients) { item in
                IngredientChip(
                    name: item.name,
                    emoji: item.emoji,
                    isSelected: !excluded.contains(item.id),
                    onToggle: { toggle(item) },
                    onRemove: { remove(item) }
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92)
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.88)
                            .combined(with: .opacity)
                    )
                )
            }

            addPill
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
    }

    // MARK: - Add pill (inline)

    @ViewBuilder
    private var addPill: some View {
        if isAddingIngredient {
            inlineAddField
        } else {
            Button(action: beginAdding) {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .regular))
                    Text("Add ingredient")
                        .font(AppTypography.body)
                        .tracking(AppTypography.bodyTracking)
                }
                .foregroundColor(AppColor.primaryOnDark)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            AppColor.primaryOnDark.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("Add ingredient")
        }
    }

    private var inlineAddField: some View {
        HStack(spacing: AppSpacing.xxs) {
            TextField("", text: $newIngredientText,
                      prompt: Text("e.g. Basil")
                        .foregroundColor(AppColor.ink.opacity(0.35)))
                .font(AppTypography.body)
                .tracking(AppTypography.bodyTracking)
                .foregroundColor(AppColor.ink)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .onSubmit(commitAdd)
                .frame(minWidth: 96, maxWidth: 220)

            Button(action: cancelAdd) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(AppColor.ink.opacity(0.4))
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("Cancel adding")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(AppColor.bodyOnDark)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppColor.primaryFocus, lineWidth: 2)
        )
    }

    // MARK: - CTA cluster

    private var ctaCluster: some View {
        VStack(spacing: AppSpacing.xs) {
            PrimaryPillButton("Generate Recipes",
                              icon: "sparkles",
                              action: generateRecipes)
                .disabled(activeCount == 0)
                .opacity(activeCount == 0 ? 0.55 : 1)

            Button(action: retakePhoto) {
                Text("Retake Photo")
                    .font(AppTypography.body)
                    .tracking(AppTypography.bodyTracking)
                    .foregroundColor(AppColor.bodyMuted)
                    .padding(.vertical, AppSpacing.xs)
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("Retake photo")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived

    private var activeCount: Int {
        ingredients.reduce(0) { acc, item in
            acc + (excluded.contains(item.id) ? 0 : 1)
        }
    }

    // MARK: - Mutations

    private func toggle(_ item: DetectedIngredient) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            if excluded.contains(item.id) {
                excluded.remove(item.id)
            } else {
                excluded.insert(item.id)
            }
        }
    }

    private func remove(_ item: DetectedIngredient) {
        withAnimation(.easeOut(duration: 0.28)) {
            ingredients.removeAll { $0.id == item.id }
            excluded.remove(item.id)
        }
    }

    // MARK: - Add-pill flow

    private func beginAdding() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        newIngredientText = ""
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isAddingIngredient = true
        }
        // Slight delay so the capsule transition completes before focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            addFieldFocused = true
        }
    }

    private func commitAdd() {
        let trimmed = newIngredientText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelAdd()
            return
        }
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        // User-added ingredient — `emoji` is intentionally `nil` here.
        // We do NOT guess client-side: keyword matching produces incorrect
        // glyphs on typos, composed phrases, and non-English input. The
        // OpenAI enrichment call (future) will populate `emoji` on this
        // item in place, matched by `id`. Until then, the chip renders
        // name-only — which is honest about what we know.
        let newItem = DetectedIngredient(name: trimmed, emoji: nil)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            ingredients.append(newItem)
            isAddingIngredient = false
            newIngredientText = ""
        }
        addFieldFocused = false
    }

    private func cancelAdd() {
        withAnimation(.easeOut(duration: 0.22)) {
            isAddingIngredient = false
            newIngredientText = ""
        }
        addFieldFocused = false
    }

    // MARK: - Navigation actions

    private func generateRecipes() {
        // Until RecipeResultsView lands, the CTA confirms tactilely without
        // advancing. The medium haptic from PrimaryPillButton already fired;
        // a quiet success notification confirms the commitment.
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
    }

    private func retakePhoto() {
        // Pop everything above CameraView so the user lands back in the
        // viewfinder. CameraView sits at path[0]; we keep one entry.
        while path.count > 1 {
            path.removeLast()
        }
    }

    // MARK: - Entrance

    private func animateEntrance() {
        withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
            eyebrowVisible = true
        }
        withAnimation(.easeOut(duration: 0.85).delay(0.18)) {
            headlineVisible = true
        }
        withAnimation(.easeOut(duration: 0.85).delay(0.36)) {
            chipsVisible = true
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.55)) {
            ctaVisible = true
        }
    }
}

// MARK: - Responsive metrics

/// Derives every horizontal dimension on the page from the live viewport.
/// Reference width = 393pt (iPhone 15 Pro). Same shape as `HomeView`'s
/// `HeroMetrics` so the two screens scale identically across devices.
private struct ScreenMetrics {
    let width: CGFloat
    let height: CGFloat

    /// Linear width scale, clamped to a tasteful band:
    ///   • iPhone SE 3 (375pt)  → ~0.95
    ///   • iPhone 15 Pro (393pt) → 1.00
    ///   • iPhone 15 Pro Max (430pt) → ~1.09
    ///   • iPad-class widths     → caps at 1.15
    var scale: CGFloat {
        let raw = width / 393
        return min(max(raw, 0.78), 1.15)
    }

    /// Horizontal gutter — 24pt minimum, expands gently on wider devices.
    var gutter: CGFloat {
        max(AppSpacing.lg, width * 0.06)
    }

    /// The single source of truth for "how wide a content block may be".
    /// Every child in the page VStack pins its `.frame(width:)` to this
    /// value so nothing can extend past the gutter under any device size
    /// or Dynamic Type setting.
    var contentWidth: CGFloat {
        max(0, width - 2 * gutter)
    }

    /// Headline size — scales with the viewport but stays in the
    /// `displayMedium` neighbourhood (28pt at 1.0×).
    var headlineSize: CGFloat { 28 * scale }
}

// MARK: - Previews

#Preview("IngredientSelectionView — default") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        IngredientSelectionView(
            photo: CapturedPhoto(image: UIImage()),
            detected: DetectedIngredient.sampleFridge,
            path: path
        )
    }
}

#Preview("IngredientSelectionView — sparse list") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        IngredientSelectionView(
            photo: CapturedPhoto(image: UIImage()),
            detected: Array(DetectedIngredient.sampleFridge.prefix(3)),
            path: path
        )
    }
}

#Preview("IngredientSelectionView — Accessibility XL") {
    StatefulPreviewWrapper(NavigationPath()) { path in
        IngredientSelectionView(
            photo: CapturedPhoto(image: UIImage()),
            detected: DetectedIngredient.sampleFridge,
            path: path
        )
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
