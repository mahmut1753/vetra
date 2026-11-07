import Foundation
import CoreGraphics

public enum TileLayoutKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case grid = "grid"
    case columns = "columns"
    case rows = "rows"
    case side = "side"

    public var id: String { rawValue }

    public var systemImageName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .columns: return "rectangle.split.3x1"
        case .rows: return "rectangle.split.1x2"
        case .side: return "sidebar.left"
        }
    }
}

public enum MasterRatioPreset: Double, CaseIterable, Codable, Sendable, Identifiable {
    case fifty = 0.50
    case sixty = 0.60
    case twoThirds = 0.6667

    public var id: Double { rawValue }

    public var displayLabel: String {
        switch self {
        case .fifty: return "50%"
        case .sixty: return "60%"
        case .twoThirds: return "66.7%"
        }
    }
}

public enum DividerAxis: String, Codable, Sendable, Equatable {
    case vertical   // A vertical divider line separating left and right regions (dragged horizontally)
    case horizontal // A horizontal divider line separating top and bottom regions (dragged vertically)
}

public enum DividerRole: String, Codable, Sendable, Equatable {
    case primary        // Main split (masterRatio)
    case leftSecondary  // Split between windows stacked on the left/first pane (leftSplitRatio)
    case rightSecondary // Split between windows stacked on the right/second pane (secondaryRatio)
}

public struct DividerGeometry: Sendable, Equatable, Identifiable {
    public let id: String
    public let role: DividerRole
    public let frame: CGRect
    public let axis: DividerAxis
    public let currentRatio: CGFloat
    public let containerLength: CGFloat
    public let minRatio: CGFloat
    public let maxRatio: CGFloat

    public init(
        id: String,
        role: DividerRole = .primary,
        frame: CGRect,
        axis: DividerAxis,
        currentRatio: CGFloat,
        containerLength: CGFloat,
        minRatio: CGFloat = 0.18,
        maxRatio: CGFloat = 0.82
    ) {
        self.id = id
        self.role = role
        self.frame = frame
        self.axis = axis
        self.currentRatio = currentRatio
        self.containerLength = containerLength
        self.minRatio = minRatio
        self.maxRatio = maxRatio
    }
}

public struct ScreenBounds: Sendable, Equatable {
    public let displayID: UInt32
    public let visibleFrame: CGRect
    public let fullFrame: CGRect

    public init(displayID: UInt32, visibleFrame: CGRect, fullFrame: CGRect) {
        self.displayID = displayID
        self.visibleFrame = visibleFrame
        self.fullFrame = fullFrame
    }

    public var aspectRatio: CGFloat {
        guard visibleFrame.height > 0 else { return 1.0 }
        return visibleFrame.width / visibleFrame.height
    }

    public var isUltrawide: Bool {
        aspectRatio >= 2.1
    }

    public var isPortrait: Bool {
        visibleFrame.height > visibleFrame.width
    }

    public var maxTileCapacity: Int {
        isUltrawide ? 5 : 4
    }
}

public struct LayoutWindowInput: Sendable, Equatable, Identifiable {
    public let id: String
    public let pid: Int32
    public let bundleIdentifier: String
    public let label: String
    public let minimumSize: CGSize
    public let currentFrame: CGRect

    public init(
        id: String,
        pid: Int32,
        bundleIdentifier: String,
        label: String = "",
        minimumSize: CGSize = .zero,
        currentFrame: CGRect = .zero
    ) {
        self.id = id
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.label = label
        self.minimumSize = minimumSize
        self.currentFrame = currentFrame
    }
}

public struct LayoutConfiguration: Sendable, Equatable {
    public var layout: TileLayoutKind
    public var innerGap: CGFloat
    public var outerPadding: CGFloat
    public var masterRatio: CGFloat
    public var leftSplitRatio: CGFloat
    public var secondaryRatio: CGFloat
    public var leftPaneCount: Int
    public var maxTilesOverride: Int?
    public var smartGaps: Bool
    public var activeTileIndex: Int
    public var activeStackOffset: Int

    public init(
        layout: TileLayoutKind = .side,
        innerGap: CGFloat = 10,
        outerPadding: CGFloat = 12,
        masterRatio: CGFloat = 0.50,
        leftSplitRatio: CGFloat = 0.50,
        secondaryRatio: CGFloat = 0.50,
        leftPaneCount: Int = 1,
        maxTilesOverride: Int? = nil,
        smartGaps: Bool = true,
        activeTileIndex: Int = 0,
        activeStackOffset: Int = 0
    ) {
        self.layout = layout
        self.innerGap = max(0, innerGap)
        self.outerPadding = max(0, outerPadding)
        self.masterRatio = min(max(masterRatio, 0.18), 0.82)
        self.leftSplitRatio = min(max(leftSplitRatio, 0.18), 0.82)
        self.secondaryRatio = min(max(secondaryRatio, 0.18), 0.82)
        self.leftPaneCount = max(1, leftPaneCount)
        self.maxTilesOverride = maxTilesOverride
        self.smartGaps = smartGaps
        self.activeTileIndex = max(0, activeTileIndex)
        self.activeStackOffset = max(0, activeStackOffset)
    }
}

public enum WindowPlacementMode: Sendable, Equatable {
    case tiled(tileIndex: Int, stackPosition: Int, stackCount: Int, isTopOfStack: Bool)
    case floating
}

public struct WindowPlacementResult: Sendable, Equatable, Identifiable {
    public let id: String
    public let pid: Int32
    public let targetFrame: CGRect
    public let mode: WindowPlacementMode

    public init(
        id: String,
        pid: Int32,
        targetFrame: CGRect,
        mode: WindowPlacementMode
    ) {
        self.id = id
        self.pid = pid
        self.targetFrame = targetFrame
        self.mode = mode
    }

    public var isFloating: Bool {
        if case .floating = mode { return true }
        return false
    }

    public var tileIndex: Int? {
        if case .tiled(let idx, _, _, _) = mode { return idx }
        return nil
    }
}

public struct StackBadgeDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let tileIndex: Int
    public let tileFrame: CGRect
    public let activeOneBasedIndex: Int
    public let totalCount: Int
    public let windowIDs: [String]
    public let windowLabels: [String]

    public var badgeText: String {
        "[\(activeOneBasedIndex)/\(totalCount)]"
    }

    public init(
        tileIndex: Int,
        tileFrame: CGRect,
        activeOneBasedIndex: Int,
        totalCount: Int,
        windowIDs: [String],
        windowLabels: [String] = []
    ) {
        self.id = "stack-badge-\(tileIndex)"
        self.tileIndex = tileIndex
        self.tileFrame = tileFrame
        self.activeOneBasedIndex = activeOneBasedIndex
        self.totalCount = totalCount
        self.windowIDs = windowIDs
        self.windowLabels = windowLabels
    }
}

public struct LayoutCalculationOutput: Sendable, Equatable {
    public let placements: [WindowPlacementResult]
    public let tileFrames: [CGRect]
    public let stackBadges: [StackBadgeDescriptor]
    public let dividers: [DividerGeometry]
    public let effectiveMasterRatio: CGFloat

    public init(
        placements: [WindowPlacementResult],
        tileFrames: [CGRect],
        stackBadges: [StackBadgeDescriptor],
        dividers: [DividerGeometry],
        effectiveMasterRatio: CGFloat
    ) {
        self.placements = placements
        self.tileFrames = tileFrames
        self.stackBadges = stackBadges
        self.dividers = dividers
        self.effectiveMasterRatio = effectiveMasterRatio
    }
}
