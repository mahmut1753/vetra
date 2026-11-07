import Foundation
import AppKit
import SwiftUI
import CoreGraphics

@_silgen_name("CGSMainConnectionID")
private func _BorderCGSConnectionID() -> UInt32

@_silgen_name("CGSSetConnectionProperty")
private func _BorderCGSSetConnectionProperty(
    _ cid: UInt32,
    _ targetCID: UInt32,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

@MainActor
public final class BorderOverlayManager {
    public static let shared = BorderOverlayManager()

    /// Parameters: (displayID, dividerRole, newRatio, isDragFinished)
    public var onDividerRatioDragged: ((CGDirectDisplayID, DividerRole, Double, Bool) -> Void)?
    /// Parameters: (stackPositionIndex, windowID)
    public var onStackTabSelected: ((Int, String) -> Void)?
    /// Triggered when user clicks the on-window quick button to float/re-tile the active window
    public var onToggleFloatActiveWindow: (() -> Void)?
    /// Triggered when user clicks the on-window quick button to ignore/unignore the active app
    public var onToggleIgnoreActiveApp: (() -> Void)?

    private var borderPanels: [NSPanel] = []
    private var badgePanels: [NSPanel] = []
    private var tabPreviewPanel: NSPanel?
    private var quickActionPanel: NSPanel?
    private var isQuickPillExpanded: Bool = false
    private var quickPillExpandTimer: Timer?
    private var quickPillMouseMonitorTimer: Timer?
    private var cachedQuickWinAppKit: NSRect = .zero
    private var cachedQuickIsFloated: Bool = false
    private var cachedQuickIsIgnored: Bool = false
    private var cachedQuickAppName: String = ""
    private weak var cachedSettings: SettingsStore?
    private var hudToastPanel: NSPanel?
    private var hudDismissTimer: Timer?
    private var dividerPanelsByID: [String: (panel: NSPanel, view: DividerDragTrackingView)] = [:]

    public init() {
        // Allow non-activating overlay panels to change the macOS system cursor while in the background
        let cid = _BorderCGSConnectionID()
        if cid != 0 {
            _ = _BorderCGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        }
    }

    public func clearAllOverlays() {
        for panel in borderPanels { panel.orderOut(nil) }
        borderPanels.removeAll()

        for panel in badgePanels { panel.orderOut(nil) }
        badgePanels.removeAll()

        tabPreviewPanel?.orderOut(nil)
        tabPreviewPanel = nil

        quickPillExpandTimer?.invalidate()
        quickPillExpandTimer = nil
        quickPillMouseMonitorTimer?.invalidate()
        quickPillMouseMonitorTimer = nil
        isQuickPillExpanded = false
        quickActionPanel?.orderOut(nil)

        for (_, entry) in dividerPanelsByID {
            entry.panel.orderOut(nil)
        }
        dividerPanelsByID.removeAll()
    }

    public func updateOverlays(
        activeFrameAX: CGRect?,
        focusedWindowFrameAX: CGRect? = nil,
        isFocusedWindowFloated: Bool = false,
        isFocusedAppIgnored: Bool = false,
        focusedAppName: String = "",
        allTileFramesAX: [CGRect],
        badges: [StackBadgeDescriptor],
        dividersByDisplay: [(displayID: CGDirectDisplayID, divider: DividerGeometry)],
        settings: SettingsStore
    ) {
        guard !settings.isEffectivelyPaused else {
            clearAllOverlays()
            return
        }

        // In Focus mode, hide window highlight borders ("odak aktifken kenar gozukmesin"),
        // while keeping Tab View (Stack Badges/Tabs) active so the user can switch windows via tabs!
        let effectiveHighlightMode: HighlightMode = settings.isFocusModeEnabled ? .none : settings.highlightMode

        updateHighlightBorders(
            activeFrameAX: activeFrameAX,
            allTileFramesAX: allTileFramesAX,
            mode: effectiveHighlightMode,
            color: settings.highlightNSColor,
            lineWidth: CGFloat(settings.borderWidth)
        )

        updateStackBadges(
            badges: badges,
            accentColor: settings.highlightNSColor,
            useTabView: settings.isTabViewEnabled
        )
        updateDividerHandles(
            dividersByDisplay: settings.isFocusModeEnabled ? [] : dividersByDisplay,
            accentColor: settings.highlightNSColor
        )
        updateQuickActionPill(
            focusedWindowFrameAX: focusedWindowFrameAX ?? activeFrameAX,
            isWindowFloated: isFocusedWindowFloated,
            isAppIgnored: isFocusedAppIgnored,
            appName: focusedAppName,
            settings: settings
        )
    }

    // MARK: - On-Window Quick Untile / Float Pill & HUD Toast

    private func updateQuickActionPill(
        focusedWindowFrameAX: CGRect?,
        isWindowFloated: Bool,
        isAppIgnored: Bool,
        appName: String,
        settings: SettingsStore
    ) {
        guard settings.isWindowQuickActionBarEnabled,
              let winAX = focusedWindowFrameAX,
              winAX.width > 220,
              winAX.height > 120 else {
            quickPillExpandTimer?.invalidate()
            quickPillExpandTimer = nil
            quickPillMouseMonitorTimer?.invalidate()
            quickPillMouseMonitorTimer = nil
            isQuickPillExpanded = false
            quickActionPanel?.orderOut(nil)
            return
        }

        let winAppKit = ScreenManager.shared.toAppKit(winAX)
        self.cachedQuickWinAppKit = winAppKit
        self.cachedQuickIsFloated = isWindowFloated
        self.cachedQuickIsIgnored = isAppIgnored
        self.cachedQuickAppName = appName
        self.cachedSettings = settings

        renderQuickActionPanel()
    }

    private func renderQuickActionPanel() {
        guard let settings = cachedSettings,
              cachedQuickWinAppKit.width > 220 else {
            quickActionPanel?.orderOut(nil)
            return
        }

        let winAppKit = cachedQuickWinAppKit
        let isBottom = settings.quickActionAtBottom
        let ratio = CGFloat(min(max(settings.quickActionHorizontalRatio, 0.15), 0.92))

        // Collapsed state is a tiny 48x7pt micro-notch right on the outer border line (above Chrome tabs & toolbar buttons!)
        let pillWidth: CGFloat = isQuickPillExpanded ? 242 : 48
        let pillHeight: CGFloat = isQuickPillExpanded ? 28 : 7

        let centerX = winAppKit.minX + winAppKit.width * ratio
        let minAllowedX = winAppKit.minX + 86
        let maxAllowedX = max(minAllowedX, winAppKit.maxX - pillWidth - 14)
        let targetX = min(max(centerX - pillWidth / 2.0, minAllowedX), maxAllowedX).rounded()

        let targetY: CGFloat
        if isBottom {
            targetY = isQuickPillExpanded
                ? (winAppKit.minY + 4).rounded()
                : (winAppKit.minY - 3).rounded()
        } else {
            // In collapsed state, sits at maxY - 2 (straddling the top border line, 100% ABOVE Chrome's tab bar and IDE toolbar buttons!)
            targetY = isQuickPillExpanded
                ? (winAppKit.maxY - pillHeight - 2).rounded()
                : (winAppKit.maxY - 2).rounded()
        }

        let pillFrame = NSRect(x: targetX, y: targetY, width: pillWidth, height: pillHeight)

        let panel: NSPanel
        if let existing = quickActionPanel {
            panel = existing
            panel.setFrame(pillFrame, display: true)
        } else {
            let newPanel = NSPanel(
                contentRect: pillFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .floating
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.ignoresMouseEvents = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            self.quickActionPanel = newPanel
            panel = newPanel
        }

        let hosting = NSHostingView(
            rootView: ActiveWindowQuickActionPillView(
                isExpanded: isQuickPillExpanded,
                isAtBottom: isBottom,
                isWindowFloated: cachedQuickIsFloated,
                isAppIgnored: cachedQuickIsIgnored,
                appName: cachedQuickAppName,
                language: settings.language,
                accentColor: settings.highlightSwiftUIColor,
                onHoverChanged: { [weak self] hovering in
                    self?.handleQuickPillHover(hovering)
                },
                onToggleFloatWindow: { [weak self] in
                    self?.setQuickPillExpanded(false)
                    self?.onToggleFloatActiveWindow?()
                },
                onToggleIgnoreApp: { [weak self] in
                    self?.setQuickPillExpanded(false)
                    self?.onToggleIgnoreActiveApp?()
                },
                onFlipEdge: { [weak self] in
                    guard let self, let settings = self.cachedSettings else { return }
                    settings.quickActionAtBottom.toggle()
                    self.renderQuickActionPanel()
                },
                onDragHorizontalDelta: { [weak self] deltaX in
                    guard let self, let settings = self.cachedSettings, self.cachedQuickWinAppKit.width > 220 else { return }
                    let newRatio = settings.quickActionHorizontalRatio + Double(deltaX / self.cachedQuickWinAppKit.width)
                    settings.quickActionHorizontalRatio = min(max(newRatio, 0.15), 0.92)
                    self.renderQuickActionPanel()
                }
            )
        )
        hosting.frame = NSRect(origin: .zero, size: pillFrame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
    }

    private func handleQuickPillHover(_ hovering: Bool) {
        if hovering {
            if isQuickPillExpanded { return }
            quickPillExpandTimer?.invalidate()
            let delay: TimeInterval = NSEvent.modifierFlags.contains(.option) ? 0.01 : 0.12
            quickPillExpandTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.setQuickPillExpanded(true)
                }
            }
        } else {
            quickPillExpandTimer?.invalidate()
            quickPillExpandTimer = nil
            // Check if mouse is actually outside the expanded panel before collapsing
            if let panel = quickActionPanel, panel.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                return
            }
            setQuickPillExpanded(false)
        }
    }

    private func setQuickPillExpanded(_ expanded: Bool) {
        guard isQuickPillExpanded != expanded else { return }
        isQuickPillExpanded = expanded
        renderQuickActionPanel()

        quickPillMouseMonitorTimer?.invalidate()
        quickPillMouseMonitorTimer = nil
        if expanded {
            quickPillMouseMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isQuickPillExpanded else { return }
                    guard let panel = self.quickActionPanel else {
                        self.setQuickPillExpanded(false)
                        return
                    }
                    let mouseLoc = NSEvent.mouseLocation
                    if !panel.frame.insetBy(dx: -10, dy: -10).contains(mouseLoc) {
                        self.setQuickPillExpanded(false)
                    }
                }
            }
        }
    }

    public func showHUDToast(
        message: String,
        systemImage: String,
        accentColor: Color,
        anchorAXFrame: CGRect?
    ) {
        hudDismissTimer?.invalidate()
        hudDismissTimer = nil

        let screenRect: NSRect
        if let anchorAXFrame {
            screenRect = ScreenManager.shared.toAppKit(anchorAXFrame)
        } else {
            screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }

        let toastW: CGFloat = 260
        let toastH: CGFloat = 44
        let toastFrame = NSRect(
            x: (screenRect.midX - toastW / 2.0).rounded(),
            y: (screenRect.midY - toastH / 2.0).rounded(),
            width: toastW,
            height: toastH
        )

        let panel: NSPanel
        if let existing = hudToastPanel {
            panel = existing
            panel.setFrame(toastFrame, display: true)
        } else {
            let newPanel = makeClickThroughPanel(frame: toastFrame)
            newPanel.level = .statusBar
            newPanel.hasShadow = true
            self.hudToastPanel = newPanel
            panel = newPanel
        }

        let hosting = NSHostingView(
            rootView: HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.86))
                    .overlay(
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.75), lineWidth: 1.2)
                    )
            )
        )
        hosting.frame = NSRect(origin: .zero, size: toastFrame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()

        hudDismissTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hudToastPanel?.orderOut(nil)
            }
        }
    }

    // MARK: - Highlight Borders (Reused Click-Through NSPanels)

    private func updateHighlightBorders(
        activeFrameAX: CGRect?,
        allTileFramesAX: [CGRect],
        mode: HighlightMode,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        guard mode != .none else {
            for panel in borderPanels { panel.orderOut(nil) }
            borderPanels.removeAll()
            return
        }

        let targetFramesAX: [CGRect]
        switch mode {
        case .none:
            targetFramesAX = []
        case .activeBorder, .glow:
            if let activeFrameAX {
                targetFramesAX = [activeFrameAX]
            } else {
                targetFramesAX = []
            }
        case .allBorders:
            targetFramesAX = allTileFramesAX
        }

        let isGlow = (mode == .glow)
        let expansion: CGFloat = isGlow ? 10.0 : 2.0

        // Trim extra panels if count decreased
        while borderPanels.count > targetFramesAX.count {
            let removed = borderPanels.removeLast()
            removed.orderOut(nil)
        }

        for (index, axRect) in targetFramesAX.enumerated() {
            let appKitRect = ScreenManager.shared.toAppKit(axRect).insetBy(dx: -expansion, dy: -expansion)
            if index < borderPanels.count {
                let panel = borderPanels[index]
                panel.setFrame(appKitRect, display: true)
                if let borderView = panel.contentView as? HighlightBorderDrawingView {
                    borderView.frame = NSRect(origin: .zero, size: appKitRect.size)
                    borderView.configure(
                        strokeColor: color,
                        lineWidth: lineWidth,
                        insetAmount: expansion,
                        drawsGlow: isGlow
                    )
                }
                panel.orderFrontRegardless()
            } else {
                let panel = makeClickThroughPanel(frame: appKitRect)
                let borderView = HighlightBorderDrawingView(
                    frame: NSRect(origin: .zero, size: appKitRect.size),
                    strokeColor: color,
                    lineWidth: lineWidth,
                    insetAmount: expansion,
                    drawsGlow: isGlow
                )
                panel.contentView = borderView
                panel.orderFrontRegardless()
                borderPanels.append(panel)
            }
        }
    }

    // MARK: - Stack Count Badges & Interactive Tab View

    private func updateStackBadges(
        badges: [StackBadgeDescriptor],
        accentColor: NSColor,
        useTabView: Bool
    ) {
        for panel in badgePanels { panel.orderOut(nil) }
        badgePanels.removeAll()

        for badge in badges where badge.totalCount > 1 {
            let tileAppKit = ScreenManager.shared.toAppKit(badge.tileFrame)

            if useTabView {
                let tabBarWidth = min(max(CGFloat(badge.totalCount) * 115.0, 180.0), tileAppKit.width - 24.0)
                let tabBarHeight: CGFloat = 28.0
                // Place at bottom-center of the tile so browser tabs (Chrome/Safari) and top window toolbars are never covered
                let tabBarFrame = NSRect(
                    x: tileAppKit.midX - tabBarWidth / 2.0,
                    y: tileAppKit.minY + 6.0,
                    width: tabBarWidth,
                    height: tabBarHeight
                )

                let panel = NSPanel(
                    contentRect: tabBarFrame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .floating
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.ignoresMouseEvents = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

                let hosting = NSHostingView(
                    rootView: StackTabViewBar(
                        badge: badge,
                        accentColor: Color(nsColor: accentColor),
                        onHoverTab: { [weak self] hoveredIdx, winID, label in
                            if let hoveredIdx {
                                self?.showTabHoverPreview(
                                    forWindowID: winID,
                                    label: label,
                                    oneBasedIndex: hoveredIdx + 1,
                                    totalCount: badge.totalCount,
                                    tabBarFrame: tabBarFrame,
                                    accentColor: Color(nsColor: accentColor)
                                )
                            } else {
                                self?.hideTabHoverPreview()
                            }
                        },
                        onSelectTab: { [weak self] idx, winID in
                            self?.hideTabHoverPreview()
                            self?.onStackTabSelected?(idx, winID)
                        }
                    )
                )
                hosting.frame = NSRect(origin: .zero, size: tabBarFrame.size)
                panel.contentView = hosting
                panel.orderFrontRegardless()
                badgePanels.append(panel)
            } else {
                let badgeWidth: CGFloat = 54
                let badgeHeight: CGFloat = 24
                let margin: CGFloat = 10

                let badgeFrame = NSRect(
                    x: tileAppKit.maxX - badgeWidth - margin,
                    y: tileAppKit.maxY - badgeHeight - margin,
                    width: badgeWidth,
                    height: badgeHeight
                )

                let panel = makeClickThroughPanel(frame: badgeFrame)
                let hosting = NSHostingView(
                    rootView: StackBadgePillView(
                        text: badge.badgeText,
                        accentColor: Color(nsColor: accentColor)
                    )
                )
                hosting.frame = NSRect(origin: .zero, size: badgeFrame.size)
                panel.contentView = hosting
                panel.orderFrontRegardless()
                badgePanels.append(panel)
            }
        }
    }

    private func showTabHoverPreview(
        forWindowID windowID: String,
        label: String,
        oneBasedIndex: Int,
        totalCount: Int,
        tabBarFrame: NSRect,
        accentColor: Color
    ) {
        let previewWidth: CGFloat = 280
        let previewHeight: CGFloat = 188
        let frac = CGFloat(oneBasedIndex - 1) / CGFloat(max(1, totalCount))
        let anchorX = tabBarFrame.minX + tabBarFrame.width * (frac + 0.5 / CGFloat(max(1, totalCount)))
        let targetX = min(max(anchorX - previewWidth / 2.0, tabBarFrame.minX - 20), tabBarFrame.maxX - previewWidth + 20)
        let targetY = tabBarFrame.maxY + 8.0

        let previewFrame = NSRect(x: targetX.rounded(), y: targetY.rounded(), width: previewWidth, height: previewHeight)
        let panel: NSPanel
        if let existing = tabPreviewPanel {
            panel = existing
            panel.setFrame(previewFrame, display: true)
        } else {
            let newPanel = makeClickThroughPanel(frame: previewFrame)
            newPanel.level = .statusBar
            newPanel.hasShadow = true
            self.tabPreviewPanel = newPanel
            panel = newPanel
        }

        let snapshotImage = WindowSnapshotService.shared.snapshot(forWindowID: windowID)
        let meta = WindowSnapshotService.shared.metadata(forWindowID: windowID)
        let appIcon: NSImage? = meta.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }

        let hosting = NSHostingView(
            rootView: StackTabHoverPreviewCardView(
                label: label,
                oneBasedIndex: oneBasedIndex,
                totalCount: totalCount,
                snapshotImage: snapshotImage,
                appIcon: appIcon,
                accentColor: accentColor
            )
        )
        hosting.frame = NSRect(origin: .zero, size: previewFrame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
    }

    private func hideTabHoverPreview() {
        tabPreviewPanel?.orderOut(nil)
    }

    // MARK: - Persistent Live Divider Drag Handles (Never Destroyed Mid-Drag!)

    private func updateDividerHandles(
        dividersByDisplay: [(displayID: CGDirectDisplayID, divider: DividerGeometry)],
        accentColor: NSColor
    ) {
        var activeKeys = Set<String>()

        for entry in dividersByDisplay {
            let key = "\(entry.displayID)-\(entry.divider.id)"
            activeKeys.insert(key)
            let appKitFrame = ScreenManager.shared.toAppKit(entry.divider.frame)

            if let existing = dividerPanelsByID[key] {
                existing.view.accentColor = accentColor
                // Only reposition the panel from outside when user is NOT actively dragging it
                if !existing.view.isDragging {
                    existing.view.divider = entry.divider
                    existing.panel.setFrame(appKitFrame, display: true)
                    existing.view.frame = NSRect(origin: .zero, size: appKitFrame.size)
                    existing.view.needsDisplay = true
                }
                existing.panel.orderFrontRegardless()
            } else {
                let panel = NSPanel(
                    contentRect: appKitFrame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .floating
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

                let dragView = DividerDragTrackingView(
                    frame: NSRect(origin: .zero, size: appKitFrame.size),
                    displayID: entry.displayID,
                    divider: entry.divider,
                    accentColor: accentColor
                ) { [weak self] displayID, role, updatedRatio, isFinished in
                    self?.onDividerRatioDragged?(displayID, role, updatedRatio, isFinished)
                }
                panel.contentView = dragView
                panel.orderFrontRegardless()
                dividerPanelsByID[key] = (panel: panel, view: dragView)
            }
        }

        // Remove stale dividers that are no longer part of the layout (and not currently being dragged)
        for (key, existing) in Array(dividerPanelsByID) {
            if !activeKeys.contains(key) && !existing.view.isDragging {
                existing.panel.orderOut(nil)
                dividerPanelsByID.removeValue(forKey: key)
            }
        }
    }

    private func makeClickThroughPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

// MARK: - Custom Drawing & Interactive Views

private final class HighlightBorderDrawingView: NSView {
    private var strokeColor: NSColor
    private var lineWidth: CGFloat
    private var insetAmount: CGFloat
    private var drawsGlow: Bool

    init(
        frame: NSRect,
        strokeColor: NSColor,
        lineWidth: CGFloat,
        insetAmount: CGFloat,
        drawsGlow: Bool
    ) {
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.insetAmount = insetAmount
        self.drawsGlow = drawsGlow
        super.init(frame: frame)
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        strokeColor: NSColor,
        lineWidth: CGFloat,
        insetAmount: CGFloat,
        drawsGlow: Bool
    ) {
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.insetAmount = insetAmount
        self.drawsGlow = drawsGlow
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()

        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        let cornerRadius: CGFloat = 10.0
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        if drawsGlow {
            ctx.setShadow(offset: .zero, blur: 10.0, color: strokeColor.withAlphaComponent(0.85).cgColor)
        }

        ctx.addPath(path)
        ctx.setStrokeColor(strokeColor.withAlphaComponent(0.92).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()

        ctx.restoreGState()
    }
}

private struct StackBadgePillView: View {
    let text: String
    let accentColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.9), lineWidth: 1.2)
                    )
            )
    }
}

private struct StackTabViewBar: View {
    let badge: StackBadgeDescriptor
    let accentColor: Color
    let onHoverTab: (Int?, String, String) -> Void
    let onSelectTab: (Int, String) -> Void

    @State private var hoveredIdx: Int?

    var body: some View {
        HStack(spacing: 4) {
            // Open window count badge (like Windows Taskbar count indicator)
            Text("\(badge.totalCount)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.85))
                )

            ForEach(0..<badge.totalCount, id: \.self) { idx in
                let isSelected = (idx + 1 == badge.activeOneBasedIndex)
                let isHovered = (hoveredIdx == idx)
                let label = idx < badge.windowLabels.count ? badge.windowLabels[idx] : "Window \(idx + 1)"
                let winID = idx < badge.windowIDs.count ? badge.windowIDs[idx] : ""

                Button {
                    onSelectTab(idx, winID)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isSelected ? accentColor : (isHovered ? Color.white : Color.secondary.opacity(0.5)))
                            .frame(width: 6, height: 6)
                        Text(label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? accentColor.opacity(0.28) : (isHovered ? Color.white.opacity(0.14) : Color.clear))
                    )
                    .foregroundStyle(isSelected || isHovered ? Color.white : Color.white.opacity(0.72))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        hoveredIdx = idx
                        onHoverTab(idx, winID, label)
                    } else if hoveredIdx == idx {
                        hoveredIdx = nil
                        onHoverTab(nil, "", "")
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                )
        )
    }
}

private struct StackTabHoverPreviewCardView: View {
    let label: String
    let oneBasedIndex: Int
    let totalCount: Int
    let snapshotImage: NSImage?
    let appIcon: NSImage?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 15, height: 15)
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("[\(oneBasedIndex)/\(totalCount)]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.12, blue: 0.15))

                if let snapshotImage {
                    GeometryReader { geo in
                        Image(nsImage: snapshotImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(1.18)
                            .blur(radius: 20)
                            .opacity(0.45)
                            .overlay(Color.black.opacity(0.28))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Image(nsImage: snapshotImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 7, y: 3)
                        .padding(5)
                } else if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 42, height: 42)
                        .shadow(radius: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.85), lineWidth: 1.5)
                )
        )
    }
}

private struct ActiveWindowQuickActionPillView: View {
    let isExpanded: Bool
    let isAtBottom: Bool
    let isWindowFloated: Bool
    let isAppIgnored: Bool
    let appName: String
    let language: AppLanguage
    let accentColor: Color
    let onHoverChanged: (Bool) -> Void
    let onToggleFloatWindow: () -> Void
    let onToggleIgnoreApp: () -> Void
    let onFlipEdge: () -> Void
    let onDragHorizontalDelta: (CGFloat) -> Void

    private var isTR: Bool { language == .turkish }

    private var windowActionTitle: String {
        if isWindowFloated {
            return isTR ? "Döşemeye Al" : "Tile Window"
        }
        return isTR ? "Döşemeyi Çöz" : "Float Window"
    }

    private var appActionTitle: String {
        if isAppIgnored {
            return isTR ? "Uyg. Dahil Et" : "Tile App"
        }
        return isTR ? "Uyg. Kapat" : "Ignore App"
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedNotchBody
            }
        }
        .onHover { hovering in
            onHoverChanged(hovering)
        }
    }

    /// Tiny 48x7pt border handle sitting right on the outer window border line — never covers Chrome tabs or app toolbar buttons!
    private var collapsedNotchBody: some View {
        ZStack {
            Capsule()
                .fill(
                    (isWindowFloated || isAppIgnored)
                    ? Color.orange.opacity(0.92)
                    : accentColor.opacity(0.88)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var expandedBody: some View {
        HStack(spacing: 4) {
            // Drag grip to slide horizontally along the window border
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 14, height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            onDragHorizontalDelta(value.translation.width)
                        }
                )
                .help(isTR ? "Kenar boyunca sola/sağa sürükle" : "Drag left/right along border")

            // Button 1: Toggle Float / Untile just this window (⌃⌥W)
            Button {
                onToggleFloatWindow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isWindowFloated ? "square.grid.2x2.fill" : "pin.slash.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isWindowFloated ? Color.orange : accentColor)
                    Text(windowActionTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isWindowFloated ? Color.orange.opacity(0.28) : Color.white.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .help(isTR ? "Aktif pencereyi döşemeden çıkar veya geri al (⌃⌥W)" : "Float or re-tile active window (⌃⌥W)")

            // Button 2: Toggle Ignore entire App (⌃⌥I)
            Button {
                onToggleIgnoreApp()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isAppIgnored ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(isAppIgnored ? Color.green : Color.white.opacity(0.85))
                    Text(appActionTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isAppIgnored ? Color.green.opacity(0.24) : Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help(isTR ? "Bu uygulamayı tamamen döşeme dışı bırak veya dahil et (⌃⌥I)" : "Ignore or include this application (⌃⌥I)")

            // Button 3: Flip between Top Border and Bottom Border
            Button {
                onFlipEdge()
            } label: {
                Image(systemName: isAtBottom ? "arrow.up.to.line" : "arrow.down.to.line")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.80))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help(isTR ? (isAtBottom ? "Üst kenar çizgisine taşı" : "Alt kenar çizgisine taşı") : "Move to opposite border")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.90))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            (isWindowFloated || isAppIgnored)
                            ? Color.orange.opacity(0.85)
                            : accentColor.opacity(0.75),
                            lineWidth: 1.0
                        )
                )
        )
    }
}

private final class DividerDragTrackingView: NSView {
    let displayID: CGDirectDisplayID
    var divider: DividerGeometry
    var accentColor: NSColor {
        didSet { needsDisplay = true }
    }
    private let onRatioChanged: (CGDirectDisplayID, DividerRole, Double, Bool) -> Void

    private var initialMouseLocation: NSPoint = .zero
    private var initialPanelOrigin: NSPoint = .zero
    private var initialRatio: CGFloat = 0.5
    private var latestRatio: CGFloat = 0.5
    private var lastEmitTimestamp: TimeInterval = 0

    var isHovering: Bool = false {
        didSet { needsDisplay = true }
    }
    var isDragging: Bool = false {
        didSet { needsDisplay = true }
    }

    init(
        frame: NSRect,
        displayID: CGDirectDisplayID,
        divider: DividerGeometry,
        accentColor: NSColor,
        onRatioChanged: @escaping (CGDirectDisplayID, DividerRole, Double, Bool) -> Void
    ) {
        self.displayID = displayID
        self.divider = divider
        self.accentColor = accentColor
        self.latestRatio = divider.currentRatio
        self.onRatioChanged = onRatioChanged
        super.init(frame: frame)
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private var activeResizeCursor: NSCursor {
        switch divider.axis {
        case .vertical:
            return NSCursor.columnResize
        case .horizontal:
            return NSCursor.rowResize
        }
    }

    private func applyResizeCursor() {
        let cid = _BorderCGSConnectionID()
        if cid != 0 {
            _ = _BorderCGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        }
        activeResizeCursor.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: activeResizeCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        applyResizeCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyResizeCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        if !isHovering {
            isHovering = true
        }
        applyResizeCursor()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            isHovering = false
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        initialMouseLocation = NSEvent.mouseLocation
        initialPanelOrigin = window?.frame.origin ?? .zero
        initialRatio = divider.currentRatio
        latestRatio = initialRatio
        lastEmitTimestamp = 0
        applyResizeCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, divider.containerLength > 10 else { return }
        applyResizeCursor()
        let currentLoc = NSEvent.mouseLocation
        let rawDelta: CGFloat
        switch divider.axis {
        case .vertical:
            rawDelta = currentLoc.x - initialMouseLocation.x
        case .horizontal:
            // In AppKit screen coordinates, dragging down decreases Y, which increases top pane height
            rawDelta = initialMouseLocation.y - currentLoc.y
        }

        let ratioDelta = rawDelta / divider.containerLength
        let clampedRatio = min(max(initialRatio + ratioDelta, divider.minRatio), divider.maxRatio)
        latestRatio = clampedRatio
        needsDisplay = true

        // Move the divider panel itself at 120Hz immediately so visual feedback is completely lag-free
        let effectivePixelDelta = (clampedRatio - initialRatio) * divider.containerLength
        if let panel = window {
            var newFrame = panel.frame
            switch divider.axis {
            case .vertical:
                newFrame.origin.x = initialPanelOrigin.x + effectivePixelDelta
            case .horizontal:
                newFrame.origin.y = initialPanelOrigin.y - effectivePixelDelta
            }
            panel.setFrame(newFrame, display: true)
        }

        // Throttle AX window resizing calls to ~50fps (20ms) so third-party apps resize smoothly without IPC queue buildup
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastEmitTimestamp >= 0.020 {
            lastEmitTimestamp = now
            onRatioChanged(displayID, divider.role, Double(clampedRatio), false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let mouseInView = convert(event.locationInWindow, from: nil)
        isHovering = bounds.contains(mouseInView)
        if isHovering {
            applyResizeCursor()
        } else {
            NSCursor.arrow.set()
        }
        divider = DividerGeometry(
            id: divider.id,
            role: divider.role,
            frame: divider.frame,
            axis: divider.axis,
            currentRatio: latestRatio,
            containerLength: divider.containerLength,
            minRatio: divider.minRatio,
            maxRatio: divider.maxRatio
        )
        onRatioChanged(displayID, divider.role, Double(latestRatio), true)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()

        let activeState = isHovering || isDragging

        // 1. Sleek luminous split-line track when hovering or dragging
        if activeState {
            ctx.saveGState()
            let trackColor = accentColor.withAlphaComponent(isDragging ? 0.78 : 0.45)
            ctx.setShadow(offset: .zero, blur: 6.0, color: accentColor.withAlphaComponent(0.65).cgColor)
            trackColor.setFill()
            let trackRect: NSRect
            switch divider.axis {
            case .vertical:
                trackRect = NSRect(x: bounds.midX - 1.0, y: bounds.minY + 18, width: 2.0, height: max(0, bounds.height - 36))
            case .horizontal:
                trackRect = NSRect(x: bounds.minX + 18, y: bounds.midY - 1.0, width: max(0, bounds.width - 36), height: 2.0)
            }
            NSBezierPath(roundedRect: trackRect, xRadius: 1.0, yRadius: 1.0).fill()
            ctx.restoreGState()
        }

        // 2. Modern Apple Split-View Frosted Capsule Handle
        let handleLength: CGFloat = isDragging ? 68.0 : (isHovering ? 60.0 : 42.0)
        let handleThickness: CGFloat = isDragging ? 14.0 : (isHovering ? 12.0 : 6.0)

        let pillRect: NSRect
        switch divider.axis {
        case .vertical:
            let clampedLen = min(bounds.height * 0.40, handleLength)
            pillRect = NSRect(
                x: bounds.midX - handleThickness / 2.0,
                y: bounds.midY - clampedLen / 2.0,
                width: handleThickness,
                height: clampedLen
            )
        case .horizontal:
            let clampedLen = min(bounds.width * 0.40, handleLength)
            pillRect = NSRect(
                x: bounds.midX - clampedLen / 2.0,
                y: bounds.midY - handleThickness / 2.0,
                width: clampedLen,
                height: handleThickness
            )
        }

        let radius = handleThickness / 2.0
        let outerPath = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)

        // Elevated shadow / glow around the capsule
        ctx.saveGState()
        if activeState {
            ctx.setShadow(offset: .zero, blur: 8.0, color: accentColor.withAlphaComponent(0.75).cgColor)
        } else {
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3.0, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        }
        NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: activeState ? 0.95 : 0.78).setFill()
        outerPath.fill()
        ctx.restoreGState()

        // Subtle glass rim border
        let rimColor = activeState ? accentColor : NSColor.white.withAlphaComponent(0.32)
        rimColor.setStroke()
        outerPath.lineWidth = activeState ? 1.5 : 0.8
        outerPath.stroke()

        // 3. Inner Grip Details: glowing center line + directional chevrons when hovered/dragging
        let cx = pillRect.midX
        let cy = pillRect.midY

        if activeState {
            // Three micro grip dots in center + subtle directional chevrons
            let dotRadius: CGFloat = 1.3
            let dotSpacing: CGFloat = 5.0
            for offsetIdx in -1...1 {
                let offset = CGFloat(offsetIdx) * dotSpacing
                let dotRect: NSRect
                switch divider.axis {
                case .vertical:
                    dotRect = NSRect(x: cx - dotRadius, y: cy + offset - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                case .horizontal:
                    dotRect = NSRect(x: cx + offset - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                }
                (isDragging ? accentColor : NSColor.white.withAlphaComponent(0.95)).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            // Directional micro-chevrons (< > or ^ v) inside the expanded pill
            let chevronPath = NSBezierPath()
            chevronPath.lineWidth = 1.3
            chevronPath.lineCapStyle = .round
            chevronPath.lineJoinStyle = .round

            switch divider.axis {
            case .vertical:
                // Left micro-chevron '<' and right micro-chevron '>'
                let spreadX: CGFloat = 3.2
                let armX: CGFloat = 1.6
                let armY: CGFloat = 2.4
                chevronPath.move(to: NSPoint(x: cx - spreadX + armX, y: cy + 14 + armY))
                chevronPath.line(to: NSPoint(x: cx - spreadX, y: cy + 14))
                chevronPath.line(to: NSPoint(x: cx - spreadX + armX, y: cy + 14 - armY))

                chevronPath.move(to: NSPoint(x: cx + spreadX - armX, y: cy + 14 + armY))
                chevronPath.line(to: NSPoint(x: cx + spreadX, y: cy + 14))
                chevronPath.line(to: NSPoint(x: cx + spreadX - armX, y: cy + 14 - armY))
            case .horizontal:
                let spreadY: CGFloat = 3.2
                let armY: CGFloat = 1.6
                let armX: CGFloat = 2.4
                chevronPath.move(to: NSPoint(x: cx + 14 - armX, y: cy - spreadY + armY))
                chevronPath.line(to: NSPoint(x: cx + 14, y: cy - spreadY))
                chevronPath.line(to: NSPoint(x: cx + 14 + armX, y: cy - spreadY + armY))

                chevronPath.move(to: NSPoint(x: cx + 14 - armX, y: cy + spreadY - armY))
                chevronPath.line(to: NSPoint(x: cx + 14, y: cy + spreadY))
                chevronPath.line(to: NSPoint(x: cx + 14 + armX, y: cy + spreadY - armY))
            }
            accentColor.withAlphaComponent(0.95).setStroke()
            chevronPath.stroke()
        } else {
            // Idle state: sleek minimal inner capsule (iPadOS Split View grabber look)
            let innerRect: NSRect
            switch divider.axis {
            case .vertical:
                innerRect = NSRect(x: cx - 1.0, y: cy - 10.0, width: 2.0, height: 20.0)
            case .horizontal:
                innerRect = NSRect(x: cx - 10.0, y: cy - 1.0, width: 20.0, height: 2.0)
            }
            NSColor.white.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: innerRect, xRadius: 1.0, yRadius: 1.0).fill()
        }

        ctx.restoreGState()
    }
}
