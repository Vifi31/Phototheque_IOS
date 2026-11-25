import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import PhotothequeCore

/// Un fichier à produire, préparé sur le fil principal (le catalogue n'est pas partagé entre fils).
struct ExportItem: Sendable {
    var source: URL
    var dest: URL
    var params: EditParams?
}

/// Rendu des exports : retouche, taille, profil colorimétrique, filigrane, métadonnées.
enum Exporter {
    enum Failure: LocalizedError {
        case unreadable(String), writing(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let n): return "« \(n) » ne peut pas être lue."
            case .writing(let n): return "« \(n) » n'a pas pu être écrite."
            }
        }
    }

    /// Produit tous les fichiers ; renvoie ceux qui ont été écrits et les erreurs. Les originaux ne sont jamais touchés.
    static func run(_ items: [ExportItem], options: ExportOptions, progress: @Sendable (Int, Int) -> Void) -> (done: [URL], errors: [String]) {
        let o = options.clamped
        var done: [URL] = [], errors: [String] = []
        for (i, item) in items.enumerated() {
            progress(i, items.count)
            do { try render(item, options: o); done.append(item.dest) }
            catch { errors.append(error.localizedDescription); try? FileManager.default.removeItem(at: item.dest) }
        }
        progress(items.count, items.count)
        return (done, errors)
    }

    static func render(_ item: ExportItem, options o: ExportOptions) throws {
        let name = item.source.lastPathComponent
        guard var img = CIImage(contentsOf: item.source, options: [.applyOrientationProperty: true]) else { throw Failure.unreadable(name) }
        if let p = item.params, !p.isNeutral { img = EditRenderer.apply(p, to: img) }

        // Taille
        let w = img.extent.width, h = img.extent.height
        let (tw, th) = o.targetSize(width: Int(w), height: Int(h))
        if tw != Int(w) {
            let f = CIFilter.lanczosScaleTransform(); f.inputImage = img; f.scale = Float(Double(tw) / Double(w)); f.aspectRatio = 1
            img = f.outputImage ?? img
            img = img.cropped(to: CGRect(x: img.extent.origin.x, y: img.extent.origin.y, width: CGFloat(tw), height: CGFloat(th)))
        }

        // Profil colorimétrique
        let space: CGColorSpace
        switch o.profile {
        case .sRGB: space = CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: space = CGColorSpace(name: CGColorSpace.displayP3)!
        case .keep: space = img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        }
        guard var cg = EditRenderer.context.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: space) else { throw Failure.unreadable(name) }

        if !o.watermark.trimmingCharacters(in: .whitespaces).isEmpty { cg = watermarked(cg, text: o.watermark, position: o.watermarkPosition, opacity: o.watermarkOpacity, space: space) ?? cg }

        // Métadonnées
        var props: [CFString: Any] = [:]
        if o.metadata != .none, let src = CGImageSourceCreateWithURL(item.source as CFURL, nil),
           var all = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for k in [kCGImagePropertyOrientation, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth,
                      kCGImagePropertyColorModel, kCGImagePropertyProfileName, kCGImagePropertyFileSize, kCGImagePropertyJFIFDictionary] { all[k] = nil }
            if var tiff = all[kCGImagePropertyTIFFDictionary] as? [CFString: Any] { tiff[kCGImagePropertyTIFFOrientation] = nil; all[kCGImagePropertyTIFFDictionary] = tiff }
            if o.metadata == .withoutLocation { all[kCGImagePropertyGPSDictionary] = nil }
            props = all
        }
        if o.format.supportsQuality { props[kCGImageDestinationLossyCompressionQuality] = o.quality }

        let type: String
        switch o.format {
        case .jpeg: type = UTType.jpeg.identifier
        case .png: type = UTType.png.identifier
        case .heic: type = UTType.heic.identifier
        }
        guard let dest = CGImageDestinationCreateWithURL(item.dest as CFURL, type as CFString, 1, nil) else { throw Failure.writing(item.dest.lastPathComponent) }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.writing(item.dest.lastPathComponent) }
    }

    /// Filigrane : texte blanc ombré, taille proportionnelle à l'image.
    private static func watermarked(_ cg: CGImage, text: String, position: WatermarkPosition, opacity: Double, space: CGColorSpace) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let fontSize = max(14, CGFloat(max(w, h)) / 38)
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = fontSize / 8; shadow.shadowOffset = CGSize(width: 0, height: -fontSize / 14)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: fontSize),
                                                    .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(opacity)), .shadow: shadow]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let m = fontSize * 0.8
        // UIKit dessine avec l'origine en haut à gauche : on retourne le contexte CoreGraphics (origine en bas à gauche).
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        let W = CGFloat(w), H = CGFloat(h)
        let origin: CGPoint
        switch position {
        case .bottomRight: origin = CGPoint(x: W - size.width - m, y: H - size.height - m)
        case .bottomLeft: origin = CGPoint(x: m, y: H - size.height - m)
        case .topRight: origin = CGPoint(x: W - size.width - m, y: m)
        case .topLeft: origin = CGPoint(x: m, y: m)
        case .center: origin = CGPoint(x: (W - size.width) / 2, y: (H - size.height) / 2)
        }
        UIGraphicsPushContext(ctx)
        str.draw(at: origin)
        UIGraphicsPopContext()
        return ctx.makeImage()
    }
}
