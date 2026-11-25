import UIKit
import PhotothequeCore

extension UIColor {
    /// « #rrggbb » → couleur (blanc si invalide).
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0xFFFFFF
        if s.count == 6 { Scanner(string: s).scanHexInt64(&v) }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Luminance perçue (0 noir, 1 blanc) : choix d'un texte lisible sur un fond.
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

/// Photo d'un album préparée pour le rendu (le catalogue n'est pas partagé entre fils).
struct AlbumPhotoSource: Sendable {
    var url: URL
    var width: Int?
    var height: Int?
    var edit: EditParams?
}

struct AlbumPDFOptions: Sendable {
    enum Quality: String, Sendable, CaseIterable { case print, screen
        var ppi: Double { self == .print ? 300 : 150 }
        var jpeg: CGFloat { self == .print ? 0.9 : 0.8 }
        var label: String { self == .print ? "Impression (300 ppp)" : "Écran (150 ppp)" }
    }
    enum Layout: String, Sendable, CaseIterable { case pages, spreads
        var label: String { self == .pages ? "Une page par page PDF" : "Planches de deux pages" }
    }
    var quality: Quality = .print
    var layout: Layout = .pages
    var bleed = false
    static let bleedMM = 3.0
}

/// Export PDF d'un album : cadres à gabarits, recadrage, fonds, bordures, textes, fond perdu, planches.
enum AlbumPDF {
    static func pt(_ mm: Double) -> CGFloat { CGFloat(mm / 25.4 * 72) }

    static func build(album: Album, pages: [AlbumPage], photos: [Int64: AlbumPhotoSource], options: AlbumPDFOptions, progress: @Sendable (Int, Int) -> Void) -> Data {
        let W = pt(album.widthMM), H = pt(album.heightMM)
        let bleed = options.bleed ? pt(AlbumPDFOptions.bleedMM) : 0
        let fmt = PDFDocumentBuilder.format(title: album.name)
        var cache: [Int64: UIImage] = [:]

        func image(_ id: Int64, frameW: CGFloat, frameH: CGFloat) -> UIImage? {
            guard let src = photos[id] else { return nil }
            // Pixels utiles pour la qualité demandée : on ne décode pas plus que nécessaire.
            let need = Int((max(frameW, frameH) / 72 * options.quality.ppi).rounded(.up)) * 2
            let key = id
            if let c = cache[key], max(c.size.width, c.size.height) >= CGFloat(min(need, 4096)) * 0.9 { return c }
            let maxPx = min(max(need, 600), 4096)
            let img: UIImage?
            if let p = src.edit, !p.isNeutral { img = EditRenderer.preview(url: src.url, params: p, maxPixel: maxPx) }
            else { img = ImageTools.thumbnail(of: src.url, maxPixel: maxPx).map { UIImage(cgImage: $0) } }
            if let img { cache[key] = img }
            return img
        }

        /// Dessine une page logique (simple ou double) ; `clip` : ne garder que la moitié `half` d'une double page.
        func draw(_ page: AlbumPage, in ctx: UIGraphicsPDFRendererContext, origin: CGPoint, half: Int?) {
            let spread = page.isSpread
            let logicalW = spread ? W * 2 : W
            let cg = ctx.cgContext
            cg.saveGState()
            // Zone de la page imprimée (avec fond perdu) dans la page PDF.
            let visibleW = (spread && half == nil) ? 2 * W : W      // planche entière ou une seule page
            let visible = CGRect(x: origin.x - bleed, y: origin.y - bleed, width: visibleW + 2 * bleed, height: H + 2 * bleed)
            cg.clip(to: visible)
            // Décalage de la planche : la moitié droite est dessinée décalée d'une largeur de page.
            let dx = (half == 1 ? -W : 0)
            let sheet = CGRect(x: origin.x + dx, y: origin.y, width: logicalW, height: H)
            UIColor(hex: page.background).setFill()
            UIBezierPath(rect: visible).fill()
            if spread, half == nil { UIColor(hex: page.background).setFill(); UIBezierPath(rect: sheet).fill() }
            let bg = UIColor(hex: page.background)
            let text = page.style.textColor.map { UIColor(hex: $0) } ?? (bg.luminance > 0.55 ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.96, alpha: 1))
            let lay = AlbumLayout.named(page.layout)

            for (i, f) in page.frames.enumerated() {
                var r = CGRect(x: sheet.minX + CGFloat(f.x) * logicalW, y: sheet.minY + CGFloat(f.y) * H, width: CGFloat(f.w) * logicalW, height: CGFloat(f.h) * H)
                if lay?.fullBleed == true { r = r.insetBy(dx: -bleed, dy: -bleed) }     // fond perdu : la photo déborde
                guard i < page.slots.count, let id = page.slots[i] else {
                    if options.quality == .screen { UIColor(white: 0.9, alpha: 1).setFill(); UIBezierPath(rect: r).fill() }
                    continue
                }
                cg.saveGState()
                cg.clip(to: r)
                if let img = image(id, frameW: r.width, frameH: r.height), let src = photos[id] {
                    let iw = Double(src.width ?? Int(img.size.width)), ih = Double(src.height ?? Int(img.size.height))
                    // Dimensions de l'image affichée ; si elle a été rognée par la retouche, on prend celles du rendu.
                    let (rw, rh) = (src.edit?.isNeutral ?? true) ? (iw, ih) : (Double(img.size.width), Double(img.size.height))
                    let crop = i < page.crops.count ? page.crops[i] : nil
                    let win = CropMath.window(imageW: rw, imageH: rh, frameW: Double(r.width), frameH: Double(r.height), crop: crop)
                    let dispW = r.width / CGFloat(win.width), dispH = r.height / CGFloat(win.height)
                    img.draw(in: CGRect(x: r.minX - CGFloat(win.left) * dispW, y: r.minY - CGFloat(win.top) * dispH, width: dispW, height: dispH))
                } else {
                    UIColor(white: 0.85, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
                }
                cg.restoreGState()
                if page.style.borderWidth > 0, lay?.fullBleed != true {
                    let bw = pt(page.style.borderWidth)
                    UIColor(hex: page.style.borderColor).setStroke()
                    let p = UIBezierPath(rect: r.insetBy(dx: bw / 2, dy: bw / 2)); p.lineWidth = bw; p.stroke()
                }
            }

            // Textes : titre (grand, centré sur les pages de titre) et légende dans la bande du bas.
            let para = NSMutableParagraphStyle()
            para.alignment = page.style.align == "left" ? .left : page.style.align == "right" ? .right : .center
            para.lineBreakMode = .byWordWrapping
            let margin = logicalW * CGFloat(AlbumLayout.safetyMargin)
            if !page.title.isEmpty {
                let isTitlePage = page.layout == "titre"
                let size = isTitlePage ? min(W, H) / 9 : min(W, H) / 26
                let rect = isTitlePage
                    ? CGRect(x: sheet.minX + margin, y: sheet.minY + H * 0.38, width: logicalW - 2 * margin, height: H * 0.3)
                    : CGRect(x: sheet.minX + margin, y: sheet.minY + H * 0.025, width: logicalW - 2 * margin, height: H * 0.04)
                (page.title as NSString).draw(in: rect, withAttributes: [.font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: text, .paragraphStyle: para])
            }
            if !page.caption.isEmpty, lay?.fullBleed != true {
                let isTitlePage = page.layout == "titre"
                let rect = isTitlePage
                    ? CGRect(x: sheet.minX + margin, y: sheet.minY + H * 0.62, width: logicalW - 2 * margin, height: H * 0.2)
                    : CGRect(x: sheet.minX + margin, y: sheet.minY + H * 0.905, width: logicalW - 2 * margin, height: H * 0.07)
                (page.caption as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: min(W, H) / (isTitlePage ? 22 : 34)), .foregroundColor: text, .paragraphStyle: para])
            }
            cg.restoreGState()
        }

        let mediaW = W + 2 * bleed, mediaH = H + 2 * bleed
        let total = max(1, pages.count)
        func newPage(_ ctx: UIGraphicsPDFRendererContext, width: CGFloat, height: CGFloat) {
            ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: width, height: height), pageInfo: [:])
        }

        // Une page PDF par page imprimée ; une double page est dessinée deux fois (moitié gauche, moitié droite).
        func pagesMode(_ ctx: UIGraphicsPDFRendererContext) {
            for (n, p) in pages.enumerated() {
                progress(n, total)
                if p.isSpread {
                    for half in 0...1 { newPage(ctx, width: mediaW, height: mediaH); draw(p, in: ctx, origin: CGPoint(x: bleed, y: bleed), half: half) }
                } else { newPage(ctx, width: mediaW, height: mediaH); draw(p, in: ctx, origin: CGPoint(x: bleed, y: bleed), half: nil) }
            }
        }
        // Planches : la page 1 seule à droite, puis deux pages côte à côte ; une double page occupe toute la planche.
        func spreadsMode(_ ctx: UIGraphicsPDFRendererContext) {
            let sheetW = 2 * W + 2 * bleed
            var folio = 1
            var i = 0
            var pendingLeft: AlbumPage?
            func flush(left: AlbumPage?, right: AlbumPage?) {
                newPage(ctx, width: sheetW, height: mediaH)
                if let l = left { draw(l, in: ctx, origin: CGPoint(x: bleed, y: bleed), half: l.isSpread ? 0 : nil) }
                if let r = right { draw(r, in: ctx, origin: CGPoint(x: bleed + W, y: bleed), half: r.isSpread ? 1 : nil) }
            }
            while i < pages.count {
                progress(i, total)
                let p = pages[i]
                if p.isSpread && folio % 2 == 0 {
                    if let l = pendingLeft { flush(left: l, right: nil); pendingLeft = nil }
                    newPage(ctx, width: sheetW, height: mediaH)
                    draw(p, in: ctx, origin: CGPoint(x: bleed, y: bleed), half: nil)
                    folio += 2
                } else if folio % 2 == 1 {
                    // Page de droite : elle ferme la planche commencée par la page de gauche (ou seule pour la page 1).
                    flush(left: pendingLeft, right: p); pendingLeft = nil; folio += 1
                } else {
                    pendingLeft = p; folio += 1
                }
                i += 1
            }
            if let l = pendingLeft { flush(left: l, right: nil) }
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: mediaW, height: mediaH), format: fmt)
        let data = renderer.pdfData { ctx in
            if pages.isEmpty { newPage(ctx, width: mediaW, height: mediaH); return }
            options.layout == .pages ? pagesMode(ctx) : spreadsMode(ctx)
        }
        progress(total, total)
        return data
    }
}
