//
//  ChipFlowLayout.swift
//  SousAI
//
//  A wrap-to-next-row Layout for pill chips.
//
//  Why a custom Layout (iOS 16+):
//    • SwiftUI has no native flow layout. `LazyVGrid` is rigid-column and
//      collapses chip-to-chip rhythm into uneven gutters — it makes the row
//      look like a spreadsheet, not a thought.
//    • `Layout` lets each chip take its intrinsic width and wraps cleanly to
//      the next row when the proposed width is exceeded, with a single
//      consistent horizontal and vertical gap.
//    • Resolves to a deterministic, animatable layout — which means the
//      `.transition()` modifiers on individual chips animate insertion and
//      removal smoothly without the whole row jumping.
//
//  Behavior:
//    • Items are laid out leading-to-trailing within the proposed width.
//    • When the next item would overflow the trailing edge, we drop to a
//      new row at `verticalSpacing` below the previous row.
//    • The reported size is the tight bounding box of all rows — meaning
//      the parent VStack collapses to exactly the chip cluster height.
//

import SwiftUI

struct ChipFlowLayout: Layout {

    var horizontalSpacing: CGFloat = AppSpacing.xs
    var verticalSpacing: CGFloat   = AppSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout Void) -> CGSize {
        // Critical: when SwiftUI queries us with `.unspecified` width (which
        // happens during the intrinsic-sizing pass), DO NOT broadcast the
        // single-row sum of every chip — that lets the parent VStack adopt
        // an enormous natural width and shift content off-screen left.
        // Instead, treat unspecified as zero so the parent feeds us its
        // real width on the next pass, which is the dimension we actually
        // want to wrap into.
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            // Report a tight one-row-tall height using the tallest subview,
            // and 0 width — refusing to claim any intrinsic horizontal size.
            let tallest = subviews
                .map { $0.sizeThatFits(.unspecified).height }
                .max() ?? 0
            return CGSize(width: 0, height: tallest)
        }

        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height }
                   + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = row.sizes[index - row.indices.lowerBound]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    // MARK: - Row computation

    /// One row of the flow — its source indices, the per-item sizes, and the
    /// row's bounding width/height for placement.
    private struct Row {
        var indices: Range<Int>
        var sizes: [CGSize]
        var width: CGFloat
        var height: CGFloat
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentSizes: [CGSize] = []
        var currentStart = 0
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for (offset, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let tentativeWidth = currentSizes.isEmpty
                ? size.width
                : currentWidth + horizontalSpacing + size.width

            if tentativeWidth > maxWidth, !currentSizes.isEmpty {
                rows.append(Row(
                    indices: currentStart..<offset,
                    sizes: currentSizes,
                    width: currentWidth,
                    height: currentHeight
                ))
                currentSizes = [size]
                currentStart = offset
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentSizes.append(size)
                currentWidth = tentativeWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentSizes.isEmpty {
            rows.append(Row(
                indices: currentStart..<subviews.count,
                sizes: currentSizes,
                width: currentWidth,
                height: currentHeight
            ))
        }

        return rows
    }
}
