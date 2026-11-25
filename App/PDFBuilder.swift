import UIKit
import PhotothequeCore

/// Documents PDF (UIGraphicsPDFRenderer) : rapports tabulaires ici, albums et planches-contact plus loin.
enum PDFDocumentBuilder {
    static let a4 = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)

    static func format(title: String) -> UIGraphicsPDFRendererFormat {
        let f = UIGraphicsPDFRendererFormat()
        f.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Photothèque"]
        return f
    }

    /// Rapport tabulaire paginé (A4, en paysage si le tableau a beaucoup de colonnes).
    static func table(_ t: ReportTable) -> Data {
        let landscape = t.headers.count > 5
        let page = landscape ? CGRect(x: 0, y: 0, width: a4.height, height: a4.width) : a4
        let margin: CGFloat = 36
        let usable = page.width - 2 * margin

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let subFont = UIFont.systemFont(ofSize: 10)
        let headFont = UIFont.boldSystemFont(ofSize: 8.5)
        let cellFont = UIFont.systemFont(ofSize: 8)
        let noteFont = UIFont.systemFont(ofSize: 9)

        // Largeurs de colonnes proportionnelles au contenu (bornées).
        let counts = t.headers.indices.map { i -> Int in
            let longest = ([t.headers[i]] + t.rows.prefix(200).map { i < $0.count ? $0[i] : "" }).map { $0.count }.max() ?? 4
            return max(6, min(longest, 40))
        }
        let total = CGFloat(counts.reduce(0, +))
        let widths = counts.map { usable * CGFloat($0) / max(1, total) }

        let rowHeight: CGFloat = 14
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail

        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format(title: t.title))
        return renderer.pdfData { ctx in
            var pageNo = 0
            var y: CGFloat = 0
            func newPage() {
                ctx.beginPage()
                pageNo += 1
                y = margin
                if pageNo == 1 {
                    (t.title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
                    y += 26
                    (t.subtitle as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: subFont, .foregroundColor: UIColor.darkGray])
                    y += 18
                    for n in t.notes {
                        let r = CGRect(x: margin, y: y, width: usable, height: 28)
                        (n as NSString).draw(in: r, withAttributes: [.font: noteFont, .foregroundColor: UIColor.black])
                        y += 14
                    }
                    y += 6
                }
                // En-tête de colonnes
                UIColor(white: 0.9, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: usable, height: rowHeight)).fill()
                var x = margin
                for (i, h) in t.headers.enumerated() {
                    (h as NSString).draw(in: CGRect(x: x + 2, y: y + 2, width: widths[i] - 4, height: rowHeight), withAttributes: [.font: headFont, .paragraphStyle: para])
                    x += widths[i]
                }
                y += rowHeight + 2
                let footer = "Page \(pageNo)"
                (footer as NSString).draw(at: CGPoint(x: page.width - margin - 40, y: page.height - margin + 8), withAttributes: [.font: subFont, .foregroundColor: UIColor.gray])
            }
            newPage()
            for (n, row) in t.rows.enumerated() {
                if y + rowHeight > page.height - margin { newPage() }
                if n % 2 == 1 {
                    UIColor(white: 0.96, alpha: 1).setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: y, width: usable, height: rowHeight)).fill()
                }
                var x = margin
                for (i, cell) in row.enumerated() where i < widths.count {
                    (cell as NSString).draw(in: CGRect(x: x + 2, y: y + 2, width: widths[i] - 4, height: rowHeight), withAttributes: [.font: cellFont, .paragraphStyle: para])
                    x += widths[i]
                }
                y += rowHeight
            }
            if t.rows.isEmpty {
                ("Aucune ligne." as NSString).draw(at: CGPoint(x: margin, y: y + 6), withAttributes: [.font: cellFont])
            }
        }
    }
}
