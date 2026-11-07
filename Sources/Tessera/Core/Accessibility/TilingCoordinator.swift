import Foundation
import AppKit
import CoreGraphics

@MainActor
@Observable
public final class TilingCoordinator {
    public let settings: SettingsStore
    public let screenManager: ScreenManager
    public let stageManagerMonitor: StageManagerMonitor
    public let hotkeyManager: HotkeyManager
    public let axService: AXWindowService
    public let windowObserver: WindowObserver
    public let overlayManager: BorderOverlayManager
    public let layoutEngine: LayoutEngine

    public private(set) var isAccessibilityGranted: Bool = false
    public private(set) var focusedAppBundleID: String = ""
    public private(set) var focusedAppName: String = ""
    public private(set) var focusedAppIcon: NSImage?
    public private(set) var focusedWindowID: String?
    public private(set) var manuallyFloatedWindowIDs: Set<String> = []
    public private(set) var tiledWindowCountByDisplay: [CGDirectDisplayID: Int] = [:]

    /// Preserves deterministic ordering of window IDs per display across reflows
    private var orderedWindowIDsByDisplay: [CGDirectDisplayID: [String]] = [:]
    /// Cached latest placements per display for directional swapping, manual resize adoption, and stack cycling
    private var latestOutputsByDisplay: [CGDirectDisplayID: LayoutCalculationOutput] = [:]
    /// Cached latest window metadata by ID
    private var latestWindowsByID: [String: AXWindowMetadata] = [:]

    private var permissionPollTimer: Timer?
    private var servicesStarted: Bool = false

    public init(
        settings: SettingsStore,
        screenManager: ScreenManager = .shared,
        stageManagerMonitor: StageManagerMonitor = StageManagerMonitor(),
        hotkeyManager: HotkeyManager = .shared,
        axService: AXWindowService = .shared,
        windowObserver: WindowObserver = .shared,
        overlayManager: BorderOverlayManager = .shared,
        layoutEngine: LayoutEngine = LayoutEngine()
    ) {
        self.settings = settings
        self.screenManager = screenManager
        self.stageManagerMonitor = stageManagerMonitor
        self.hotkeyManager = hotkeyManager
        self.axService = axService
        self.windowObserver = windowObserver
        self.overlayManager = overlayManager
        self.layoutEngine = layoutEngine

        bindCallbacks()
        checkAndStartIfTrusted()
    }

    // MARK: - Startup & Permission Polling

    public func checkAndStartIfTrusted(prompt: Bool = false) {
        let trusted = axService.isAccessibilityTrusted(prompt: prompt)
        isAccessibilityGranted = trusted

        if trusted {
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
            settings.hasCompletedOnboarding = true
            if !servicesStarted {
                startServices()
            }
        } else {
            servicesStarted = false
            startPermissionPolling()
        }
    }

    public func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.axService.isAccessibilityTrusted(prompt: false) {
                    self.isAccessibilityGranted = true
                    self.settings.hasCompletedOnboarding = true
                    self.permissionPollTimer?.invalidate()
                    self.permissionPollTimer = nil
                    AppWindowController.shared.closeOnboardingIfOpen()
                    if !self.servicesStarted {
                        self.startServices()
                    }
                }
            }
        }
    }

    public func startServices() {
        servicesStarted = true
        // Ensure any system or ignored apps that were previously hidden are unhidden
        for app in NSWorkspace.shared.runningApplications where app.isHidden {
            let bundleID = app.bundleIdentifier ?? ""
            if bundleID.hasPrefix("com.apple.") || settings.isBundleIgnored(bundleID) {
                app.unhide()
            }
        }
        settings.applyTheme()
        screenManager.refreshScreens()
        stageManagerMonitor.refreshState()
        settings.isPausedByStageManager = stageManagerMonitor.isStageManagerActive
        hotkeyManager.registerAll(from: settings.keyBindings)
        windowObserver.start()
        DockHoverPreviewManager.shared.onWindowSelected = { [weak self] selectedWin in
            guard let self else { return }
            self.focusedWindowID = selectedWin.id
            self.reflowAllDisplays()
        }
        DockHoverPreviewManager.shared.onWindowClosed = { [weak self] in
            self?.reflowAllDisplays()
        }
        DockHoverPreviewManager.shared.start(settings: settings)
        reflowAllDisplays()
    }

    // MARK: - Core Reflow Pipeline

    public func reflowAllDisplays(raiseActiveStackWindowOnDisplay: CGDirectDisplayID? = nil) {
        updateFrontmostAppInfo()

        // Always verify live Accessibility trust state
        let currentlyTrusted = axService.isAccessibilityTrusted(prompt: false)
        if currentlyTrusted != isAccessibilityGranted {
            isAccessibilityGranted = currentlyTrusted
            if !currentlyTrusted {
                startPermissionPolling()
            }
        }

        guard isAccessibilityGranted, !settings.isEffectivelyPaused else {
            overlayManager.clearAllOverlays()
            return
        }

        let allDiscovered = axService.discoverAllWindows()
        var tileableWindows: [AXWindowMetadata] = []
        var newWindowsByID: [String: AXWindowMetadata] = [:]

        for win in allDiscovered {
            newWindowsByID[win.id] = win
            if !manuallyFloatedWindowIDs.contains(win.id) &&
               WindowFilter.shouldTile(window: win, ignoredBundles: settings.ignoredBundleIDs) {
                tileableWindows.append(win)
            }
        }
        // Clean up any closed window IDs from manuallyFloatedWindowIDs
        manuallyFloatedWindowIDs = manuallyFloatedWindowIDs.intersection(Set(newWindowsByID.keys))

        latestWindowsByID = newWindowsByID
        WindowSnapshotService.shared.updateMetadata(for: allDiscovered)

        let rawFocusedWindow = allDiscovered.first(where: \.isFocused)

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApp?.processIdentifier
        let isFrontmostAppTiled = frontmostPID.map { pid in
            tileableWindows.contains(where: { $0.pid == pid })
        } ?? false

        if raiseActiveStackWindowOnDisplay == nil {
            if let focused = tileableWindows.first(where: \.isFocused) {
                focusedWindowID = focused.id
            } else if let currentFocusedID = focusedWindowID, !tileableWindows.contains(where: { $0.id == currentFocusedID }) {
                focusedWindowID = tileableWindows.first?.id
            }
        }

        let screens = screenManager.screens
        guard !screens.isEmpty else { return }

        // Group tileable windows by display
        var windowsByDisplay: [CGDirectDisplayID: [AXWindowMetadata]] = [:]
        for screen in screens {
            windowsByDisplay[screen.displayID] = []
        }

        for win in tileableWindows {
            if let ownerScreen = screenManager.screen(forAXFrame: win.frame) {
                windowsByDisplay[ownerScreen.displayID, default: []].append(win)
            } else if let primary = screens.first {
                windowsByDisplay[primary.displayID, default: []].append(win)
            }
        }

        // Suppress move/resize notifications caused by our own AX frame updates
        windowObserver.suppressMoveNotificationsUntil = Date().addingTimeInterval(0.25)

        var allTileFramesAX: [CGRect] = []
        var allBadges: [StackBadgeDescriptor] = []
        var allDividers: [(displayID: CGDirectDisplayID, divider: DividerGeometry)] = []
        var activeHighlightFrameAX: CGRect?

        for screen in screens {
            let displayID = screen.displayID
            let currentDisplayWindows = windowsByDisplay[displayID] ?? []
            let currentIDs = Set(currentDisplayWindows.map(\.id))

            // Maintain stable ordering per display
            var orderedIDs = (orderedWindowIDsByDisplay[displayID] ?? []).filter { currentIDs.contains($0) }
            for win in currentDisplayWindows where !orderedIDs.contains(win.id) {
                orderedIDs.append(win.id)
            }
            orderedWindowIDsByDisplay[displayID] = orderedIDs

            let orderedMetadata: [AXWindowMetadata] = orderedIDs.compactMap { id in
                currentDisplayWindows.first(where: { $0.id == id })
            }
            tiledWindowCountByDisplay[displayID] = orderedMetadata.count

            var displayState = settings.state(for: displayID)

            // Clamp leftPaneCount if windows closed
            if orderedMetadata.count >= 2 && displayState.leftPaneCount >= orderedMetadata.count {
                let clampedLeft = max(1, orderedMetadata.count - 1)
                displayState.leftPaneCount = clampedLeft
                settings.setLeftPaneCount(clampedLeft, for: displayID)
            }

            // Update activeTileIndex if the focused window is on this display within the primary capacity
            if let focusedID = focusedWindowID,
               let focusedIdx = orderedIDs.firstIndex(of: focusedID) {
                if settings.isFocusModeEnabled {
                    displayState.activeTileIndex = 0
                    if raiseActiveStackWindowOnDisplay != displayID {
                        displayState.activeStackOffset = focusedIdx
                    }
                } else if focusedIdx < screen.maxTileCapacity {
                    displayState.activeTileIndex = focusedIdx
                    settings.setActiveTileIndex(focusedIdx, for: displayID)
                }
            }

            let inputs: [LayoutWindowInput] = orderedMetadata.map { meta in
                let displayLabel = (meta.title.isEmpty || meta.title == meta.appName)
                    ? meta.appName
                    : "\(meta.appName) · \(meta.title)"
                return LayoutWindowInput(
                    id: meta.id,
                    pid: meta.pid,
                    bundleIdentifier: meta.bundleIdentifier,
                    label: displayLabel,
                    minimumSize: meta.minimumSize,
                    currentFrame: meta.frame
                )
            }

            let effectiveMaxTiles = settings.isFocusModeEnabled ? 1 : displayState.maxTilesOverride
            let effectiveInnerGap = settings.isFocusModeEnabled ? 0 : CGFloat(settings.innerGap)
            let effectiveOuterPadding = settings.isFocusModeEnabled ? 0 : CGFloat(settings.outerPadding)

            let config = LayoutConfiguration(
                layout: displayState.layout,
                innerGap: effectiveInnerGap,
                outerPadding: effectiveOuterPadding,
                masterRatio: CGFloat(displayState.masterRatio),
                leftSplitRatio: CGFloat(displayState.leftSplitRatio),
                secondaryRatio: CGFloat(displayState.secondaryRatio),
                leftPaneCount: displayState.leftPaneCount,
                maxTilesOverride: effectiveMaxTiles,
                smartGaps: settings.isFocusModeEnabled ? true : settings.smartGaps,
                activeTileIndex: displayState.activeTileIndex,
                activeStackOffset: displayState.activeStackOffset
            )

            let output = layoutEngine.calculateLayout(
                windows: inputs,
                screen: screen,
                config: config
            )
            latestOutputsByDisplay[displayID] = output

            var topStackWindowsToRaise: [AXWindowMetadata] = []

            for placement in output.placements {
                guard let winMeta = newWindowsByID[placement.id] else { continue }

                var frameToApply = placement.targetFrame
                if (settings.isNoPeekEnabled || settings.isFocusModeEnabled),
                   case .tiled(_, _, let stackCount, let isTop) = placement.mode,
                   stackCount > 1,
                   !isTop {
                    // Tuck background stacked windows inside the tile bounds so edges/shadows never peek out
                    let insetAmount: CGFloat = settings.isFocusModeEnabled ? 32 : 12
                    if placement.targetFrame.width > insetAmount * 3 && placement.targetFrame.height > insetAmount * 3 {
                        frameToApply = placement.targetFrame.insetBy(dx: insetAmount, dy: insetAmount)
                    }
                }

                axService.setFrame(frameToApply, for: winMeta.axElement)

                if placement.id == focusedWindowID {
                    activeHighlightFrameAX = placement.targetFrame
                }

                if case .tiled(_, _, let stackCount, let isTop) = placement.mode,
                   stackCount > 1,
                   isTop {
                    // Only raise stacked windows if explicitly cycling stacks OR if a tiled app is currently frontmost.
                    // Never raise tiled windows over non-tiled frontmost apps (like System Settings, dialogs, or ignored apps).
                    if raiseActiveStackWindowOnDisplay == displayID || (settings.isNoPeekEnabled && isFrontmostAppTiled) {
                        topStackWindowsToRaise.append(winMeta)
                    }
                    if raiseActiveStackWindowOnDisplay == displayID {
                        focusedWindowID = winMeta.id
                        activeHighlightFrameAX = placement.targetFrame
                        if settings.mouseFollowsFocus {
                            warpMouseToCenter(ofAXFrame: placement.targetFrame)
                        }
                    }
                }
            }

            for topWin in topStackWindowsToRaise {
                if raiseActiveStackWindowOnDisplay == displayID {
                    axService.raiseAndFocus(topWin)
                } else if isFrontmostAppTiled {
                    AXUIElementPerformAction(topWin.axElement, kAXRaiseAction as CFString)
                }
            }

            allTileFramesAX.append(contentsOf: output.tileFrames)
            allBadges.append(contentsOf: output.stackBadges)
            for div in output.dividers {
                allDividers.append((displayID: displayID, divider: div))
            }
        }

        let isRawFocusedFloated = rawFocusedWindow.map { manuallyFloatedWindowIDs.contains($0.id) } ?? false
        let isRawFocusedAppIgnored = rawFocusedWindow.map { settings.isBundleIgnored($0.bundleIdentifier) } ?? false

        overlayManager.updateOverlays(
            activeFrameAX: activeHighlightFrameAX,
            focusedWindowFrameAX: rawFocusedWindow?.frame ?? activeHighlightFrameAX,
            isFocusedWindowFloated: isRawFocusedFloated,
            isFocusedAppIgnored: isRawFocusedAppIgnored,
            focusedAppName: rawFocusedWindow?.appName ?? focusedAppName,
            allTileFramesAX: allTileFramesAX,
            badges: allBadges,
            dividersByDisplay: allDividers,
            settings: settings
        )

        // Clean Space: Only hide background tiled apps that are covered in a stack, and ONLY when a tiled app is frontmost.
        // Never hide System Settings, Apple system utilities, ignored apps, or the currently active frontmost app.
        if settings.isCleanSpaceEnabled && isFrontmostAppTiled {
            let managedTilePIDs = Set(tileableWindows.map(\.pid))
            let visibleTopPIDs: Set<pid_t>
            if settings.isFocusModeEnabled, let focusedID = focusedWindowID, let fWin = newWindowsByID[focusedID] {
                visibleTopPIDs = [fWin.pid]
            } else {
                var pids = Set<pid_t>()
                for screen in screens {
                    if let out = latestOutputsByDisplay[screen.displayID] {
                        for p in out.placements {
                            if case .tiled(_, _, _, let isTop) = p.mode, isTop {
                                pids.insert(p.pid)
                            }
                        }
                    }
                }
                visibleTopPIDs = pids
            }
            let myPID = ProcessInfo.processInfo.processIdentifier
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
                let pid = app.processIdentifier
                let bundleID = app.bundleIdentifier ?? ""
                guard pid != myPID,
                      pid != frontmostPID,
                      managedTilePIDs.contains(pid),
                      !settings.isBundleIgnored(bundleID),
                      !bundleID.hasPrefix("com.apple.") else {
                    continue
                }
                if !visibleTopPIDs.contains(pid) {
                    app.hide()
                }
            }
        }
    }

    // MARK: - Fast Live Divider Drag Reflow (Zero Discovery Overhead)

    public func performFastLiveDividerReflow(
        displayID: CGDirectDisplayID,
        role: DividerRole,
        newRatio: Double
    ) {
        guard isAccessibilityGranted,
              !settings.isEffectivelyPaused,
              let screen = screenManager.screens.first(where: { $0.displayID == displayID }),
              let orderedIDs = orderedWindowIDsByDisplay[displayID] else {
            return
        }

        let orderedMetadata = orderedIDs.compactMap { latestWindowsByID[$0] }
        guard !orderedMetadata.isEmpty else { return }

        windowObserver.suppressMoveNotificationsUntil = Date().addingTimeInterval(0.30)
        settings.setSplitRatioForLiveDrag(newRatio, role: role, for: displayID)
        let displayState = settings.state(for: displayID)

        let inputs: [LayoutWindowInput] = orderedMetadata.map { meta in
            LayoutWindowInput(
                id: meta.id,
                pid: meta.pid,
                bundleIdentifier: meta.bundleIdentifier,
                label: meta.appName,
                minimumSize: meta.minimumSize,
                currentFrame: meta.frame
            )
        }

        let effectiveMaxTiles = settings.isFocusModeEnabled ? 1 : displayState.maxTilesOverride

        let config = LayoutConfiguration(
            layout: displayState.layout,
            innerGap: CGFloat(settings.innerGap),
            outerPadding: CGFloat(settings.outerPadding),
            masterRatio: CGFloat(displayState.masterRatio),
            leftSplitRatio: CGFloat(displayState.leftSplitRatio),
            secondaryRatio: CGFloat(displayState.secondaryRatio),
            leftPaneCount: displayState.leftPaneCount,
            maxTilesOverride: effectiveMaxTiles,
            smartGaps: settings.smartGaps,
            activeTileIndex: displayState.activeTileIndex,
            activeStackOffset: displayState.activeStackOffset
        )

        let output = layoutEngine.calculateLayout(windows: inputs, screen: screen, config: config)
        latestOutputsByDisplay[displayID] = output

        var activeHighlightFrameAX: CGRect?
        for placement in output.placements {
            guard let winMeta = latestWindowsByID[placement.id] else { continue }
            axService.setFrame(placement.targetFrame, for: winMeta.axElement, isLiveResize: true)
            if placement.id == focusedWindowID {
                activeHighlightFrameAX = placement.targetFrame
            }
        }

        let allDividers = output.dividers.map { (displayID: displayID, divider: $0) }
        overlayManager.updateOverlays(
            activeFrameAX: activeHighlightFrameAX,
            allTileFramesAX: output.tileFrames,
            badges: output.stackBadges,
            dividersByDisplay: allDividers,
            settings: settings
        )
    }

    // MARK: - Adopt Manual Window Resize OR Drag-Move

    public func adoptManualWindowGeometryAndReflow() {
        guard axService.isAccessibilityTrusted(prompt: false), !settings.isEffectivelyPaused else {
            reflowAllDisplays()
            return
        }

        let allDiscovered = axService.discoverAllWindows()
        let liveByID = Dictionary(uniqueKeysWithValues: allDiscovered.map { ($0.id, $0) })
        let mouseAX = ScreenManager.appKitPointToAX(
            NSEvent.mouseLocation,
            primaryScreenHeight: screenManager.primaryScreenHeight
        )

        for screen in screenManager.screens {
            let displayID = screen.displayID
            guard let previousOutput = latestOutputsByDisplay[displayID],
                  previousOutput.tileFrames.count >= 2 else {
                continue
            }

            let outerPad = CGFloat(settings.outerPadding)
            let innerGap = CGFloat(settings.innerGap)
            let usableRect = screen.visibleFrame.insetBy(dx: outerPad, dy: outerPad)
            let availableW = max(1, usableRect.width - innerGap)
            let availableH = max(1, usableRect.height - innerGap)

            for placement in previousOutput.placements where !placement.isFloating {
                guard let liveWin = liveByID[placement.id] else { continue }
                let oldFrame = placement.targetFrame
                let newFrame = liveWin.frame

                let deltaW = abs(newFrame.width - oldFrame.width)
                let deltaH = abs(newFrame.height - oldFrame.height)
                let centerShift = hypot(newFrame.midX - oldFrame.midX, newFrame.midY - oldFrame.midY)

                // Case 1: User manually resized the window's width or height
                if deltaW > 10 || deltaH > 10 {
                    if deltaW > 10 {
                        let isLeftSideTile = abs(oldFrame.minX - usableRect.minX) < 35
                        let isRightSideTile = abs(oldFrame.maxX - usableRect.maxX) < 35

                        if isLeftSideTile {
                            let newRatio = Double(newFrame.width / availableW)
                            settings.setSplitRatio(newRatio, role: .primary, for: displayID)
                        } else if isRightSideTile {
                            let newRatio = Double(1.0 - (newFrame.width / availableW))
                            settings.setSplitRatio(newRatio, role: .primary, for: displayID)
                        }
                    }

                    if deltaH > 10 {
                        let isTopTile = abs(oldFrame.minY - usableRect.minY) < 35
                        let isBottomTile = abs(oldFrame.maxY - usableRect.maxY) < 35
                        let isLeftColumn = oldFrame.midX < usableRect.midX

                        let displayState = settings.state(for: displayID)
                        let targetRole: DividerRole
                        if displayState.layout == .rows || (displayState.layout == .side && screen.isPortrait) {
                            targetRole = .primary
                        } else if isLeftColumn {
                            targetRole = .leftSecondary
                        } else {
                            targetRole = .rightSecondary
                        }

                        if isTopTile {
                            let newRatio = Double(newFrame.height / availableH)
                            settings.setSplitRatio(newRatio, role: targetRole, for: displayID)
                        } else if isBottomTile {
                            let newRatio = Double(1.0 - (newFrame.height / availableH))
                            settings.setSplitRatio(newRatio, role: targetRole, for: displayID)
                        }
                    }
                    break
                }

                // Case 2: User dragged the window by its title bar to a new location (size unchanged)
                if centerShift > 45 {
                    let dropPoint = newFrame.contains(mouseAX)
                        ? mouseAX
                        : CGPoint(x: newFrame.midX, y: newFrame.midY)

                    applyUserWindowDrag(
                        draggedID: placement.id,
                        displayID: displayID,
                        screen: screen,
                        usableRect: usableRect,
                        dropPointAX: dropPoint,
                        previousOutput: previousOutput
                    )
                    break
                }
            }
        }

        reflowAllDisplays()
    }

    private func applyUserWindowDrag(
        draggedID: String,
        displayID: CGDirectDisplayID,
        screen: ScreenBounds,
        usableRect: CGRect,
        dropPointAX: CGPoint,
        previousOutput: LayoutCalculationOutput
    ) {
        guard var orderedIDs = orderedWindowIDsByDisplay[displayID],
              let sIdx = orderedIDs.firstIndex(of: draggedID) else {
            return
        }

        let displayState = settings.state(for: displayID)
        let totalCount = min(orderedIDs.count, screen.maxTileCapacity)

        // In Side layout with 3+ windows, dragging a window across the center divider adds it to the Left or Right pane
        if displayState.layout == .side && totalCount >= 3 && !screen.isPortrait {
            let splitX = usableRect.minX + usableRect.width * CGFloat(displayState.masterRatio)
            let effectiveLeftCount = min(max(1, displayState.leftPaneCount), totalCount - 1)

            let startedOnRight = sIdx >= effectiveLeftCount
            let endedOnLeft = dropPointAX.x < splitX

            let startedOnLeft = sIdx < effectiveLeftCount
            let endedOnRight = dropPointAX.x >= splitX

            if startedOnRight && endedOnLeft && effectiveLeftCount < totalCount - 1 {
                orderedIDs.remove(at: sIdx)
                let insertAtTop = dropPointAX.y < usableRect.midY
                let insertIdx = insertAtTop ? 0 : effectiveLeftCount
                orderedIDs.insert(draggedID, at: min(insertIdx, orderedIDs.count))
                orderedWindowIDsByDisplay[displayID] = orderedIDs
                settings.setLeftPaneCount(effectiveLeftCount + 1, for: displayID)
                return
            } else if startedOnLeft && endedOnRight && effectiveLeftCount > 1 {
                orderedIDs.remove(at: sIdx)
                let newLeftCount = effectiveLeftCount - 1
                let insertAtTopOfRight = dropPointAX.y < usableRect.midY
                let insertIdx = insertAtTopOfRight ? newLeftCount : orderedIDs.count
                orderedIDs.insert(draggedID, at: min(insertIdx, orderedIDs.count))
                orderedWindowIDsByDisplay[displayID] = orderedIDs
                settings.setLeftPaneCount(newLeftCount, for: displayID)
                return
            }
        }

        // Standard swap with the tile under dropPointAX
        if let targetPlacement = previousOutput.placements.first(where: { $0.id != draggedID && $0.targetFrame.contains(dropPointAX) }),
           let tIdx = orderedIDs.firstIndex(of: targetPlacement.id) {
            orderedIDs.swapAt(sIdx, tIdx)
            orderedWindowIDsByDisplay[displayID] = orderedIDs
        }
    }

    // MARK: - Layout Switching & Stack Cycling

    public func activeDisplayID() -> CGDirectDisplayID {
        if let focusedID = focusedWindowID,
           let win = latestWindowsByID[focusedID],
           let screen = screenManager.screen(forAXFrame: win.frame) {
            return screen.displayID
        }
        return screenManager.activeScreen()?.displayID ?? CGMainDisplayID()
    }

    public func switchLayoutOnActiveDisplay(_ layout: TileLayoutKind) {
        let displayID = activeDisplayID()
        settings.setLayout(layout, for: displayID)
        reflowAllDisplays()
    }

    public func cycleActiveStack() {
        let displayID = activeDisplayID()
        settings.incrementStackOffset(for: displayID)
        reflowAllDisplays(raiseActiveStackWindowOnDisplay: displayID)
    }

    public func adjustLeftPaneCountOnActiveDisplay(delta: Int) {
        let displayID = activeDisplayID()
        let count = tiledWindowCountByDisplay[displayID] ?? 2
        let current = settings.state(for: displayID).leftPaneCount
        let next = min(max(1, current + delta), max(1, count - 1))
        settings.setLeftPaneCount(next, for: displayID)
        reflowAllDisplays()
    }

    // MARK: - Window Swapping (Keyboard)

    public func swapFocusedWindow(direction: CardinalDirection) {
        guard let focusedID = focusedWindowID,
              let focusedWin = latestWindowsByID[focusedID],
              let screen = screenManager.screen(forAXFrame: focusedWin.frame) else {
            return
        }

        let displayID = screen.displayID
        guard var orderedIDs = orderedWindowIDsByDisplay[displayID],
              let sourceIdx = orderedIDs.firstIndex(of: focusedID),
              let output = latestOutputsByDisplay[displayID] else {
            return
        }

        guard let sourcePlacement = output.placements.first(where: { $0.id == focusedID }) else {
            return
        }
        let sourceCenter = CGPoint(x: sourcePlacement.targetFrame.midX, y: sourcePlacement.targetFrame.midY)

        let candidates = output.placements.filter { $0.id != focusedID && !$0.isFloating }
        let directionalMatches = candidates.filter { cand in
            let cx = cand.targetFrame.midX - sourceCenter.x
            let cy = cand.targetFrame.midY - sourceCenter.y
            switch direction {
            case .left:  return cx < -10 && abs(cx) >= abs(cy) * 0.4
            case .right: return cx > 10 && abs(cx) >= abs(cy) * 0.4
            case .up:    return cy < -10 && abs(cy) >= abs(cx) * 0.4
            case .down:  return cy > 10 && abs(cy) >= abs(cx) * 0.4
            }
        }

        let targetPlacement: WindowPlacementResult?
        if let nearest = directionalMatches.min(by: { a, b in
            hypot(a.targetFrame.midX - sourceCenter.x, a.targetFrame.midY - sourceCenter.y) <
            hypot(b.targetFrame.midX - sourceCenter.x, b.targetFrame.midY - sourceCenter.y)
        }) {
            targetPlacement = nearest
        } else if orderedIDs.count >= 2 {
            let offset = (direction == .left || direction == .up) ? -1 : 1
            let targetIdx = (sourceIdx + offset + orderedIDs.count) % orderedIDs.count
            let targetID = orderedIDs[targetIdx]
            targetPlacement = output.placements.first(where: { $0.id == targetID })
        } else {
            targetPlacement = nil
        }

        guard let target = targetPlacement,
              let destIdx = orderedIDs.firstIndex(of: target.id) else {
            return
        }

        orderedIDs.swapAt(sourceIdx, destIdx)
        orderedWindowIDsByDisplay[displayID] = orderedIDs
        reflowAllDisplays()

        if settings.mouseFollowsFocus,
           let updatedOutput = latestOutputsByDisplay[displayID],
           let updatedFocused = updatedOutput.placements.first(where: { $0.id == focusedID }) {
            warpMouseToCenter(ofAXFrame: updatedFocused.targetFrame)
        }
    }

    // MARK: - Multi-Monitor Window Movement (Ctrl+Option+Arrow)

    public func moveFocusedWindowToAdjacentDisplay(direction: CardinalDirection) {
        guard let focusedID = focusedWindowID,
              let focusedWin = latestWindowsByID[focusedID],
              let currentScreen = screenManager.screen(forAXFrame: focusedWin.frame),
              let targetScreen = screenManager.adjacentScreen(from: currentScreen.displayID, direction: direction) else {
            return
        }

        orderedWindowIDsByDisplay[currentScreen.displayID]?.removeAll { $0 == focusedID }
        var targetList = orderedWindowIDsByDisplay[targetScreen.displayID] ?? []
        if !targetList.contains(focusedID) {
            targetList.insert(focusedID, at: 0)
        }
        orderedWindowIDsByDisplay[targetScreen.displayID] = targetList

        let initialFrameOnTarget = CGRect(
            x: targetScreen.visibleFrame.minX + 40,
            y: targetScreen.visibleFrame.minY + 40,
            width: min(focusedWin.frame.width, targetScreen.visibleFrame.width * 0.8),
            height: min(focusedWin.frame.height, targetScreen.visibleFrame.height * 0.8)
        )
        windowObserver.suppressMoveNotificationsUntil = Date().addingTimeInterval(0.25)
        axService.setFrame(initialFrameOnTarget, for: focusedWin.axElement)

        reflowAllDisplays()

        if settings.mouseFollowsFocus,
           let updatedOutput = latestOutputsByDisplay[targetScreen.displayID],
           let movedPlacement = updatedOutput.placements.first(where: { $0.id == focusedID }) {
            warpMouseToCenter(ofAXFrame: movedPlacement.targetFrame)
        }
    }

    // MARK: - Mouse Follows Focus

    private func warpMouseToCenter(ofAXFrame axFrame: CGRect) {
        let centerPoint = CGPoint(x: axFrame.midX, y: axFrame.midY)
        CGWarpMouseCursorPosition(centerPoint)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Frontmost App & Callback Wiring

    public func updateFrontmostAppInfo() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let bundle = frontApp.bundleIdentifier ?? ""
            if bundle != "com.tessera.windowmanager" {
                focusedAppBundleID = bundle
                focusedAppName = frontApp.localizedName ?? bundle
                focusedAppIcon = frontApp.icon
            }
        }
    }

    public func toggleIgnoreFocusedApp() {
        guard !focusedAppBundleID.isEmpty else { return }
        settings.toggleIgnoreBundle(focusedAppBundleID)
        let nowIgnored = settings.isBundleIgnored(focusedAppBundleID)
        let isTR = (settings.language == .turkish)
        let msg = nowIgnored
            ? (isTR ? "\(focusedAppName) Döşeme Dışı Bırakıldı" : "\(focusedAppName) Excluded from Tiling")
            : (isTR ? "\(focusedAppName) Döşemeye Alındı" : "\(focusedAppName) Included in Tiling")
        overlayManager.showHUDToast(
            message: msg,
            systemImage: nowIgnored ? "eye.slash.fill" : "eye.fill",
            accentColor: nowIgnored ? .orange : settings.highlightSwiftUIColor,
            anchorAXFrame: focusedWindowID.flatMap { latestWindowsByID[$0]?.frame }
        )
        reflowAllDisplays()
    }

    public func toggleFloatFocusedWindow() {
        let allDiscovered = axService.discoverAllWindows()
        let targetWin = allDiscovered.first(where: \.isFocused)
            ?? focusedWindowID.flatMap { latestWindowsByID[$0] }
        guard let win = targetWin else { return }

        let isTR = (settings.language == .turkish)
        if manuallyFloatedWindowIDs.contains(win.id) {
            manuallyFloatedWindowIDs.remove(win.id)
            focusedWindowID = win.id
            overlayManager.showHUDToast(
                message: isTR ? "Pencere Döşemeye Alındı" : "Window Tiled",
                systemImage: "square.grid.2x2.fill",
                accentColor: settings.highlightSwiftUIColor,
                anchorAXFrame: win.frame
            )
        } else {
            manuallyFloatedWindowIDs.insert(win.id)
            overlayManager.showHUDToast(
                message: isTR ? "Pencere Serbest Bırakıldı" : "Window Floated",
                systemImage: "pin.slash.fill",
                accentColor: .orange,
                anchorAXFrame: win.frame
            )
        }
        reflowAllDisplays()
    }

    private func bindCallbacks() {
        settings.onSettingsChanged = { [weak self] in
            self?.reflowAllDisplays()
        }

        settings.onShortcutsChanged = { [weak self] in
            guard let self else { return }
            self.hotkeyManager.registerAll(from: self.settings.keyBindings)
        }

        screenManager.onScreensReconfigured = { [weak self] in
            self?.reflowAllDisplays()
        }

        stageManagerMonitor.onStageManagerStateChanged = { [weak self] isStageManagerOn in
            guard let self else { return }
            self.settings.isPausedByStageManager = isStageManagerOn
        }

        windowObserver.onDebouncedEvent = { [weak self] eventKind in
            guard let self else { return }
            if eventKind == .userGeometryModified {
                self.adoptManualWindowGeometryAndReflow()
            } else {
                self.reflowAllDisplays()
            }
        }

        overlayManager.onDividerRatioDragged = { [weak self] displayID, role, newRatio, isFinished in
            guard let self else { return }
            if isFinished {
                self.settings.setSplitRatio(newRatio, role: role, for: displayID)
            } else {
                self.performFastLiveDividerReflow(displayID: displayID, role: role, newRatio: newRatio)
            }
        }

        overlayManager.onStackTabSelected = { [weak self] stackIdx, winID in
            guard let self else { return }
            let displayID = self.activeDisplayID()
            self.focusedWindowID = winID
            if let winMeta = self.latestWindowsByID[winID] {
                self.axService.raiseAndFocus(winMeta)
            }
            self.settings.setStackOffset(stackIdx, for: displayID)
            self.reflowAllDisplays(raiseActiveStackWindowOnDisplay: displayID)
        }

        overlayManager.onToggleFloatActiveWindow = { [weak self] in
            self?.toggleFloatFocusedWindow()
        }

        overlayManager.onToggleIgnoreActiveApp = { [weak self] in
            self?.toggleIgnoreFocusedApp()
        }

        hotkeyManager.onActionTriggered = { [weak self] action in
            self?.handleShortcutAction(action)
        }
    }

    private func handleShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .toggleFloatWindow:
            toggleFloatFocusedWindow()
        case .toggleIgnoreApp:
            toggleIgnoreFocusedApp()
        case .toggleTiling:
            settings.isTilingPaused.toggle()
        case .cycleStack:
            cycleActiveStack()
        case .toggleFocusMode:
            settings.isFocusModeEnabled.toggle()
        case .layoutGrid:
            switchLayoutOnActiveDisplay(.grid)
        case .layoutColumns:
            switchLayoutOnActiveDisplay(.columns)
        case .layoutRows:
            switchLayoutOnActiveDisplay(.rows)
        case .layoutSide:
            switchLayoutOnActiveDisplay(.side)
        case .moveDisplayLeft:
            moveFocusedWindowToAdjacentDisplay(direction: .left)
        case .moveDisplayRight:
            moveFocusedWindowToAdjacentDisplay(direction: .right)
        case .moveDisplayUp:
            moveFocusedWindowToAdjacentDisplay(direction: .up)
        case .moveDisplayDown:
            moveFocusedWindowToAdjacentDisplay(direction: .down)
        case .swapWindowLeft:
            swapFocusedWindow(direction: .left)
        case .swapWindowRight:
            swapFocusedWindow(direction: .right)
        case .swapWindowUp:
            swapFocusedWindow(direction: .up)
        case .swapWindowDown:
            swapFocusedWindow(direction: .down)
        }
    }
}
