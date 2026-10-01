import AppKit

let path = "Resources/MascotSleeping.png"
guard let img = NSImage(contentsOfFile: path),
      let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Cannot load image")
    exit(1)
}

let w = cgImg.width
let h = cgImg.height
let rep = NSBitmapImageRep(cgImage: cgImg)

var alpha = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)
var r = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)
var g = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)
var b = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)

for y in 0..<h {
    for x in 0..<w {
        if let c = rep.colorAt(x: x, y: y) {
            alpha[y][x] = c.alphaComponent
            r[y][x] = c.redComponent
            g[y][x] = c.greenComponent
            b[y][x] = c.blueComponent
        }
    }
}

// 1. Remove faint noise pixels (alpha < 0.12)
var cleanedAlpha = alpha
var faintCount = 0
for y in 0..<h {
    for x in 0..<w {
        if cleanedAlpha[y][x] < 0.12 {
            if cleanedAlpha[y][x] > 0 {
                faintCount += 1
            }
            cleanedAlpha[y][x] = 0.0
        }
    }
}
print("Removed faint noise pixels: \(faintCount)")

// 2. Remove isolated specks (connected component of non-zero alpha with small area < 40 pixels)
var visited = [[Bool]](repeating: [Bool](repeating: false, count: w), count: h)
var removedComponents = 0
var removedPixels = 0

for y in 0..<h {
    for x in 0..<w {
        if cleanedAlpha[y][x] > 0.05 && !visited[y][x] {
            var component = [(Int, Int)]()
            var queue = [(x, y)]
            visited[y][x] = true
            
            var head = 0
            while head < queue.count {
                let (cx, cy) = queue[head]
                head += 1
                component.append((cx, cy))
                
                let neighbors = [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1), (cx+1, cy+1), (cx-1, cy-1), (cx+1, cy-1), (cx-1, cy+1)]
                for (nx, ny) in neighbors {
                    if nx >= 0 && nx < w && ny >= 0 && ny < h && !visited[ny][nx] && cleanedAlpha[ny][nx] > 0.05 {
                        visited[ny][nx] = true
                        queue.append((nx, ny))
                    }
                }
            }
            
            // If component is small (isolated speckle/dot), clear it
            if component.count < 35 {
                removedComponents += 1
                removedPixels += component.count
                for (px, py) in component {
                    cleanedAlpha[py][px] = 0.0
                }
            }
        }
    }
}
print("Removed \(removedComponents) isolated speckles totaling \(removedPixels) pixels")

// Write back to a new NSBitmapImageRep
guard let outRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: w,
    pixelsHigh: h,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: w * 4,
    bitsPerPixel: 32
) else {
    print("Cannot create output rep")
    exit(1)
}

for y in 0..<h {
    for x in 0..<w {
        let a = cleanedAlpha[y][x]
        let red = r[y][x]
        let green = g[y][x]
        let blue = b[y][x]
        let col = NSColor(deviceRed: red, green: green, blue: blue, alpha: a)
        outRep.setColor(col, atX: x, y: y)
    }
}

if let pngData = outRep.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "Resources/MascotSleeping.png"))
    print("Successfully saved denoised Resources/MascotSleeping.png")
}
