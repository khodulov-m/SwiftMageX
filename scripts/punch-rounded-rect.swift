#!/usr/bin/env swift
// Run: swift scripts/punch-rounded-rect.swift <input.png> <output.png> <x> <y> <w> <h> [radius]
//
// Punches a transparent rounded-rectangle hole into `input.png` and writes the
// result to `output.png`. Used at vendoring time to convert third-party device
// mockups (which often render the screen as a flat fill on top of the body)
// into bezels with a true transparent screen cutout — the shape SwiftMageX's
// `frameScreenshot` pipeline needs.
//
// The pixels inside the rounded rect get `alpha = 0`; pixels on the rounded
// border are anti-aliased against the existing colour. The rest of the image
// is untouched.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 7 else {
    FileHandle.standardError.write(Data("usage: punch-rounded-rect.swift <input.png> <output.png> <x> <y> <w> <h> [radius]\n".utf8))
    exit(2)
}
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let rectX = Int(CommandLine.arguments[3])!
let rectY = Int(CommandLine.arguments[4])!
let rectW = Int(CommandLine.arguments[5])!
let rectH = Int(CommandLine.arguments[6])!
let radius: Double = CommandLine.arguments.count >= 8 ? (Double(CommandLine.arguments[7]) ?? 0) : 0

guard let image = NSImage(contentsOf: inputURL),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("could not decode input\n".utf8))
    exit(1)
}
let width = cg.width
let height = cg.height
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * height)
let row = ctx.bytesPerRow

/// Signed distance from `(px, py)` (image coordinates, origin top-left) to the
/// rounded-rect's interior. Negative = inside, 0 = on edge, positive = outside.
@inline(__always) func sdRoundedRect(px: Double, py: Double) -> Double {
    let rx0 = Double(rectX), ry0 = Double(rectY)
    let rx1 = Double(rectX + rectW), ry1 = Double(rectY + rectH)
    // Reflect into the lower-right quadrant relative to the rect centre, then
    // measure to the corner circle.
    let halfW = (rx1 - rx0) * 0.5
    let halfH = (ry1 - ry0) * 0.5
    let cx = (rx0 + rx1) * 0.5
    let cy = (ry0 + ry1) * 0.5
    let qx = abs(px - cx) - (halfW - radius)
    let qy = abs(py - cy) - (halfH - radius)
    let outside = max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)
    let inside = min(max(qx, qy), 0)
    return inside + outside.squareRoot() - radius
}

let minY = max(0, rectY - 1)
let maxY = min(height - 1, rectY + rectH + 1)
let minX = max(0, rectX - 1)
let maxX = min(width - 1, rectX + rectW + 1)
for y in minY...maxY {
    for x in minX...maxX {
        // Sample at pixel centre so straight edges align with pixel rows.
        let d = sdRoundedRect(px: Double(x) + 0.5, py: Double(y) + 0.5)
        // Anti-alias the boundary across a 1-pixel band: inside (d ≤ -1) goes
        // fully transparent, outside (d ≥ 0) keeps its original alpha, and
        // pixels straddling the edge get linearly interpolated.
        let coverage: Double
        if d <= -1 { coverage = 1 }
        else if d >= 0 { coverage = 0 }
        else { coverage = -d }
        guard coverage > 0 else { continue }
        let i = y * row + x * 4
        let existing = Double(pixels[i + 3])
        let newAlpha = existing * (1.0 - coverage)
        pixels[i + 3] = UInt8(max(0, min(255, newAlpha.rounded())))
    }
}

guard let outImage = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: outImage)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: outputURL)
print("wrote \(outputURL.path) — punched x=\(rectX) y=\(rectY) w=\(rectW) h=\(rectH) radius=\(radius)")
