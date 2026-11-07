import AppKit
import CoreGraphics
import Foundation

func drawVetraIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.saveGState()

    // macOS Sonoma/Sequoia standard icon inset (~9.5% margin around 1024 canvas)
    let margin = size * 0.088
    let iconSize = size - margin * 2.0
    let iconRect = CGRect(x: margin, y: margin, width: iconSize, height: iconSize)
    let cornerRadius = iconSize * 0.225

    // Drop shadow under squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.022),
        blur: size * 0.045,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.42).cgColor
    )
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // 1. Deep Obsidian-Sapphire Multi-Stop Background Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(calibratedRed: 0.14, green: 0.19, blue: 0.30, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 1.0).cgColor
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
            options: []
        )
    }

    // 2. Ambient Cyan-Blue Top-Left Radial Glow
    let glowColors = [
        NSColor(calibratedRed: 0.22, green: 0.68, blue: 1.0, alpha: 0.36).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.96, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        let glowCenter = CGPoint(x: iconRect.minX + iconSize * 0.26, y: iconRect.maxY - iconSize * 0.22)
        ctx.drawRadialGradient(
            glowGrad,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: iconSize * 0.72,
            options: []
        )
    }

    // 3. Asymmetric Architectural Window Panes (Vetra Signature Layout)
    let innerPad = iconSize * 0.165
    let gap = iconSize * 0.055
    let contentRect = iconRect.insetBy(dx: innerPad, dy: innerPad)
    let paneCorner = iconSize * 0.068

    let leftWidth = (contentRect.width - gap) * 0.52
    let rightWidth = contentRect.width - gap - leftWidth
    let rightTopHeight = (contentRect.height - gap) * 0.52
    let rightBottomHeight = contentRect.height - gap - rightTopHeight

    let masterRect = CGRect(
        x: contentRect.minX,
        y: contentRect.minY,
        width: leftWidth,
        height: contentRect.height
    )
    let topRightRect = CGRect(
        x: contentRect.minX + leftWidth + gap,
        y: contentRect.minY + rightBottomHeight + gap,
        width: rightWidth,
        height: rightTopHeight
    )
    let bottomRightRect = CGRect(
        x: contentRect.minX + leftWidth + gap,
        y: contentRect.minY,
        width: rightWidth,
        height: rightBottomHeight
    )

    // Helper to draw a 3D glass pane
    func drawPane(rect: CGRect, topColor: NSColor, bottomColor: NSColor, borderAlpha: CGFloat, hasTrafficDots: Bool) {
        let path = CGPath(roundedRect: rect, cornerWidth: paneCorner, cornerHeight: paneCorner, transform: nil)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.015),
            blur: size * 0.032,
            color: NSColor(calibratedWhite: 0, alpha: 0.38).cgColor
        )
        ctx.addPath(path)
        ctx.setFillColor(bottomColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let paneColors = [topColor.cgColor, bottomColor.cgColor] as CFArray
        if let paneGrad = CGGradient(colorsSpace: colorSpace, colors: paneColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                paneGrad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
        }

        // Top glass header strip
        let headerH = rect.height * (hasTrafficDots ? 0.18 : 0.24)
        let headerRect = CGRect(x: rect.minX, y: rect.maxY - headerH, width: rect.width, height: headerH)
        ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: hasTrafficDots ? 0.22 : 0.14).cgColor)
        ctx.fill(headerRect)

        if hasTrafficDots {
            let dotR = max(1.5, size * 0.016)
            let dotY = rect.maxY - headerH * 0.52
            for idx in 0..<2 {
                let dotX = rect.minX + iconSize * 0.048 + CGFloat(idx) * (dotR * 2.8)
                let dotRect = CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)
                ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: idx == 0 ? 0.92 : 0.55).cgColor)
                ctx.fillEllipse(in: dotRect)
            }
        }
        ctx.restoreGState()

        // Specular rim stroke
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: borderAlpha).cgColor)
        ctx.setLineWidth(max(1.0, size * 0.012))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Draw Master Left Pane (Vibrant Azure -> Royal Blue)
    drawPane(
        rect: masterRect,
        topColor: NSColor(calibratedRed: 0.34, green: 0.78, blue: 1.0, alpha: 1.0),
        bottomColor: NSColor(calibratedRed: 0.10, green: 0.46, blue: 0.96, alpha: 1.0),
        borderAlpha: 0.62,
        hasTrafficDots: true
    )

    // Draw Top-Right Pane (Frosted Ice Glass)
    drawPane(
        rect: topRightRect,
        topColor: NSColor(calibratedRed: 0.52, green: 0.84, blue: 1.0, alpha: 0.48),
        bottomColor: NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.95, alpha: 0.32),
        borderAlpha: 0.38,
        hasTrafficDots: false
    )

    // Draw Bottom-Right Pane (Subtle Slate Glass)
    drawPane(
        rect: bottomRightRect,
        topColor: NSColor(calibratedRed: 0.85, green: 0.93, blue: 1.0, alpha: 0.24),
        bottomColor: NSColor(calibratedRed: 0.45, green: 0.65, blue: 0.92, alpha: 0.15),
        borderAlpha: 0.24,
        hasTrafficDots: false
    )

    ctx.restoreGState() // End squircle clip

    // Outer Squircle Specular Rim
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.26).cgColor)
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()
    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, pixelSize: Int, to path: String) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}

let fm = FileManager.default
let assetsDir = "Assets"
let iconsetDir = "\(assetsDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in specs {
    let img = drawVetraIcon(size: CGFloat(spec.pixels))
    try savePNG(image: img, pixelSize: spec.pixels, to: "\(iconsetDir)/\(spec.name)")
}

// Save 256x256 README hero logo
let logoImg = drawVetraIcon(size: 256)
try savePNG(image: logoImg, pixelSize: 256, to: "\(assetsDir)/logo.png")

