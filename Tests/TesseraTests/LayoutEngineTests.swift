import Testing
import Foundation
import CoreGraphics
@testable import Tessera

@Suite("LayoutEngine Pure Geometry & Constraint Tests")
struct LayoutEngineTests {
    let engine = LayoutEngine()

    let standardScreen = ScreenBounds(
        displayID: 1,
        visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),
        fullFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )

    let ultrawideScreen = ScreenBounds(
        displayID: 2,
        visibleFrame: CGRect(x: 0, y: 25, width: 3440, height: 1415),
        fullFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440)
    )

    let portraitScreen = ScreenBounds(
        displayID: 3,
        visibleFrame: CGRect(x: 0, y: 25, width: 1080, height: 1895),
        fullFrame: CGRect(x: 0, y: 0, width: 1080, height: 1920)
    )

    private func makeWindows(count: Int, minSize: CGSize = .zero) -> [LayoutWindowInput] {
        (0..<count).map { idx in
            LayoutWindowInput(
                id: "win-\(idx)",
                pid: Int32(100 + idx),
                bundleIdentifier: "com.example.app\(idx)",
                minimumSize: minSize,
                currentFrame: CGRect(x: 100, y: 100, width: 800, height: 600)
            )
        }
    }

    @Test("Smart Gaps removes outer padding and inner gap when single window is tiled")
    func smartGapsSingleWindow() {
        let windows = makeWindows(count: 1)
        let configSmart = LayoutConfiguration(
            layout: .side,
            innerGap: 12,
            outerPadding: 16,
            masterRatio: 0.5,
            smartGaps: true
        )

        let outputSmart = engine.calculateLayout(windows: windows, screen: standardScreen, config: configSmart)
        #expect(outputSmart.placements.count == 1)
        #expect(outputSmart.placements[0].targetFrame == standardScreen.visibleFrame)

        let configFixed = LayoutConfiguration(
            layout: .side,
            innerGap: 12,
            outerPadding: 16,
            masterRatio: 0.5,
            smartGaps: false
        )
        let outputFixed = engine.calculateLayout(windows: windows, screen: standardScreen, config: configFixed)
        let expectedInset = standardScreen.visibleFrame.insetBy(dx: 16, dy: 16)
        #expect(outputFixed.placements[0].targetFrame == expectedInset)
    }

    @Test("Side layout on Landscape places Master on Left and stack on Right")
    func sideLayoutLandscape() {
        let windows = makeWindows(count: 3)
        let config = LayoutConfiguration(
            layout: .side,
            innerGap: 10,
            outerPadding: 10,
            masterRatio: 0.60,
            smartGaps: false
        )

        let output = engine.calculateLayout(windows: windows, screen: standardScreen, config: config)
        #expect(output.tileFrames.count == 3)
        #expect(output.dividers.count == 2)
        #expect(output.dividers[0].axis == .vertical)
        #expect(output.dividers[0].role == .primary)
        #expect(output.dividers[1].axis == .horizontal)
        #expect(output.dividers[1].role == .rightSecondary)

        let master = output.tileFrames[0]
        let rightTop = output.tileFrames[1]
        let rightBottom = output.tileFrames[2]

        #expect(master.minX == 10)
        #expect(rightTop.minX > master.maxX)
        #expect(rightTop.minX == rightBottom.minX)
        #expect(rightBottom.minY > rightTop.maxY)
        #expect(master.height == 1035)
    }

    @Test("Side layout supports multiple windows on the Left side when leftPaneCount > 1")
    func sideLayoutMultipleLeftWindows() {
        let windows = makeWindows(count: 3)
        let config = LayoutConfiguration(
            layout: .side,
            innerGap: 10,
            outerPadding: 10,
            masterRatio: 0.50,
            leftSplitRatio: 0.60,
            secondaryRatio: 0.50,
            leftPaneCount: 2,
            smartGaps: false
        )

        let output = engine.calculateLayout(windows: windows, screen: standardScreen, config: config)
        #expect(output.tileFrames.count == 3)
        #expect(output.dividers.count == 2)

        let leftTop = output.tileFrames[0]
        let leftBottom = output.tileFrames[1]
        let rightFull = output.tileFrames[2]

        // Both leftTop and leftBottom are in the left column
        #expect(leftTop.minX == leftBottom.minX)
        #expect(leftBottom.minY > leftTop.maxY)
        #expect(leftTop.height > leftBottom.height)
        // Right window spans full height on the right side
        #expect(rightFull.minX > leftTop.maxX)
        #expect(rightFull.height == 1035)
    }

    @Test("Side layout on Portrait monitor places Master at Top and secondary windows at Bottom in columns")
    func sideLayoutPortrait() {
        #expect(portraitScreen.isPortrait == true)
        let windows = makeWindows(count: 3)
        let config = LayoutConfiguration(
            layout: .side,
            innerGap: 10,
            outerPadding: 10,
            masterRatio: 0.50,
            smartGaps: false
        )

        let output = engine.calculateLayout(windows: windows, screen: portraitScreen, config: config)
        #expect(output.tileFrames.count == 3)
        #expect(output.dividers.count == 2)
        #expect(output.dividers[0].axis == .horizontal)
        #expect(output.dividers[1].axis == .vertical)

        let masterTop = output.tileFrames[0]
        let bottomLeft = output.tileFrames[1]
        let bottomRight = output.tileFrames[2]

        // Master spans full usable width at the top
        #expect(masterTop.width == portraitScreen.visibleFrame.width - 20)
        // Secondary windows are below master and arranged in columns
        #expect(bottomLeft.minY > masterTop.maxY)
        #expect(bottomRight.minY == bottomLeft.minY)
        #expect(bottomRight.minX > bottomLeft.maxX)
    }

    @Test("Grid, Columns, and Rows layouts produce non-overlapping tiles for 4 windows")
    func allLayoutsFourWindows() {
        let windows = makeWindows(count: 4)
        for layoutKind in TileLayoutKind.allCases {
            let config = LayoutConfiguration(
                layout: layoutKind,
                innerGap: 8,
                outerPadding: 8,
                masterRatio: 0.5,
                smartGaps: false
            )
            let output = engine.calculateLayout(windows: windows, screen: standardScreen, config: config)
            #expect(output.tileFrames.count == 4)

            // Verify no two tile frames intersect
            for i in 0..<output.tileFrames.count {
                for j in (i + 1)..<output.tileFrames.count {
                    #expect(!output.tileFrames[i].intersects(output.tileFrames[j]))
                }
            }
        }
    }

    @Test("Ultrawide screen supports up to 5 distinct tiles while standard screen caps at 4")
    func ultrawideCapacityVsStandard() {
        #expect(standardScreen.isUltrawide == false)
        #expect(standardScreen.maxTileCapacity == 4)
        #expect(ultrawideScreen.isUltrawide == true)
        #expect(ultrawideScreen.maxTileCapacity == 5)

        let fiveWindows = makeWindows(count: 5)
        let config = LayoutConfiguration(layout: .columns, innerGap: 10, outerPadding: 10, masterRatio: 0.5)

        let stdOutput = engine.calculateLayout(windows: fiveWindows, screen: standardScreen, config: config)
        #expect(stdOutput.tileFrames.count == 4)
        #expect(stdOutput.stackBadges.count == 1)

        let uwOutput = engine.calculateLayout(windows: fiveWindows, screen: ultrawideScreen, config: config)
        #expect(uwOutput.tileFrames.count == 5)
        #expect(uwOutput.stackBadges.isEmpty)
    }

    @Test("Overflow stacking places extra windows onto activeTileIndex and cycles top of stack")
    func overflowStackingAndCycling() {
        let sixWindows = makeWindows(count: 6)
        let config0 = LayoutConfiguration(
            layout: .grid,
            innerGap: 10,
            outerPadding: 10,
            masterRatio: 0.5,
            smartGaps: true,
            activeTileIndex: 2,
            activeStackOffset: 0
        )

        let out0 = engine.calculateLayout(windows: sixWindows, screen: standardScreen, config: config0)
        #expect(out0.tileFrames.count == 4)
        #expect(out0.stackBadges.count == 1)

        let badge0 = out0.stackBadges[0]
        #expect(badge0.tileIndex == 2)
        #expect(badge0.totalCount == 3) // win-2, win-4, win-5
        #expect(badge0.activeOneBasedIndex == 1)
        #expect(badge0.badgeText == "[1/3]")
        #expect(badge0.windowIDs == ["win-2", "win-4", "win-5"])

        // Cycle stack offset to 1
        var config1 = config0
        config1.activeStackOffset = 1
        let out1 = engine.calculateLayout(windows: sixWindows, screen: standardScreen, config: config1)
        let badge1 = out1.stackBadges[0]
        #expect(badge1.activeOneBasedIndex == 2)
        #expect(badge1.badgeText == "[2/3]")

        // Verify win-4 is now top of stack
        let win4Placement = out1.placements.first { $0.id == "win-4" }
        #expect(win4Placement?.mode == .tiled(tileIndex: 2, stackPosition: 1, stackCount: 3, isTopOfStack: true))
    }

    @Test("Minimum Size Resolution shifts divider dynamically when window requires wider slot")
    func minimumSizeShiftsDivider() {
        let w0 = LayoutWindowInput(id: "w0", pid: 1, bundleIdentifier: "app.0", minimumSize: CGSize(width: 1200, height: 400))
        let w1 = LayoutWindowInput(id: "w1", pid: 2, bundleIdentifier: "app.1", minimumSize: CGSize(width: 400, height: 400))

        let config = LayoutConfiguration(layout: .side, innerGap: 10, outerPadding: 10, masterRatio: 0.50, smartGaps: false)
        let output = engine.calculateLayout(windows: [w0, w1], screen: standardScreen, config: config)

        #expect(output.placements.count == 2)
        #expect(!output.placements[0].isFloating)
        #expect(!output.placements[1].isFloating)
        #expect(output.effectiveMasterRatio > 0.60)
        #expect(output.placements[0].targetFrame.width >= 1200)
    }

    @Test("Conflicting minimum sizes mark the offending window as floating and reflow remaining")
    func minimumSizeFloatingFallback() {
        // Two windows each demanding 1300px width on a 1920px wide screen cannot both tile side by side
        let w0 = LayoutWindowInput(id: "w0", pid: 1, bundleIdentifier: "app.0", minimumSize: CGSize(width: 800, height: 400))
        let w1 = LayoutWindowInput(id: "w1", pid: 2, bundleIdentifier: "app.1", minimumSize: CGSize(width: 1500, height: 400))

        let config = LayoutConfiguration(layout: .columns, innerGap: 10, outerPadding: 10, masterRatio: 0.50, smartGaps: true)
        let output = engine.calculateLayout(windows: [w0, w1], screen: standardScreen, config: config)

        let p0 = output.placements.first { $0.id == "w0" }!
        let p1 = output.placements.first { $0.id == "w1" }!

        // w1 has larger overflow so w1 floats, while w0 reflows to fill the screen
        #expect(p1.isFloating == true)
        #expect(p0.isFloating == false)
        #expect(p0.targetFrame == standardScreen.visibleFrame)
    }

    @Test("WindowFilter excludes PiP, dialogs, sheets, non-resizable, and ignored bundle windows")
    func windowFilterExclusions() {
        let ignored: Set<String> = ["com.ignored.app"]

        let normalWindow = FilterableWindowProperties(bundleIdentifier: "com.apple.Safari")
        #expect(WindowFilter.shouldTile(properties: normalWindow, ignoredBundles: ignored) == true)

        let pipSubrole = FilterableWindowProperties(bundleIdentifier: "com.apple.Safari", subrole: "AXFloatingWindow")
        #expect(WindowFilter.shouldTile(properties: pipSubrole, ignoredBundles: ignored) == false)

        let pipTitle = FilterableWindowProperties(bundleIdentifier: "com.apple.Safari", title: "Picture in Picture")
        #expect(WindowFilter.shouldTile(properties: pipTitle, ignoredBundles: ignored) == false)

        let dialogWindow = FilterableWindowProperties(bundleIdentifier: "com.apple.Finder", subrole: "AXDialog")
        #expect(WindowFilter.shouldTile(properties: dialogWindow, ignoredBundles: ignored) == false)

        let missingButtons = FilterableWindowProperties(bundleIdentifier: "com.apple.Finder", hasMinimizeButton: false, hasZoomButton: false)
        #expect(WindowFilter.shouldTile(properties: missingButtons, ignoredBundles: ignored) == false)

        let ignoredApp = FilterableWindowProperties(bundleIdentifier: "com.ignored.app")
        #expect(WindowFilter.shouldTile(properties: ignoredApp, ignoredBundles: ignored) == false)
    }

    @Test("ScreenManager coordinate conversion between AppKit Bottom-Left and AX Top-Left is symmetric")
    func coordinateSpaceConversion() {
        let primaryH: CGFloat = 1080
        let appKitRect = CGRect(x: 100, y: 200, width: 600, height: 400)
        let axRect = ScreenManager.appKitRectToAX(appKitRect, primaryScreenHeight: primaryH)

        // Expected AX Y = 1080 - 200 - 400 = 480
        #expect(axRect.origin.x == 100)
        #expect(axRect.origin.y == 480)
        #expect(axRect.size.width == 600)
        #expect(axRect.size.height == 400)

        let roundTrip = ScreenManager.axRectToAppKit(axRect, primaryScreenHeight: primaryH)
        #expect(roundTrip == appKitRect)
    }

    @Test("SettingsStore detects shortcut conflicts and persists per-display states")
    @MainActor
    func settingsConflictAndDisplayPersistence() {
        let suiteName = "com.tessera.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: testDefaults)
        #expect(store.conflictingActions(for: .toggleTiling).isEmpty)

        // Force a duplicate binding
        store.keyBindings[.cycleStack] = store.keyBindings[.toggleTiling]
        let conflicts = store.conflictingActions(for: .toggleTiling)
        #expect(conflicts.contains(.cycleStack))

        store.setLayout(.grid, for: 42)
        store.setMasterRatio(0.66, for: 42)
        let state = store.state(for: 42)
        #expect(state.layout == .grid)
        #expect(abs(state.masterRatio - 0.66) < 0.001)
    }
}
