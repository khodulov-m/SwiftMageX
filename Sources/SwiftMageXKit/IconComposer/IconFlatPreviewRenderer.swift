import CoreGraphics
import Foundation

/// Renders the background canvas for the flat (non-Liquid-Glass) preview of
/// a composed icon. The preview approximates stacking only — glass,
/// refraction, and the squircle mask are the system renderer's job.
enum IconFlatPreviewRenderer {
    /// A square canvas filled with the icon background: a flat color for
    /// ``IconFill/solid(_:)``, or a vertical two-stop gradient (lightened at
    /// the top) approximating ``IconFill/automaticGradient(_:)``.
    static func canvas(fill: IconFill, sizePx: Int) throws -> RasterImage {
        guard sizePx > 0 else {
            throw SwiftMageXError.invalidInput("preview size must be positive (got \(sizePx))")
        }
        guard let color = CoreImageRasterEngine.parseHexColor(fill.hex),
              let components = color.components,
              components.count == 4 else {
            throw SwiftMageXError.invalidInput(
                "malformed color '\(fill.hex)'; use #RRGGBB or #RRGGBBAA"
            )
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: sizePx,
            height: sizePx,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SwiftMageXError.raster("unable to create bitmap context")
        }
        let bounds = CGRect(x: 0, y: 0, width: sizePx, height: sizePx)

        switch fill {
        case .solid:
            context.setFillColor(color)
            context.fill(bounds)
        case .automaticGradient:
            // Approximate the system gradient: base color at the bottom,
            // the same color blended 25% toward white at the top.
            let lightened = components.enumerated().map { index, value in
                index < 3 ? value + (1 - value) * 0.25 : value
            }
            guard let gradient = CGGradient(
                colorSpace: colorSpace,
                colorComponents: lightened + components,
                locations: [0, 1],
                count: 2
            ) else {
                throw SwiftMageXError.raster("unable to create gradient")
            }
            // CoreGraphics is y-up: location 0 is drawn at the top edge here.
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(sizePx)),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        guard let output = context.makeImage() else {
            throw SwiftMageXError.raster("preview canvas rendering failed")
        }
        return RasterImage(cgImage: output)
    }
}
