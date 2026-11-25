import Foundation

// Albums : pages à gabarits, recadrage, doubles pages, annuler / rétablir, contrôles, projet JSON.
// Même modèle que la version de bureau (lib/albums.mjs, docs/ARCHITECTURE.md §9) : gabarits en fractions de la page,
// recadrage { x, y, zoom }, fichier de projet « phototheque-album » échangeable entre les deux applications
// (les photos sont retrouvées par leur empreinte SHA-256). Un album ne contient que des références aux photos.

// MARK: - Formats et gabarits

public struct AlbumFormat: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let widthMM: Double
    public let heightMM: Double

    public static let all: [AlbumFormat] = [
        AlbumFormat(id: "carre-30", label: "Carré 30 × 30 cm", widthMM: 300, heightMM: 300),
        AlbumFormat(id: "carre-20", label: "Carré 20 × 20 cm", widthMM: 200, heightMM: 200),
        AlbumFormat(id: "a4-portrait", label: "A4 portrait (21 × 29,7 cm)", widthMM: 210, heightMM: 297),
        AlbumFormat(id: "a4-paysage", label: "A4 paysage (29,7 × 21 cm)", widthMM: 297, heightMM: 210),
        AlbumFormat(id: "20x30-portrait", label: "Portrait 20 × 30 cm", widthMM: 200, heightMM: 300),
        AlbumFormat(id: "30x20-paysage", label: "Paysage 30 × 20 cm", widthMM: 300, heightMM: 200),
    ]
    public static func named(_ id: String) -> AlbumFormat? { all.first { $0.id == id } }
    public static let sizeRange: ClosedRange<Double> = 50...1000
}

public struct FrameRect: Equatable, Hashable, Codable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        func r4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
        self.x = r4(x); self.y = r4(y); self.w = r4(w); self.h = r4(h)
    }
}

public struct AlbumLayout: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let frames: [FrameRect]
    public let fullBleed: Bool
    public let spread: Bool

    // Marge de sécurité 6 %, gouttière 3 %, bande de légende 6 % en bas ; seul « plein » va jusqu'au bord.
    static let M = 0.06, G = 0.03, CAP = 0.06
    static let area = (x: M, y: M, w: 1 - 2 * M, h: 1 - 2 * M - CAP)

    static func grid(_ cols: Int, _ rows: Int, in a: (x: Double, y: Double, w: Double, h: Double) = area, gx: Double = G, gy: Double = G) -> [FrameRect] {
        let w = (a.w - gx * Double(cols - 1)) / Double(cols), h = (a.h - gy * Double(rows - 1)) / Double(rows)
        var out: [FrameRect] = []
        for r in 0..<rows { for c in 0..<cols { out.append(FrameRect(a.x + Double(c) * (w + gx), a.y + Double(r) * (h + gy), w, h)) } }
        return out
    }

    // Doubles pages : fractions de la planche (deux pages côte à côte).
    static let HM = M / 2, HG = G / 2
    static func pageArea(_ k: Int) -> (x: Double, y: Double, w: Double, h: Double) { (Double(k) * 0.5 + HM, M, 0.5 - 2 * HM, area.h) }
    static var spreadBand: [FrameRect] {
        let band = (area.h - G) / 2
        var out = [FrameRect(HM, M, 1 - 2 * HM, band)]
        for k in 0...1 {
            let a = pageArea(k)
            out += grid(2, 1, in: (a.x, M + band + G, a.w, area.h - band - G), gx: HG)
        }
        return out
    }
    static var bigLeft: [FrameRect] {
        let wBig = (area.w - G) * 2 / 3
        return [FrameRect(area.x, area.y, wBig, area.h)] + grid(1, 2, in: (area.x + wBig + G, area.y, area.w - wBig - G, area.h))
    }

    public static let all: [AlbumLayout] = [
        AlbumLayout(id: "titre", label: "Page de titre (texte seul)", frames: [], fullBleed: false, spread: false),
        AlbumLayout(id: "plein", label: "1 photo pleine page (fond perdu)", frames: [FrameRect(0, 0, 1, 1)], fullBleed: true, spread: false),
        AlbumLayout(id: "une", label: "1 photo avec marges", frames: grid(1, 1), fullBleed: false, spread: false),
        AlbumLayout(id: "deux-cote", label: "2 photos côte à côte", frames: grid(2, 1), fullBleed: false, spread: false),
        AlbumLayout(id: "deux-pile", label: "2 photos l'une sous l'autre", frames: grid(1, 2), fullBleed: false, spread: false),
        AlbumLayout(id: "trois", label: "3 photos (1 grande + 2)", frames: bigLeft, fullBleed: false, spread: false),
        AlbumLayout(id: "quatre", label: "4 photos (2 × 2)", frames: grid(2, 2), fullBleed: false, spread: false),
        AlbumLayout(id: "six", label: "6 photos (3 × 2)", frames: grid(3, 2), fullBleed: false, spread: false),
        AlbumLayout(id: "double-plein", label: "Double page : 1 panoramique (fond perdu)", frames: [FrameRect(0, 0, 1, 1)], fullBleed: true, spread: true),
        AlbumLayout(id: "double-marges", label: "Double page : 1 panoramique avec marges", frames: [FrameRect(HM, M, 1 - 2 * HM, area.h)], fullBleed: false, spread: true),
        AlbumLayout(id: "double-face", label: "Double page : 2 photos face à face", frames: (0...1).flatMap { grid(1, 1, in: pageArea($0)) }, fullBleed: false, spread: true),
        AlbumLayout(id: "double-bandeau", label: "Double page : bandeau panoramique + 4", frames: spreadBand, fullBleed: false, spread: true),
    ]
    public static func named(_ id: String) -> AlbumLayout? { all.first { $0.id == id } }
    public static let safetyMargin = M
}

// MARK: - Recadrage

public struct AlbumCrop: Codable, Equatable, Hashable, Sendable {
    public static let zoomMax = 5.0
    public var x: Double
    public var y: Double
    public var zoom: Double
    public init(x: Double = 0.5, y: Double = 0.5, zoom: Double = 1) { self.x = x; self.y = y; self.zoom = zoom }

    /// Recadrage nettoyé, ou `nil` s'il équivaut au recadrage par défaut (centré, sans zoom).
    public var cleaned: AlbumCrop? {
        func r4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
        func c(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v.isFinite ? v : a)) }
        let n = AlbumCrop(x: r4(c(x, 0, 1)), y: r4(c(y, 0, 1)), zoom: r4(c(zoom, 1, AlbumCrop.zoomMax)))
        return n == AlbumCrop() ? nil : n
    }
}

public enum CropMath {
    /// Partie visible d'une image `iw × ih` dans un cadre `fw × fh` (même unité), en fractions de l'image.
    public static func window(imageW iw: Double, imageH ih: Double, frameW fw: Double, frameH fh: Double, crop: AlbumCrop?) -> (left: Double, top: Double, width: Double, height: Double) {
        let z = crop?.zoom ?? 1, s = max(fw / iw, fh / ih) * z
        let w = min(1, fw / (iw * s)), h = min(1, fh / (ih * s))
        func cl(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }
        let cx = cl(crop?.x ?? 0.5, w / 2, 1 - w / 2), cy = cl(crop?.y ?? 0.5, h / 2, 1 - h / 2)
        return (cx - w / 2, cy - h / 2, w, h)
    }
}

// MARK: - Style de page

public struct PageStyle: Codable, Equatable, Hashable, Sendable {
    public static let borderMax = 10.0
    public var borderWidth: Double = 0          // mm, filet tracé à l'intérieur de chaque cadre
    public var borderColor: String = "#ffffff"
    public var textColor: String?               // nil : couleur lisible selon le fond
    public var align: String = "center"         // center | left | right

    public init() {}

    static func hex(_ s: String?, _ d: String) -> String {
        guard let s, s.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil else { return d }
        return s.lowercased()
    }
    public var cleaned: PageStyle {
        var p = self
        p.borderWidth = (min(PageStyle.borderMax, max(0, borderWidth.isFinite ? borderWidth : 0)) * 10).rounded() / 10
        p.borderColor = PageStyle.hex(borderColor, "#ffffff")
        p.textColor = textColor.flatMap { PageStyle.hex($0, "") }.flatMap { $0.isEmpty ? nil : $0 }
        p.align = ["center", "left", "right"].contains(align) ? align : "center"
        return p
    }
}

/// Modèles graphiques : fond + style, appliqués à une page ou à tout l'album.
public struct StylePreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let background: String
    public let style: PageStyle

    static func make(_ id: String, _ name: String, _ bg: String, _ bw: Double, _ bc: String, _ tc: String?, _ al: String) -> StylePreset {
        var s = PageStyle(); s.borderWidth = bw; s.borderColor = bc; s.textColor = tc; s.align = al
        return StylePreset(id: id, name: name, background: bg, style: s)
    }
    public static let all: [StylePreset] = [
        make("classique", "Classique (blanc, sans bordure)", "#ffffff", 0, "#ffffff", nil, "center"),
        make("galerie", "Galerie (filet noir, texte à gauche)", "#ffffff", 0.5, "#1e293b", "#1e293b", "left"),
        make("passe", "Passe-partout (crème, bordure blanche)", "#f4efe6", 4, "#ffffff", "#5b4636", "center"),
        make("nuit", "Nuit (fond noir, filet clair)", "#141414", 0.3, "#e5e5e5", "#f5f5f5", "center"),
        make("kraft", "Kraft (fond brun, bordure ivoire)", "#c9a97c", 2, "#fffaf0", "#3b2a1a", "right"),
    ]
}

// MARK: - Modèles

public struct Album: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var description: String
    public var format: String
    public var widthMM: Double
    public var heightMM: Double
    public var createdAt: String
    public var updatedAt: String
    public var pageCount: Int

    init(row r: Row, pageCount: Int = 0) {
        id = r.int64("id") ?? 0
        name = r.string("name") ?? ""
        description = r.string("description") ?? ""
        format = r.string("format") ?? "a4-portrait"
        widthMM = r.double("width_mm") ?? 210
        heightMM = r.double("height_mm") ?? 297
        createdAt = r.string("created_at") ?? ""
        updatedAt = r.string("updated_at") ?? ""
        self.pageCount = pageCount
    }
    public var orientation: String { widthMM > heightMM ? "landscape" : widthMM < heightMM ? "portrait" : "square" }
}

public struct AlbumPage: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var albumId: Int64
    public var position: Int
    public var layout: String
    public var background: String
    public var title: String
    public var caption: String
    public var slots: [Int64?]
    public var crops: [AlbumCrop?]
    public var style: PageStyle

    public var frames: [FrameRect] { AlbumLayout.named(layout)?.frames ?? [] }
    public var isSpread: Bool { AlbumLayout.named(layout)?.spread ?? false }
}

struct PageData: Codable {
    var slots: [Int64?] = []
    var crops: [AlbumCrop?] = []
    var title: String = ""
    var caption: String = ""
    var style: PageStyle = PageStyle()
}

/// Numérotation des pages imprimées : un gabarit double occupe deux pages ; la page 1 est une page de droite.
public struct Folio: Equatable, Sendable {
    public var folio: Int
    public var span: Int
    public var label: String { span == 2 ? "Pages \(folio)–\(folio + 1)" : "Page \(folio)" }
    /// Une double page doit commencer sur un numéro pair (sinon le pli coupe la photo).
    public var misaligned: Bool { span == 2 && folio % 2 != 0 }
}

public enum AlbumIssueKind: String, Sendable { case missingPhoto, unavailableFile, lowResolution, warnResolution, emptyFrame, spreadAlignment }

public struct AlbumIssue: Identifiable, Equatable, Sendable {
    public var id: String { "\(page)-\(slot ?? -1)-\(kind.rawValue)" }
    public var page: Int          // numéro de page de l'album (à partir de 1)
    public var slot: Int?
    public var kind: AlbumIssueKind
    public var message: String
    /// Bloquant pour l'impression.
    public var blocking: Bool { kind == .missingPhoto || kind == .lowResolution }
}

extension Catalog {
    // MARK: - Albums

    public static let dpiLow = 150.0, dpiWarn = 240.0

    public func albums() throws -> [Album] {
        try db.query("""
            SELECT a.*, (SELECT COUNT(*) FROM album_pages p WHERE p.album_id = a.id) AS n FROM albums a ORDER BY a.updated_at DESC, a.id DESC
            """).map { Album(row: $0, pageCount: $0.int("n") ?? 0) }
    }

    public func album(_ id: Int64) throws -> Album? {
        try db.first("SELECT a.*, (SELECT COUNT(*) FROM album_pages p WHERE p.album_id = a.id) AS n FROM albums a WHERE a.id = ?", [.int(id)])
            .map { Album(row: $0, pageCount: $0.int("n") ?? 0) }
    }

    /// Crée un album vide. `format` : identifiant d'un format prédéfini, ou « custom » avec des dimensions en mm.
    @discardableResult
    public func createAlbum(name: String, format: String = "a4-portrait", widthMM: Double? = nil, heightMM: Double? = nil, description: String = "") throws -> Album {
        let (f, w, h) = try resolveFormat(format, widthMM, heightMM)
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nm.isEmpty else { throw SQLiteError("L'album doit avoir un nom") }
        let now = ISODate.now
        try db.run("INSERT INTO albums(name, description, format, width_mm, height_mm, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                   [.text(nm), .text(description), .text(f), .of(w), .of(h), .text(now), .text(now)])
        let id = db.lastInsertId
        log("album", "Création de « \(nm) »")
        return try album(id)!
    }

    private func resolveFormat(_ format: String, _ w: Double?, _ h: Double?) throws -> (String, Double, Double) {
        if let f = AlbumFormat.named(format) { return (f.id, f.widthMM, f.heightMM) }
        guard let w, let h, AlbumFormat.sizeRange.contains(w), AlbumFormat.sizeRange.contains(h) else {
            throw SQLiteError("Format personnalisé : largeur et hauteur entre 50 et 1000 mm")
        }
        return ("custom", w, h)
    }

    public func updateAlbum(_ id: Int64, name: String? = nil, description: String? = nil, format: String? = nil, widthMM: Double? = nil, heightMM: Double? = nil) throws {
        try mutateAlbum(id) {
            if let name { let t = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { throw SQLiteError("L'album doit avoir un nom") }; try db.run("UPDATE albums SET name = ? WHERE id = ?", [.text(t), .int(id)]) }
            if let description { try db.run("UPDATE albums SET description = ? WHERE id = ?", [.text(description), .int(id)]) }
            if let format {
                let (f, w, h) = try resolveFormat(format, widthMM, heightMM)
                try db.run("UPDATE albums SET format = ?, width_mm = ?, height_mm = ? WHERE id = ?", [.text(f), .of(w), .of(h), .int(id)])
            }
        }
    }

    public func deleteAlbum(_ id: Int64) throws {
        try db.run("DELETE FROM albums WHERE id = ?", [.int(id)])
        albumHistory.forget(id)
        log("album", "Suppression de l'album \(id)")
    }

    @discardableResult
    public func duplicateAlbum(_ id: Int64, name: String? = nil) throws -> Album {
        guard let a = try album(id) else { throw SQLiteError("Album inconnu") }
        let copy = try createAlbum(name: name ?? a.name + " (copie)", format: a.format, widthMM: a.widthMM, heightMM: a.heightMM, description: a.description)
        for p in try pages(id) {
            try db.run("INSERT INTO album_pages(album_id, position, layout, background, data) VALUES (?, ?, ?, ?, ?)",
                       [.int(copy.id), .of(p.position), .text(p.layout), .text(p.background), .text(Catalog.encodePageData(PageData(slots: p.slots, crops: p.crops, title: p.title, caption: p.caption, style: p.style)))])
        }
        return try album(copy.id)!
    }

    // MARK: - Pages

    static func encodePageData(_ d: PageData) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return (try? String(data: e.encode(d), encoding: .utf8)) ?? "{}"
    }

    private func page(row r: Row) -> AlbumPage {
        let d = (r.string("data")?.data(using: .utf8)).flatMap { try? JSONDecoder().decode(PageData.self, from: $0) } ?? PageData()
        let layout = AlbumLayout.named(r.string("layout") ?? "") != nil ? (r.string("layout") ?? "une") : "une"
        let n = AlbumLayout.named(layout)?.frames.count ?? 0
        var slots = Array(d.slots.prefix(n)); while slots.count < n { slots.append(nil) }
        var crops = Array(d.crops.prefix(n)); while crops.count < n { crops.append(nil) }
        return AlbumPage(id: r.int64("id") ?? 0, albumId: r.int64("album_id") ?? 0, position: r.int("position") ?? 0, layout: layout,
                         background: PageStyle.hex(r.string("background"), "#ffffff"), title: d.title, caption: d.caption, slots: slots, crops: crops, style: d.style.cleaned)
    }

    public func pages(_ albumId: Int64) throws -> [AlbumPage] {
        try db.query("SELECT * FROM album_pages WHERE album_id = ? ORDER BY position", [.int(albumId)]).map { page(row: $0) }
    }

    public func albumPage(_ id: Int64) throws -> AlbumPage? {
        try db.first("SELECT * FROM album_pages WHERE id = ?", [.int(id)]).map { page(row: $0) }
    }

    /// Numérotation des pages imprimées.
    public static func folios(_ pages: [AlbumPage]) -> [Folio] {
        var f = 1
        return pages.map { p in let span = p.isSpread ? 2 : 1; defer { f += span }; return Folio(folio: f, span: span) }
    }

    private func renumber(_ albumId: Int64) throws {
        for (i, p) in try pages(albumId).enumerated() where p.position != i + 1 {
            try db.run("UPDATE album_pages SET position = ? WHERE id = ?", [.of(i + 1), .int(p.id)])
        }
    }

    private func touch(_ albumId: Int64) throws {
        try db.run("UPDATE albums SET updated_at = ? WHERE id = ?", [.text(ISODate.now), .int(albumId)])
    }

    @discardableResult
    public func addPage(_ albumId: Int64, layout: String = "quatre", at position: Int? = nil, photoIds: [Int64] = []) throws -> AlbumPage {
        guard let lay = AlbumLayout.named(layout) else { throw SQLiteError("Gabarit inconnu") }
        var out: AlbumPage!
        try mutateAlbum(albumId) {
            let count = try db.scalarInt("SELECT COUNT(*) FROM album_pages WHERE album_id = ?", [.int(albumId)])
            let pos = min(max(1, position ?? count + 1), count + 1)
            try db.run("UPDATE album_pages SET position = position + 1 WHERE album_id = ? AND position >= ?", [.int(albumId), .of(pos)])
            var data = PageData()
            data.slots = (0..<lay.frames.count).map { $0 < photoIds.count ? photoIds[$0] : nil }
            data.crops = Array(repeating: nil, count: lay.frames.count)
            try db.run("INSERT INTO album_pages(album_id, position, layout, background, data) VALUES (?, ?, ?, ?, ?)",
                       [.int(albumId), .of(pos), .text(layout), .text("#ffffff"), .text(Catalog.encodePageData(data))])
            out = try albumPage(db.lastInsertId)
        }
        return out
    }

    /// Modifie une page : gabarit, fond, textes, cadres, style. Les cadres sont adaptés au gabarit ; un cadre perd son recadrage quand sa photo change.
    @discardableResult
    public func updatePage(_ id: Int64, _ change: (inout AlbumPage) -> Void) throws -> AlbumPage {
        guard var p = try albumPage(id) else { throw SQLiteError("Page inconnue") }
        let before = p
        change(&p)
        guard AlbumLayout.named(p.layout) != nil else { throw SQLiteError("Gabarit inconnu") }
        let n = AlbumLayout.named(p.layout)!.frames.count
        while p.slots.count < n { p.slots.append(nil) }; p.slots = Array(p.slots.prefix(n))
        while p.crops.count < n { p.crops.append(nil) }; p.crops = Array(p.crops.prefix(n))
        for i in 0..<n {
            p.crops[i] = p.crops[i]?.cleaned
            if i < before.slots.count, before.slots[i] != p.slots[i], before.crops.indices.contains(i), before.crops[i] == p.crops[i] { p.crops[i] = nil }
        }
        p.background = PageStyle.hex(p.background, "#ffffff")
        p.style = p.style.cleaned
        p.title = String(p.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        p.caption = String(p.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        if p == before { return p }
        try mutateAlbum(p.albumId) {
            try db.run("UPDATE album_pages SET layout = ?, background = ?, data = ? WHERE id = ?",
                       [.text(p.layout), .text(p.background), .text(Catalog.encodePageData(PageData(slots: p.slots, crops: p.crops, title: p.title, caption: p.caption, style: p.style))), .int(id)])
        }
        return try albumPage(id)!
    }

    public func deletePage(_ id: Int64) throws {
        guard let p = try albumPage(id) else { return }
        try mutateAlbum(p.albumId) {
            try db.run("DELETE FROM album_pages WHERE id = ?", [.int(id)])
            try renumber(p.albumId)
        }
    }

    public func movePage(_ id: Int64, to position: Int) throws {
        guard let p = try albumPage(id) else { return }
        try mutateAlbum(p.albumId) {
            var ids = try pages(p.albumId).map(\.id)
            ids.removeAll { $0 == id }
            ids.insert(id, at: min(max(0, position - 1), ids.count))
            for (i, pid) in ids.enumerated() { try db.run("UPDATE album_pages SET position = ? WHERE id = ?", [.of(i + 1), .int(pid)]) }
        }
    }

    @discardableResult
    public func duplicatePage(_ id: Int64) throws -> AlbumPage {
        guard let p = try albumPage(id) else { throw SQLiteError("Page inconnue") }
        var out: AlbumPage!
        try mutateAlbum(p.albumId) {
            try db.run("UPDATE album_pages SET position = position + 1 WHERE album_id = ? AND position > ?", [.int(p.albumId), .of(p.position)])
            try db.run("INSERT INTO album_pages(album_id, position, layout, background, data) VALUES (?, ?, ?, ?, ?)",
                       [.int(p.albumId), .of(p.position + 1), .text(p.layout), .text(p.background), .text(Catalog.encodePageData(PageData(slots: p.slots, crops: p.crops, title: p.title, caption: p.caption, style: p.style)))])
            out = try albumPage(db.lastInsertId)
        }
        return out
    }

    /// Échange le contenu de deux cadres (glisser-déposer) : une seule étape annulable.
    public func swapSlots(page a: Int64, slot sa: Int, with b: Int64, slot sb: Int) throws {
        guard var pa = try albumPage(a), var pb = try albumPage(b), pa.slots.indices.contains(sa), pb.slots.indices.contains(sb) else { throw SQLiteError("Cadre inconnu") }
        try mutateAlbum(pa.albumId) {
            if a == b {
                pa.slots.swapAt(sa, sb); pa.crops.swapAt(sa, sb)
                try savePage(pa)
            } else {
                let (s, c) = (pa.slots[sa], pa.crops[sa])
                pa.slots[sa] = pb.slots[sb]; pa.crops[sa] = pb.crops[sb]
                pb.slots[sb] = s; pb.crops[sb] = c
                try savePage(pa); try savePage(pb)
            }
        }
    }

    private func savePage(_ p: AlbumPage) throws {
        try db.run("UPDATE album_pages SET layout = ?, background = ?, data = ? WHERE id = ?",
                   [.text(p.layout), .text(p.background), .text(Catalog.encodePageData(PageData(slots: p.slots, crops: p.crops, title: p.title, caption: p.caption, style: p.style))), .int(p.id)])
    }

    /// Applique un modèle graphique à une page ou à toutes les pages de l'album.
    public func applyStyle(_ preset: StylePreset, album albumId: Int64, page pageId: Int64? = nil) throws {
        try mutateAlbum(albumId) {
            for var p in try pages(albumId) where pageId == nil || p.id == pageId {
                p.background = preset.background; p.style = preset.style
                try savePage(p)
            }
        }
    }

    /// Remplit l'album avec des photos : une page par groupe de `perPage` (gabarit adapté), dans l'ordre donné.
    @discardableResult
    public func autoFill(_ albumId: Int64, photoIds: [Int64], layout: String = "quatre") throws -> [AlbumPage] {
        guard let lay = AlbumLayout.named(layout), !lay.frames.isEmpty else { throw SQLiteError("Gabarit inconnu ou sans cadre photo") }
        var out: [AlbumPage] = []
        try mutateAlbum(albumId) {
            var rest = photoIds[...]
            while !rest.isEmpty {
                let chunk = Array(rest.prefix(lay.frames.count)); rest = rest.dropFirst(chunk.count)
                // Dernière page incomplète : gabarit plus petit (aucun cadre vide).
                let l = chunk.count == lay.frames.count ? layout : AlbumLayout.fitting(chunk.count, spread: lay.spread)
                out.append(try addPage(albumId, layout: l, photoIds: chunk))
            }
        }
        return out
    }

    // MARK: - Contrôles

    /// Contrôles avant impression : photo retirée, fichier absent, résolution effective, cadres vides, doubles pages mal placées.
    public func albumChecks(_ albumId: Int64) throws -> [AlbumIssue] {
        guard let a = try album(albumId) else { return [] }
        let pgs = try pages(albumId)
        let fol = Catalog.folios(pgs)
        var issues: [AlbumIssue] = []
        for (i, p) in pgs.enumerated() {
            let n = i + 1
            if fol[i].misaligned { issues.append(AlbumIssue(page: n, slot: nil, kind: .spreadAlignment, message: "Double page sur les pages \(fol[i].folio)–\(fol[i].folio + 1) : elle devrait commencer sur une page paire (le pli couperait la photo).")) }
            let lay = AlbumLayout.named(p.layout)
            for (s, f) in p.frames.enumerated() {
                guard let pid = p.slots[s] else { issues.append(AlbumIssue(page: n, slot: s, kind: .emptyFrame, message: "Page \(n), cadre \(s + 1) : vide.")); continue }
                guard let ph = try photo(pid) else { issues.append(AlbumIssue(page: n, slot: s, kind: .missingPhoto, message: "Page \(n), cadre \(s + 1) : la photo n'est plus dans le catalogue.")); continue }
                if !fileExists(ph) { issues.append(AlbumIssue(page: n, slot: s, kind: .unavailableFile, message: "Page \(n), cadre \(s + 1) : le fichier de « \(ph.fileName) » est absent.")) }
                guard let iw = ph.width, let ih = ph.height else { continue }
                let pageW = a.widthMM * (lay?.spread == true ? 2 : 1)
                let fw = f.w * pageW, fh = f.h * a.heightMM
                let win = CropMath.window(imageW: Double(iw), imageH: Double(ih), frameW: fw, frameH: fh, crop: p.crops[s])
                let dpi = min(Double(iw) * win.width / (fw / 25.4), Double(ih) * win.height / (fh / 25.4))
                if dpi < Catalog.dpiLow { issues.append(AlbumIssue(page: n, slot: s, kind: .lowResolution, message: "Page \(n), cadre \(s + 1) : \(Int(dpi)) ppp, trop peu pour imprimer (150 ppp minimum).")) }
                else if dpi < Catalog.dpiWarn { issues.append(AlbumIssue(page: n, slot: s, kind: .warnResolution, message: "Page \(n), cadre \(s + 1) : \(Int(dpi)) ppp, limite pour l'impression (240 ppp conseillés).")) }
            }
        }
        return issues
    }

    // MARK: - Annuler / rétablir

    /// Exécute une modification de l'album : l'état précédent (album et pages) est mémorisé s'il a réellement changé.
    func mutateAlbum(_ id: Int64, _ body: () throws -> Void) throws {
        // Imbriqué (ex. remplissage automatique = plusieurs pages) : une seule étape annulable pour l'ensemble.
        if albumHistory.depth > 0 { try body(); return }
        albumHistory.depth += 1
        defer { albumHistory.depth -= 1 }
        let before = try albumSnapshot(id)
        try db.transaction { try body() }
        let after = try albumSnapshot(id)
        if after != before {
            albumHistory.push(id, before)
            try touch(id)
        }
    }

    func albumSnapshot(_ id: Int64) throws -> AlbumSnapshot {
        let a = try db.first("SELECT name, description, format, width_mm, height_mm FROM albums WHERE id = ?", [.int(id)])
        let rows = try db.query("SELECT layout, background, data FROM album_pages WHERE album_id = ? ORDER BY position", [.int(id)])
        return AlbumSnapshot(name: a?.string("name") ?? "", description: a?.string("description") ?? "", format: a?.string("format") ?? "a4-portrait",
                             width: a?.double("width_mm") ?? 210, height: a?.double("height_mm") ?? 297,
                             pages: rows.map { .init(layout: $0.string("layout") ?? "une", background: $0.string("background") ?? "#ffffff", data: $0.string("data") ?? "{}") })
    }

    private func restore(_ s: AlbumSnapshot, _ id: Int64) throws {
        try db.transaction {
            try db.run("UPDATE albums SET name = ?, description = ?, format = ?, width_mm = ?, height_mm = ?, updated_at = ? WHERE id = ?",
                       [.text(s.name), .text(s.description), .text(s.format), .of(s.width), .of(s.height), .text(ISODate.now), .int(id)])
            try db.run("DELETE FROM album_pages WHERE album_id = ?", [.int(id)])
            for (i, p) in s.pages.enumerated() {
                try db.run("INSERT INTO album_pages(album_id, position, layout, background, data) VALUES (?, ?, ?, ?, ?)",
                           [.int(id), .of(i + 1), .text(p.layout), .text(p.background), .text(p.data)])
            }
        }
    }

    public func canUndoAlbum(_ id: Int64) -> Bool { albumHistory.canUndo(id) }
    public func canRedoAlbum(_ id: Int64) -> Bool { albumHistory.canRedo(id) }

    public func undoAlbum(_ id: Int64) throws {
        guard let prev = albumHistory.popUndo(id) else { return }
        albumHistory.pushRedo(id, try albumSnapshot(id))
        try restore(prev, id)
    }

    public func redoAlbum(_ id: Int64) throws {
        guard let next = albumHistory.popRedo(id) else { return }
        albumHistory.pushUndo(id, try albumSnapshot(id))
        try restore(next, id)
    }
}

/// Photo d'un album à un instant donné (pour annuler / rétablir).
struct AlbumSnapshot: Equatable {
    struct Page: Equatable { var layout: String; var background: String; var data: String }
    var name: String, description: String, format: String, width: Double, height: Double
    var pages: [Page]
}

/// Piles d'annulation en mémoire (50 étapes par album), perdues à la fermeture : l'annulation sert pendant l'édition.
public final class AlbumHistory: @unchecked Sendable {
    static let limit = 50
    var depth = 0
    private var undo: [Int64: [AlbumSnapshot]] = [:]
    private var redo: [Int64: [AlbumSnapshot]] = [:]
    func push(_ id: Int64, _ s: AlbumSnapshot) { pushUndo(id, s); redo[id] = [] }
    func pushUndo(_ id: Int64, _ s: AlbumSnapshot) { var l = undo[id] ?? []; l.append(s); if l.count > Self.limit { l.removeFirst() }; undo[id] = l }
    func pushRedo(_ id: Int64, _ s: AlbumSnapshot) { var l = redo[id] ?? []; l.append(s); if l.count > Self.limit { l.removeFirst() }; redo[id] = l }
    func popUndo(_ id: Int64) -> AlbumSnapshot? { undo[id]?.popLast() }
    func popRedo(_ id: Int64) -> AlbumSnapshot? { redo[id]?.popLast() }
    func canUndo(_ id: Int64) -> Bool { !(undo[id] ?? []).isEmpty }
    func canRedo(_ id: Int64) -> Bool { !(redo[id] ?? []).isEmpty }
    func forget(_ id: Int64) { undo[id] = nil; redo[id] = nil }
}

extension AlbumLayout {
    /// Gabarit simple le plus adapté à `n` photos (1 à 6) pour une page incomplète.
    static func fitting(_ n: Int, spread: Bool) -> String {
        if spread { return n >= 2 ? "double-face" : "double-marges" }
        switch n { case ...1: return "une"; case 2: return "deux-cote"; case 3: return "trois"; case 4: return "quatre"; default: return "six" }
    }
}
