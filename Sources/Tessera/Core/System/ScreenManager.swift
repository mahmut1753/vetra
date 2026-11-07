import Foundation
import AppKit
import CoreGraphics

private func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // Only act after configuration completes (ignore beginConfigurationFlag)
    if flags.contains(.beginConfigurationFlag) {
        return
    }
    Task { @MainActor in
        ScreenManager.shared.refreshScreens()
    }
}

@MainActor
@Observable
public final class ScreenManager {
    public static let shared = ScreenManager()

    public private(set) var screens: [ScreenBounds] = []
    public var onScreensReconfigured: (() -> Void)?

    private var screenParamsObserver: NSObjectProtocol?
    private var isCallbackRegistered = false

    public init() {
        refreshScreens()
        registerCallbacks()
    }

    public var primaryScreenHeight: CGFloat {
        // Primary screen in AppKit is always NSScreen.screens.first (origin 0,0)
        NSScreen.screens.first?.frame.height ?? 1080.0
    }

    public func refreshScreens() {
        let primaryH = primaryScreenHeight
        var updated: [ScreenBounds] = []

        for nsScreen in NSScreen.screens {
            guard let number = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let axVisible = Self.appKitRectToAX(nsScreen.visibleFrame, primaryScreenHeight: primaryH)
            let axFull = Self.appKitRectToAX(nsScreen.frame, primaryScreenHeight: primaryH)
            updated.append(
                ScreenBounds(
                    displayID: displayID,
                    visibleFrame: axVisible,
                    fullFrame: axFull
                )
            )
        }

        let changed = (updated != screens)
        screens = updated
        if changed {
            onScreensReconfigured?()
        }
    }

    // MARK: - Coordinate Space Conversion (Isolated Here)

    /// Converts an AppKit (Bottom-Left origin) rectangle to AXUIElement (Top-Left origin) coordinates.
    public nonisolated static func appKitRectToAX(_ appKitRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let axY = primaryScreenHeight - appKitRect.origin.y - appKitRect.size.height
        return CGRect(
            x: appKitRect.origin.x,
            y: axY,
            width: appKitRect.size.width,
            height: appKitRect.size.height
        )
    }

    /// Converts an AXUIElement (Top-Left origin) rectangle to AppKit (Bottom-Left origin) coordinates.
    public nonisolated static func axRectToAppKit(_ axRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let appKitY = primaryScreenHeight - axRect.origin.y - axRect.size.height
        return CGRect(
            x: axRect.origin.x,
            y: appKitY,
            width: axRect.size.width,
            height: axRect.size.height
        )
    }

    /// Converts an AppKit point (Bottom-Left origin) to AX/Quartz global point (Top-Left origin).
    public nonisolated static func appKitPointToAX(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Converts an AX/Quartz global point (Top-Left origin) to AppKit point (Bottom-Left origin).
    public nonisolated static func axPointToAppKit(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    public func toAppKit(_ axRect: CGRect) -> CGRect {
        Self.axRectToAppKit(axRect, primaryScreenHeight: primaryScreenHeight)
    }

    public func toAX(_ appKitRect: CGRect) -> CGRect {
        Self.appKitRectToAX(appKitRect, primaryScreenHeight: primaryScreenHeight)
    }

    // MARK: - Screen Lookup & Multi-Monitor Navigation

    /// Determines which screen owns a given AX-coordinate window frame based on maximum intersection area,
    /// falling back to nearest center distance.
    public func screen(forAXFrame frame: CGRect) -> ScreenBounds? {
        if screens.isEmpty {
            refreshScreens()
        }
        guard !screens.isEmpty else { return nil }

        var bestScreen: ScreenBounds?
        var bestArea: CGFloat = 0

        for screen in screens {
            let intersection = frame.intersection(screen.fullFrame)
            if !intersection.isNull {
                let area = intersection.width * intersection.height
                if area > bestArea {
                    bestArea = area
                    bestScreen = screen
                }
            }
        }

        if let bestScreen {
            return bestScreen
        }

        // Fallback: closest display center to the window center
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { a, b in
            let distA = hypot(a.fullFrame.midX - center.x, a.fullFrame.midY - center.y)
            let distB = hypot(b.fullFrame.midX - center.x, b.fullFrame.midY - center.y)
            return distA < distB
        }
    }

    /// Returns the screen currently containing the mouse cursor (or primary screen fallback).
    public func activeScreen() -> ScreenBounds? {
        if screens.isEmpty {
            refreshScreens()
        }
        let mouseAppKit = NSEvent.mouseLocation
        let mouseAX = Self.appKitPointToAX(mouseAppKit, primaryScreenHeight: primaryScreenHeight)
        if let match = screens.first(where: { $0.fullFrame.contains(mouseAX) }) {
            return match
        }
        return screens.first
    }

    /// Finds the adjacent screen in the requested cardinal direction (in AX Top-Left coordinates).
    public func adjacentScreen(from currentDisplayID: CGDirectDisplayID, direction: CardinalDirection) -> ScreenBounds? {
        guard screens.count > 1,
              let current = screens.first(where: { $0.displayID == currentDisplayID }) else {
            return nil
        }

        let currentCenter = CGPoint(x: current.fullFrame.midX, y: current.fullFrame.midY)
        let others = screens.filter { $0.displayID != currentDisplayID }

        let directionalMatches = others.filter { candidate in
            let candCenter = CGPoint(x: candidate.fullFrame.midX, y: candidate.fullFrame.midY)
            let dx = candCenter.x - currentCenter.x
            let dy = candCenter.y - currentCenter.y
            switch direction {
            case .left:
                return dx < -10 && abs(dx) >= abs(dy) * 0.5
            case .right:
                return dx > 10 && abs(dx) >= abs(dy) * 0.5
            case .up:
                return dy < -10 && abs(dy) >= abs(dx) * 0.5
            case .down:
                return dy > 10 && abs(dy) >= abs(dx) * 0.5
            }
        }

        if let closest = directionalMatches.min(by: { a, b in
            let distA = hypot(a.fullFrame.midX - currentCenter.x, a.fullFrame.midY - currentCenter.y)
            let distB = hypot(b.fullFrame.midX - currentCenter.x, b.fullFrame.midY - currentCenter.y)
            return distA < distB
        }) {
            return closest
        }

        // If user has 2 monitors and presses left/right, cycle to the other monitor cleanly
        if (direction == .left || direction == .right), let firstOther = others.first {
            return firstOther
        }

        return nil
    }

    // MARK: - Reconfiguration Callbacks

    private func registerCallbacks() {
        guard !isCallbackRegistered else { return }
        isCallbackRegistered = true

        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreens()
            }
        }
    }
}
