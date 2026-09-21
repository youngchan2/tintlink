import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let palette = [0x0A84FF, 0xB8A1FF, 0xFF4FA3, 0xFF453A, 0xFF9F0A, 0xFFCC00, 0x30D158]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let p = CGFloat(pixels)
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84), xRadius: p * 0.20, yRadius: p * 0.20).fill()
        for (index, hex) in palette.enumerated() {
            let angle = Double(index) * Double.pi * 2 / 7 + Double.pi / 2
            let x = p * (0.5 + 0.235 * cos(angle)), y = p * (0.5 + 0.235 * sin(angle))
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - p * 0.076, y: y - p * 0.076, width: p * 0.152, height: p * 0.152)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// ICNS is a container of PNG representations. Generate it here so building the
// app, as well as running it, needs no Python installation.
if CommandLine.arguments.count > 2 {
    func word(_ value: Int) -> Data {
        var big = UInt32(value).bigEndian
        return withUnsafeBytes(of: &big) { Data($0) }
    }
    var records = Data()
    for (kind, name) in [("icp4", "16x16"), ("icp5", "32x32"), ("icp6", "32x32@2x"), ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"), ("ic10", "512x512@2x")] {
        let png = try Data(contentsOf: destination.appendingPathComponent("icon_" + name + ".png"))
        records.append(Data(kind.utf8)); records.append(word(png.count + 8)); records.append(png)
    }
    var icon = Data("icns".utf8)
    icon.append(word(records.count + 8)); icon.append(records)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
