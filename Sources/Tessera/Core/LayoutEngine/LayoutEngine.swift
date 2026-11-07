import Foundation
import CoreGraphics

public struct LayoutEngine: Sendable {
    public init() {}

    /// Main entry point for computing window placements, tile frames, stack badges, and divider handles.
    public func calculateLayout(
        windows: [LayoutWindowInput],
        screen: ScreenBounds,
        config: LayoutConfiguration
    ) -> LayoutCalculationOutput {
        guard !windows.isEmpty else {
            return LayoutCalculationOutput(
                placements: [],
                tileFrames: [],
                stackBadges: [],
                dividers: [],
                effectiveMasterRatio: config.masterRatio
            )
        }

        var floatingIDs = Set<String>()
        let maxTileCount: Int
        if let overrideCap = config.maxTilesOverride {
            maxTileCount = min(max(1, overrideCap), screen.maxTileCapacity)
        } else {
            maxTileCount = screen.maxTileCapacity
        }

        // Iteratively resolve minimum size constraints.
        // If a window cannot fit even after shifting the split ratio, mark it floating and reflow.
        var effectiveRatio = min(max(config.masterRatio, 0.18), 0.82)
        var resolvedSlots: [CGRect] = []
        var resolvedBuckets: [[LayoutWindowInput]] = []
        var resolvedDividers: [DividerGeometry] = []

        while true {
            let tileCandidates = windows.filter { !floatingIDs.contains($0.id) }
            if tileCandidates.isEmpty {
                resolvedSlots = []
                resolvedBuckets = []
                resolvedDividers = []
                break
            }

            let activeTileCount = min(tileCandidates.count, maxTileCount)
            let clampedActiveTile = min(max(config.activeTileIndex, 0), max(0, activeTileCount - 1))

            // Partition candidates into tile buckets (0 ..< activeTileCount).
            // Overflow windows (index >= maxTileCount) stack onto clampedActiveTile.
            var buckets: [[LayoutWindowInput]] = Array(repeating: [], count: activeTileCount)
            for (index, win) in tileCandidates.enumerated() {
                if index < activeTileCount {
                    buckets[index].append(win)
                } else {
                    buckets[clampedActiveTile].append(win)
                }
            }

            // Compute required minimum sizes per tile bucket (max width and max height of windows in that bucket).
            let bucketMinSizes: [CGSize] = buckets.map { bucket in
                var maxW: CGFloat = 0
                var maxH: CGFloat = 0
                for w in bucket {
                    if w.minimumSize.width > maxW { maxW = w.minimumSize.width }
                    if w.minimumSize.height > maxH { maxH = w.minimumSize.height }
                }
                return CGSize(width: maxW, height: maxH)
            }

            let useZeroGaps = config.smartGaps && activeTileCount == 1
            let outerPad: CGFloat = useZeroGaps ? 0 : config.outerPadding
            let innerGap: CGFloat = useZeroGaps ? 0 : config.innerGap

            let usableRect = screen.visibleFrame.insetBy(dx: outerPad, dy: outerPad)
            guard usableRect.width > 10, usableRect.height > 10 else {
                for w in tileCandidates {
                    floatingIDs.insert(w.id)
                }
                continue
            }

            // Adjust split ratio dynamically based on bucket minimum sizes.
            let adjustedRatio = Self.adjustRatioForMinimumSizes(
                baseRatio: config.masterRatio,
                layout: config.layout,
                leftPaneCount: config.leftPaneCount,
                isPortrait: screen.isPortrait,
                usableRect: usableRect,
                innerGap: innerGap,
                bucketMinSizes: bucketMinSizes
            )

            let (slots, dividers) = Self.computeTileFramesAndDividers(
                count: activeTileCount,
                layout: config.layout,
                leftPaneCount: config.leftPaneCount,
                isPortrait: screen.isPortrait,
                usableRect: usableRect,
                innerGap: innerGap,
                masterRatio: adjustedRatio,
                leftSplitRatio: config.leftSplitRatio,
                secondaryRatio: config.secondaryRatio
            )

            // Verify if every window in each bucket fits its assigned slot.
            var worstOffenderID: String?
            var worstOverflow: CGFloat = 0

            for (tileIdx, bucket) in buckets.enumerated() where tileIdx < slots.count {
                let slot = slots[tileIdx]
                for win in bucket {
                    let overflowW = max(0, win.minimumSize.width - slot.width)
                    let overflowH = max(0, win.minimumSize.height - slot.height)
                    let totalOverflow = overflowW + overflowH
                    if (overflowW > 0.5 || overflowH > 0.5) && totalOverflow > worstOverflow {
                        worstOverflow = totalOverflow
                        worstOffenderID = win.id
                    }
                }
            }

            if let offender = worstOffenderID {
                floatingIDs.insert(offender)
            } else {
                effectiveRatio = adjustedRatio
                resolvedSlots = slots
                resolvedBuckets = buckets
                resolvedDividers = dividers
                break
            }
        }

        // Map buckets and floating windows back into ordered WindowPlacementResult list
        var placementByID: [String: WindowPlacementResult] = [:]
        var stackBadges: [StackBadgeDescriptor] = []

        for (tileIdx, bucket) in resolvedBuckets.enumerated() where tileIdx < resolvedSlots.count {
            let slotFrame = resolvedSlots[tileIdx]
            let count = bucket.count
            let activePos = count > 1 ? (config.activeStackOffset % count) : 0

            for (stackPos, win) in bucket.enumerated() {
                let isTop = (stackPos == activePos)
                placementByID[win.id] = WindowPlacementResult(
                    id: win.id,
                    pid: win.pid,
                    targetFrame: Self.pixelAligned(slotFrame),
                    mode: .tiled(
                        tileIndex: tileIdx,
                        stackPosition: stackPos,
                        stackCount: count,
                        isTopOfStack: isTop
                    )
                )
            }

            if count > 1 {
                stackBadges.append(
                    StackBadgeDescriptor(
                        tileIndex: tileIdx,
                        tileFrame: Self.pixelAligned(slotFrame),
                        activeOneBasedIndex: activePos + 1,
                        totalCount: count,
                        windowIDs: bucket.map(\.id),
                        windowLabels: bucket.map { $0.label.isEmpty ? $0.bundleIdentifier : $0.label }
                    )
                )
            }
        }

        for win in windows where floatingIDs.contains(win.id) {
            let centered = Self.centeredFloatingFrame(for: win, in: screen.visibleFrame)
            placementByID[win.id] = WindowPlacementResult(
                id: win.id,
                pid: win.pid,
                targetFrame: Self.pixelAligned(centered),
                mode: .floating
            )
        }

        let orderedPlacements = windows.compactMap { placementByID[$0.id] }

        return LayoutCalculationOutput(
            placements: orderedPlacements,
            tileFrames: resolvedSlots.map(Self.pixelAligned),
            stackBadges: stackBadges,
            dividers: resolvedDividers,
            effectiveMasterRatio: effectiveRatio
        )
    }

    // MARK: - Minimum Size Ratio Shifting

    private static func adjustRatioForMinimumSizes(
        baseRatio: CGFloat,
        layout: TileLayoutKind,
        leftPaneCount: Int,
        isPortrait: Bool,
        usableRect: CGRect,
        innerGap: CGFloat,
        bucketMinSizes: [CGSize]
    ) -> CGFloat {
        let count = bucketMinSizes.count
        let clampedBase = min(max(baseRatio, 0.18), 0.82)
        guard count >= 2 else { return clampedBase }

        let minAllowedRatio: CGFloat = 0.15
        let maxAllowedRatio: CGFloat = 0.85

        switch layout {
        case .side:
            let effectiveLeftCount = min(max(1, leftPaneCount), count - 1)
            if isPortrait {
                let availableH = usableRect.height - innerGap
                guard availableH > 0 else { return clampedBase }
                let masterMinH = bucketMinSizes.prefix(effectiveLeftCount).map(\.height).max() ?? 0
                let secondaryMinH = bucketMinSizes.dropFirst(effectiveLeftCount).map(\.height).max() ?? 0

                if masterMinH + secondaryMinH > availableH {
                    return clampedBase
                }

                var ratio = clampedBase
                let minRatioForMaster = masterMinH / availableH
                let maxRatioForSecondary = 1.0 - (secondaryMinH / availableH)
                if ratio < minRatioForMaster { ratio = minRatioForMaster }
                if ratio > maxRatioForSecondary { ratio = maxRatioForSecondary }
                return min(max(ratio, minAllowedRatio), maxAllowedRatio)
            } else {
                let availableW = usableRect.width - innerGap
                guard availableW > 0 else { return clampedBase }
                let masterMinW = bucketMinSizes.prefix(effectiveLeftCount).map(\.width).max() ?? 0
                let secondaryMinW = bucketMinSizes.dropFirst(effectiveLeftCount).map(\.width).max() ?? 0

                if masterMinW + secondaryMinW > availableW {
                    return clampedBase
                }

                var ratio = clampedBase
                let minRatioForMaster = masterMinW / availableW
                let maxRatioForSecondary = 1.0 - (secondaryMinW / availableW)
                if ratio < minRatioForMaster { ratio = minRatioForMaster }
                if ratio > maxRatioForSecondary { ratio = maxRatioForSecondary }
                return min(max(ratio, minAllowedRatio), maxAllowedRatio)
            }

        case .grid:
            if count >= 2 && count <= 4 {
                let availableW = usableRect.width - innerGap
                guard availableW > 0 else { return clampedBase }
                let leftIndices: [Int] = count == 2 ? [0] : (count == 3 ? [0] : [0, 2])
                let rightIndices: [Int] = count == 2 ? [1] : (count == 3 ? [1, 2] : [1, 3])

                let leftMinW = leftIndices.compactMap { $0 < count ? bucketMinSizes[$0].width : nil }.max() ?? 0
                let rightMinW = rightIndices.compactMap { $0 < count ? bucketMinSizes[$0].width : nil }.max() ?? 0

                if leftMinW + rightMinW > availableW {
                    return clampedBase
                }

                var ratio = clampedBase
                let minRatioLeft = leftMinW / availableW
                let maxRatioRight = 1.0 - (rightMinW / availableW)
                if ratio < minRatioLeft { ratio = minRatioLeft }
                if ratio > maxRatioRight { ratio = maxRatioRight }
                return min(max(ratio, minAllowedRatio), maxAllowedRatio)
            }
            return clampedBase

        case .columns:
            if count == 2 {
                let availableW = usableRect.width - innerGap
                guard availableW > 0 else { return clampedBase }
                let leftMinW = bucketMinSizes[0].width
                let rightMinW = bucketMinSizes[1].width
                if leftMinW + rightMinW > availableW {
                    return clampedBase
                }
                var ratio = clampedBase
                let minRatioLeft = leftMinW / availableW
                let maxRatioRight = 1.0 - (rightMinW / availableW)
                if ratio < minRatioLeft { ratio = minRatioLeft }
                if ratio > maxRatioRight { ratio = maxRatioRight }
                return min(max(ratio, minAllowedRatio), maxAllowedRatio)
            }
            return clampedBase

        case .rows:
            if count == 2 {
                let availableH = usableRect.height - innerGap
                guard availableH > 0 else { return clampedBase }
                let topMinH = bucketMinSizes[0].height
                let bottomMinH = bucketMinSizes[1].height
                if topMinH + bottomMinH > availableH {
                    return clampedBase
                }
                var ratio = clampedBase
                let minRatioTop = topMinH / availableH
                let maxRatioBottom = 1.0 - (bottomMinH / availableH)
                if ratio < minRatioTop { ratio = minRatioTop }
                if ratio > maxRatioBottom { ratio = maxRatioBottom }
                return min(max(ratio, minAllowedRatio), maxAllowedRatio)
            }
            return clampedBase
        }
    }

    // MARK: - Geometry Generators

    private static func computeTileFramesAndDividers(
        count: Int,
        layout: TileLayoutKind,
        leftPaneCount: Int,
        isPortrait: Bool,
        usableRect: CGRect,
        innerGap: CGFloat,
        masterRatio: CGFloat,
        leftSplitRatio: CGFloat,
        secondaryRatio: CGFloat
    ) -> ([CGRect], [DividerGeometry]) {
        guard count > 0 else { return ([], []) }
        if count == 1 {
            return ([usableRect], [])
        }

        switch layout {
        case .side:
            return computeSideLayout(
                count: count,
                leftPaneCount: leftPaneCount,
                isPortrait: isPortrait,
                usableRect: usableRect,
                innerGap: innerGap,
                masterRatio: masterRatio,
                leftSplitRatio: leftSplitRatio,
                secondaryRatio: secondaryRatio
            )
        case .columns:
            return computeColumnsLayout(
                count: count,
                usableRect: usableRect,
                innerGap: innerGap,
                masterRatio: masterRatio,
                secondaryRatio: secondaryRatio
            )
        case .rows:
            return computeRowsLayout(
                count: count,
                usableRect: usableRect,
                innerGap: innerGap,
                masterRatio: masterRatio,
                secondaryRatio: secondaryRatio
            )
        case .grid:
            return computeGridLayout(
                count: count,
                usableRect: usableRect,
                innerGap: innerGap,
                masterRatio: masterRatio,
                leftSplitRatio: leftSplitRatio,
                secondaryRatio: secondaryRatio
            )
        }
    }

    private static func computeSideLayout(
        count: Int,
        leftPaneCount: Int,
        isPortrait: Bool,
        usableRect: CGRect,
        innerGap: CGFloat,
        masterRatio: CGFloat,
        leftSplitRatio: CGFloat,
        secondaryRatio: CGFloat
    ) -> ([CGRect], [DividerGeometry]) {
        let effectiveLeftCount = min(max(1, leftPaneCount), count - 1)
        let secondaryCount = count - effectiveLeftCount
        let handleThickness = max(innerGap, 18)

        if isPortrait {
            // Portrait: Top pane (effectiveLeftCount columns) + Bottom pane (secondaryCount columns)
            let availableH = max(0, usableRect.height - innerGap)
            let masterH = availableH * masterRatio
            let secondaryH = availableH - masterH

            let topArea = CGRect(
                x: usableRect.minX,
                y: usableRect.minY,
                width: usableRect.width,
                height: masterH
            )

            let bottomY = usableRect.minY + masterH + innerGap
            let bottomArea = CGRect(
                x: usableRect.minX,
                y: bottomY,
                width: usableRect.width,
                height: secondaryH
            )

            let (topFrames, topDivs) = splitIntoColumnsWithRatio(
                rect: topArea,
                count: effectiveLeftCount,
                gap: innerGap,
                firstRatio: leftSplitRatio,
                role: .leftSecondary,
                idPrefix: "portrait-top-col"
            )
            let (bottomFrames, bottomDivs) = splitIntoColumnsWithRatio(
                rect: bottomArea,
                count: secondaryCount,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "portrait-bottom-col"
            )

            let dividerY = usableRect.minY + masterH + (innerGap / 2.0) - (handleThickness / 2.0)
            let primaryDivider = DividerGeometry(
                id: "primary-horizontal",
                role: .primary,
                frame: CGRect(x: usableRect.minX, y: dividerY, width: usableRect.width, height: handleThickness),
                axis: .horizontal,
                currentRatio: masterRatio,
                containerLength: availableH
            )
            return (topFrames + bottomFrames, [primaryDivider] + topDivs + bottomDivs)
        } else {
            // Landscape: Left pane (effectiveLeftCount rows) + Right pane (secondaryCount rows)
            let availableW = max(0, usableRect.width - innerGap)
            let masterW = availableW * masterRatio
            let secondaryW = availableW - masterW

            let leftArea = CGRect(
                x: usableRect.minX,
                y: usableRect.minY,
                width: masterW,
                height: usableRect.height
            )

            let secondaryX = usableRect.minX + masterW + innerGap
            let rightArea = CGRect(
                x: secondaryX,
                y: usableRect.minY,
                width: secondaryW,
                height: usableRect.height
            )

            let (leftFrames, leftDivs) = splitIntoRowsWithRatio(
                rect: leftArea,
                count: effectiveLeftCount,
                gap: innerGap,
                firstRatio: leftSplitRatio,
                role: .leftSecondary,
                idPrefix: "side-left-row"
            )
            let (rightFrames, rightDivs) = splitIntoRowsWithRatio(
                rect: rightArea,
                count: secondaryCount,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "side-right-row"
            )

            let dividerX = usableRect.minX + masterW + (innerGap / 2.0) - (handleThickness / 2.0)
            let primaryDivider = DividerGeometry(
                id: "primary-vertical",
                role: .primary,
                frame: CGRect(x: dividerX, y: usableRect.minY, width: handleThickness, height: usableRect.height),
                axis: .vertical,
                currentRatio: masterRatio,
                containerLength: availableW
            )
            return (leftFrames + rightFrames, [primaryDivider] + leftDivs + rightDivs)
        }
    }

    private static func computeColumnsLayout(
        count: Int,
        usableRect: CGRect,
        innerGap: CGFloat,
        masterRatio: CGFloat,
        secondaryRatio: CGFloat
    ) -> ([CGRect], [DividerGeometry]) {
        let handleThickness = max(innerGap, 18)
        if count == 2 {
            let availableW = max(0, usableRect.width - innerGap)
            let firstW = availableW * masterRatio
            let secondW = availableW - firstW
            let left = CGRect(x: usableRect.minX, y: usableRect.minY, width: firstW, height: usableRect.height)
            let right = CGRect(x: usableRect.minX + firstW + innerGap, y: usableRect.minY, width: secondW, height: usableRect.height)
            let dividerX = usableRect.minX + firstW + (innerGap / 2.0) - (handleThickness / 2.0)
            let divider = DividerGeometry(
                id: "columns-vertical",
                role: .primary,
                frame: CGRect(x: dividerX, y: usableRect.minY, width: handleThickness, height: usableRect.height),
                axis: .vertical,
                currentRatio: masterRatio,
                containerLength: availableW
            )
            return ([left, right], [divider])
        } else if count >= 3 {
            let availableW = max(0, usableRect.width - innerGap)
            let firstW = availableW * masterRatio
            let remainingW = availableW - firstW
            let firstCol = CGRect(x: usableRect.minX, y: usableRect.minY, width: firstW, height: usableRect.height)
            let remainingArea = CGRect(
                x: usableRect.minX + firstW + innerGap,
                y: usableRect.minY,
                width: remainingW,
                height: usableRect.height
            )
            let (otherCols, otherDivs) = splitIntoColumnsWithRatio(
                rect: remainingArea,
                count: count - 1,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "columns-sub"
            )
            let dividerX = usableRect.minX + firstW + (innerGap / 2.0) - (handleThickness / 2.0)
            let primaryDiv = DividerGeometry(
                id: "columns-primary",
                role: .primary,
                frame: CGRect(x: dividerX, y: usableRect.minY, width: handleThickness, height: usableRect.height),
                axis: .vertical,
                currentRatio: masterRatio,
                containerLength: availableW
            )
            return ([firstCol] + otherCols, [primaryDiv] + otherDivs)
        }
        return (splitIntoEqualColumns(rect: usableRect, count: count, gap: innerGap), [])
    }

    private static func computeRowsLayout(
        count: Int,
        usableRect: CGRect,
        innerGap: CGFloat,
        masterRatio: CGFloat,
        secondaryRatio: CGFloat
    ) -> ([CGRect], [DividerGeometry]) {
        let handleThickness = max(innerGap, 18)
        if count == 2 {
            let availableH = max(0, usableRect.height - innerGap)
            let firstH = availableH * masterRatio
            let secondH = availableH - firstH
            let top = CGRect(x: usableRect.minX, y: usableRect.minY, width: usableRect.width, height: firstH)
            let bottom = CGRect(x: usableRect.minX, y: usableRect.minY + firstH + innerGap, width: usableRect.width, height: secondH)
            let dividerY = usableRect.minY + firstH + (innerGap / 2.0) - (handleThickness / 2.0)
            let divider = DividerGeometry(
                id: "rows-horizontal",
                role: .primary,
                frame: CGRect(x: usableRect.minX, y: dividerY, width: usableRect.width, height: handleThickness),
                axis: .horizontal,
                currentRatio: masterRatio,
                containerLength: availableH
            )
            return ([top, bottom], [divider])
        } else if count >= 3 {
            let availableH = max(0, usableRect.height - innerGap)
            let firstH = availableH * masterRatio
            let remainingH = availableH - firstH
            let firstRow = CGRect(x: usableRect.minX, y: usableRect.minY, width: usableRect.width, height: firstH)
            let remainingArea = CGRect(
                x: usableRect.minX,
                y: usableRect.minY + firstH + innerGap,
                width: usableRect.width,
                height: remainingH
            )
            let (otherRows, otherDivs) = splitIntoRowsWithRatio(
                rect: remainingArea,
                count: count - 1,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "rows-sub"
            )
            let dividerY = usableRect.minY + firstH + (innerGap / 2.0) - (handleThickness / 2.0)
            let primaryDiv = DividerGeometry(
                id: "rows-primary",
                role: .primary,
                frame: CGRect(x: usableRect.minX, y: dividerY, width: usableRect.width, height: handleThickness),
                axis: .horizontal,
                currentRatio: masterRatio,
                containerLength: availableH
            )
            return ([firstRow] + otherRows, [primaryDiv] + otherDivs)
        }
        return (splitIntoEqualRows(rect: usableRect, count: count, gap: innerGap), [])
    }

    private static func computeGridLayout(
        count: Int,
        usableRect: CGRect,
        innerGap: CGFloat,
        masterRatio: CGFloat,
        leftSplitRatio: CGFloat,
        secondaryRatio: CGFloat
    ) -> ([CGRect], [DividerGeometry]) {
        let handleThickness = max(innerGap, 18)

        switch count {
        case 2:
            return computeColumnsLayout(
                count: 2,
                usableRect: usableRect,
                innerGap: innerGap,
                masterRatio: masterRatio,
                secondaryRatio: secondaryRatio
            )

        case 3:
            let availableW = max(0, usableRect.width - innerGap)
            let leftW = availableW * masterRatio
            let rightW = availableW - leftW
            let leftRect = CGRect(x: usableRect.minX, y: usableRect.minY, width: leftW, height: usableRect.height)
            let rightArea = CGRect(x: usableRect.minX + leftW + innerGap, y: usableRect.minY, width: rightW, height: usableRect.height)
            let (rightRows, rightDivs) = splitIntoRowsWithRatio(
                rect: rightArea,
                count: 2,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "grid-right"
            )
            let dividerX = usableRect.minX + leftW + (innerGap / 2.0) - (handleThickness / 2.0)
            let divider = DividerGeometry(
                id: "grid-vertical",
                role: .primary,
                frame: CGRect(x: dividerX, y: usableRect.minY, width: handleThickness, height: usableRect.height),
                axis: .vertical,
                currentRatio: masterRatio,
                containerLength: availableW
            )
            return ([leftRect] + rightRows, [divider] + rightDivs)

        case 4:
            let availableW = max(0, usableRect.width - innerGap)
            let leftW = availableW * masterRatio
            let rightW = availableW - leftW
            let leftArea = CGRect(x: usableRect.minX, y: usableRect.minY, width: leftW, height: usableRect.height)
            let rightArea = CGRect(x: usableRect.minX + leftW + innerGap, y: usableRect.minY, width: rightW, height: usableRect.height)
            let (leftRows, leftDivs) = splitIntoRowsWithRatio(
                rect: leftArea,
                count: 2,
                gap: innerGap,
                firstRatio: leftSplitRatio,
                role: .leftSecondary,
                idPrefix: "grid-left"
            )
            let (rightRows, rightDivs) = splitIntoRowsWithRatio(
                rect: rightArea,
                count: 2,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "grid-right"
            )
            // Order: Top-Left (0), Top-Right (1), Bottom-Left (2), Bottom-Right (3)
            let frames = [leftRows[0], rightRows[0], leftRows[1], rightRows[1]]
            let dividerX = usableRect.minX + leftW + (innerGap / 2.0) - (handleThickness / 2.0)
            let divider = DividerGeometry(
                id: "grid-vertical",
                role: .primary,
                frame: CGRect(x: dividerX, y: usableRect.minY, width: handleThickness, height: usableRect.height),
                axis: .vertical,
                currentRatio: masterRatio,
                containerLength: availableW
            )
            return (frames, [divider] + leftDivs + rightDivs)

        default:
            let cols = splitIntoEqualColumns(rect: usableRect, count: 3, gap: innerGap)
            let (col1Rows, col1Divs) = splitIntoRowsWithRatio(
                rect: cols[1],
                count: 2,
                gap: innerGap,
                firstRatio: leftSplitRatio,
                role: .leftSecondary,
                idPrefix: "grid5-col1"
            )
            let (col2Rows, col2Divs) = splitIntoRowsWithRatio(
                rect: cols[2],
                count: 2,
                gap: innerGap,
                firstRatio: secondaryRatio,
                role: .rightSecondary,
                idPrefix: "grid5-col2"
            )
            return ([cols[0], col1Rows[0], col2Rows[0], col1Rows[1], col2Rows[1]], col1Divs + col2Divs)
        }
    }

    private static func splitIntoRowsWithRatio(
        rect: CGRect,
        count: Int,
        gap: CGFloat,
        firstRatio: CGFloat,
        role: DividerRole,
        idPrefix: String
    ) -> ([CGRect], [DividerGeometry]) {
        guard count > 0 else { return ([], []) }
        if count == 1 { return ([rect], []) }

        let handleThickness = max(gap, 18)
        let clampedRatio = min(max(firstRatio, 0.18), 0.82)

        if count == 2 {
            let availableH = max(0, rect.height - gap)
            let firstH = availableH * clampedRatio
            let secondH = availableH - firstH
            let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstH)
            let bottom = CGRect(x: rect.minX, y: rect.minY + firstH + gap, width: rect.width, height: secondH)
            let dividerY = rect.minY + firstH + (gap / 2.0) - (handleThickness / 2.0)
            let div = DividerGeometry(
                id: "\(idPrefix)-horizontal",
                role: role,
                frame: CGRect(x: rect.minX, y: dividerY, width: rect.width, height: handleThickness),
                axis: .horizontal,
                currentRatio: clampedRatio,
                containerLength: availableH
            )
            return ([top, bottom], [div])
        } else {
            // For 3+ rows, first row uses clampedRatio of the first pair's space, remaining rows split equally
            let availableH = max(0, rect.height - gap)
            let firstH = availableH * clampedRatio
            let remainingH = max(0, availableH - firstH)
            let firstRow = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstH)
            let remainingRect = CGRect(x: rect.minX, y: rect.minY + firstH + gap, width: rect.width, height: remainingH)
            let restRows = splitIntoEqualRows(rect: remainingRect, count: count - 1, gap: gap)
            let dividerY = rect.minY + firstH + (gap / 2.0) - (handleThickness / 2.0)
            let div = DividerGeometry(
                id: "\(idPrefix)-horizontal",
                role: role,
                frame: CGRect(x: rect.minX, y: dividerY, width: rect.width, height: handleThickness),
                axis: .horizontal,
                currentRatio: clampedRatio,
                containerLength: availableH
            )
            return ([firstRow] + restRows, [div])
        }
    }

    private static func splitIntoColumnsWithRatio(
        rect: CGRect,
        count: Int,
        gap: CGFloat,
        firstRatio: CGFloat,
        role: DividerRole,
        idPrefix: String
    ) -> ([CGRect], [DividerGeometry]) {
        guard count > 0 else { return ([], []) }
        if count == 1 { return ([rect], []) }

        let handleThickness = max(gap, 18)
        let clampedRatio = min(max(firstRatio, 0.18), 0.82)

        if count == 2 {
            let availableW = max(0, rect.width - gap)
            let firstW = availableW * clampedRatio
            let secondW = availableW - firstW
            let left = CGRect(x: rect.minX, y: rect.minY, width: firstW, height: rect.height)
            let right = CGRect(x: rect.minX + firstW + gap, y: rect.minY, width: secondW, height: rect.height)
            let dividerX = rect.minX + firstW + (gap / 2.0) - (handleThickness / 2.0)
            let div = DividerGeometry(
                id: "\(idPrefix)-vertical",
                role: role,
                frame: CGRect(x: dividerX, y: rect.minY, width: handleThickness, height: rect.height),
                axis: .vertical,
                currentRatio: clampedRatio,
                containerLength: availableW
            )
            return ([left, right], [div])
        } else {
            let availableW = max(0, rect.width - gap)
            let firstW = availableW * clampedRatio
            let remainingW = max(0, availableW - firstW)
            let firstCol = CGRect(x: rect.minX, y: rect.minY, width: firstW, height: rect.height)
            let remainingRect = CGRect(x: rect.minX + firstW + gap, y: rect.minY, width: remainingW, height: rect.height)
            let restCols = splitIntoEqualColumns(rect: remainingRect, count: count - 1, gap: gap)
            let dividerX = rect.minX + firstW + (gap / 2.0) - (handleThickness / 2.0)
            let div = DividerGeometry(
                id: "\(idPrefix)-vertical",
                role: role,
                frame: CGRect(x: dividerX, y: rect.minY, width: handleThickness, height: rect.height),
                axis: .vertical,
                currentRatio: clampedRatio,
                containerLength: availableW
            )
            return ([firstCol] + restCols, [div])
        }
    }

    private static func splitIntoEqualColumns(rect: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        if count == 1 { return [rect] }
        let totalGaps = gap * CGFloat(count - 1)
        let colW = max(0, (rect.width - totalGaps) / CGFloat(count))
        return (0..<count).map { idx in
            let x = rect.minX + CGFloat(idx) * (colW + gap)
            return CGRect(x: x, y: rect.minY, width: colW, height: rect.height)
        }
    }

    private static func splitIntoEqualRows(rect: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        if count == 1 { return [rect] }
        let totalGaps = gap * CGFloat(count - 1)
        let rowH = max(0, (rect.height - totalGaps) / CGFloat(count))
        return (0..<count).map { idx in
            let y = rect.minY + CGFloat(idx) * (rowH + gap)
            return CGRect(x: rect.minX, y: y, width: rect.width, height: rowH)
        }
    }

    private static func centeredFloatingFrame(for window: LayoutWindowInput, in visibleFrame: CGRect) -> CGRect {
        let defaultW = min(max(window.currentFrame.width, 800), visibleFrame.width * 0.85)
        let defaultH = min(max(window.currentFrame.height, 600), visibleFrame.height * 0.85)
        let width = min(max(defaultW, window.minimumSize.width), visibleFrame.width)
        let height = min(max(defaultH, window.minimumSize.height), visibleFrame.height)
        let x = visibleFrame.minX + (visibleFrame.width - width) / 2.0
        let y = visibleFrame.minY + (visibleFrame.height - height) / 2.0
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x.rounded(),
            y: rect.origin.y.rounded(),
            width: rect.size.width.rounded(),
            height: rect.size.height.rounded()
        )
    }
}
