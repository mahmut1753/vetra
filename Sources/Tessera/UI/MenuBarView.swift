import SwiftUI
import AppKit

public struct MenuBarView: View {
    @Bindable var coordinator: TilingCoordinator
    @Bindable var settings: SettingsStore
    public var onOpenSettings: () -> Void
    public var onOpenOnboarding: () -> Void

    public init(
        coordinator: TilingCoordinator,
        settings: SettingsStore,
        onOpenSettings: @escaping () -> Void = {},
        onOpenOnboarding: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
    }

    public var body: some View {
        UnifiedControlPanelView(coordinator: coordinator, settings: settings)
            .frame(width: 366, height: 640)
    }
}

// MARK: - Shared Apple-Style Control Card (Matches Uploaded Design Reference)

public struct StyleControlCardView: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n

    public init(settings: SettingsStore, l10n: L10n) {
        self.settings = settings
        self.l10n = l10n
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Highlight 2x2 Grid
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.headerHighlight)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(HighlightMode.allCases) { mode in
                        let isSelected = (settings.highlightMode == mode)
                        Button {
                            settings.highlightMode = mode
                        } label: {
                            Text(l10n.highlightShortName(mode))
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color 6 Swatches
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.headerColor)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(PresetColorSwatch.allCases) { swatch in
                        let isSelected = (settings.highlightColorHex.uppercased() == swatch.rawValue.uppercased())
                        Button {
                            settings.highlightColorHex = swatch.rawValue
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(swatch.swiftUIColor)
                                    .frame(width: 26, height: 26)

                                if isSelected {
                                    Circle()
                                        .strokeBorder(swatch.swiftUIColor, lineWidth: 2)
                                        .frame(width: 34, height: 34)
                                }
                            }
                            .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            // Space · X pt Slider
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.headerSpace(Int(settings.unifiedSpacePt)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Slider(value: $settings.unifiedSpacePt, in: 0...28, step: 2)
                    .tint(.accentColor)
            }

            // App icon · Focus (7 Squircles)
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.headerAppIcon(settings.appIconStyle.displayName))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(AppIconStyle.allCases) { style in
                        let isSelected = (settings.appIconStyle == style)
                        Button {
                            settings.appIconStyle = style
                        } label: {
                            AppIconArtworkView(style: style, size: 32)
                                .padding(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
