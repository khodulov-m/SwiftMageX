#!/usr/bin/env swift
// Run: swift scripts/detect-screen-rect.swift path/to/bezel.png
//
// Prints the bounding box of the largest enclosed transparent region in
// `bezel.png`, suitable for embedding into `Resources/Frames/frames.json`'s
// `screenRect`. Picks the largest connected transparent component that does
// NOT touch the image border — robust to anti-aliased bezels and to small
// extra cutouts (camera notch, speaker grille) that would defeat the simple
// flood-fill auto-detector.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: detect-screen-rect.swift <bezel.png> [alphaThreshold]\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let cliThreshold = CommandLine.arguments.count >= 3 ? Int(CommandLine.arguments[2]) : nil
guard let image = NSImage(contentsOf: url),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("could not decode image\n".utf8))
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
let threshold: UInt8 = UInt8(max(1, min(255, cliThreshold ?? 16)))
FileHandle.standardError.write(Data("alpha threshold: \(threshold)\n".utf8))

@inline(__always) func transparent(_ x: Int, _ y: Int) -> Bool {
    pixels[y * row + x * 4 + 3] < threshold
}

var label = [Int](repeating: 0, count: width * height)
var nextID = 0
var components: [(id: Int, count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int, touchesBorder: Bool)] = []

for startY in 0..<height {
    for startX in 0..<width where label[startY * width + startX] == 0 && transparent(startX, startY) {
        nextID += 1
        var minX = startX, minY = startY, maxX = startX, maxY = startY
        var count = 0
        var touchesBorder = false
        var stack: [(Int, Int)] = [(startX, startY)]
        label[startY * width + startX] = nextID
        while let (x, y) = stack.popLast() {
            count += 1
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
            if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesBorder = true }
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let idx = ny * width + nx
                if label[idx] == 0 && transparent(nx, ny) {
                    label[idx] = nextID
                    stack.append((nx, ny))
                }
            }
        }
        components.append((nextID, count, minX, minY, maxX, maxY, touchesBorder))
    }
}

let enclosed = components.filter { !$0.touchesBorder }
guard let biggest = enclosed.max(by: { $0.count < $1.count }) else {
    FileHandle.standardError.write(Data("no enclosed transparent regions found\n".utf8))
    exit(1)
}
let w = biggest.maxX - biggest.minX + 1
let h = biggest.maxY - biggest.minY + 1
print("image: \(width)x\(height)")
print("screenRect (top-left origin): x=\(biggest.minX), y=\(biggest.minY), width=\(w), height=\(h)")
print("frames.json snippet:")
print("  \"screenRect\": { \"x\": \(biggest.minX), \"y\": \(biggest.minY), \"width\": \(w), \"height\": \(h) }")
