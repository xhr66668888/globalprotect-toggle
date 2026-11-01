import AppKit

let folder = CommandLine.arguments[1]
guard let logo = NSImage(contentsOfFile: "\(folder)/ou-official.png") else {
    fatalError("Cannot load the official OU monogram")
}

func writePNG(pixels: Int, path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    logo.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot render icon")
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let iconset = "\(folder)/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(pixels: size * scale, path: "\(iconset)/icon_\(size)x\(size)\(suffix).png")
    }
}
try writePNG(pixels: 108, path: "\(folder)/OUMonogram.png")
let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "\(folder)/OUMonogram.png")))!
guard bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0,
      bitmap.colorAt(x: 20, y: 30)!.alphaComponent > 0.9 else {
    throw NSError(domain: "OUIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Logo transparency check failed"])
}
print("Official logo icons rendered with transparency.")
