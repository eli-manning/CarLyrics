import CoreImage
import UIKit

/// Loads album art and picks a background color from it, darkened enough that
/// white lyrics stay readable on top.
enum ArtworkPalette {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func load(_ url: URL) async -> (image: UIImage, hex: String)? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data), let ci = CIImage(image: image) else { return nil }

        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ])!
        var px = [UInt8](repeating: 0, count: 4)
        context.render(filter.outputImage!, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        let tuned = UIColor(hue: h, saturation: min(s * 1.1, 0.75), brightness: min(max(b, 0.22), 0.38), alpha: 1)

        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
        tuned.getRed(&r, green: &g, blue: &bl, alpha: nil)
        let hex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(bl * 255))
        return (image, hex)
    }
}
