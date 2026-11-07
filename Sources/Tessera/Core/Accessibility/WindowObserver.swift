import Foundation
import AppKit
import ApplicationServices

public enum WindowObserverEventKind: Sendable {
    case windowCreated
    case windowDestroyed
    case windowMinimizedChanged
    case focusChanged
    case userGeometryModified
    case workspaceAppChanged
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    let notifName = notification as String
    Task { @MainActor in
        WindowObserver.shared.handleAXNotification(name: notifName)
    }
}

@MainActor
public final class WindowObserver {
    public static let shared = WindowObserver()

    public var onDebouncedEvent: ((WindowObserverEventKind) -> Void)?

    /// Timestamp until which programmatic moves/resizes by Tessera should be ignored
    public var suppressMoveNotificationsUntil: Date = .distantPast

    private var observersByPID: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?
    private var pendingEventKind: WindowObserverEventKind = .userGeometryModified

    public init() {}

    public func start() {
        stop()
        registerWorkspaceNotifications()
        syncAllRunningApplicationObservers()
    }

    public func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()

        for (_, obs) in observersByPID {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(obs),
                .defaultMode
            )
        }
        observersByPID.removeAll()
    }

    public func syncAllRunningApplicationObservers() {
        guard AXIsProcessTrusted() else { return }

        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let activePIDs = Set(regularApps.map(\.processIdentifier))

        for existingPID in Array(observersByPID.keys) where !activePIDs.contains(existingPID) {
            removeObserver(for: existingPID)
        }

        for app in regularApps where observersByPID[app.processIdentifier] == nil {
            addObserver(for: app.processIdentifier)
        }
    }

    // MARK: - AX Notification Handling & Mouse-Safe Debounce

    fileprivate func handleAXNotification(name: String) {
        let now = Date()
        let isMove = (name == kAXWindowMovedNotification)
        let isResize = (name == kAXWindowResizedNotification)

        if (isMove || isResize) && now < suppressMoveNotificationsUntil {
            return
        }

        let kind: WindowObserverEventKind
        switch name {
        case kAXWindowCreatedNotification:
            kind = .windowCreated
        case kAXUIElementDestroyedNotification:
            kind = .windowDestroyed
        case kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification:
            kind = .windowMinimizedChanged
        case kAXFocusedWindowChangedNotification:
            kind = .focusChanged
        default:
            kind = .userGeometryModified
        }

        scheduleDebouncedCallback(kind: kind)
    }

    private func scheduleDebouncedCallback(kind: WindowObserverEventKind) {
        // Lifecycle events take precedence over geometry modifications
        if pendingEventKind == .userGeometryModified || kind != .userGeometryModified {
            pendingEventKind = kind
        }

        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self else { return }

            // Wait while the user is actively holding down the left mouse button
            // (e.g., dragging a window title bar or resizing a window edge).
            // Using NSEvent.pressedMouseButtons directly never gets stuck if mouseUp is swallowed by WindowServer.
            var waitCycles = 0
            while (NSEvent.pressedMouseButtons & 1) != 0 && waitCycles < 200 {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                waitCycles += 1
            }

            let eventToFire = self.pendingEventKind
            self.pendingEventKind = .userGeometryModified
            self.onDebouncedEvent?(eventToFire)
        }
    }

    // MARK: - Per-App AXObserver Registration

    private func addObserver(for pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        let err = AXObserverCreate(pid, axObserverCallback, &observer)
        guard err == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let notifications: [CFString] = [
            kAXWindowCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
            kAXWindowMiniaturizedNotification as CFString,
            kAXWindowDeminiaturizedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
            kAXWindowMovedNotification as CFString,
            kAXWindowResizedNotification as CFString
        ]

        for notif in notifications {
            AXObserverAddNotification(observer, appElement, notif, nil)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observersByPID[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        guard let obs = observersByPID.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
    }

    // MARK: - NSWorkspace Notifications

    private func registerWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter

        let launchToken = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncAllRunningApplicationObservers()
                self?.scheduleDebouncedCallback(kind: .workspaceAppChanged)
            }
        }

        let terminateToken = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncAllRunningApplicationObservers()
                self?.scheduleDebouncedCallback(kind: .workspaceAppChanged)
            }
        }

        let hideToken = nc.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedCallback(kind: .workspaceAppChanged)
            }
        }

        let unhideToken = nc.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedCallback(kind: .workspaceAppChanged)
            }
        }

        let activateToken = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedCallback(kind: .focusChanged)
            }
        }

        let spaceToken = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedCallback(kind: .workspaceAppChanged)
            }
        }

        workspaceTokens = [launchToken, terminateToken, hideToken, unhideToken, activateToken, spaceToken]
    }
}
