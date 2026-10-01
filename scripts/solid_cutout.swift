import AppKit

let rawPath = "/Users/duynguyen/.gemini/antigravity/brain/3ed3cbb4-1874-4cf7-b791-6111e6620207/transtools_mascot_1790755107149.jpg"
guard let img = NSImage(contentsOfFile: rawPath),
      let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Cannot load raw image")
    exit(1)
}

let w = cgImg.width
let h = cgImg.height
let rep = NSBitmapImageRep(cgImage: cgImg)

// Sample corner background color
var bgR = 0.0, bgG = 0.0, bgB = 0.0
let samplePoints = [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1), (w/2, 0), (0, h/2), (w-1, h/2)]
for (sx, sy) in samplePoints {
    if let c = rep.colorAt(x: sx, y: sy) {
        bgR += c.redComponent
        bgG += c.greenComponent
        bgB += c.blueComponent
    }
}
bgR /= Double(samplePoints.count)
bgG /= Double(samplePoints.count)
bgB /= Double(samplePoints.count)

print("Average border BG color: R:\(bgR), G:\(bgG), B:\(bgB)")

// Flood fill from all 4 borders
var isBg = [Bool](repeating: false, count: w * h)
var queue = [(Int, Int)]()
queue.reserveCapacity(w * 4)

for x in 0..<w {
    queue.append((x, 0))
    queue.append((x, h - 1))
    isBg[0 * w + x] = true
    isBg[(h - 1) * w + x] = true
}
for y in 1..<(h - 1) {
    queue.append((0, y))
    queue.append((w - 1, y))
    isBg[y * w + 0] = true
    isBg[y * w + (w - 1)] = true
}

// Background threshold
// The studio background has a slight gradient, max distance from border sample is ~0.08
let threshold = 0.075

var head = 0
while head < queue.count {
    let (cx, cy) = queue[head]
    head += 1
    
    let neighbors = [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)]
    for (nx, ny) in neighbors {
        guard nx >= 0 && nx < w && ny >= 0 && ny < h else { continue }
        let idx = ny * w + nx
        if !isBg[idx] {
            if let c = rep.colorAt(x: nx, y: ny) {
                // Background gradient estimation based on Y
                let t = Double(ny) / Double(h)
                let localBgR = 0.855 * (1.0 - t) + 0.925 * t
                let localBgG = 0.855 * (1.0 - t) + 0.910 * t
                let localBgB = 0.840 * (1.0 - t) + 0.898 * t
                
                let dr = c.redComponent - localBgR
                let dg = c.greenComponent - localBgG
                let db = c.blueComponent - localBgB
                let dist = sqrt(dr*dr + dg*dg + db*db)
                
                if dist < threshold {
                    isBg[idx] = true
                    queue.append((nx, ny))
                }
            }
        }
    }
}

print("Flood filled \(queue.count) background pixels out of \(w * h)")

// Create output image: where !isBg, alpha = 1.0 (SOLID OPAQUE!)
guard let outRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: w,
                                    pixelsHigh: h,
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bytesPerRow: w * 4,
                                    bitsPerPixel: 32) else {
    exit(1)
}

var minX = w, maxX = 0, minY = h, maxY = 0

for y in 0..<h {
    for x in 0..<w {
        let idx = y * w + x
        if isBg[idx] {
            // Transparent background
            outRep.setColor(NSColor.clear, atX: x, y: y)
        } else {
            // Anti-aliased edge or 100% SOLID interior
            if let c = rep.colorAt(x: x, y: y) {
                // Check if any neighbor is background to anti-alias the single boundary pixel
                var bgNeighborCount = 0
                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0 && nx < w && ny >= 0 && ny < h && isBg[ny * w + nx] {
                        bgNeighborCount += 1
                    }
                }
                let alpha: Double = (bgNeighborCount > 0) ? (1.0 - Double(bgNeighborCount) * 0.18) : 1.0
                let col = NSColor(deviceRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: alpha)
                outRep.setColor(col, atX: x, y: y)
                
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
}

print("Bounds: X: \(minX)...\(maxX), Y: \(minY)...\(maxY), Width: \(maxX - minX), Height: \(maxY - minY)")

// Crop with padding
let pad = 16
let cropX = max(0, minX - pad)
let cropY = max(0, minY - pad)
let cropW = min(w - cropX, (maxX - minX) + pad * 2)
let cropH = min(h - cropY, (maxY - minY) + pad * 2)

guard let croppedRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: cropW,
                                       pixelsHigh: cropH,
                                       bitsPerSample: 8,
                                       samplesPerPixel: 4,
                                       hasAlpha: true,
                                       isPlanar: false,
                                       colorSpaceName: .deviceRGB,
                                       bytesPerRow: cropW * 4,
                                       bitsPerPixel: 32) else {
    exit(1)
}

for y in 0..<cropH {
    for x in 0..<cropW {
        if let c = outRep.colorAt(x: cropX + x, y: cropY + y) {
            croppedRep.setColor(c, atX: x, y: y)
        }
    }
}

if let pngData = croppedRep.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "Resources/Mascot3D.png"))
    print("SUCCESS: Generated 100% SOLID opaque Mascot3D.png (\(cropW)x\(cropH))!")
}
