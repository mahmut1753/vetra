import Foundation
import AppKit
import SwiftUI

@MainActor
public final class DockHoverPreviewManager {
    public static let shared = DockHoverPreviewManager()

    public var onWindowSelected: ((AXWindowMetadata) -> Void)?
    public var onWindowClosed: (() -> Void)?

    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var hideGraceTimer: Timer?
    private var lastCheckTime: TimeInterval = 0

    private var previewPanel: NSPanel?
    private var currentHoveredPID: pid_t?
    private var currentDockItemAppKitFrame: CGRect = .zero
    private weak var currentSettings: SettingsStore?

    public init() {}

    public func start(settings: SettingsStore) {
        self.currentSettings = settings
        guard globalMoveMonitor == nil else { return }

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.currentSettings else { return }
                self.handleMouseMoved(settings: s)
            }
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                guard let self, let s = self.currentSettings else { return }
                self.handleMouseMoved(settings: s)
            }
            return event
        }
    }

    public func stop() {
        hideGraceTimer?.invalidate()
        hideGraceTimer = nil
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m); globalMoveMonitor = nil }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m); localMoveMonitor = nil }
        hidePreviewPanelImmediately()
    }

    private func isCursorInsidePreviewOrDockCorridor(_ mouseAppKit: NSPoint) -> Bool {
        guard let panel = previewPanel, panel.isVisible else { return false }
        let expandedPanelRect = panel.frame.insetBy(dx: -16, dy: -16)
        if expandedPanelRect.contains(mouseAppKit) {
            return true
        }
        let dockCorridorRect = currentDockItemAppKitFrame.insetBy(dx: -14, dy: -24)
        if dockCorridorRect.contains(mouseAppKit) {
            return true
        }
        return false
    }

    private func handleMouseMoved(settings: SettingsStore) {
        guard settings.isTaskbarPreviewEnabled, AXIsProcessTrusted() else {
            hidePreviewPanelImmediately()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCheckTime >= 0.065 else { return }
        lastCheckTime = now

        let mouseAppKit = NSEvent.mouseLocation

        // 1. If preview panel is open and cursor is directly inside the preview panel, keep it open
        if let panel = previewPanel, panel.isVisible,
           panel.frame.insetBy(dx: -14, dy: -12).contains(mouseAppKit) {
            hideGraceTimer?.invalidate()
            hideGraceTimer = nil
            return
        }

        let primaryH = ScreenManager.shared.primaryScreenHeight
        let mouseAX = ScreenManager.appKitPointToAX(mouseAppKit, primaryScreenHeight: primaryH)

        // 2. Check if cursor is hovering over a Dock application icon
        if let (app, dockAXFrame) = AXWindowService.shared.dockHoveredApplication(atAXPoint: mouseAX) {
            hideGraceTimer?.invalidate()
            hideGraceTimer = nil

            let dockAppKitFrame = ScreenManager.axRectToAppKit(dockAXFrame, primaryScreenHeight: primaryH)
            currentDockItemAppKitFrame = dockAppKitFrame

            if currentHoveredPID != app.processIdentifier || !(previewPanel?.isVisible ?? false) {
                showOrUpdatePreview(for: app, dockAppKitFrame: dockAppKitFrame, settings: settings)
            }
            return
        }

        // 3. If cursor is still on the current Dock icon frame or crossing the 14pt gap into the panel, keep it open
        if isCursorInsidePreviewOrDockCorridor(mouseAppKit) {
            hideGraceTimer?.invalidate()
            hideGraceTimer = nil
            return
        }

        scheduleHideWithGraceDelay()
    }

    private func showOrUpdatePreview(
        for app: NSRunningApplication,
        dockAppKitFrame: CGRect,
        settings: SettingsStore
    ) {
        let windows = AXWindowService.shared.discoverWindows(for: app)
        guard !windows.isEmpty else {
            hidePreviewPanelImmediately()
            return
        }

        currentHoveredPID = app.processIdentifier
        let visibleCount = min(windows.count, 5)
        let cardWidth: CGFloat = 292
        let spacing: CGFloat = 14
        let horizontalPadding: CGFloat = 28
        let panelWidth = CGFloat(visibleCount) * cardWidth + CGFloat(max(0, visibleCount - 1)) * spacing + horizontalPadding
        let panelHeight: CGFloat = 252

        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(dockAppKitFrame) })?.frame
            ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Position panel above the Dock icon (or beside it if Dock is on Left/Right edge)
        var targetX = dockAppKitFrame.midX - panelWidth / 2.0
        var targetY = dockAppKitFrame.maxY + 14.0

        if dockAppKitFrame.minY > screenFrame.minY + 120 {
            // Side Dock (Left or Right)
            targetY = min(max(dockAppKitFrame.midY - panelHeight / 2.0, screenFrame.minY + 16), screenFrame.maxY - panelHeight - 16)
            if dockAppKitFrame.midX < screenFrame.midX {
                targetX = dockAppKitFrame.maxX + 14.0
            } else {
                targetX = dockAppKitFrame.minX - panelWidth - 14.0
            }
        } else {
            // Bottom Dock
            targetX = min(max(targetX, screenFrame.minX + 16), screenFrame.maxX - panelWidth - 16)
        }

        let panelFrame = NSRect(x: targetX.rounded(), y: targetY.rounded(), width: panelWidth, height: panelHeight)

        let panel: NSPanel
        if let existing = previewPanel {
            panel = existing
            panel.setFrame(panelFrame, display: true)
        } else {
            let newPanel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.level = .statusBar
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.ignoresMouseEvents = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            self.previewPanel = newPanel
            panel = newPanel
        }

        // Capture live hardware screenshots for each window when enabled
        var snapshotsByID: [String: NSImage] = [:]
        if settings.isLivePreviewScreenshotsEnabled {
            for win in windows.prefix(5) {
                if let snap = WindowSnapshotService.shared.snapshot(for: win) {
                    snapshotsByID[win.id] = snap
                }
            }
        }

        let screenBoundsAX = ScreenManager.shared.screen(forAXFrame: windows[0].frame)?.fullFrame
            ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let rootView = DockWindowPreviewStripView(
            appName: app.localizedName ?? "App",
            appIcon: app.icon,
            windows: windows,
            snapshotsByID: snapshotsByID,
            isLiveScreenshotsEnabled: settings.isLivePreviewScreenshotsEnabled,
            hasScreenCapturePermission: WindowSnapshotService.shared.hasScreenCapturePermission,
            screenBoundsAX: screenBoundsAX,
            accentColor: settings.highlightSwiftUIColor,
            language: settings.language,
            onHoverWindow: { win in
                if !win.isMinimized {
                    AXUIElementPerformAction(win.axElement, kAXRaiseAction as CFString)
                }
            },
            onSelectWindow: { [weak self] win in
                self?.hidePreviewPanelImmediately()
                AXWindowService.shared.raiseAndFocus(win)
                self?.onWindowSelected?(win)
            },
            onMinimizeWindow: { [weak self] win in
                AXWindowService.shared.toggleMinimize(win)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard let self else { return }
                    self.showOrUpdatePreview(for: app, dockAppKitFrame: dockAppKitFrame, settings: settings)
                    self.onWindowClosed?()
                }
            },
            onCloseWindow: { [weak self] win in
                AXWindowService.shared.closeWindow(win)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard let self else { return }
                    self.showOrUpdatePreview(for: app, dockAppKitFrame: dockAppKitFrame, settings: settings)
                    self.onWindowClosed?()
                }
            },
            onRequestScreenCaptureSettings: {
                _ = WindowSnapshotService.shared.requestScreenCapturePermission()
                WindowSnapshotService.shared.openScreenRecordingSettings()
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: panelFrame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
    }

    private func scheduleHideWithGraceDelay() {
        guard previewPanel?.isVisible == true, hideGraceTimer == nil else { return }
        hideGraceTimer = Timer.scheduledTimer(withTimeInterval: 0.26, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let mouseAppKit = NSEvent.mouseLocation
                if self.isCursorInsidePreviewOrDockCorridor(mouseAppKit) {
                    self.hideGraceTimer = nil
                    return
                }
                self.hidePreviewPanelImmediately()
            }
        }
    }

    public func hidePreviewPanelImmediately() {
        hideGraceTimer?.invalidate()
        hideGraceTimer = nil
        currentHoveredPID = nil
        previewPanel?.orderOut(nil)
    }
}

// MARK: - Refined macOS Sequoia & DockDoor Frosted Glass Preview Strip

private struct DockWindowPreviewStripView: View {
    let appName: String
    let appIcon: NSImage?
    let windows: [AXWindowMetadata]
    let snapshotsByID: [String: NSImage]
    let isLiveScreenshotsEnabled: Bool
    let hasScreenCapturePermission: Bool
    let screenBoundsAX: CGRect
    let accentColor: Color
    let language: AppLanguage
    let onHoverWindow: (AXWindowMetadata) -> Void
    let onSelectWindow: (AXWindowMetadata) -> Void
    let onMinimizeWindow: (AXWindowMetadata) -> Void
    let onCloseWindow: (AXWindowMetadata) -> Void
    let onRequestScreenCaptureSettings: () -> Void

    private var openCountText: String {
        switch language {
        case .english:
            return "\(windows.count) \(windows.count == 1 ? "Window" : "Windows")"
        case .turkish:
            return "\(windows.count) Pencere"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Top Frosted Header Bar
            HStack(spacing: 8) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }

                Text(appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isLiveScreenshotsEnabled && snapshotsByID.isEmpty && !hasScreenCapturePermission {
                    Button {
                        onRequestScreenCaptureSettings()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 10, weight: .semibold))
                            Text(language == .turkish ? "Canlı Önizleme İzni" : "Grant Access")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.88))
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                    Text(openCountText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                        )
                )
            }
            .padding(.horizontal, 6)

            // Horizontal Strip of DockDoor-Style Live Window Cards
            HStack(spacing: 14) {
                ForEach(Array(windows.prefix(5).enumerated()), id: \.element.id) { index, win in
                    WindowThumbnailCardView(
                        index: index + 1,
                        window: win,
                        snapshotImage: snapshotsByID[win.id],
                        isLiveScreenshotsEnabled: isLiveScreenshotsEnabled,
                        appIcon: appIcon,
                        screenBoundsAX: screenBoundsAX,
                        accentColor: accentColor,
                        language: language,
                        onHover: { onHoverWindow(win) },
                        onSelect: { onSelectWindow(win) },
                        onMinimize: { onMinimizeWindow(win) },
                        onClose: { onCloseWindow(win) }
                    )
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.88),
                                Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.94)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            )
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct WindowThumbnailCardView: View {
    let index: Int
    let window: AXWindowMetadata
    let snapshotImage: NSImage?
    let isLiveScreenshotsEnabled: Bool
    let appIcon: NSImage?
    let screenBoundsAX: CGRect
    let accentColor: Color
    let language: AppLanguage
    let onHover: () -> Void
    let onSelect: () -> Void
    let onMinimize: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false
    @State private var isHoveringClose: Bool = false
    @State private var isHoveringMin: Bool = false
    @State private var liveImage: NSImage?

    private var displayTitle: String {
        let trimmed = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "\(window.appName) #\(index)"
    }

    var body: some View {
        let effectiveImage = isLiveScreenshotsEnabled ? (liveImage ?? snapshotImage) : nil

        VStack(alignment: .leading, spacing: 8) {
            // Sleek Window Title Bar with macOS Traffic-Light Action Pills
            HStack(spacing: 6) {
                if window.isFocused {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: accentColor.opacity(0.8), radius: 3)
                } else if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 14, height: 14)
                }

                Text(displayTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.88))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if window.isMinimized {
                    Text(language == .turkish ? "Simge" : "Min")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.yellow.opacity(0.18)))
                }

                // Minimize / Restore Traffic-Light Button
                Button {
                    onMinimize()
                } label: {
                    Image(systemName: window.isMinimized ? "arrow.up.left.and.arrow.down.right" : "minus")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isHoveringMin ? .black.opacity(0.85) : .white.opacity(0.80))
                        .frame(width: 17, height: 17)
                        .background(
                            Circle()
                                .fill(isHoveringMin ? Color.yellow : Color.white.opacity(isHovered ? 0.16 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringMin = $0 }

                // Close Traffic-Light Button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(
                            Circle()
                                .fill(isHoveringClose ? Color.red : (isHovered ? Color.red.opacity(0.72) : Color.white.opacity(0.10)))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
            }
            .padding(.horizontal, 2)

            // Ambient Blurred Backdrop + Crisp Elevated Live Window Screenshot
            Button {
                onSelect()
            } label: {
                ZStack {
                    // Base dark canvas
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(red: 0.10, green: 0.11, blue: 0.14))

                    if let effectiveImage {
                        // Layer 1: Softly blurred ambient color backdrop from the window's own screenshot (eliminates dead gray bars)
                        GeometryReader { geo in
                            Image(nsImage: effectiveImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(1.18)
                                .blur(radius: 22)
                                .opacity(0.45)
                                .overlay(Color.black.opacity(0.28))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        // Layer 2: Crisp, elevated foreground window screenshot with macOS window shadow & rim
                        Image(nsImage: effectiveImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                            )
                            .shadow(color: Color.black.opacity(0.60), radius: 8, y: 3)
                            .padding(6)
                    } else {
                        // Clean proportional mini-window fallback when live screenshots are turned off
                        GeometryReader { geo in
                            let normRect = normalizedWindowRect(in: geo.size)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(accentColor.opacity(isHovered ? 0.30 : 0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(accentColor.opacity(0.75), lineWidth: 1.2)
                                )
                                .frame(width: normRect.width, height: normRect.height)
                                .offset(x: normRect.minX, y: normRect.minY)
                        }
                        .padding(8)

                        VStack(spacing: 6) {
                            if let appIcon {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .shadow(radius: 4)
                            }
                            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                        }
                    }
                }
                .frame(height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 292)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.11) : Color.white.opacity(0.04))
                .shadow(color: isHovered ? accentColor.opacity(0.22) : .clear, radius: 10, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    isHovered ? accentColor.opacity(0.85) : Color.white.opacity(0.09),
                    lineWidth: isHovered ? 1.5 : 0.8
                )
        )
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                if isLiveScreenshotsEnabled, let refreshed = WindowSnapshotService.shared.snapshot(for: window) {
                    liveImage = refreshed
                }
                onHover()
            }
        }
    }

    private func normalizedWindowRect(in canvasSize: CGSize) -> CGRect {
        guard screenBoundsAX.width > 0, screenBoundsAX.height > 0, !window.isMinimized else {
            let w = canvasSize.width * 0.6
            let h = canvasSize.height * 0.6
            return CGRect(x: (canvasSize.width - w) / 2, y: (canvasSize.height - h) / 2, width: w, height: h)
        }
        let relX = max(0, min(1, (window.frame.minX - screenBoundsAX.minX) / screenBoundsAX.width))
        let relY = max(0, min(1, (window.frame.minY - screenBoundsAX.minY) / screenBoundsAX.height))
        let relW = max(0.18, min(1.0 - relX, window.frame.width / screenBoundsAX.width))
        let relH = max(0.22, min(1.0 - relY, window.frame.height / screenBoundsAX.height))

        return CGRect(
            x: relX * canvasSize.width,
            y: relY * canvasSize.height,
            width: relW * canvasSize.width,
            height: relH * canvasSize.height
        )
    }
}
