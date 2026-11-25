import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotothequeCore

/// Rendu d'une retouche non destructive (CoreImage) : géométrie, lumière, couleur, détail, courbe.
/// L'original n'est jamais modifié : on calcule l'image retouchée à la demande.
enum EditRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let cubeCache = NSCache<NSString, NSData>()

    // MARK: - Application des réglages

    static func apply(_ params: EditParams, to input: CIImage) -> CIImage {
        let p = params.normalized()
        var img = geometry(p, input)

        if p.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = img; f.ev = Float(p.exposure); img = f.outputImage ?? img
        }
        if p.temperature != 0 || p.tint != 0 {
            // Gains par canal : chaud = plus de rouge, moins de bleu ; teinte magenta = moins de vert.
            let t = CGFloat(p.temperature) / 400, g = CGFloat(p.tint) / 500
            let f = CIFilter.colorMatrix(); f.inputImage = img
            f.rVector = CIVector(x: 1 + t, y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: 1 - g, z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: 1 - t, w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            img = f.outputImage ?? img
        }
        if p.highlights != 0 || p.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = img
            f.highlightAmount = Float(1 + min(0, p.highlights / 100))   // < 1 : assombrit les hautes lumières (1 = inchangé)
            f.shadowAmount = Float(p.shadows / 100)
            img = f.outputImage ?? img
        }
        if p.brightness != 0 || p.contrast != 0 || p.saturation != 0 {
            let f = CIFilter.colorControls(); f.inputImage = img
            f.brightness = Float(p.brightness / 200)
            f.contrast = Float(1 + p.contrast / 100)
            f.saturation = Float(1 + p.saturation / 100)
            img = f.outputImage ?? img
        }
        if p.vibrance != 0 {
            let f = CIFilter.vibrance(); f.inputImage = img; f.amount = Float(p.vibrance / 100); img = f.outputImage ?? img
        }
        if let pts = p.curve, let cube = curveCube(pts) {
            let f = CIFilter.colorCubeWithColorSpace(); f.inputImage = img
            f.cubeDimension = 64; f.cubeData = cube; f.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            img = f.outputImage ?? img
        }
        switch p.mono {
        case .bw?:
            let f = CIFilter.colorControls(); f.inputImage = img; f.saturation = 0; img = f.outputImage ?? img
        case .sepia?:
            let f = CIFilter.sepiaTone(); f.inputImage = img; f.intensity = 1; img = f.outputImage ?? img
        case nil: break
        }
        let noise = max(p.noise, p.colorNoise)
        if noise > 0 {
            let f = CIFilter.noiseReduction(); f.inputImage = img
            f.noiseLevel = Float(noise / 100 * 0.06); f.sharpness = 0.4
            img = f.outputImage ?? img
        }
        if p.sharpen > 0 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = img
            f.sharpness = Float(p.sharpen / 100 * 1.6); f.radius = 1.2
            img = f.outputImage ?? img
        }
        return img
    }

    /// Rotation par pas de 90°, retournements, redressement (recadré sur le plus grand rectangle utile), puis recadrage.
    private static func geometry(_ p: EditParams, _ input: CIImage) -> CIImage {
        var img = input
        func normalize() { img = img.transformed(by: CGAffineTransform(translationX: -img.extent.origin.x, y: -img.extent.origin.y)) }
        normalize()
        if p.rotate != 0 {
            img = img.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(p.rotate) * .pi / 180)); normalize()
        }
        if p.flipH { img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1)); normalize() }
        if p.flipV { img = img.transformed(by: CGAffineTransform(scaleX: 1, y: -1)); normalize() }
        if abs(p.straighten) > 0.01 {
            let w = img.extent.width, h = img.extent.height
            let a = abs(CGFloat(p.straighten)) * .pi / 180
            let c = cos(a), s = sin(a)
            let k = min(w / (w * c + h * s), h / (w * s + h * c))
            var t = CGAffineTransform(translationX: w / 2, y: h / 2)
            t = t.rotated(by: -CGFloat(p.straighten) * .pi / 180)
            t = t.translatedBy(x: -w / 2, y: -h / 2)
            img = img.transformed(by: t)
            let r = CGRect(x: (w - w * k) / 2, y: (h - h * k) / 2, width: w * k, height: h * k)
            img = img.cropped(to: r); normalize()
        }
        if let c = p.crop?.clamped, !c.isFull {
            let w = img.extent.width, h = img.extent.height
            // Fraction depuis le coin haut gauche ; CoreImage compte depuis le bas.
            let r = CGRect(x: c.x * w, y: (1 - c.y - c.h) * h, width: c.w * w, height: c.h * h).integral
            img = img.cropped(to: r); normalize()
        }
        return img
    }

    /// Table 3D 64³ d'une courbe de tonalité appliquée à chaque canal.
    private static func curveCube(_ pts: [CurvePoint]) -> Data? {
        guard CurveLUT.validPoints(pts) != nil else { return nil }
        let key = pts.map { "\($0.x),\($0.y)" }.joined(separator: ";") as NSString
        if let d = cubeCache.object(forKey: key) { return d as Data }
        let lut = CurveLUT.make(pts), n = 64
        var data = [Float](); data.reserveCapacity(n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            data.append(Float(lut[r * 255 / (n - 1)]) / 255)
            data.append(Float(lut[g * 255 / (n - 1)]) / 255)
            data.append(Float(lut[b * 255 / (n - 1)]) / 255)
            data.append(1)
        } } }
        let d = data.withUnsafeBufferPointer { Data(buffer: $0) }
        cubeCache.setObject(d as NSData, forKey: key)
        return d
    }

    // MARK: - Rendu

    /// Aperçu réduit (grand côté `maxPixel`) : ne décode pas l'image entière.
    static func preview(url: URL, params: EditParams, maxPixel: Int) -> UIImage? {
        guard let cg = ImageTools.thumbnail(of: url, maxPixel: maxPixel) else { return nil }
        let out = apply(params, to: CIImage(cgImage: cg))
        guard let res = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: res)
    }

    /// Image retouchée à pleine définition (export). `nil` si l'image ne se décode pas.
    static func full(url: URL, params: EditParams) -> CIImage? {
        guard let src = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        return apply(params, to: src)
    }
}

extension EditRenderer {
    /// Aperçu à partir d'une image déjà décodée (curseurs : on ne relit pas le fichier à chaque réglage).
    static func render(base: CGImage, params: EditParams) -> UIImage? {
        let out = apply(params, to: CIImage(cgImage: base))
        guard let res = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: res)
    }
}
