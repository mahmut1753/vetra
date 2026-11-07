import SwiftUI
import AppKit

@MainActor
public final class AppWindowController {
    public static let shared = AppWindowController()

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    public init() {}

    public func showSettings(coordinator: TilingCoordinator, settings: SettingsStore) {
        if let existing = settingsWindow {
            existing.level = .normal
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(coordinator: coordinator, settings: settings)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Vetra — \(L10n(settings.language).openSettings.replacingOccurrences(of: "...", with: ""))"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .normal
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    public func showOnboarding(coordinator: TilingCoordinator, settings: SettingsStore) {
        if let existing = onboardingWindow {
            existing.level = .normal
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(
            coordinator: coordinator,
            settings: settings,
            onClose: { [weak self] in
                self?.onboardingWindow?.close()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Vetra — \(L10n(settings.language).onboardingWelcomeTitle)"
        window.styleMask = [.titled, .closable]
        window.level = .normal
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    public func closeOnboardingIfOpen() {
        onboardingWindow?.close()
    }
}

@MainActor
public final class TesseraAppDelegate: NSObject, NSApplicationDelegate {
    public let settings = SettingsStore()
    public lazy var coordinator = TilingCoordinator(settings: settings)

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings.applyTheme()
        settings.applyAppIcon()

        if !coordinator.isAccessibilityGranted {
            coordinator.checkAndStartIfTrusted(prompt: true)
        } else {
            coordinator.reflowAllDisplays()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator.windowObserver.stop()
        coordinator.hotkeyManager.unregisterAll()
        coordinator.overlayManager.clearAllOverlays()
    }
}

@main
public struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(TesseraAppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                coordinator: appDelegate.coordinator,
                settings: appDelegate.settings,
                onOpenSettings: {
                    AppWindowController.shared.showSettings(
                        coordinator: appDelegate.coordinator,
                        settings: appDelegate.settings
                    )
                },
                onOpenOnboarding: {
                    AppWindowController.shared.showOnboarding(
                        coordinator: appDelegate.coordinator,
                        settings: appDelegate.settings
                    )
                }
            )
        } label: {
            MenuBarBrandIcon(isPaused: appDelegate.settings.isEffectivelyPaused)
        }
        .menuBarExtraStyle(.window)
    }
}
