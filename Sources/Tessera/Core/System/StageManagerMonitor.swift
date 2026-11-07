import Foundation
import AppKit

@MainActor
@Observable
public final class StageManagerMonitor {
    public private(set) var isStageManagerActive: Bool = false
    public private(set) var hasSequoiaNativeMarginsEnabled: Bool = false

    public var onStageManagerStateChanged: ((Bool) -> Void)?

    private var pollTimer: Timer?
    private let suiteName = "com.apple.WindowManager"

    public init() {
        refreshState()
        startMonitoring()
    }

    public func startMonitoring() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState()
            }
        }
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func refreshState() {
        let wmDefaults = UserDefaults(suiteName: suiteName)
        let stageEnabled = wmDefaults?.bool(forKey: "GloballyEnabled") ?? false

        // On macOS 15 Sequoia, "Tiled windows have margins" is controlled under com.apple.WindowManager
        // via EnableTiledWindowMargins (defaults to true when unset on Sequoia).
        let marginsFlag: Bool
        if let explicitObj = wmDefaults?.object(forKey: "EnableTiledWindowMargins") as? Bool {
            marginsFlag = explicitObj
        } else if let altObj = wmDefaults?.object(forKey: "TiledWindowsHaveMargins") as? Bool {
            marginsFlag = altObj
        } else {
            // Default on macOS 15+ is enabled unless disabled by user
            marginsFlag = true
        }

        hasSequoiaNativeMarginsEnabled = marginsFlag

        if stageEnabled != isStageManagerActive {
            isStageManagerActive = stageEnabled
            onStageManagerStateChanged?(stageEnabled)
        }
    }

    public func openDesktopAndDockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

