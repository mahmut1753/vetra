import Foundation

public struct L10n: Sendable {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }

    private func tr(_ en: String, _ tr: String) -> String {
        switch language {
        case .english: return en
        case .turkish: return tr
        }
    }

    // MARK: - General & Menu Bar

    public var appTitle: String { "Vetra" }
    public var appSubtitle: String {
        tr("Automatic Window Tiling & Live Previews for macOS", "macOS için Otomatik Pencere Düzenleyici ve Canlı Önizleme")
    }
    public var statusActive: String { tr("Active", "Aktif") }
    public var statusPaused: String { tr("Paused", "Duraklatıldı") }
    public var statusPausedByStageManager: String {
        tr("Stage Manager Active", "Sahne Yöneticisi Aktif")
    }
    public var activeDisplayLayout: String { tr("Layout", "Düzen") }
    public var maxWindowsPerScreenLabel: String { tr("Tiles per screen", "Ekran başına bölme") }
    public var autoCapacityLabel: String { tr("Auto", "Oto") }
    public var reflowNow: String { tr("Reflow Windows", "Yeniden Hizala") }
    public var cycleStack: String { tr("Cycle Stack", "Yığını Döndür") }
    public var pauseTiling: String { tr("Pause", "Duraklat") }
    public var resumeTiling: String { tr("Resume", "Sürdür") }
    public var ignoreFocusedApp: String { tr("Ignore", "Yoksay") }
    public var unignoreFocusedApp: String { tr("Unignore", "Dahil Et") }
    public var openSettings: String { tr("Settings...", "Ayarlar...") }
    public var openOnboarding: String { tr("Accessibility Setup...", "Erişilebilirlik Kurulumu...") }
    public var quitTessera: String { tr("Quit", "Çıkış") }

    // MARK: - Built-in Modes (Focus, No Peek, Clean Space, Tab View)

    public var sectionModes: String { tr("Workspace Modes", "Çalışma Modları") }
    public var modeFocus: String { tr("Focus", "Odak") }
    public var modeNoPeek: String { tr("No peek", "Sızma yok") }
    public var modeCleanSpace: String { tr("Clean Space", "Temiz Alan") }
    public var modeTabView: String { tr("Tab View", "Sekme Görünümü") }
    public var modeTaskbarPreview: String { tr("Dock Previews", "Görev Çubuğu Önizleme") }
    public var modeLivePreviewScreenshots: String {
        tr("Live Window Content in Previews", "Önizlemede Canlı Pencere Görüntüsü")
    }
    public var taskbarPreviewSubtitle: String {
        tr("Show open windows when hovering over apps in the macOS Dock", "Dock'taki açık uygulamaların üzerine gelindiğinde pencereleri göster")
    }
    public var livePreviewScreenshotsSubtitle: String {
        tr("Capture and display real-time window screenshots inside preview cards", "Önizleme kartlarında açık pencerelerin gerçek ekran görüntüsünü göster")
    }

    // MARK: - System Permissions (Accessibility & Screen Recording)

    public var sectionPermissions: String {
        tr("System Permissions", "Sistem İzinleri")
    }
    public var accessibilityPermissionTitle: String {
        tr("Accessibility Access", "Erişilebilirlik İzni")
    }
    public var accessibilityPermissionSubtitle: String {
        tr("Required to automatically tile, move, and resize application windows.", "Pencereleri otomatik döşemek, taşımak ve boyutlandırmak için gereklidir.")
    }
    public var screenRecordingPermissionTitle: String {
        tr("Screen Recording (Live Previews)", "Ekran Kaydı (Canlı Önizleme İzni)")
    }
    public var screenRecordingPermissionSubtitle: String {
        tr("Used to render live window thumbnails in Dock and Tab previews.", "Dock ve Sekme önizlemelerinde pencere içeriklerini canlı göstermek için kullanılır.")
    }
    public var requestPermissionButton: String {
        tr("Request Access", "İzin İste")
    }
    public var openSystemSettingsButton: String {
        tr("System Settings...", "Ayarları Aç...")
    }
    public var refreshStatusButton: String {
        tr("Refresh Status", "Durumu Yenile")
    }
    public var permissionActiveLabel: String {
        tr("Active", "Aktif")
    }
    public var permissionMissingLabel: String {
        tr("Required", "İzin Gerekli")
    }

    // MARK: - Highlight, Color, Space, App Icon (Exact Apple Card Style)

    public var headerHighlight: String { tr("Highlight", "Vurgu") }
    public var headerColor: String { tr("Color", "Renk") }
    public func headerSpace(_ pt: Int) -> String {
        tr("Space · \(pt) pt", "Boşluk · \(pt) pt")
    }
    public func headerAppIcon(_ name: String) -> String {
        tr("App icon · \(name)", "Uygulama ikonu · \(name)")
    }

    public func highlightShortName(_ mode: HighlightMode) -> String {
        switch mode {
        case .none: return tr("None", "Yok")
        case .activeBorder: return tr("Active border", "Aktif kenarlık")
        case .allBorders: return tr("All borders", "Tüm kenarlıklar")
        case .glow: return tr("Glow", "Parlama")
        }
    }

    // MARK: - Layouts

    public func layoutName(_ kind: TileLayoutKind) -> String {
        switch kind {
        case .grid: return tr("Grid", "Izgara")
        case .columns: return tr("Columns", "Sütunlar")
        case .rows: return tr("Rows", "Satırlar")
        case .side: return tr("Side", "Yan")
        }
    }

    public func layoutDescription(_ kind: TileLayoutKind) -> String {
        switch kind {
        case .grid:
            return tr("2x2 grid (up to 5 on Ultrawide)", "2x2 ızgara (Geniş ekranda 5 bölme)")
        case .columns:
            return tr("Side-by-side vertical columns", "Yan yana dikey sütunlar")
        case .rows:
            return tr("Stacked horizontal rows", "Alt alta yatay satırlar")
        case .side:
            return tr("Master + stack (drag window to left to add more)", "Ana + yığın (sola pencere sürükleyerek çoğaltın)")
        }
    }

    // MARK: - Settings Sections

    public var tabAppearance: String { tr("Style", "Görünüm") }
    public var tabLayoutAndGaps: String { tr("Layout", "Düzen") }
    public var tabShortcuts: String { tr("Shortcuts", "Kısayollar") }
    public var tabExcludedApps: String { tr("Ignored", "Yoksayılanlar") }
    public var tabGeneral: String { tr("General", "Genel") }

    public var sectionGapsAndPadding: String { tr("Spacing & Smart Gaps", "Boşluklar") }
    public var innerGapLabel: String { tr("Inner Gap", "İç Boşluk") }
    public var outerPaddingLabel: String { tr("Outer Margin", "Dış Kenar Payı") }
    public var smartGapsToggle: String {
        tr("Smart Gaps (full screen when 1 window is open)", "Akıllı Boşluklar (tek pencerede tam ekran)")
    }
    public var sectionMasterSplit: String { tr("Split Ratio & Left Pane", "Bölme Oranı ve Sol Alan") }
    public var defaultMasterRatioLabel: String { tr("Master Split Ratio", "Ana Bölme Oranı") }
    public var leftPaneCountLabel: String { tr("Windows on Left Side", "Sol Taraftaki Pencere Sayısı") }
    public var addWindowToLeftMenu: String { tr("Add Window to Left (+)", "Sol Tarafa Ekle (+)") }
    public var removeWindowFromLeftMenu: String { tr("Move from Left to Right (-)", "Soldan Sağa Aktar (-)") }
    public var presetRatiosLabel: String { tr("Presets", "Ön Ayarlar") }
    public var liveDividerHint: String {
        tr("Drag the handle between windows or resize any window edge to adjust sizes.", "Pencereler arasındaki tutamacı sürükleyerek veya pencere kenarından çekerek boyutu değiştirebilirsiniz.")
    }

    public var sectionHighlight: String { tr("Active Window Highlight", "Pencere Vurgusu") }
    public var highlightModeLabel: String { tr("Highlight Style", "Vurgu Stili") }
    public var highlightColorLabel: String { tr("Custom Color", "Özel Renk") }
    public var borderWidthLabel: String { tr("Border Thickness", "Kenarlık Kalınlığı") }

    public func highlightModeName(_ mode: HighlightMode) -> String {
        highlightShortName(mode)
    }

    public var sectionBehavior: String { tr("Mouse & Navigation", "Fare ve Gezinme") }
    public var mouseFollowsFocusToggle: String {
        tr("Center cursor on focused window after keyboard swap", "Klavye geçişinde fare imlecini pencereye ortala")
    }
    public var commandDragSwapHint: String {
        tr("Drag any window or use ⌃⌥ + Arrow keys to swap two windows.", "Pencereyi sürükleyerek veya ⌃⌥ + Yön tuşlarıyla iki pencerenin yerini değiştirin.")
    }

    // MARK: - Shortcuts

    public var resetShortcutsButton: String { tr("Reset Defaults", "Varsayılanlara Sıfırla") }
    public var shortcutConflictWarning: String {
        tr("Duplicate shortcut", "Çakışan kısayol")
    }
    public var pressKeysPrompt: String { tr("Press keys...", "Tuşlara basın...") }

    public func shortcutActionName(_ action: ShortcutAction) -> String {
        switch action {
        case .toggleFloatWindow: return tr("Float / Re-tile Active Window", "Aktif Pencereyi Serbest Bırak / Döşe")
        case .toggleIgnoreApp: return tr("Ignore / Include Active App", "Aktif Uygulamayı Hariç Tut / Döşe")
        case .toggleTiling: return tr("Pause / Resume Tiling", "Döşemeyi Duraklat / Sürdür")
        case .cycleStack: return tr("Cycle Stacked Windows", "Yığındaki Pencereleri Döndür")
        case .toggleFocusMode: return tr("Toggle Focus Mode", "Odak Modunu Aç / Kapat")
        case .layoutGrid: return tr("Grid Layout", "Izgara Düzeni")
        case .layoutColumns: return tr("Columns Layout", "Sütunlar Düzeni")
        case .layoutRows: return tr("Rows Layout", "Satırlar Düzeni")
        case .layoutSide: return tr("Side Layout", "Yan Düzen")
        case .swapWindowLeft: return tr("Swap Window Left", "Sol Pencereyle Değiştir")
        case .swapWindowRight: return tr("Swap Window Right", "Sağ Pencereyle Değiştir")
        case .swapWindowUp: return tr("Swap Window Up", "Üst Pencereyle Değiştir")
        case .swapWindowDown: return tr("Swap Window Down", "Alt Pencereyle Değiştir")
        case .moveDisplayLeft: return tr("Move to Left Display", "Sol Monitöre Taşı")
        case .moveDisplayRight: return tr("Move to Right Display", "Sağ Monitöre Taşı")
        case .moveDisplayUp: return tr("Move to Upper Display", "Üst Monitöre Taşı")
        case .moveDisplayDown: return tr("Move to Lower Display", "Alt Monitöre Taşı")
        }
    }

    // MARK: - Ignored Apps

    public var ignoredAppsHeader: String {
        tr("Excluded apps are never automatically tiled.", "Bu listedeki uygulamalar otomatik döşenmez.")
    }
    public var addBundleIDPlaceholder: String { tr("com.apple.Calculator", "com.apple.Calculator") }
    public var addButton: String { tr("Add", "Ekle") }
    public var removeButton: String { tr("Remove", "Kaldır") }

    // MARK: - General

    public var themeLabel: String { tr("Appearance", "Görünüm") }
    public var languageLabel: String { tr("Language", "Dil") }
    public var launchAtLoginToggle: String { tr("Open at Login", "Oturum Açıldığında Başlat") }

    public func themeName(_ option: AppThemeOption) -> String {
        switch option {
        case .system: return tr("System", "Sistem")
        case .light: return tr("Light", "Açık")
        case .dark: return tr("Dark", "Koyu")
        }
    }

    public var sequoiaMarginsWarningTitle: String {
        tr("macOS Native Tiling Margins", "macOS Yerel Kenar Boşlukları")
    }
    public var sequoiaMarginsWarningBody: String {
        tr("Disable 'Tiled windows have margins' in System Settings > Desktop & Dock for exact alignment.", "Tam hizalama için Sistem Ayarları > Masaüstü ve Dock altındaki 'Döşenmiş pencerelerde kenar boşluğu olsun' ayarını kapatın.")
    }
    public var openDesktopAndDockButton: String {
        tr("Open Desktop & Dock", "Masaüstü ve Dock'u Aç")
    }

    // MARK: - Onboarding

    public var onboardingWelcomeTitle: String { tr("Welcome to Vetra", "Vetra'ya Hoş Geldiniz") }
    public var onboardingStep1Title: String { tr("Enable Accessibility", "Erişilebilirlik İznini Etkinleştirin") }
    public var onboardingStep1Body: String {
        tr("Vetra arranges your windows automatically as they open and close. Grant Accessibility access in System Settings to begin.", "Vetra pencereleriniz açılıp kapandıkça onları otomatik olarak yerleştirir. Başlamak için Sistem Ayarları'ndan Erişilebilirlik izni verin.")
    }
    public var grantPermissionButton: String {
        tr("Open Accessibility Settings", "Erişilebilirlik Ayarlarını Aç")
    }
    public var permissionGrantedBadge: String {
        tr("Ready", "Hazır")
    }
    public var permissionWaitingBadge: String {
        tr("Waiting for permission...", "İzin bekleniyor...")
    }
    public var continueToTesseraButton: String {
        tr("Get Started", "Başla")
    }
}
