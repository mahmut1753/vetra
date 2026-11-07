import SwiftUI
import AppKit
import Carbon

/// Unified Single-Menu Control Center with tactile visual layout cards, quick-action tiles,
/// hairline toggle rows, frontmost app switch, and inline drawers (no second window needed).
public struct UnifiedControlPanelView: View {
    @Bindable var coordinator: TilingCoordinator
    @Bindable var settings: SettingsStore

    @State private var expandedDrawer: InlineDrawerSection? = nil
    @State private var newBundleIDInput: String = ""
    @State private var recordingAction: ShortcutAction?
    @State private var hasScreenCapturePermission: Bool = WindowSnapshotService.shared.hasScreenCapturePermission

    private let permissionCheckTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private enum InlineDrawerSection: Equatable {
        case styleAndSpacing
        case permissionsAndGeneral
        case shortcuts
        case ignoredApps
    }

    public init(coordinator: TilingCoordinator, settings: SettingsStore) {
        self.coordinator = coordinator
        self.settings = settings
    }

    private var l10n: L10n { L10n(settings.language) }
    private var isTR: Bool { settings.language == .turkish }

    public var body: some View {
        let activeID = coordinator.activeDisplayID()
        let activeState = settings.state(for: activeID)
        let effectiveCap = activeState.maxTilesOverride ?? min(max(coordinator.tiledWindowCountByDisplay[activeID] ?? 3, 1), 4)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. TOP HEADER & STATUS DOT
                headerSection

                // 2. CALLOUT ACTION BANNER (Setup / Tidy Action)
                calloutBannerSection

                // 3. VISUAL SCREEN LAYOUT & MINIATURE CAPACITY MATRIX (1, 2, 3, 4)
                visualLayoutMatrixSection(
                    activeID: activeID,
                    activeState: activeState,
                    effectiveCap: effectiveCap
                )

                // 4. THREE QUICK-ACTION TACTILE CARDS (Retile, Borders, Mouse Focus)
                quickActionsRow

                // Inline Style Drawer if opened via "Borders" quick card
                if expandedDrawer == .styleAndSpacing {
                    inlineStyleDrawer(activeID: activeID, activeState: activeState)
                }

                Divider().opacity(0.45)

                // 5. CLEAN TOGGLE ROWS WITH SHORTCUT HINTS
                modeTogglesSection

                Divider().opacity(0.45)

                // 6. FRONTMOST APPLICATION TOGGLE ROW (with real App Icon)
                frontmostAppToggleRow

                Divider().opacity(0.45)

                // 7. INLINE EXPANDABLE NAVIGATION ROWS (Never leaves this menu!)
                inlineNavigationRows(activeID: activeID, activeState: activeState)

                Divider().opacity(0.45)

                // 8. MINIMAL FOOTER (Quit + Quick Language Switch)
                footerRow
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.appTheme.colorScheme)
        .onAppear {
            coordinator.updateFrontmostAppInfo()
            refreshPermissionStates()
            if !coordinator.isAccessibilityGranted {
                expandedDrawer = .permissionsAndGeneral
            }
        }
        .onReceive(permissionCheckTimer) { _ in
            refreshPermissionStates()
        }
    }

    private func refreshPermissionStates() {
        coordinator.checkAndStartIfTrusted(prompt: false)
        hasScreenCapturePermission = WindowSnapshotService.shared.hasScreenCapturePermission
    }

    // MARK: - 1. Top Header & Status Indicator

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AppIconArtworkView(style: settings.appIconStyle, size: 28)

                Text("Vetra")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { !settings.isTilingPaused },
                    set: { settings.isTilingPaused = !$0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusDotColor.opacity(0.55), radius: 3)

                Text(statusDescriptionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
        }
    }

    private var statusDotColor: Color {
        if !coordinator.isAccessibilityGranted {
            return .orange
        }
        if settings.isEffectivelyPaused {
            return .yellow
        }
        return .green
    }

    private var statusDescriptionText: String {
        if !coordinator.isAccessibilityGranted {
            return isTR ? "Kurulumun tamamlanması bekleniyor" : "Waiting for setup to finish"
        }
        if settings.isPausedByStageManager {
            return l10n.statusPausedByStageManager
        }
        if settings.isTilingPaused {
            return isTR ? "Otomatik döşeme duraklatıldı" : "Automatic tiling is paused"
        }
        return isTR ? "Masaüstü otomatik düzenleniyor" : "Automatically arranging windows"
    }

    // MARK: - 2. Callout Banner

    private var calloutBannerSection: some View {
        let needsSetup = !coordinator.isAccessibilityGranted || (settings.isTaskbarPreviewEnabled && settings.isLivePreviewScreenshotsEnabled && !hasScreenCapturePermission)

        return HStack(spacing: 12) {
            Image(systemName: needsSetup ? "sparkles" : "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(needsSetup ? Color.orange : settings.highlightSwiftUIColor)

            Text(
                !coordinator.isAccessibilityGranted
                ? (isTR ? "Vetra masaüstünüzü düzenlemek için izin bekliyor." : "Vetra is waiting to tidy this desktop.")
                : (!hasScreenCapturePermission && settings.isLivePreviewScreenshotsEnabled
                    ? (isTR ? "Canlı pencere önizlemesi için ekran kaydı izni gerekli." : "Grant Screen Recording for live window previews.")
                    : (isTR ? "Açık tüm pencereleri anında hizalayın." : "Tidy and align all open windows on screen."))
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                if !coordinator.isAccessibilityGranted {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        expandedDrawer = .permissionsAndGeneral
                    }
                    _ = coordinator.axService.requestAccessibilityPermission()
                    refreshPermissionStates()
                } else if !hasScreenCapturePermission && settings.isLivePreviewScreenshotsEnabled {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        expandedDrawer = .permissionsAndGeneral
                    }
                    hasScreenCapturePermission = WindowSnapshotService.shared.requestScreenCapturePermission()
                } else {
                    coordinator.reflowAllDisplays()
                }
            } label: {
                Text(
                    !coordinator.isAccessibilityGranted
                    ? (isTR ? "İzin Ver" : "Allow")
                    : (!hasScreenCapturePermission && settings.isLivePreviewScreenshotsEnabled
                        ? (isTR ? "İzin Ver" : "Allow")
                        : (isTR ? "Düzenle" : "Tidy it"))
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(needsSetup ? Color.orange : settings.highlightSwiftUIColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder((needsSetup ? Color.orange : settings.highlightSwiftUIColor).opacity(0.30), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((needsSetup ? Color.orange : settings.highlightSwiftUIColor).opacity(0.11))
        )
    }

    // MARK: - 3. Visual Layout Bar & 1-4 Capacity Preview Cards

    private func visualLayoutMatrixSection(
        activeID: CGDirectDisplayID,
        activeState: DisplayLayoutState,
        effectiveCap: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Title & Dynamic Subtitle
            HStack {
                Text(isTR ? "Bu ekrandaki pencereler" : "Windows on this screen")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(layoutSubtitle(kind: activeState.layout, cap: effectiveCap))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            // 4-Segment Custom Vector Layout Switcher
            HStack(spacing: 4) {
                ForEach(TileLayoutKind.allCases) { kind in
                    let isSelected = (activeState.layout == kind)
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            coordinator.switchLayoutOnActiveDisplay(kind)
                        }
                    } label: {
                        LayoutVectorGlyph(kind: kind, isSelected: isSelected)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                    .shadow(color: isSelected ? .black.opacity(0.10) : .clear, radius: 2, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )

            // 4 Miniature Screen Capacity Cards (1, 2, 3, 4)
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { count in
                    let isSelected = (effectiveCap == count)
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            if activeState.maxTilesOverride == count {
                                settings.setMaxTilesOverride(nil, for: activeID)
                            } else {
                                settings.setMaxTilesOverride(count, for: activeID)
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            MiniScreenDiagramView(
                                layout: activeState.layout,
                                windowCount: count,
                                isSelected: isSelected,
                                accentColor: settings.highlightSwiftUIColor
                            )
                            .frame(height: 34)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)

                            Text("\(count)")
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? settings.highlightSwiftUIColor : .secondary)
                                .padding(.bottom, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? settings.highlightSwiftUIColor.opacity(0.08) : Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isSelected ? settings.highlightSwiftUIColor.opacity(0.55) : Color.primary.opacity(0.06),
                                    lineWidth: isSelected ? 1.5 : 1.0
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Compact Left-Pane & Split Ratio Pill Bar when Side layout is active
            if activeState.layout == .side {
                HStack(spacing: 6) {
                    Text(isTR ? "Sol Bölme:" : "Left Pane:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach([1, 2], id: \.self) { leftCount in
                        CapacityPillButton(
                            title: "\(leftCount)",
                            isSelected: activeState.leftPaneCount == leftCount
                        ) {
                            settings.setLeftPaneCount(leftCount, for: activeID)
                        }
                    }

                    Spacer()

                    Text(isTR ? "Oran:" : "Split:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(MasterRatioPreset.allCases) { preset in
                        CapacityPillButton(
                            title: preset.displayLabel,
                            isSelected: abs(activeState.masterRatio - preset.rawValue) < 0.02
                        ) {
                            settings.defaultMasterRatio = preset.rawValue
                            settings.setMasterRatio(preset.rawValue, for: activeID)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func layoutSubtitle(kind: TileLayoutKind, cap: Int) -> String {
        let name = l10n.layoutName(kind)
        if isTR {
            switch cap {
            case 1: return "\(name) · Tam ekran"
            case 2: return "\(name) · İki dengeli bölme"
            case 3: return "\(name) · bir büyük, iki küçük"
            default: return "\(name) · dörtlü yerleşim"
            }
        } else {
            switch cap {
            case 1: return "\(name) · Single full window"
            case 2: return "\(name) · Two balanced panes"
            case 3: return "\(name) · One big, two small"
            default: return "\(name) · Four-pane arrangement"
            }
        }
    }

    // MARK: - 4. Three Quick-Action Tactile Cards

    private var quickActionsRow: some View {
        let isBordersActive = settings.highlightMode != .none

        return HStack(spacing: 8) {
            // Action 1: Retile / Hizala
            QuickActionTileButton(
                title: isTR ? "Hizala" : "Retile",
                systemImage: "arrow.clockwise",
                isActive: false,
                accentColor: settings.highlightSwiftUIColor
            ) {
                coordinator.reflowAllDisplays()
            }

            // Action 2: Borders & Style Drawer Toggle
            QuickActionTileButton(
                title: isTR ? "Kenarlık" : "Borders",
                systemImage: "square.inset.filled",
                isActive: isBordersActive || expandedDrawer == .styleAndSpacing,
                accentColor: settings.highlightSwiftUIColor
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    if expandedDrawer == .styleAndSpacing {
                        expandedDrawer = nil
                    } else {
                        expandedDrawer = .styleAndSpacing
                    }
                }
            }

            // Action 3: Hover / Mouse Follows Focus
            QuickActionTileButton(
                title: isTR ? "Fare Odağı" : "Hover focus",
                systemImage: "cursorarrow.click.2",
                isActive: settings.mouseFollowsFocus,
                accentColor: settings.highlightSwiftUIColor
            ) {
                settings.mouseFollowsFocus.toggle()
            }
        }
    }

    private func inlineStyleDrawer(activeID: CGDirectDisplayID, activeState: DisplayLayoutState) -> some View {
        AppleCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                StyleControlCardView(settings: settings, l10n: l10n)

                Divider().opacity(0.4)

                Toggle(l10n.smartGapsToggle, isOn: $settings.smartGaps)
                    .font(.system(size: 12))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 5. Clean Hairline-Separated Mode Toggle Rows

    private var modeTogglesSection: some View {
        VStack(spacing: 12) {
            // Focus Mode
            CleanSwitchRow(
                icon: "viewfinder",
                title: isTR ? "Odak Modu" : "Focus Mode",
                shortcutHint: settings.keyBindings[.toggleFocusMode]?.displayString ?? "⌃⌥F",
                isOn: $settings.isFocusModeEnabled
            )

            // Clean Space
            CleanSwitchRow(
                icon: "rectangle.dashed",
                title: l10n.modeCleanSpace,
                shortcutHint: nil,
                isOn: $settings.isCleanSpaceEnabled
            )

            // No Peek Mode
            CleanSwitchRow(
                icon: "circle.lefthalf.filled",
                title: isTR ? "Sızma Yok Modu" : "No peek mode",
                shortcutHint: nil,
                isOn: $settings.isNoPeekEnabled
            )

            // Tab View
            CleanSwitchRow(
                icon: "macwindow.on.rectangle",
                title: l10n.modeTabView,
                shortcutHint: settings.keyBindings[.cycleStack]?.displayString ?? "⌃⌥Space",
                isOn: $settings.isTabViewEnabled
            )

            // On-Window Quick Float / Untile Pill
            CleanSwitchRow(
                icon: "pin.slash",
                title: isTR ? "Pencere Üstü Hızlı Çöz Butonu" : "On-Window Quick Untile Button",
                shortcutHint: settings.keyBindings[.toggleFloatWindow]?.displayString ?? "⌃⌥W",
                isOn: $settings.isWindowQuickActionBarEnabled
            )

            // Dock Hover Previews + Live Screenshot Sub-Toggle
            VStack(alignment: .leading, spacing: 8) {
                CleanSwitchRow(
                    icon: "dock.rectangle",
                    title: l10n.modeTaskbarPreview,
                    shortcutHint: nil,
                    isOn: $settings.isTaskbarPreviewEnabled
                )

                if settings.isTaskbarPreviewEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(isTR ? "Canlı Pencere Görüntüsü" : "Live Window Screenshots")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if settings.isLivePreviewScreenshotsEnabled && !hasScreenCapturePermission {
                            Button {
                                hasScreenCapturePermission = WindowSnapshotService.shared.requestScreenCapturePermission()
                            } label: {
                                Text(isTR ? "İzin Ver" : "Grant")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }

                        Toggle("", isOn: $settings.isLivePreviewScreenshotsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }

    // MARK: - 6. Frontmost Application Toggle Row (Like "Tile Browser" in Reference)

    private var frontmostAppToggleRow: some View {
        let appName = coordinator.focusedAppName.isEmpty ? "Finder" : coordinator.focusedAppName
        let bundleID = coordinator.focusedAppBundleID
        let isTiled = bundleID.isEmpty ? true : !settings.isBundleIgnored(bundleID)

        return HStack(spacing: 10) {
            if let icon = coordinator.focusedAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(settings.highlightSwiftUIColor)
                    .frame(width: 22, height: 22)
            }

            Text(isTR ? "Döşe: \(appName)" : "Tile \(appName)")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: Binding(
                get: { isTiled },
                set: { _ in
                    coordinator.toggleIgnoreFocusedApp()
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(bundleID.isEmpty)
        }
    }

    // MARK: - 7. Inline Expandable Drawers (Permissions, Style, Shortcuts, Ignored Apps)

    private func inlineNavigationRows(activeID: CGDirectDisplayID, activeState: DisplayLayoutState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row A: Style & Appearance Settings
            InlineDrawerHeaderButton(
                icon: "sun.max",
                title: isTR ? "Görünüm ve Boşluk Ayarları" : "Appearance & Spacing",
                trailingText: "\(Int(settings.unifiedSpacePt)) pt",
                isExpanded: expandedDrawer == .styleAndSpacing
            ) {
                toggleDrawer(.styleAndSpacing)
            }

            // Row B: System Permissions & General Settings
            InlineDrawerHeaderButton(
                icon: "checkmark.shield",
                title: isTR ? "İzinler ve Genel Ayarlar" : "Permissions & General",
                trailingBadgeColor: (!coordinator.isAccessibilityGranted || !hasScreenCapturePermission) ? .orange : .green,
                isExpanded: expandedDrawer == .permissionsAndGeneral
            ) {
                toggleDrawer(.permissionsAndGeneral)
            }

            if expandedDrawer == .permissionsAndGeneral {
                permissionsAndGeneralInlineDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Row C: Keyboard Shortcuts
            InlineDrawerHeaderButton(
                icon: "command",
                title: isTR ? "Klavye Kısayolları" : "Keyboard shortcuts",
                trailingText: nil,
                isExpanded: expandedDrawer == .shortcuts
            ) {
                toggleDrawer(.shortcuts)
            }

            if expandedDrawer == .shortcuts {
                shortcutsInlineDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Row D: Excluded Applications List
            InlineDrawerHeaderButton(
                icon: "eye.slash",
                title: isTR ? "Yoksayılan Uygulamalar" : "Excluded Applications",
                trailingText: "\(settings.ignoredBundleIDs.count)",
                isExpanded: expandedDrawer == .ignoredApps
            ) {
                toggleDrawer(.ignoredApps)
            }

            if expandedDrawer == .ignoredApps {
                ignoredAppsInlineDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleDrawer(_ section: InlineDrawerSection) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            if expandedDrawer == section {
                expandedDrawer = nil
            } else {
                expandedDrawer = section
            }
        }
    }

    private var permissionsAndGeneralInlineDrawer: some View {
        AppleCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                // 1. Accessibility Permission
                HStack(spacing: 8) {
                    Image(systemName: coordinator.isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(coordinator.isAccessibilityGranted ? .green : .orange)
                    Text(l10n.accessibilityPermissionTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    PermissionStatusPill(
                        isGranted: coordinator.isAccessibilityGranted,
                        activeText: l10n.permissionActiveLabel,
                        missingText: l10n.permissionMissingLabel
                    )
                }

                HStack(spacing: 6) {
                    Button(l10n.requestPermissionButton) {
                        _ = coordinator.axService.requestAccessibilityPermission()
                        refreshPermissionStates()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(coordinator.isAccessibilityGranted)

                    Button(l10n.openSystemSettingsButton) {
                        coordinator.axService.openSystemAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider().opacity(0.4)

                // 2. Screen Recording Permission
                HStack(spacing: 8) {
                    Image(systemName: hasScreenCapturePermission ? "checkmark.circle.fill" : "camera.viewfinder")
                        .foregroundStyle(hasScreenCapturePermission ? .green : .orange)
                    Text(l10n.screenRecordingPermissionTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    PermissionStatusPill(
                        isGranted: hasScreenCapturePermission,
                        activeText: l10n.permissionActiveLabel,
                        missingText: l10n.permissionMissingLabel
                    )
                }

                HStack(spacing: 6) {
                    Button(l10n.requestPermissionButton) {
                        hasScreenCapturePermission = WindowSnapshotService.shared.requestScreenCapturePermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(hasScreenCapturePermission)

                    Button(l10n.openSystemSettingsButton) {
                        WindowSnapshotService.shared.openScreenRecordingSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        WindowSnapshotService.shared.relaunchApplication()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isTR ? "İzni Uygula (Yeniden Başlat)" : "Apply Permission (Restart)")
                }

                Divider().opacity(0.4)

                // 3. Theme & Launch at Login
                HStack {
                    Text(l10n.themeLabel)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.appTheme) {
                        ForEach(AppThemeOption.allCases) { option in
                            Text(l10n.themeName(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Toggle(l10n.launchAtLoginToggle, isOn: $settings.launchAtLogin)
                    .font(.system(size: 12))
            }
        }
    }

    private var shortcutsInlineDrawer: some View {
        AppleCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l10n.commandDragSwapHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(l10n.resetShortcutsButton) {
                        recordingAction = nil
                        settings.resetShortcutsToDefault()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Divider().opacity(0.4)

                ForEach(ShortcutAction.allCases) { action in
                    let conflicts = settings.conflictingActions(for: action)
                    HStack {
                        Text(l10n.shortcutActionName(action))
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        ShortcutRecorderButton(
                            action: action,
                            currentBinding: settings.keyBindings[action] ?? KeyBinding(keyCode: 0, carbonModifiers: 0),
                            isRecording: recordingAction == action,
                            hasConflict: !conflicts.isEmpty,
                            promptText: l10n.pressKeysPrompt,
                            onStartRecording: {
                                recordingAction = action
                            },
                            onRecorded: { newBinding in
                                settings.keyBindings[action] = newBinding
                                recordingAction = nil
                            }
                        )
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var ignoredAppsInlineDrawer: some View {
        AppleCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(l10n.addBundleIDPlaceholder, text: $newBundleIDInput)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    Button(l10n.addButton) {
                        let trimmed = newBundleIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        settings.ignoredBundleIDs.insert(trimmed)
                        newBundleIDInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newBundleIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ForEach(Array(settings.ignoredBundleIDs).sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if !SettingsStore.defaultIgnoredBundles.contains(bundleID) {
                            Button(role: .destructive) {
                                settings.ignoredBundleIDs.remove(bundleID)
                            } label: {
                                Text(l10n.removeButton)
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 8. Minimal Footer Row

    private var footerRow: some View {
        HStack {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isTR ? "Vetra'dan Çık" : "Quit Vetra")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Quick TR / EN Pill Switcher
            HStack(spacing: 2) {
                ForEach(AppLanguage.allCases) { lang in
                    let isSelected = (settings.language == lang)
                    Button {
                        settings.language = lang
                    } label: {
                        Text(lang == .turkish ? "TR" : "EN")
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                            )
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
    }
}

public struct SettingsView: View {
    @Bindable var coordinator: TilingCoordinator
    @Bindable var settings: SettingsStore

    public init(coordinator: TilingCoordinator, settings: SettingsStore) {
        self.coordinator = coordinator
        self.settings = settings
    }

    public var body: some View {
        UnifiedControlPanelView(coordinator: coordinator, settings: settings)
            .frame(width: 380, height: 660)
    }
}

// MARK: - Custom Vector Diagrams & Tactile Subcomponents

private struct LayoutVectorGlyph: View {
    let kind: TileLayoutKind
    let isSelected: Bool

    var body: some View {
        let color = isSelected ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.65)
        HStack(spacing: 2) {
            switch kind {
            case .grid:
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                }
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                }
            case .columns:
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                RoundedRectangle(cornerRadius: 1.5).fill(color)
            case .rows:
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                }
            case .side:
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                    .frame(width: 11)
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                    RoundedRectangle(cornerRadius: 1.5).fill(color)
                }
            }
        }
        .frame(width: 24, height: 15)
    }
}

private struct MiniScreenDiagramView: View {
    let layout: TileLayoutKind
    let windowCount: Int
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        let fill = isSelected ? accentColor.opacity(0.38) : Color.primary.opacity(0.12)

        Group {
            if windowCount == 1 {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill)
            } else if windowCount == 2 {
                if layout == .rows {
                    VStack(spacing: 2.5) {
                        RoundedRectangle(cornerRadius: 2.5).fill(fill)
                        RoundedRectangle(cornerRadius: 2.5).fill(fill)
                    }
                } else {
                    HStack(spacing: 2.5) {
                        RoundedRectangle(cornerRadius: 2.5).fill(fill)
                        RoundedRectangle(cornerRadius: 2.5).fill(fill)
                    }
                }
            } else if windowCount == 3 {
                switch layout {
                case .columns:
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2).fill(fill)
                        RoundedRectangle(cornerRadius: 2).fill(fill)
                        RoundedRectangle(cornerRadius: 2).fill(fill)
                    }
                case .rows:
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2).fill(fill)
                        RoundedRectangle(cornerRadius: 2).fill(fill)
                        RoundedRectangle(cornerRadius: 2).fill(fill)
                    }
                case .grid, .side:
                    HStack(spacing: 2.5) {
                        RoundedRectangle(cornerRadius: 2.5).fill(fill)
                        VStack(spacing: 2.5) {
                            RoundedRectangle(cornerRadius: 2.5).fill(fill)
                            RoundedRectangle(cornerRadius: 2.5).fill(fill)
                        }
                    }
                }
            } else {
                switch layout {
                case .columns:
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(fill)
                        }
                    }
                case .rows:
                    VStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(fill)
                        }
                    }
                case .side:
                    HStack(spacing: 2.5) {
                        RoundedRectangle(cornerRadius: 2.5).fill(fill)
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                        }
                    }
                case .grid:
                    VStack(spacing: 2.5) {
                        HStack(spacing: 2.5) {
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                        }
                        HStack(spacing: 2.5) {
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                            RoundedRectangle(cornerRadius: 2).fill(fill)
                        }
                    }
                }
            }
        }
    }
}

private struct QuickActionTileButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? accentColor : .primary.opacity(0.80))

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isActive ? accentColor : .primary.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? accentColor.opacity(0.45) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CleanSwitchRow: View {
    let icon: String
    let title: String
    let shortcutHint: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            if let shortcutHint {
                Text(shortcutHint)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.65))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct InlineDrawerHeaderButton: View {
    let icon: String
    let title: String
    var trailingText: String? = nil
    var trailingBadgeColor: Color? = nil
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if let trailingBadgeColor {
                    Circle()
                        .fill(trailingBadgeColor)
                        .frame(width: 7, height: 7)
                }

                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.75))
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Apple Card & Pill Components

public struct AppleCardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

public struct PermissionStatusPill: View {
    public let isGranted: Bool
    public let activeText: String
    public let missingText: String

    public init(isGranted: Bool, activeText: String, missingText: String) {
        self.isGranted = isGranted
        self.activeText = activeText
        self.missingText = missingText
    }

    public var body: some View {
        Text(isGranted ? activeText : missingText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isGranted ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((isGranted ? Color.green : Color.orange).opacity(0.15))
            )
    }
}

public struct ModePillToggle: View {
    public let title: String
    public let icon: String
    @Binding public var isOn: Bool

    public init(title: String, icon: String, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct CapacityPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.2)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutRecorderButton: View {
    let action: ShortcutAction
    let currentBinding: KeyBinding
    let isRecording: Bool
    let hasConflict: Bool
    let promptText: String
    let onStartRecording: () -> Void
    let onRecorded: (KeyBinding) -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopListening()
            } else {
                startListening()
            }
        } label: {
            Text(isRecording ? promptText : currentBinding.displayString)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: 86)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            hasConflict ? Color.orange : (isRecording ? Color.accentColor : Color.clear),
                            lineWidth: 1.4
                        )
                )
                .foregroundStyle(hasConflict ? .orange : (isRecording ? .accentColor : .primary))
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopListening()
        }
    }

    private func startListening() {
        onStartRecording()
        stopListening()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbonMods: UInt32 = 0
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }

            guard carbonMods != 0 else {
                return nil
            }
            let binding = KeyBinding(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
            stopListening()
            onRecorded(binding)
            return nil
        }
    }

    private func stopListening() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
