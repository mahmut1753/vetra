import Foundation
import AppKit
import ApplicationServices

// Declare private CoreGraphics SPI for exact CGWindowID lookup from AXUIElement when available
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

public struct AXWindowMetadata: @unchecked Sendable, Identifiable {
    public let id: String
    public let windowNumber: CGWindowID
    public let pid: pid_t
    public let bundleIdentifier: String
    public let appName: String
    public let axElement: AXUIElement
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
    public let isFocused: Bool
}

@MainActor
public final class AXWindowService {
    public static let shared = AXWindowService()

    public init() {}

    // MARK: - Accessibility Permission Management

    public func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if !prompt {
            return AXIsProcessTrusted()
        }
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        openSystemAccessibilitySettings()
        return trusted
    }

    public func openSystemAccessibilitySettings() {
        WindowObserver.shared.suppressMoveNotificationsUntil = Date().addingTimeInterval(0.8)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == "com.apple.SystemSettings" || app.bundleIdentifier == "com.apple.systempreferences" {
                app.unhide()
                app.activate()
            }
        }
    }

    // MARK: - Window Discovery

    public func discoverAllWindows() -> [AXWindowMetadata] {
        guard AXIsProcessTrusted() else { return [] }

        let workspaceApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isTerminated && !app.isHidden
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var results: [AXWindowMetadata] = []

        for app in workspaceApps {
            let pid = app.processIdentifier
            let bundleID = app.bundleIdentifier ?? "unknown.\(pid)"
            let appName = app.localizedName ?? bundleID
            let appElement = AXUIElementCreateApplication(pid)

            let focusedWindowElement: AXUIElement? = (pid == frontmostPID)
                ? copyElementAttribute(appElement, attribute: kAXFocusedWindowAttribute as String)
                : nil

            guard let windowElements = copyElementArrayAttribute(appElement, attribute: kAXWindowsAttribute as String) else {
                continue
            }

            for (idx, winElement) in windowElements.enumerated() {
                guard let metadata = inspectWindow(
                    element: winElement,
                    fallbackIndex: idx,
                    pid: pid,
                    bundleIdentifier: bundleID,
                    appName: appName,
                    focusedElement: focusedWindowElement
                ) else {
                    continue
                }
                results.append(metadata)
            }
        }

        return results
    }

    public func inspectWindow(
        element: AXUIElement,
        fallbackIndex: Int,
        pid: pid_t,
        bundleIdentifier: String,
        appName: String,
        focusedElement: AXUIElement?,
        allowMinimizedZeroFrame: Bool = false
    ) -> AXWindowMetadata? {
        let isMinimized = copyBoolAttribute(element, attribute: kAXMinimizedAttribute as String) ?? false
        let rawFrame = getFrame(of: element)
        let frame: CGRect
        if let rawFrame, rawFrame.width > 1, rawFrame.height > 1 {
            frame = rawFrame
        } else if allowMinimizedZeroFrame && isMinimized {
            frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        } else {
            return nil
        }

        var cgWinID: CGWindowID = 0
        let err = _AXUIElementGetWindow(element, &cgWinID)
        let uniqueID: String
        if err == .success && cgWinID != 0 {
            uniqueID = "\(pid)-\(cgWinID)"
        } else {
            let hash = CFHash(element)
            uniqueID = "\(pid)-h\(hash)-\(fallbackIndex)"
        }

        let role = copyStringAttribute(element, attribute: kAXRoleAttribute as String) ?? ""
        let subrole = copyStringAttribute(element, attribute: kAXSubroleAttribute as String) ?? ""
        let title = copyStringAttribute(element, attribute: kAXTitleAttribute as String) ?? ""
        let isFullscreen = copyBoolAttribute(element, attribute: "AXFullScreen") ?? false
        let isModal = copyBoolAttribute(element, attribute: kAXModalAttribute as String) ?? false
        let minSize = getMinimumSize(of: element)

        var sizeSettable: DarwinBoolean = false
        let settableErr = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable)
        let isResizable = (settableErr == .success) && sizeSettable.boolValue

        let hasMinBtn = copyElementAttribute(element, attribute: kAXMinimizeButtonAttribute as String) != nil
        let hasZoomBtn = copyElementAttribute(element, attribute: kAXZoomButtonAttribute as String) != nil

        let isFocused: Bool
        if let focusedElement {
            isFocused = CFEqual(element, focusedElement)
        } else {
            isFocused = copyBoolAttribute(element, attribute: kAXFocusedAttribute as String) ?? false
        }

        return AXWindowMetadata(
            id: uniqueID,
            windowNumber: cgWinID,
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            axElement: element,
            role: role,
            subrole: subrole,
            title: title,
            frame: frame,
            minimumSize: minSize,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen,
            isModal: isModal,
            isResizable: isResizable,
            hasMinimizeButton: hasMinBtn,
            hasZoomButton: hasZoomBtn,
            isFocused: isFocused
        )
    }

    // MARK: - Window Frame & Focus Manipulation

    public func getFrame(of element: AXUIElement) -> CGRect? {
        guard let pos = getPointAttribute(element, attribute: kAXPositionAttribute as String),
              let size = getSizeAttribute(element, attribute: kAXSizeAttribute as String) else {
            return nil
        }
        return CGRect(origin: pos, size: size)
    }

    public func getMinimumSize(of element: AXUIElement) -> CGSize {
        if let minSize = getSizeAttribute(element, attribute: "AXMinimumSize") {
            return minSize
        }
        return .zero
    }

    public func setFrame(_ targetFrame: CGRect, for element: AXUIElement, isLiveResize: Bool = false) {
        if let current = getFrame(of: element) {
            if abs(current.origin.x - targetFrame.origin.x) < 1.0 &&
               abs(current.origin.y - targetFrame.origin.y) < 1.0 &&
               abs(current.size.width - targetFrame.size.width) < 1.0 &&
               abs(current.size.height - targetFrame.size.height) < 1.0 {
                return
            }
        }

        var point = targetFrame.origin
        var size = targetFrame.size

        if isLiveResize {
            if let posVal = AXValueCreate(.cgPoint, &point) {
                AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
            }
            if let sizeVal = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
            }
            return
        }

        // Size -> Position -> Size sequence handles cross-monitor DPI and boundary constraints reliably
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    public func raiseAndFocus(_ window: AXWindowMetadata) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.axElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window.axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
    }

    public func closeWindow(_ window: AXWindowMetadata) {
        if let closeBtn = copyElementAttribute(window.axElement, attribute: kAXCloseButtonAttribute as String) {
            AXUIElementPerformAction(closeBtn, kAXPressAction as CFString)
        }
    }

    public func toggleMinimize(_ window: AXWindowMetadata) {
        let newState: CFBoolean = window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue
        AXUIElementSetAttributeValue(window.axElement, kAXMinimizedAttribute as CFString, newState)
    }

    /// Discovers all standard windows (including minimized ones) for a single running application.
    public func discoverWindows(for app: NSRunningApplication) -> [AXWindowMetadata] {
        guard AXIsProcessTrusted(), !app.isTerminated else { return [] }
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? "unknown.\(pid)"
        let appName = app.localizedName ?? bundleID
        let appElement = AXUIElementCreateApplication(pid)

        let focusedWindowElement: AXUIElement? = copyElementAttribute(appElement, attribute: kAXFocusedWindowAttribute as String)
        guard let windowElements = copyElementArrayAttribute(appElement, attribute: kAXWindowsAttribute as String) else {
            return []
        }

        var results: [AXWindowMetadata] = []
        for (idx, winElement) in windowElements.enumerated() {
            if let meta = inspectWindow(
                element: winElement,
                fallbackIndex: idx,
                pid: pid,
                bundleIdentifier: bundleID,
                appName: appName,
                focusedElement: focusedWindowElement,
                allowMinimizedZeroFrame: true
            ) {
                // Exclude non-standard floating popovers/menus
                if meta.role == (kAXWindowRole as String) &&
                   (meta.subrole == (kAXStandardWindowSubrole as String) || meta.isMinimized) {
                    results.append(meta)
                }
            }
        }
        return results
    }

    /// Detects if the given AX global coordinate hovers over an application icon in the macOS Dock.
    public func dockHoveredApplication(atAXPoint point: CGPoint) -> (app: NSRunningApplication, dockItemAXFrame: CGRect)? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hitElement)
        guard err == .success, var current = hitElement else { return nil }

        // Walk up at most 3 levels in case the hit element is a child badge/label inside AXDockItem
        for _ in 0..<3 {
            let role = copyStringAttribute(current, attribute: kAXRoleAttribute as String) ?? ""
            if role == "AXDockItem" {
                let subrole = copyStringAttribute(current, attribute: kAXSubroleAttribute as String) ?? ""
                guard subrole == "AXApplicationDockItem" else { return nil }
                guard let itemFrame = getFrame(of: current) else { return nil }

                // Match running application by URL attribute first, then by localized title
                if let url = copyURLAttribute(current, attribute: kAXURLAttribute as String),
                   let bundle = Bundle(url: url),
                   let bundleID = bundle.bundleIdentifier,
                   let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID && !$0.isTerminated }) {
                    return (runningApp, itemFrame)
                }

                if let title = copyStringAttribute(current, attribute: kAXTitleAttribute as String),
                   !title.isEmpty {
                    let cleanTitle = title.lowercased()
                    if let runningApp = NSWorkspace.shared.runningApplications.first(where: { app in
                        guard !app.isTerminated else { return false }
                        if app.localizedName?.lowercased() == cleanTitle { return true }
                        if app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == cleanTitle { return true }
                        return false
                    }) {
                        return (runningApp, itemFrame)
                    }
                }

                return nil
            }
            if let parent = copyElementAttribute(current, attribute: kAXParentAttribute as String) {
                current = parent
            } else {
                break
            }
        }
        return nil
    }

    // MARK: - Attribute Helpers

    private func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let str = value as? String else { return nil }
        return str
    }

    private func copyURLAttribute(_ element: AXUIElement, attribute: String) -> URL? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value else { return nil }
        if CFGetTypeID(val) == CFURLGetTypeID() {
            return (val as! CFURL) as URL
        }
        if let str = val as? String {
            return URL(string: str)
        }
        return nil
    }

    private func copyBoolAttribute(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let num = value as? Bool else { return nil }
        return num
    }

    private func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value, CFGetTypeID(val) == AXUIElementGetTypeID() else {
            return nil
        }
        return (val as! AXUIElement)
    }

    private func copyElementArrayAttribute(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    private func getPointAttribute(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value, CFGetTypeID(val) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(val as! AXValue, .cgPoint, &ValueWrapper(&point).pointee) else {
            return nil
        }
        return point
    }

    private func getSizeAttribute(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value, CFGetTypeID(val) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(val as! AXValue, .cgSize, &ValueWrapper(&size).pointee) else {
            return nil
        }
        return size
    }
}

private struct ValueWrapper<T> {
    var pointer: UnsafeMutablePointer<T>
    init(_ ptr: UnsafeMutablePointer<T>) {
        self.pointer = ptr
    }
    var pointee: T {
        get { pointer.pointee }
        nonmutating set { pointer.pointee = newValue }
    }
}

