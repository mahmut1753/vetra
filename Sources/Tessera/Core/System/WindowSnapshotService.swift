import Foundation
import AppKit
import CoreGraphics

// Bridge CoreGraphics CGWindowListCreateImage with the exact C ABI return type (Unmanaged<CGImage>?)
// Using CGWindowListCreateImage on-demand avoids triggering the persistent purple Screen Capture pill in the macOS Menu Bar.
@_silgen_name("CGWindowListCreateImage")
private func _TesseraCGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: UInt32,
    _ windowID: CGWindowID,
    _ imageOption: UInt32
) -> Unmanaged<CGImage>?

@MainActor
public final class WindowSnapshotService {
    public static let shared = WindowSnapshotService()

    private var thumbnailCache: [String: NSImage] = [:]
    private var latestMetadataByID: [String: AXWindowMetadata] = [:]

    // CGWindowListOption: kCGWindowListOptionIncludingWindow (1 << 3)
    private let optionIncludingWindow: UInt32 = (1 << 3)
    // CGWindowImageOption: kCGWindowImageBoundsIgnoreFraming (1 << 0) | kCGWindowImageNominalResolution (1 << 4)
    private let imageOptions: UInt32 = (1 << 0) | (1 << 4)

    public init() {}

    /// Checks whether Screen Recording permission is currently active without triggering the purple menu bar indicator.
    public var hasScreenCapturePermission: Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return probeLiveScreenCaptureAccess()
    }

    /// Probes whether WindowServer exposes other apps' window titles (which only happens when Screen Recording is granted).
    /// This metadata check does NOT trigger the macOS purple menu bar recording indicator.
    private func probeLiveScreenCaptureAccess() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for entry in infoList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }

            if let winName = entry[kCGWindowName as String] as? String, !winName.isEmpty {
                return true
            }
        }
        return false
    }

    @discardableResult
    public func requestScreenCapturePermission() -> Bool {
        if hasScreenCapturePermission {
            return true
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.vetra.windowmanager"
        let resetProcess = Process()
        resetProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        resetProcess.arguments = ["reset", "ScreenCapture", bundleID]
        try? resetProcess.run()
        resetProcess.waitUntilExit()

        let granted = CGRequestScreenCaptureAccess()
        openScreenRecordingSettings()
        return granted || hasScreenCapturePermission
    }

    public func openScreenRecordingSettings() {
        WindowObserver.shared.suppressMoveNotificationsUntil = Date().addingTimeInterval(0.8)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
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

    /// Relaunches Tessera.app so macOS applies newly granted Screen Recording TCC tokens immediately.
    public func relaunchApplication() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        let path = bundleURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        task.arguments = ["-c", "sleep 0.35 && open \"\(path)\""]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    public func metadata(forWindowID windowID: String) -> AXWindowMetadata? {
        latestMetadataByID[windowID]
    }

    public func snapshot(forWindowID windowID: String) -> NSImage? {
        if let meta = latestMetadataByID[windowID] {
            return snapshot(for: meta)
        }
        return thumbnailCache[windowID]
    }

    /// Updates window metadata mapping without performing any screen capture in the background (so the purple menu bar pill never appears while idle).
    public func updateMetadata(for windows: [AXWindowMetadata]) {
        for win in windows {
            latestMetadataByID[win.id] = win
        }
    }

    /// Captures a window screenshot strictly on-demand when the user hovers over the Dock or Stack Tab.
    public func snapshot(for window: AXWindowMetadata) -> NSImage? {
        latestMetadataByID[window.id] = window

        let resolvedWinID = resolveWindowID(for: window)
        if resolvedWinID != 0 && !window.isMinimized {
            if let cgImg = captureWindowCGImage(windowID: resolvedWinID) {
                let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                thumbnailCache[window.id] = nsImg
                return nsImg
            }
        }

        return thumbnailCache[window.id]
    }

    private func captureWindowCGImage(windowID: CGWindowID) -> CGImage? {
        guard let cgImg = _TesseraCGWindowListCreateImage(
            .null,
            optionIncludingWindow,
            windowID,
            imageOptions
        )?.takeRetainedValue(),
        cgImg.width > 8 && cgImg.height > 8 else {
            return nil
        }
        return cgImg
    }

    private func resolveWindowID(for window: AXWindowMetadata) -> CGWindowID {
        if window.windowNumber != 0 {
            return window.windowNumber
        }

        guard let infoList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }

        var fallbackMatch: CGWindowID = 0

        for entry in infoList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == window.pid,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let winNum = entry[kCGWindowNumber as String] as? UInt32 else {
                continue
            }

            if fallbackMatch == 0 {
                fallbackMatch = CGWindowID(winNum)
            }

            if let winName = entry[kCGWindowName as String] as? String,
               !winName.isEmpty,
               !window.title.isEmpty,
               winName == window.title {
                return CGWindowID(winNum)
            }

            if let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: boundsDict) {
                if abs(rect.origin.x - window.frame.origin.x) < 24 &&
                   abs(rect.origin.y - window.frame.origin.y) < 24 &&
                   abs(rect.width - window.frame.width) < 36 {
                    return CGWindowID(winNum)
                }
            }
        }

        return fallbackMatch
    }
}
