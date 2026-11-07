import Foundation
import ApplicationServices

public struct FilterableWindowProperties: Sendable, Equatable {
    public let bundleIdentifier: String
    public let role: String
    public let subrole: String
    public let title: String
    public let frame: CGRect
    public let minimumSize: CGSize
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let isModal: Bool
    public let isResizable: Bool
    public let hasMinimizeButton: Bool
    public let hasZoomButton: Bool

    public init(
        bundleIdentifier: String,
        role: String = "AXWindow",
        subrole: String = "AXStandardWindow",
        title: String = "Document",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        minimumSize: CGSize = CGSize(width: 200, height: 150),
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        isModal: Bool = false,
        isResizable: Bool = true,
        hasMinimizeButton: Bool = true,
        hasZoomButton: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.title = title
        self.frame = frame
        self.minimumSize = minimumSize
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isModal = isModal
        self.isResizable = isResizable
        self.hasMinimizeButton = hasMinimizeButton
        self.hasZoomButton = hasZoomButton
    }
}

public struct WindowFilter: Sendable {
    private static let excludedSubroles: Set<String> = [
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String,
        kAXFloatingWindowSubrole as String,
        kAXSystemFloatingWindowSubrole as String,
        "AXSheet",
        "AXDrawer",
        "AXUnknown"
    ]

    private static let excludedRoles: Set<String> = [
        "AXSheet",
        "AXDrawer",
        "AXPopover",
        "AXHelpTag",
        "AXMenu",
        "AXGrowArea"
    ]

    private static let pipAndSettingsKeywords: [String] = [
        "picture in picture",
        "picture-in-picture",
        "resim içinde resim",
        "mini player",
        "miniplayer",
        "preferences",
        "settings",
        "ayarlar",
        "tercihler",
        "about ",
        "hakkında"
    ]

    private static let pipAgentBundles: Set<String> = [
        "com.apple.PIPAgent",
        "com.apple.systempreferences",
        "com.apple.SystemSettings"
    ]

    public static func shouldTile(
        window: AXWindowMetadata,
        ignoredBundles: Set<String>
    ) -> Bool {
        let props = FilterableWindowProperties(
            bundleIdentifier: window.bundleIdentifier,
            role: window.role,
            subrole: window.subrole,
            title: window.title,
            frame: window.frame,
            minimumSize: window.minimumSize,
            isMinimized: window.isMinimized,
            isFullscreen: window.isFullscreen,
            isModal: window.isModal,
            isResizable: window.isResizable,
            hasMinimizeButton: window.hasMinimizeButton,
            hasZoomButton: window.hasZoomButton
        )
        return shouldTile(properties: props, ignoredBundles: ignoredBundles)
    }

    public static func shouldTile(
        properties: FilterableWindowProperties,
        ignoredBundles: Set<String>
    ) -> Bool {
        // 1. User or system ignored bundle IDs & PiP agent
        if ignoredBundles.contains(properties.bundleIdentifier) ||
           pipAgentBundles.contains(properties.bundleIdentifier) {
            return false
        }

        // 2. Minimized, Fullscreen, or Modal windows are never tiled
        if properties.isMinimized || properties.isFullscreen || properties.isModal {
            return false
        }

        // 3. Must be a standard window role (ignore sheets, popovers, panels)
        if excludedRoles.contains(properties.role) || properties.role != (kAXWindowRole as String) {
            return false
        }

        // 4. Exclude floating windows, dialogs, system dialogs, sheets
        if excludedSubroles.contains(properties.subrole) {
            return false
        }

        if !properties.subrole.isEmpty && properties.subrole != (kAXStandardWindowSubrole as String) {
            return false
        }

        // 5. Non-resizable windows or windows missing both Minimize & Zoom buttons (alerts, panels, PiP overlays, About boxes)
        if !properties.isResizable {
            return false
        }

        if !properties.hasMinimizeButton && !properties.hasZoomButton {
            return false
        }

        // 6. Fixed size or tiny utility/mini-player windows
        if properties.frame.width < 160 || properties.frame.height < 120 {
            return false
        }

        if properties.minimumSize.width > 0 && properties.minimumSize.height > 0 {
            let fixedWidth = abs(properties.frame.width - properties.minimumSize.width) < 1.0
            let fixedHeight = abs(properties.frame.height - properties.minimumSize.height) < 1.0
            if fixedWidth && fixedHeight && properties.frame.width < 500 && properties.frame.height < 500 {
                return false
            }
        }

        // 7. Title heuristics for PiP, Mini Players, and Settings windows
        let lowerTitle = properties.title.lowercased()
        for keyword in pipAndSettingsKeywords {
            if lowerTitle.contains(keyword) {
                // Allow normal full-size browser/editor windows whose document title happens to contain a word if large,
                // except explicit PiP or small settings windows
                if keyword.contains("picture") || keyword.contains("resim") || keyword.contains("mini") {
                    return false
                }
                if properties.frame.width < 760 && properties.frame.height < 680 {
                    return false
                }
            }
        }

        return true
    }
}

