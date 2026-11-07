import Foundation
import SwiftUI
import AppKit
import Carbon
import ServiceManagement

public enum HighlightMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case none = "none"
    case activeBorder = "activeBorder"
    case allBorders = "allBorders"
    case glow = "glow"

    public var id: String { rawValue }
}

public enum PresetColorSwatch: String, CaseIterable, Codable, Sendable, Identifiable {
    case blue = "#007AFF"
    case purple = "#9B51E0"
    case pink = "#F43F85"
    case orange = "#FF9500"
    case green = "#28CD41"
    case gray = "#8E8E93"

    public var id: String { rawValue }

    public var swiftUIColor: Color {
        Color(nsColor: NSColor(hexString: rawValue) ?? .systemBlue)
    }
}

public enum AppIconStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case classic = "classic"
    case gold = "gold"
    case blue = "blue"
    case neon = "neon"
    case coral = "coral"
    case aurora = "aurora"
    case focus = "focus"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .gold: return "Amber"
        case .blue: return "Ocean"
        case .neon: return "Neon"
        case .coral: return "Coral"
        case .aurora: return "Aurora"
        case .focus: return "Focus"
        }
    }
}

public enum AppThemeOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case turkish = "tr"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }
}

public enum CardinalDirection: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case up
    case down
}

public enum ShortcutAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case toggleFloatWindow = "toggleFloatWindow"
    case toggleIgnoreApp = "toggleIgnoreApp"
    case toggleTiling = "toggleTiling"
    case cycleStack = "cycleStack"
    case toggleFocusMode = "toggleFocusMode"
    case layoutGrid = "layoutGrid"
    case layoutColumns = "layoutColumns"
    case layoutRows = "layoutRows"
    case layoutSide = "layoutSide"
    case swapWindowLeft = "swapWindowLeft"
    case swapWindowRight = "swapWindowRight"
    case swapWindowUp = "swapWindowUp"
    case swapWindowDown = "swapWindowDown"
    case moveDisplayLeft = "moveDisplayLeft"
    case moveDisplayRight = "moveDisplayRight"
    case moveDisplayUp = "moveDisplayUp"
    case moveDisplayDown = "moveDisplayDown"

    public var id: String { rawValue }

    public var hotKeyNumericID: UInt32 {
        switch self {
        case .toggleTiling: return 1
        case .cycleStack: return 2
        case .layoutGrid: return 3
        case .layoutColumns: return 4
        case .layoutRows: return 5
        case .layoutSide: return 6
        case .moveDisplayLeft: return 7
        case .moveDisplayRight: return 8
        case .moveDisplayUp: return 9
        case .moveDisplayDown: return 10
        case .swapWindowLeft: return 11
        case .swapWindowRight: return 12
        case .swapWindowUp: return 13
        case .swapWindowDown: return 14
        case .toggleFocusMode: return 15
        case .toggleFloatWindow: return 16
        case .toggleIgnoreApp: return 17
        }
    }
}

public struct KeyBinding: Codable, Sendable, Equatable, Hashable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public var displayString: String {
        var parts: [String] = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { parts.append("⌃") }
        if (carbonModifiers & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "")
    }

    public static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return "Key(\(keyCode))"
        }
    }

    public static func defaultBindings() -> [ShortcutAction: KeyBinding] {
        let ctrlOpt = UInt32(controlKey | optionKey)
        let ctrlOptShift = UInt32(controlKey | optionKey | shiftKey)

        // Following Shoji convention: ⌃⌥ + Arrow swaps windows; ⌃⌥⇧ + Arrow moves window to another monitor
        return [
            .toggleFloatWindow: KeyBinding(keyCode: UInt32(kVK_ANSI_W), carbonModifiers: ctrlOpt),
            .toggleIgnoreApp: KeyBinding(keyCode: UInt32(kVK_ANSI_I), carbonModifiers: ctrlOpt),
            .toggleTiling: KeyBinding(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: ctrlOpt),
            .cycleStack: KeyBinding(keyCode: UInt32(kVK_Space), carbonModifiers: ctrlOpt),
            .toggleFocusMode: KeyBinding(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: ctrlOpt),
            .layoutGrid: KeyBinding(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: ctrlOpt),
            .layoutColumns: KeyBinding(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: ctrlOpt),
            .layoutRows: KeyBinding(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: ctrlOpt),
            .layoutSide: KeyBinding(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: ctrlOpt),
            .swapWindowLeft: KeyBinding(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: ctrlOpt),
            .swapWindowRight: KeyBinding(keyCode: UInt32(kVK_RightArrow), carbonModifiers: ctrlOpt),
            .swapWindowUp: KeyBinding(keyCode: UInt32(kVK_UpArrow), carbonModifiers: ctrlOpt),
            .swapWindowDown: KeyBinding(keyCode: UInt32(kVK_DownArrow), carbonModifiers: ctrlOpt),
            .moveDisplayLeft: KeyBinding(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: ctrlOptShift),
            .moveDisplayRight: KeyBinding(keyCode: UInt32(kVK_RightArrow), carbonModifiers: ctrlOptShift),
            .moveDisplayUp: KeyBinding(keyCode: UInt32(kVK_UpArrow), carbonModifiers: ctrlOptShift),
            .moveDisplayDown: KeyBinding(keyCode: UInt32(kVK_DownArrow), carbonModifiers: ctrlOptShift)
        ]
    }
}

public struct DisplayLayoutState: Codable, Sendable, Equatable {
    public var layout: TileLayoutKind
    public var masterRatio: Double
    public var leftSplitRatio: Double
    public var secondaryRatio: Double
    public var leftPaneCount: Int
    public var maxTilesOverride: Int?
    public var activeTileIndex: Int
    public var activeStackOffset: Int

    public init(
        layout: TileLayoutKind = .side,
        masterRatio: Double = 0.50,
        leftSplitRatio: Double = 0.50,
        secondaryRatio: Double = 0.50,
        leftPaneCount: Int = 1,
        maxTilesOverride: Int? = nil,
        activeTileIndex: Int = 0,
        activeStackOffset: Int = 0
    ) {
        self.layout = layout
        self.masterRatio = min(max(masterRatio, 0.18), 0.82)
        self.leftSplitRatio = min(max(leftSplitRatio, 0.18), 0.82)
        self.secondaryRatio = min(max(secondaryRatio, 0.18), 0.82)
        self.leftPaneCount = max(1, leftPaneCount)
        self.maxTilesOverride = maxTilesOverride
        self.activeTileIndex = max(0, activeTileIndex)
        self.activeStackOffset = max(0, activeStackOffset)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.layout = try container.decodeIfPresent(TileLayoutKind.self, forKey: .layout) ?? .side
        let mr = try container.decodeIfPresent(Double.self, forKey: .masterRatio) ?? 0.50
        let lr = try container.decodeIfPresent(Double.self, forKey: .leftSplitRatio) ?? 0.50
        let sr = try container.decodeIfPresent(Double.self, forKey: .secondaryRatio) ?? 0.50
        self.masterRatio = min(max(mr, 0.18), 0.82)
        self.leftSplitRatio = min(max(lr, 0.18), 0.82)
        self.secondaryRatio = min(max(sr, 0.18), 0.82)
        self.leftPaneCount = max(1, try container.decodeIfPresent(Int.self, forKey: .leftPaneCount) ?? 1)
        self.maxTilesOverride = try container.decodeIfPresent(Int.self, forKey: .maxTilesOverride)
        self.activeTileIndex = max(0, try container.decodeIfPresent(Int.self, forKey: .activeTileIndex) ?? 0)
        self.activeStackOffset = max(0, try container.decodeIfPresent(Int.self, forKey: .activeStackOffset) ?? 0)
    }
}

@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults

    public var innerGap: Double {
        didSet {
            defaults.set(innerGap, forKey: Keys.innerGap)
            onSettingsChanged?()
        }
    }

    public var outerPadding: Double {
        didSet {
            defaults.set(outerPadding, forKey: Keys.outerPadding)
            onSettingsChanged?()
        }
    }

    /// Unified Space slider (0...32 pt) matching the Apple-style minimal card UI
    public var unifiedSpacePt: Double {
        get { innerGap }
        set {
            let rounded = newValue.rounded()
            let cb = onSettingsChanged
            onSettingsChanged = nil
            innerGap = rounded
            outerPadding = rounded
            onSettingsChanged = cb
            onSettingsChanged?()
        }
    }

    public var defaultMasterRatio: Double {
        didSet {
            let clamped = min(max(defaultMasterRatio, 0.18), 0.82)
            if defaultMasterRatio != clamped {
                defaultMasterRatio = clamped
                return
            }
            defaults.set(defaultMasterRatio, forKey: Keys.defaultMasterRatio)
            onSettingsChanged?()
        }
    }

    public var smartGaps: Bool {
        didSet {
            defaults.set(smartGaps, forKey: Keys.smartGaps)
            onSettingsChanged?()
        }
    }

    public var highlightMode: HighlightMode {
        didSet {
            defaults.set(highlightMode.rawValue, forKey: Keys.highlightMode)
            onSettingsChanged?()
        }
    }

    public var highlightColorHex: String {
        didSet {
            defaults.set(highlightColorHex, forKey: Keys.highlightColorHex)
            onSettingsChanged?()
        }
    }

    public var borderWidth: Double {
        didSet {
            defaults.set(borderWidth, forKey: Keys.borderWidth)
            onSettingsChanged?()
        }
    }

    public var appIconStyle: AppIconStyle {
        didSet {
            defaults.set(appIconStyle.rawValue, forKey: Keys.appIconStyle)
            applyAppIcon()
        }
    }

    // Built-in signature modes: Focus, No Peek, Clean Space, Tab View
    public var isFocusModeEnabled: Bool {
        didSet {
            defaults.set(isFocusModeEnabled, forKey: Keys.isFocusModeEnabled)
            onSettingsChanged?()
        }
    }

    public var isNoPeekEnabled: Bool {
        didSet {
            defaults.set(isNoPeekEnabled, forKey: Keys.isNoPeekEnabled)
            onSettingsChanged?()
        }
    }

    public var isCleanSpaceEnabled: Bool {
        didSet {
            defaults.set(isCleanSpaceEnabled, forKey: Keys.isCleanSpaceEnabled)
            onSettingsChanged?()
        }
    }

    public var isTabViewEnabled: Bool {
        didSet {
            defaults.set(isTabViewEnabled, forKey: Keys.isTabViewEnabled)
            onSettingsChanged?()
        }
    }

    public var isTaskbarPreviewEnabled: Bool {
        didSet {
            defaults.set(isTaskbarPreviewEnabled, forKey: Keys.isTaskbarPreviewEnabled)
            onSettingsChanged?()
        }
    }

    public var isLivePreviewScreenshotsEnabled: Bool {
        didSet {
            defaults.set(isLivePreviewScreenshotsEnabled, forKey: Keys.isLivePreviewScreenshotsEnabled)
            onSettingsChanged?()
        }
    }

    public var isWindowQuickActionBarEnabled: Bool {
        didSet {
            defaults.set(isWindowQuickActionBarEnabled, forKey: Keys.isWindowQuickActionBarEnabled)
            onSettingsChanged?()
        }
    }

    public var quickActionHorizontalRatio: Double {
        didSet {
            let clamped = min(max(quickActionHorizontalRatio, 0.15), 0.92)
            if quickActionHorizontalRatio != clamped {
                quickActionHorizontalRatio = clamped
                return
            }
            defaults.set(quickActionHorizontalRatio, forKey: Keys.quickActionHorizontalRatio)
            onSettingsChanged?()
        }
    }

    public var quickActionAtBottom: Bool {
        didSet {
            defaults.set(quickActionAtBottom, forKey: Keys.quickActionAtBottom)
            onSettingsChanged?()
        }
    }

    public var mouseFollowsFocus: Bool {
        didSet {
            defaults.set(mouseFollowsFocus, forKey: Keys.mouseFollowsFocus)
        }
    }

    public var isTilingPaused: Bool {
        didSet {
            defaults.set(isTilingPaused, forKey: Keys.isTilingPaused)
            onSettingsChanged?()
        }
    }

    public var isPausedByStageManager: Bool = false {
        didSet {
            onSettingsChanged?()
        }
    }

    public var isEffectivelyPaused: Bool {
        isTilingPaused || isPausedByStageManager
    }

    public var ignoredBundleIDs: Set<String> {
        didSet {
            defaults.set(Array(ignoredBundleIDs).sorted(), forKey: Keys.ignoredBundleIDs)
            onSettingsChanged?()
        }
    }

    public var displayStates: [String: DisplayLayoutState] {
        didSet {
            saveCodable(displayStates, forKey: Keys.displayStates)
            onSettingsChanged?()
        }
    }

    public var keyBindings: [ShortcutAction: KeyBinding] {
        didSet {
            saveCodable(keyBindings, forKey: Keys.keyBindings)
            onShortcutsChanged?()
        }
    }

    public var appTheme: AppThemeOption {
        didSet {
            defaults.set(appTheme.rawValue, forKey: Keys.appTheme)
            applyTheme()
        }
    }

    public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }

    public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLoginService(enabled: launchAtLogin)
        }
    }

    public var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    public var onSettingsChanged: (() -> Void)?
    public var onShortcutsChanged: (() -> Void)?

    private enum Keys {
        static let innerGap = "tessera.innerGap"
        static let outerPadding = "tessera.outerPadding"
        static let defaultMasterRatio = "tessera.defaultMasterRatio"
        static let smartGaps = "tessera.smartGaps"
        static let highlightMode = "tessera.highlightMode"
        static let highlightColorHex = "tessera.highlightColorHex"
        static let borderWidth = "tessera.borderWidth"
        static let appIconStyle = "tessera.appIconStyle"
        static let isFocusModeEnabled = "tessera.isFocusModeEnabled"
        static let isNoPeekEnabled = "tessera.isNoPeekEnabled"
        static let isCleanSpaceEnabled = "tessera.isCleanSpaceEnabled"
        static let isTabViewEnabled = "tessera.isTabViewEnabled"
        static let isTaskbarPreviewEnabled = "tessera.isTaskbarPreviewEnabled"
        static let isLivePreviewScreenshotsEnabled = "tessera.isLivePreviewScreenshotsEnabled"
        static let isWindowQuickActionBarEnabled = "tessera.isWindowQuickActionBarEnabled"
        static let quickActionHorizontalRatio = "tessera.quickActionHorizontalRatio"
        static let quickActionAtBottom = "tessera.quickActionAtBottom"
        static let mouseFollowsFocus = "tessera.mouseFollowsFocus"
        static let isTilingPaused = "tessera.isTilingPaused"
        static let ignoredBundleIDs = "tessera.ignoredBundleIDs"
        static let displayStates = "tessera.displayStates"
        static let keyBindings = "tessera.keyBindings"
        static let appTheme = "tessera.appTheme"
        static let language = "tessera.language"
        static let launchAtLogin = "tessera.launchAtLogin"
        static let hasCompletedOnboarding = "tessera.hasCompletedOnboarding"
    }

    public static let defaultIgnoredBundles: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.screencaptureui",
        "com.tessera.windowmanager",
        "com.vetra.windowmanager"
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.innerGap = defaults.object(forKey: Keys.innerGap) as? Double ?? 12.0
        self.outerPadding = defaults.object(forKey: Keys.outerPadding) as? Double ?? 12.0
        self.defaultMasterRatio = defaults.object(forKey: Keys.defaultMasterRatio) as? Double ?? 0.50
        self.smartGaps = defaults.object(forKey: Keys.smartGaps) as? Bool ?? true

        if let rawHighlight = defaults.string(forKey: Keys.highlightMode),
           let mode = HighlightMode(rawValue: rawHighlight) {
            self.highlightMode = mode
        } else {
            self.highlightMode = .glow
        }

        self.highlightColorHex = defaults.string(forKey: Keys.highlightColorHex) ?? PresetColorSwatch.blue.rawValue
        self.borderWidth = defaults.object(forKey: Keys.borderWidth) as? Double ?? 3.0

        if let rawIcon = defaults.string(forKey: Keys.appIconStyle),
           let style = AppIconStyle(rawValue: rawIcon) {
            self.appIconStyle = style
        } else {
            self.appIconStyle = .focus
        }

        self.isFocusModeEnabled = defaults.object(forKey: Keys.isFocusModeEnabled) as? Bool ?? false
        self.isNoPeekEnabled = defaults.object(forKey: Keys.isNoPeekEnabled) as? Bool ?? true
        self.isCleanSpaceEnabled = defaults.object(forKey: Keys.isCleanSpaceEnabled) as? Bool ?? false
        self.isTabViewEnabled = defaults.object(forKey: Keys.isTabViewEnabled) as? Bool ?? true
        self.isTaskbarPreviewEnabled = defaults.object(forKey: Keys.isTaskbarPreviewEnabled) as? Bool ?? true
        self.isLivePreviewScreenshotsEnabled = defaults.object(forKey: Keys.isLivePreviewScreenshotsEnabled) as? Bool ?? true
        self.isWindowQuickActionBarEnabled = defaults.object(forKey: Keys.isWindowQuickActionBarEnabled) as? Bool ?? true
        self.quickActionHorizontalRatio = min(max(defaults.object(forKey: Keys.quickActionHorizontalRatio) as? Double ?? 0.62, 0.15), 0.92)
        self.quickActionAtBottom = defaults.object(forKey: Keys.quickActionAtBottom) as? Bool ?? false

        self.mouseFollowsFocus = defaults.object(forKey: Keys.mouseFollowsFocus) as? Bool ?? false
        self.isTilingPaused = defaults.object(forKey: Keys.isTilingPaused) as? Bool ?? false

        if let savedIgnored = defaults.stringArray(forKey: Keys.ignoredBundleIDs) {
            self.ignoredBundleIDs = Set(savedIgnored).union(Self.defaultIgnoredBundles)
        } else {
            self.ignoredBundleIDs = Self.defaultIgnoredBundles
        }

        if let data = defaults.data(forKey: Keys.displayStates),
           let decoded = try? JSONDecoder().decode([String: DisplayLayoutState].self, from: data) {
            self.displayStates = decoded
        } else {
            self.displayStates = [:]
        }

        if let data = defaults.data(forKey: Keys.keyBindings),
           let decoded = try? JSONDecoder().decode([ShortcutAction: KeyBinding].self, from: data) {
            var merged = KeyBinding.defaultBindings()
            for (k, v) in decoded { merged[k] = v }
            self.keyBindings = merged
        } else {
            self.keyBindings = KeyBinding.defaultBindings()
        }

        if let rawTheme = defaults.string(forKey: Keys.appTheme),
           let theme = AppThemeOption(rawValue: rawTheme) {
            self.appTheme = theme
        } else {
            self.appTheme = .system
        }

        if let rawLang = defaults.string(forKey: Keys.language),
           let lang = AppLanguage(rawValue: rawLang) {
            self.language = lang
        } else {
            self.language = .turkish
        }

        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
    }

    // MARK: - Display Layout Helpers

    public func state(for displayID: CGDirectDisplayID) -> DisplayLayoutState {
        let key = String(displayID)
        if let existing = displayStates[key] {
            return existing
        }
        return DisplayLayoutState(layout: .side, masterRatio: defaultMasterRatio, activeTileIndex: 0, activeStackOffset: 0)
    }

    public func setLayout(_ layout: TileLayoutKind, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        current.layout = layout
        current.activeStackOffset = 0
        displayStates[key] = current
    }

    public func setMaxTilesOverride(_ maxTiles: Int?, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        current.maxTilesOverride = maxTiles
        displayStates[key] = current
    }

    public func setMasterRatio(_ ratio: Double, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        current.masterRatio = min(max(ratio, 0.18), 0.82)
        displayStates[key] = current
    }

    public func setSplitRatio(_ ratio: Double, role: DividerRole, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        let clamped = min(max(ratio, 0.18), 0.82)
        switch role {
        case .primary:
            current.masterRatio = clamped
        case .leftSecondary:
            current.leftSplitRatio = clamped
        case .rightSecondary:
            current.secondaryRatio = clamped
        }
        displayStates[key] = current
    }

    public func setSplitRatioForLiveDrag(_ ratio: Double, role: DividerRole, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        let clamped = min(max(ratio, 0.18), 0.82)
        switch role {
        case .primary:
            current.masterRatio = clamped
        case .leftSecondary:
            current.leftSplitRatio = clamped
        case .rightSecondary:
            current.secondaryRatio = clamped
        }
        let callback = onSettingsChanged
        onSettingsChanged = nil
        displayStates[key] = current
        onSettingsChanged = callback
    }

    public func setLeftPaneCount(_ count: Int, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        let clamped = max(1, count)
        if current.leftPaneCount != clamped {
            current.leftPaneCount = clamped
            displayStates[key] = current
        }
    }

    public func setActiveTileIndex(_ index: Int, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        if current.activeTileIndex != index {
            current.activeTileIndex = max(0, index)
            displayStates[key] = current
        }
    }

    public func setStackOffset(_ offset: Int, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        current.activeStackOffset = max(0, offset)
        displayStates[key] = current
    }

    public func incrementStackOffset(for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        var current = state(for: displayID)
        current.activeStackOffset += 1
        displayStates[key] = current
    }

    // MARK: - App Exclusion Helpers

    public func isBundleIgnored(_ bundleID: String) -> Bool {
        ignoredBundleIDs.contains(bundleID)
    }

    public func toggleIgnoreBundle(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        if ignoredBundleIDs.contains(bundleID) {
            ignoredBundleIDs.remove(bundleID)
        } else {
            ignoredBundleIDs.insert(bundleID)
        }
    }

    // MARK: - Shortcut Conflict Detection

    public func conflictingActions(for action: ShortcutAction) -> [ShortcutAction] {
        guard let targetBinding = keyBindings[action] else { return [] }
        return ShortcutAction.allCases.filter { other in
            other != action && keyBindings[other] == targetBinding
        }
    }

    public func resetShortcutsToDefault() {
        keyBindings = KeyBinding.defaultBindings()
    }

    // MARK: - Color & Icon Helpers

    public var highlightNSColor: NSColor {
        NSColor(hexString: highlightColorHex) ?? NSColor.systemBlue
    }

    public var highlightSwiftUIColor: Color {
        get { Color(nsColor: highlightNSColor) }
        set {
            if let nsColor = NSColor(newValue).usingColorSpace(.sRGB) {
                highlightColorHex = nsColor.toHexString()
            }
        }
    }

    public func applyTheme() {
        switch appTheme {
        case .system:
            NSApp?.appearance = nil
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    public func applyAppIcon() {
        let renderer = ImageRenderer(content: AppIconArtworkView(style: appIconStyle, size: 256))
        renderer.scale = 2.0
        if let nsImage = renderer.nsImage {
            NSApp?.applicationIconImage = nsImage
        }
    }

    private func updateLaunchAtLoginService(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {}
    }

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Bespoke Menu Bar Brand Logo & 3D Glass Squircle App Icon

public struct MenuBarBrandIcon: View {
    public let isPaused: Bool

    public init(isPaused: Bool) {
        self.isPaused = isPaused
    }

    public var body: some View {
        Image(nsImage: Self.makeTemplateImage(isPaused: isPaused))
    }

    public static func makeTemplateImage(isPaused: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            let alpha: CGFloat = isPaused ? 0.45 : 1.0
            let color = NSColor.labelColor.withAlphaComponent(alpha).cgColor
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)

            // Outer frame border
            let outerRect = NSRect(x: 1.5, y: 2.5, width: 15.0, height: 13.0)
            let outerPath = CGPath(roundedRect: outerRect, cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)
            ctx.setLineWidth(1.4)
            ctx.addPath(outerPath)
            ctx.strokePath()

            // Left Master Pane (Filled)
            let leftPane = NSRect(x: 3.4, y: 4.4, width: 5.2, height: 9.2)
            let leftPath = CGPath(roundedRect: leftPane, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(leftPath)
            ctx.fillPath()

            // Top-Right Pane
            let topRightPane = NSRect(x: 10.0, y: 9.4, width: 4.6, height: 4.2)
            let trPath = CGPath(roundedRect: topRightPane, cornerWidth: 1.3, cornerHeight: 1.3, transform: nil)
            ctx.setFillColor(NSColor.labelColor.withAlphaComponent(alpha * 0.80).cgColor)
            ctx.addPath(trPath)
            ctx.fillPath()

            // Bottom-Right Pane
            let bottomRightPane = NSRect(x: 10.0, y: 4.4, width: 4.6, height: 3.8)
            let brPath = CGPath(roundedRect: bottomRightPane, cornerWidth: 1.3, cornerHeight: 1.3, transform: nil)
            ctx.setFillColor(NSColor.labelColor.withAlphaComponent(alpha * 0.55).cgColor)
            ctx.addPath(brPath)
            ctx.fillPath()

            ctx.restoreGState()
            return true
        }
        img.isTemplate = true
        return img
    }
}

public struct AppIconArtworkView: View {
    public let style: AppIconStyle
    public let size: CGFloat

    public init(style: AppIconStyle, size: CGFloat = 36) {
        self.style = style
        self.size = size
    }

    public var body: some View {
        let corner = size * 0.225
        let pad = size * 0.175
        let gap = size * 0.062
        let tileCorner = size * 0.075

        ZStack {
            // 1. Squircle Base with Rich Multi-Stop Gradient
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(backgroundGradient)

            // 2. Ambient Radial Top-Left Highlight
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [ambientGlowColor.opacity(0.32), Color.clear],
                        center: .topLeading,
                        startRadius: size * 0.04,
                        endRadius: size * 0.78
                    )
                )

            // 3. Asymmetric Vetra Architectural Panes (Tall Master Left + 2 Stacked Right)
            HStack(spacing: gap) {
                // Left Master Pane with subtle glass header strip
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                        .fill(masterTileFill)
                        .shadow(color: .black.opacity(0.24), radius: size * 0.035, y: size * 0.018)

                    // Subtle top header bar inside the master pane
                    UnevenRoundedRectangle(
                        topLeadingRadius: tileCorner,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: tileCorner,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.24))
                    .frame(height: size * 0.11)

                    RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.65), Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(0.7, size * 0.016)
                        )
                }
                .frame(width: (size - pad * 2 - gap) * 0.50)

                // Right Stacked Panes
                VStack(spacing: gap) {
                    ZStack {
                        RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                            .fill(topRightTileFill)
                            .shadow(color: .black.opacity(0.18), radius: size * 0.025, y: size * 0.012)
                        RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: max(0.6, size * 0.013))
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                            .fill(bottomRightTileFill)
                            .shadow(color: .black.opacity(0.18), radius: size * 0.025, y: size * 0.012)
                        RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: max(0.6, size * 0.013))
                    }
                }
            }
            .padding(pad)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.white.opacity(0.08), Color.black.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.8, size * 0.02)
                )
        )
    }

    private var ambientGlowColor: Color {
        switch style {
        case .classic: return Color.white
        case .gold: return Color(red: 1.0, green: 0.78, blue: 0.35)
        case .blue: return Color(red: 0.55, green: 0.88, blue: 1.0)
        case .neon: return Color(red: 0.98, green: 0.38, blue: 0.82)
        case .coral: return Color(red: 1.0, green: 0.82, blue: 0.45)
        case .aurora: return Color.white
        case .focus: return Color(red: 0.25, green: 0.68, blue: 1.0)
        }
    }

    private var backgroundGradient: LinearGradient {
        switch style {
        case .classic:
            return LinearGradient(colors: [Color(red: 0.95, green: 0.93, blue: 0.89), Color(red: 0.85, green: 0.82, blue: 0.76)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gold:
            return LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.10), Color(red: 0.07, green: 0.06, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .blue:
            return LinearGradient(colors: [Color(red: 0.16, green: 0.54, blue: 1.0), Color(red: 0.06, green: 0.24, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neon:
            return LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.25), Color(red: 0.06, green: 0.04, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .coral:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.46, blue: 0.28), Color(red: 0.82, green: 0.20, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .aurora:
            return LinearGradient(colors: [Color(red: 0.32, green: 0.28, blue: 0.92), Color(red: 0.86, green: 0.36, blue: 0.64), Color(red: 0.96, green: 0.66, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .focus:
            return LinearGradient(colors: [Color(red: 0.14, green: 0.17, blue: 0.24), Color(red: 0.07, green: 0.08, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var masterTileFill: AnyShapeStyle {
        switch style {
        case .classic:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.18, green: 0.19, blue: 0.22), Color(red: 0.10, green: 0.11, blue: 0.13)], startPoint: .top, endPoint: .bottom))
        case .gold:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.56), Color(red: 0.90, green: 0.60, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .blue, .coral:
            return AnyShapeStyle(LinearGradient(colors: [Color.white, Color(white: 0.90)], startPoint: .top, endPoint: .bottom))
        case .neon:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.58), Color(red: 0.68, green: 0.28, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .aurora:
            return AnyShapeStyle(LinearGradient(colors: [Color.white, Color.white.opacity(0.86)], startPoint: .top, endPoint: .bottom))
        case .focus:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.32, green: 0.76, blue: 1.0), Color(red: 0.10, green: 0.46, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var topRightTileFill: AnyShapeStyle {
        switch style {
        case .classic:
            return AnyShapeStyle(Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.78))
        case .gold:
            return AnyShapeStyle(Color(red: 0.96, green: 0.74, blue: 0.38).opacity(0.82))
        case .blue, .coral:
            return AnyShapeStyle(Color.white.opacity(0.82))
        case .neon:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.32, green: 0.86, blue: 1.0), Color(red: 0.46, green: 0.36, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .aurora:
            return AnyShapeStyle(Color.white.opacity(0.76))
        case .focus:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.38, green: 0.78, blue: 1.0).opacity(0.45), Color(red: 0.20, green: 0.52, blue: 0.96).opacity(0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var bottomRightTileFill: AnyShapeStyle {
        switch style {
        case .classic:
            return AnyShapeStyle(Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.55))
        case .gold:
            return AnyShapeStyle(Color(red: 0.96, green: 0.74, blue: 0.38).opacity(0.48))
        case .blue, .coral:
            return AnyShapeStyle(Color.white.opacity(0.56))
        case .neon:
            return AnyShapeStyle(Color(red: 0.78, green: 0.36, blue: 0.96).opacity(0.50))
        case .aurora:
            return AnyShapeStyle(Color.white.opacity(0.52))
        case .focus:
            return AnyShapeStyle(Color.white.opacity(0.18))
        }
    }
}

extension NSColor {
    public convenience init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let rgbValue = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    public func toHexString() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#007AFF" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
