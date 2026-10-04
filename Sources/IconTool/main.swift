// Renders AppIcon.iconset PNGs from QIcon. Usage: IconTool <output .iconset dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        let png = QIcon.appIcon(px: pt * scale).representation(using: .png, properties: [:])!
        try png.write(to: out.appendingPathComponent(name))
    }
}
