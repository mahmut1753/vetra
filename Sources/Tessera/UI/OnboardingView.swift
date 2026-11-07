import SwiftUI
import AppKit

public struct OnboardingView: View {
    @Bindable var coordinator: TilingCoordinator
    @Bindable var settings: SettingsStore
    public var onClose: () -> Void

    @State private var hasScreenCapturePermission: Bool = WindowSnapshotService.shared.hasScreenCapturePermission

    public init(
        coordinator: TilingCoordinator,
        settings: SettingsStore,
        onClose: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.onClose = onClose
    }

    private var l10n: L10n { L10n(settings.language) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppIconArtworkView(style: settings.appIconStyle, size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.onboardingWelcomeTitle)
                        .font(.system(size: 20, weight: .bold))
                    Text(l10n.appSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            AppleCardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(l10n.onboardingStep1Title)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        statusBadge
                    }

                    Text(l10n.onboardingStep1Body)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            coordinator.checkAndStartIfTrusted(prompt: true)
                            coordinator.axService.openSystemAccessibilitySettings()
                        } label: {
                            Text(l10n.grantPermissionButton)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(coordinator.isAccessibilityGranted)
                    }

                    Divider().opacity(0.4)

                    HStack {
                        Text(l10n.screenRecordingPermissionTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        PermissionStatusPill(
                            isGranted: hasScreenCapturePermission,
                            activeText: l10n.permissionActiveLabel,
                            missingText: l10n.permissionMissingLabel
                        )
                    }

                    Text(l10n.screenRecordingPermissionSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            hasScreenCapturePermission = WindowSnapshotService.shared.requestScreenCapturePermission()
                        } label: {
                            Text(l10n.requestPermissionButton)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                        .disabled(hasScreenCapturePermission)

                        Button {
                            WindowSnapshotService.shared.openScreenRecordingSettings()
                        } label: {
                            Text(l10n.openSystemSettingsButton)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            AppleCardContainer {
                StyleControlCardView(settings: settings, l10n: l10n)
            }

            HStack {
                Spacer()
                Button {
                    settings.hasCompletedOnboarding = true
                    onClose()
                } label: {
                    Text(l10n.continueToTesseraButton)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.isAccessibilityGranted)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            coordinator.checkAndStartIfTrusted(prompt: false)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if coordinator.isAccessibilityGranted {
            Label(l10n.permissionGrantedBadge, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        } else {
            Label(l10n.permissionWaitingBadge, systemImage: "clock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }
}
