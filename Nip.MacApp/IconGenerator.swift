import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let backgroundTop = NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.15, alpha: 1.0)
private let backgroundBottom = NSColor(calibratedRed: 0.01, green: 0.04, blue: 0.07, alpha: 1.0)
private let gold = NSColor(calibratedRed: 0.86, green: 0.73, blue: 0.43, alpha: 1.0)
private let goldDim = NSColor(calibratedRed: 0.62, green: 0.50, blue: 0.27, alpha: 1.0)
private let goldSoft = NSColor(calibratedRed: 0.95, green: 0.88, blue: 0.67, alpha: 0.92)

private func drawLine(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.move(to: start)
    path.line(to: end)
    color.setStroke()
    path.stroke()
}

private func drawDiamond(center: NSPoint, radius: CGFloat, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: center.x, y: center.y + radius))
    path.line(to: NSPoint(x: center.x + radius, y: center.y))
    path.line(to: NSPoint(x: center.x, y: center.y - radius))
    path.line(to: NSPoint(x: center.x - radius, y: center.y))
    path.close()
    color.setStroke()
    path.stroke()
}

private func drawCornerMotif(in rect: NSRect, size: CGFloat, flipX: Bool, flipY: Bool) {
    let corner = NSPoint(
        x: flipX ? rect.maxX : rect.minX,
        y: flipY ? rect.maxY : rect.minY
    )
    let dx: CGFloat = flipX ? -1 : 1
    let dy: CGFloat = flipY ? -1 : 1
    let step = size * 0.055
    let lineWidth = max(2.0, size * 0.012)

    for index in 0..<3 {
        let offset = CGFloat(index) * step * 0.44
        let start1 = NSPoint(x: corner.x + dx * offset, y: corner.y + dy * step)
        let end1 = NSPoint(x: corner.x + dx * step, y: corner.y + dy * step)
        let end2 = NSPoint(x: corner.x + dx * step, y: corner.y + dy * offset)
        drawLine(from: start1, to: end1, width: lineWidth, color: gold)
        drawLine(from: end1, to: end2, width: lineWidth, color: gold)
    }
}

private func drawSunburst(center: NSPoint, size: CGFloat) {
    let baseY = center.y + size * 0.15
    let topY = center.y + size * 0.30
    let widths = [0.0, 0.05, -0.05, 0.10, -0.10]
    let lineWidth = max(2.0, size * 0.010)

    for factor in widths {
        let x1 = center.x + size * factor * 0.28
        let x2 = center.x + size * factor * 0.62
        drawLine(
            from: NSPoint(x: x1, y: baseY),
            to: NSPoint(x: x2, y: topY),
            width: lineWidth,
            color: goldSoft
        )
        drawLine(
            from: NSPoint(x: x1, y: center.y - (baseY - center.y)),
            to: NSPoint(x: x2, y: center.y - (topY - center.y)),
            width: lineWidth,
            color: goldSoft
        )
    }
}

private func makeBitmap(size: CGFloat) -> NSBitmapImageRep? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    guard let context = NSGraphicsContext.current else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }

    context.cgContext.interpolationQuality = .high
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    let clipPath = NSBezierPath(roundedRect: bounds, xRadius: size * 0.22, yRadius: size * 0.22)
    clipPath.addClip()

    let gradient = NSGradient(starting: backgroundTop, ending: backgroundBottom)
    gradient?.draw(in: bounds, angle: -90)

    NSColor(calibratedWhite: 1.0, alpha: 0.04).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.18, y: size * 0.60, width: size * 0.64, height: size * 0.26)).fill()

    let outerRect = bounds.insetBy(dx: size * 0.10, dy: size * 0.10)
    let innerRect = bounds.insetBy(dx: size * 0.17, dy: size * 0.17)

    let outerFrame = NSBezierPath(roundedRect: outerRect, xRadius: size * 0.12, yRadius: size * 0.12)
    outerFrame.lineWidth = max(4.0, size * 0.016)
    gold.setStroke()
    outerFrame.stroke()

    let innerFrame = NSBezierPath(roundedRect: innerRect, xRadius: size * 0.08, yRadius: size * 0.08)
    innerFrame.lineWidth = max(2.0, size * 0.008)
    goldDim.setStroke()
    innerFrame.stroke()

    drawCornerMotif(in: outerRect, size: size, flipX: false, flipY: false)
    drawCornerMotif(in: outerRect, size: size, flipX: true, flipY: false)
    drawCornerMotif(in: outerRect, size: size, flipX: false, flipY: true)
    drawCornerMotif(in: outerRect, size: size, flipX: true, flipY: true)

    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    drawSunburst(center: center, size: size)

    let lineWidth = max(2.0, size * 0.010)
    drawLine(
        from: NSPoint(x: center.x, y: innerRect.maxY - size * 0.09),
        to: NSPoint(x: center.x, y: center.y + size * 0.20),
        width: lineWidth,
        color: goldSoft
    )
    drawLine(
        from: NSPoint(x: center.x, y: innerRect.minY + size * 0.09),
        to: NSPoint(x: center.x, y: center.y - size * 0.20),
        width: lineWidth,
        color: goldSoft
    )
    drawLine(
        from: NSPoint(x: center.x - size * 0.18, y: center.y),
        to: NSPoint(x: center.x + size * 0.18, y: center.y),
        width: lineWidth,
        color: goldSoft
    )

    drawDiamond(center: center, radius: size * 0.20, width: max(5.0, size * 0.016), color: gold)
    drawDiamond(center: center, radius: size * 0.145, width: max(3.0, size * 0.010), color: goldSoft)
    drawDiamond(center: center, radius: size * 0.090, width: max(2.0, size * 0.007), color: goldDim)

    let nodeRadius = size * 0.024
    goldSoft.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - nodeRadius,
        y: center.y - nodeRadius,
        width: nodeRadius * 2,
        height: nodeRadius * 2
    )).fill()

    NSGraphicsContext.restoreGraphicsState()

    return bitmap
}

private let iconEntries: [(String, CGFloat)] = [
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

private func writeIconset(to outputDirectory: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: outputDirectory.path) {
        try fileManager.removeItem(at: outputDirectory)
    }
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for (filename, size) in iconEntries {
        guard
            let bitmap = makeBitmap(size: size),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(filename)"])
        }
        try pngData.write(to: outputDirectory.appendingPathComponent(filename))
    }
}

private func writeICNS(to outputURL: URL) throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }

    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.icns.identifier as CFString,
        iconEntries.count,
        nil
    ) else {
        throw NSError(domain: "IconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create ICNS destination"])
    }

    for (_, size) in iconEntries {
        guard
            let bitmap = makeBitmap(size: size),
            let image = bitmap.cgImage
        else {
            throw NSError(domain: "IconGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not render ICNS frame \(Int(size))"])
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyPixelWidth: Int(size),
            kCGImagePropertyPixelHeight: Int(size)
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IconGenerator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not finalize ICNS file"])
    }
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/Nip.MacApp/AppIcon.iconset"

let icnsPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : FileManager.default.currentDirectoryPath + "/Nip.MacApp/AppIcon.icns"

do {
    try writeIconset(to: URL(fileURLWithPath: outputPath, isDirectory: true))
    try writeICNS(to: URL(fileURLWithPath: icnsPath))
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
