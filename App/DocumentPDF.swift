import UIKit
import PhotothequeCore

/// Données d'une photo préparées pour le rendu d'un document.
struct DocPhoto: Sendable {
    var photo: Photo
    var url: URL
    var edit: EditParams?
    var lines: [String]          // légende (champs choisis)
    var keywords: String
    var colorName: String
}

/// Dessin des documents PDF d'après un `DocumentPlan` : couverture, sommaire, grilles, fiches, portfolio.
enum DocumentPDF {
    static func build(plan: DocumentPlan, photos: [Int64: DocPhoto], progress: @Sendable (Int, Int) -> Void) -> Data {
        let o = plan.options
        let size = o.pageSize.size
        let page = CGRect(x: 0, y: 0, width: size.w, height: size.h)
        let margin: CGFloat = 36
        let bg = UIColor(hex: o.background)
        let ink = bg.luminance > 0.55 ? UIColor(white: 0.1, alpha: 1) : UIColor(white: 0.95, alpha: 1)
        let sub = ink.withAlphaComponent(0.6)
        let title = o.title.isEmpty ? o.kind.label : o.title
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: PDFDocumentBuilder.format(title: title))
        var cache: [String: UIImage] = [:]

        func image(_ id: Int64, maxPixel: Int) -> UIImage? {
            guard let dp = photos[id] else { return nil }
            let key = "\(id)-\(maxPixel)"
            if let c = cache[key] { return c }
            let img: UIImage?
            if o.useEdits, let p = dp.edit, !p.isNeutral { img = EditRenderer.preview(url: dp.url, params: p, maxPixel: maxPixel) }
            else { img = ImageTools.thumbnail(of: dp.url, maxPixel: maxPixel).map { UIImage(cgImage: $0) } }
            if let img { if cache.count > 60 { cache.removeAll() }; cache[key] = img }
            return img
        }

        /// Image contenue dans `rect` (rapport conservé, centrée).
        func drawFit(_ img: UIImage, in rect: CGRect) {
            let k = min(rect.width / img.size.width, rect.height / img.size.height)
            let w = img.size.width * k, h = img.size.height * k
            img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        }
        func text(_ s: String, _ rect: CGRect, size: CGFloat, bold: Bool = false, color: UIColor? = nil, align: NSTextAlignment = .left) {
            let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
            (s as NSString).draw(in: rect, withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                                                             .foregroundColor: color ?? ink, .paragraphStyle: p])
        }
        func background(_ ctx: UIGraphicsPDFRendererContext) { bg.setFill(); UIBezierPath(rect: page).fill() }
        func footer(_ n: Int) { text("\(n)", CGRect(x: page.width - margin - 60, y: page.height - margin + 6, width: 60, height: 12), size: 8, color: sub, align: .right) }

        let total = plan.pages.count
        let dateText = Date().formatted(date: .long, time: .omitted)
        return renderer.pdfData { ctx in
            for (n, pg) in plan.pages.enumerated() {
                progress(n, total)
                ctx.beginPage()
                background(ctx)
                switch pg {
                case .cover:
                    let first = plan.sections.flatMap(\.photoIds).first
                    if let first, let img = image(first, maxPixel: 1600) {
                        drawFit(img, in: CGRect(x: margin, y: page.height * 0.12, width: page.width - 2 * margin, height: page.height * 0.52))
                    }
                    text(title, CGRect(x: margin, y: page.height * 0.68, width: page.width - 2 * margin, height: 60), size: 34, bold: true, align: .center)
                    if !o.subtitle.isEmpty { text(o.subtitle, CGRect(x: margin, y: page.height * 0.68 + 52, width: page.width - 2 * margin, height: 30), size: 16, color: sub, align: .center) }
                    if !o.author.isEmpty { text(o.author, CGRect(x: margin, y: page.height * 0.68 + 90, width: page.width - 2 * margin, height: 24), size: 13, align: .center) }
                    text(dateText, CGRect(x: margin, y: page.height - margin - 20, width: page.width - 2 * margin, height: 16), size: 9, color: sub, align: .center)

                case .toc:
                    text("Sommaire", CGRect(x: margin, y: margin, width: page.width - 2 * margin, height: 30), size: 22, bold: true)
                    var y = margin + 48
                    for e in plan.toc {
                        if y > page.height - margin - 20 { break }
                        text(e.title, CGRect(x: margin, y: y, width: page.width - 2 * margin - 120, height: 16), size: 11)
                        text("\(e.count) photo(s)", CGRect(x: page.width - margin - 190, y: y, width: 100, height: 16), size: 9, color: sub, align: .right)
                        text("\(e.page)", CGRect(x: page.width - margin - 60, y: y, width: 60, height: 16), size: 11, align: .right)
                        y += 20
                    }
                    footer(n + 1)

                case .grid(let section, let ids, let number, let of):
                    var top = margin
                    if let section, !section.isEmpty {
                        text(section + (of > 1 ? "  (\(number)/\(of))" : ""), CGRect(x: margin, y: top, width: page.width - 2 * margin, height: 22), size: 15, bold: true)
                        top += 28
                    } else if !title.isEmpty {
                        text(title, CGRect(x: margin, y: top, width: page.width - 2 * margin, height: 20), size: 12, bold: true, color: sub); top += 26
                    }
                    let cols = o.columns, rows = o.rows
                    let gap: CGFloat = 8
                    let availW = page.width - 2 * margin, availH = page.height - top - margin - 14
                    let cw = (availW - gap * CGFloat(cols - 1)) / CGFloat(cols), ch = (availH - gap * CGFloat(rows - 1)) / CGFloat(rows)
                    let capH: CGFloat = o.fields.isEmpty ? 0 : min(34, 10.5 * CGFloat(min(3, o.fields.count)) + 2)
                    for (i, id) in ids.enumerated() {
                        let r = CGRect(x: margin + CGFloat(i % cols) * (cw + gap), y: top + CGFloat(i / cols) * (ch + gap), width: cw, height: ch)
                        if let img = image(id, maxPixel: Int(max(cw, ch) * 3)) { drawFit(img, in: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - capH)) }
                        if let lines = photos[id]?.lines, capH > 0 {
                            for (j, l) in lines.prefix(3).enumerated() {
                                text(l, CGRect(x: r.minX, y: r.maxY - capH + CGFloat(j) * 10.5 + 1, width: r.width, height: 11), size: 7, color: j == 0 ? ink : sub, align: .center)
                            }
                        }
                    }
                    footer(n + 1)

                case .detail(let id):
                    guard let dp = photos[id] else { break }
                    let imgRect = CGRect(x: margin, y: margin, width: page.width - 2 * margin, height: page.height * 0.52)
                    if let img = image(id, maxPixel: 1800) { drawFit(img, in: imgRect) }
                    var y = imgRect.maxY + 16
                    text(dp.photo.displayTitle, CGRect(x: margin, y: y, width: page.width - 2 * margin, height: 22), size: 16, bold: true); y += 28
                    let p = dp.photo
                    var rows: [(String, String)] = [("Fichier", p.fileName), ("Légende", p.caption), ("Prise de vue", p.takenAt.map { Fmt.date($0) } ?? ""), ("Appareil", p.camera), ("Objectif", p.lens),
                                                    ("Dimensions", p.width.map { "\($0) × \(p.height ?? 0) px" } ?? ""), ("Format", "\(p.format) · \(Fmt.bytes(p.size))"),
                                                    ("Note", p.rating > 0 ? String(repeating: "★", count: p.rating) : ""), ("Étiquette", dp.colorName), ("Lieu", p.place),
                                                    ("Position", p.latitude.flatMap { la in p.longitude.map { String(format: "%.5f, %.5f", la, $0) } } ?? ""), ("Mots-clés", dp.keywords)]
                    rows = rows.filter { !$0.1.isEmpty }
                    for (k, v) in rows {
                        if y > page.height - margin - 14 { break }
                        text(k, CGRect(x: margin, y: y, width: 90, height: 14), size: 9, bold: true, color: sub)
                        text(v, CGRect(x: margin + 96, y: y, width: page.width - 2 * margin - 96, height: 14), size: 9)
                        y += 15
                    }
                    footer(n + 1)

                case .portfolio(let id):
                    guard let dp = photos[id] else { break }
                    let capH: CGFloat = 54
                    if let img = image(id, maxPixel: 2400) { drawFit(img, in: CGRect(x: margin, y: margin, width: page.width - 2 * margin, height: page.height - 2 * margin - capH)) }
                    var y = page.height - margin - capH + 8
                    if !dp.photo.title.isEmpty { text(dp.photo.title, CGRect(x: margin, y: y, width: page.width - 2 * margin, height: 18), size: 13, bold: true, align: .center); y += 18 }
                    for l in dp.lines.prefix(2) where l != dp.photo.title { text(l, CGRect(x: margin, y: y, width: page.width - 2 * margin, height: 14), size: 9, color: sub, align: .center); y += 14 }
                    footer(n + 1)

                case .colophon:
                    text(title, CGRect(x: margin, y: page.height * 0.42, width: page.width - 2 * margin, height: 30), size: 20, bold: true, align: .center)
                    let who = o.author.isEmpty ? "" : o.author + " — "
                    text("\(who)\(plan.photoCount) photo(s) — \(dateText)", CGRect(x: margin, y: page.height * 0.42 + 38, width: page.width - 2 * margin, height: 18), size: 11, color: sub, align: .center)
                    text("Document créé avec Photothèque", CGRect(x: margin, y: page.height - margin - 20, width: page.width - 2 * margin, height: 14), size: 8, color: sub, align: .center)
                }
            }
            if plan.pages.isEmpty { ctx.beginPage(); text("Aucune photo.", CGRect(x: margin, y: margin, width: 300, height: 20), size: 12) }
        }
    }
}
