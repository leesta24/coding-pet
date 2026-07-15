#!/usr/bin/env swift

import AppKit
import Foundation

let canvasSize = NSSize(width: 660, height: 420)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: render-dmg-background.swift OUTPUT.png\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Could not create DMG background canvas\n".utf8))
    exit(1)
}
bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(origin: .zero, size: canvasSize)
NSGradient(colors: [
    NSColor(calibratedRed: 0.965, green: 0.978, blue: 0.992, alpha: 1),
    NSColor(calibratedRed: 0.985, green: 0.989, blue: 0.996, alpha: 1)
])?.draw(in: canvas, angle: 90)

func drawGlow(in rect: NSRect, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: rect).addClip()
    NSGradient(
        starting: color.withAlphaComponent(0.16),
        ending: color.withAlphaComponent(0)
    )?.draw(in: rect, relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()
}

drawGlow(
    in: NSRect(x: -90, y: 210, width: 330, height: 330),
    color: NSColor(calibratedRed: 0.18, green: 0.75, blue: 0.58, alpha: 1)
)
drawGlow(
    in: NSRect(x: 440, y: 170, width: 330, height: 330),
    color: NSColor(calibratedRed: 0.19, green: 0.55, blue: 0.96, alpha: 1)
)

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

NSString(string: "Install CodingPet").draw(
    in: NSRect(x: 70, y: 344, width: 520, height: 34),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 25, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.11, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)

NSString(string: "Drag your companion into Applications").draw(
    in: NSRect(x: 70, y: 316, width: 520, height: 22),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.36, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)

let arrowPlate = NSBezierPath(
    roundedRect: NSRect(x: 276, y: 172, width: 108, height: 46),
    xRadius: 23,
    yRadius: 23
)
NSColor.white.withAlphaComponent(0.72).setFill()
arrowPlate.fill()
NSColor(calibratedWhite: 0.12, alpha: 0.06).setStroke()
arrowPlate.lineWidth = 1
arrowPlate.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 300, y: 195))
arrow.line(to: NSPoint(x: 356, y: 195))
arrow.move(to: NSPoint(x: 344, y: 184))
arrow.line(to: NSPoint(x: 356, y: 195))
arrow.line(to: NSPoint(x: 344, y: 206))
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.lineWidth = 3.2
NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.94, alpha: 0.88).setStroke()
arrow.stroke()

NSString(string: "Copy once. CodingPet stays quietly on your desktop.").draw(
    in: NSRect(x: 90, y: 34, width: 480, height: 18),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not render DMG background\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
