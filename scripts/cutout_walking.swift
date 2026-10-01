import AppKit
import Vision
import CoreImage

let rawPath = "/Users/duynguyen/.gemini/antigravity/brain/3ed3cbb4-1874-4cf7-b791-6111e6620207/robot_walking_side_1790845973373.jpg"
guard let img = NSImage(contentsOfFile: rawPath),
      let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Cannot load raw image")
    exit(1)
}

if #available(macOS 14.0, *) {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
    do {
        try handler.perform([request])
        guard let result = request.results?.first else {
            print("No mask result")
            exit(1)
        }
        
        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        let inputImage = CIImage(cgImage: cgImg)
        
        // Blend input with clear background using mask
        let clearImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: inputImage.extent)
        let filter = CIFilter(name: "CIBlendWithMask")!
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(clearImage, forKey: kCIInputBackgroundImageKey)
        filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
        
        guard let outputCIImage = filter.outputImage else {
            print("Blend filter failed")
            exit(1)
        }
        
        let ciContext = CIContext(options: nil)
        guard let outputCGImage = ciContext.createCGImage(outputCIImage, from: inputImage.extent) else {
            print("Failed to create output CGImage")
            exit(1)
        }
        
        // Find bounding box to crop tightly
        let w = outputCGImage.width
        let h = outputCGImage.height
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: h * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bmContext = CGContext(
            data: &rawData,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        bmContext.draw(outputCGImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                let alpha = rawData[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > 15 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        
        print("Bounding box: x: \(minX)..\(maxX), y: \(minY)..\(maxY)")
        let pad = 8
        // Note: CoreGraphics coordinate origin is bottom-left or top-left depending on context
        // bmContext was created with standard CG, y=0 is bottom
        let cropRect = CGRect(
            x: max(0, minX - pad),
            y: max(0, minY - pad),
            width: min(w - max(0, minX - pad), (maxX - minX) + pad * 2),
            height: min(h - max(0, minY - pad), (maxY - minY) + pad * 2)
        )
        
        guard let croppedCGImage = bmContext.makeImage()?.cropping(to: cropRect) else {
            print("Crop failed")
            exit(1)
        }
        
        let rep = NSBitmapImageRep(cgImage: croppedCGImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            print("PNG representation failed")
            exit(1)
        }
        
        let outPath = "/Users/duynguyen/projects/MacTools/Resources/MascotWalking.png"
        try pngData.write(to: URL(fileURLWithPath: outPath))
        print("SUCCESS! Output written to \(outPath) (\(croppedCGImage.width)x\(croppedCGImage.height))")
        
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}
