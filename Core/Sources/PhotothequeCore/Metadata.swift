import Foundation

// Métadonnées : modification en masse (aperçu, annulation), annexes XMP, photos récemment vues.

/// Modification appliquée à plusieurs photos à la fois. Seuls les champs renseignés sont changés.
public struct BulkChange: Codable, Equatable, Sendable {
    public var title: String?              // modèle : {nom} {n} {date}
    public var caption: String?
    public var place: String?
    public var rating: Int?
    public var color: Int?
    public var addKeywords: [String] = []      // chemins « Lieux/France »
    public var removeKeywords: [String] = []
    public var clearKeywords = false
    public var takenAtShiftSeconds: Int?       // décalage de la date de prise de vue (horloge d'appareil mal réglée)
    public init() {}

    public var isEmpty: Bool { self == BulkChange() }
}

/// Valeurs d'une photo avant / après une modification en masse (pour l'aperçu).
public struct BulkPreviewRow: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var fileName: String
    public var changes: [(field: String, before: String, after: String)]
    public static func == (a: BulkPreviewRow, b: BulkPreviewRow) -> Bool {
        a.id == b.id && a.fileName == b.fileName && a.changes.map { "\($0.field)|\($0.before)|\($0.after)" } == b.changes.map { "\($0.field)|\($0.before)|\($0.after)" }
    }
}

struct BulkUndoPhoto: Codable {
    var id: Int64
    var title: String, caption: String, place: String, rating: Int, color: Int, takenAt: String?
    var keywordIds: [Int64]
}

public struct MetaBatch: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var at: String
    public var summary: String
    public var undone: Bool
}

extension Catalog {
    static func expandTemplate(_ t: String, photo p: Photo, index: Int) -> String {
        let base = (p.fileName as NSString).deletingPathExtension
        return t.replacingOccurrences(of: "{nom}", with: base)
            .replacingOccurrences(of: "{n}", with: String(format: "%03d", index))
            .replacingOccurrences(of: "{date}", with: p.takenAt.map { String($0.prefix(10)) } ?? "")
    }

    private func shifted(_ iso: String?, _ seconds: Int?) -> String? {
        guard let s = seconds, s != 0, let d = ISODate.date(iso) else { return iso }
        return ISODate.string(d.addingTimeInterval(TimeInterval(s)))
    }

    /// Ce qui changerait, sans rien écrire.
    public func bulkPreview(_ ids: [Int64], _ c: BulkChange) throws -> [BulkPreviewRow] {
        var rows: [BulkPreviewRow] = []
        for (i, p) in try photos(ids: ids).enumerated() {
            var ch: [(String, String, String)] = []
            if let t = c.title { let n = Catalog.expandTemplate(t, photo: p, index: i + 1).trimmingCharacters(in: .whitespacesAndNewlines); if n != p.title { ch.append(("Titre", p.title, n)) } }
            if let t = c.caption { let n = Catalog.expandTemplate(t, photo: p, index: i + 1).trimmingCharacters(in: .whitespacesAndNewlines); if n != p.caption { ch.append(("Légende", p.caption, n)) } }
            if let pl = c.place, pl.trimmingCharacters(in: .whitespacesAndNewlines) != p.place { ch.append(("Lieu", p.place, pl.trimmingCharacters(in: .whitespacesAndNewlines))) }
            if let r = c.rating, max(0, min(5, r)) != p.rating { ch.append(("Note", String(p.rating), String(max(0, min(5, r))))) }
            if let col = c.color, max(0, min(5, col)) != p.color { ch.append(("Étiquette", ColorLabel(rawValue: p.color)?.name ?? "", ColorLabel(rawValue: max(0, min(5, col)))?.name ?? "")) }
            if let sh = c.takenAtShiftSeconds, sh != 0, let n = shifted(p.takenAt, sh) { ch.append(("Date de prise de vue", p.takenAt ?? "", n)) }
            let have = Set(try keywordsOf(p.id).map { try keywordPathName($0.id, separator: "/") })
            if c.clearKeywords && !have.isEmpty { ch.append(("Mots-clés", have.sorted().joined(separator: ", "), "(aucun)")) }
            else {
                let add = c.addKeywords.filter { k in !have.contains { TextFold.fold($0) == TextFold.fold(k) } }
                if !add.isEmpty { ch.append(("Mots-clés ajoutés", "", add.joined(separator: ", "))) }
                let rem = c.removeKeywords.filter { k in have.contains { TextFold.fold($0) == TextFold.fold(k) } }
                if !rem.isEmpty { ch.append(("Mots-clés retirés", rem.joined(separator: ", "), "")) }
            }
            if !ch.isEmpty { rows.append(BulkPreviewRow(id: p.id, fileName: p.fileName, changes: ch)) }
        }
        return rows
    }

    /// Applique la modification en une seule étape annulable (`undoBulk`). Renvoie le lot et le nombre de photos modifiées.
    @discardableResult
    public func applyBulk(_ ids: [Int64], _ c: BulkChange) throws -> (batch: Int64?, changed: Int) {
        let preview = try bulkPreview(ids, c)
        guard !preview.isEmpty else { return (nil, 0) }
        let changedIds = Set(preview.map(\.id))
        var snapshots: [BulkUndoPhoto] = []
        for p in try photos(ids: ids) where changedIds.contains(p.id) {
            snapshots.append(BulkUndoPhoto(id: p.id, title: p.title, caption: p.caption, place: p.place, rating: p.rating, color: p.color, takenAt: p.takenAt,
                                           keywordIds: try keywordsOf(p.id).map(\.id)))
        }
        var batchId: Int64 = 0
        try db.transaction {
            let order = try photos(ids: ids)
            for (i, p) in order.enumerated() where changedIds.contains(p.id) {
                if let t = c.title { try db.run("UPDATE photos SET title = ? WHERE id = ?", [.text(Catalog.expandTemplate(t, photo: p, index: i + 1).trimmingCharacters(in: .whitespacesAndNewlines)), .int(p.id)]) }
                if let t = c.caption { try db.run("UPDATE photos SET caption = ? WHERE id = ?", [.text(Catalog.expandTemplate(t, photo: p, index: i + 1).trimmingCharacters(in: .whitespacesAndNewlines)), .int(p.id)]) }
                if let pl = c.place { try db.run("UPDATE photos SET place = ? WHERE id = ?", [.text(pl.trimmingCharacters(in: .whitespacesAndNewlines)), .int(p.id)]) }
                if let r = c.rating { try db.run("UPDATE photos SET rating = ? WHERE id = ?", [.of(max(0, min(5, r))), .int(p.id)]) }
                if let col = c.color { try db.run("UPDATE photos SET color = ? WHERE id = ?", [.of(max(0, min(5, col))), .int(p.id)]) }
                if let sh = c.takenAtShiftSeconds, sh != 0 { try db.run("UPDATE photos SET taken_at = ? WHERE id = ?", [.of(shifted(p.takenAt, sh)), .int(p.id)]) }
                if c.clearKeywords { try db.run("DELETE FROM photo_keywords WHERE photo_id = ?", [.int(p.id)]) }
                for k in c.addKeywords where !k.trimmingCharacters(in: .whitespaces).isEmpty {
                    let kid = try keywordPath(k)
                    try db.run("INSERT OR IGNORE INTO photo_keywords(photo_id, keyword_id) VALUES (?, ?)", [.int(p.id), .int(kid)])
                }
                for k in c.removeKeywords {
                    for kw in try keywordsOf(p.id) where TextFold.fold((try? keywordPathName(kw.id, separator: "/")) ?? "") == TextFold.fold(k) {
                        try db.run("DELETE FROM photo_keywords WHERE photo_id = ? AND keyword_id = ?", [.int(p.id), .int(kw.id)])
                    }
                }
            }
            try refreshSearchText(Array(changedIds))
            let data = String(data: try JSONEncoder().encode(snapshots), encoding: .utf8) ?? "[]"
            try db.run("INSERT INTO meta_batches(at, summary, data) VALUES (?, ?, ?)", [.text(ISODate.now), .text("\(changedIds.count) photo(s) modifiée(s)"), .text(data)])
            batchId = db.lastInsertId
        }
        log("métadonnées", "Modification en masse : \(changedIds.count) photo(s)")
        return (batchId, changedIds.count)
    }

    public func metaBatches(limit: Int = 20) throws -> [MetaBatch] {
        try db.query("SELECT id, at, summary, undone FROM meta_batches ORDER BY id DESC LIMIT ?", [.of(limit)])
            .map { MetaBatch(id: $0.int64("id") ?? 0, at: $0.string("at") ?? "", summary: $0.string("summary") ?? "", undone: ($0.int("undone") ?? 0) == 1) }
    }

    /// Rétablit les valeurs d'avant le lot. Les photos retirées du catalogue depuis sont ignorées.
    @discardableResult
    public func undoBulk(_ batchId: Int64) throws -> Int {
        guard let r = try db.first("SELECT data, undone FROM meta_batches WHERE id = ?", [.int(batchId)]) else { throw SQLiteError("Lot inconnu") }
        guard (r.int("undone") ?? 0) == 0 else { throw SQLiteError("Ce lot est déjà annulé") }
        let snaps = (try? JSONDecoder().decode([BulkUndoPhoto].self, from: Data((r.string("data") ?? "[]").utf8))) ?? []
        var n = 0
        try db.transaction {
            for s in snaps where try photo(s.id) != nil {
                try db.run("UPDATE photos SET title = ?, caption = ?, place = ?, rating = ?, color = ?, taken_at = ? WHERE id = ?",
                           [.text(s.title), .text(s.caption), .text(s.place), .of(s.rating), .of(s.color), .of(s.takenAt), .int(s.id)])
                try db.run("DELETE FROM photo_keywords WHERE photo_id = ?", [.int(s.id)])
                for k in s.keywordIds where try keyword(k) != nil {
                    try db.run("INSERT OR IGNORE INTO photo_keywords(photo_id, keyword_id) VALUES (?, ?)", [.int(s.id), .int(k)])
                }
                n += 1
            }
            try refreshSearchText(snaps.map(\.id))
            try db.run("UPDATE meta_batches SET undone = 1 WHERE id = ?", [.int(batchId)])
        }
        log("métadonnées", "Annulation d'une modification en masse : \(n) photo(s)")
        return n
    }

    // MARK: - Photos récemment vues

    public static let recentLimit = 60

    public func noteViewed(_ id: Int64) {
        var ids = recentIds().filter { $0 != id }
        ids.insert(id, at: 0)
        try? setSetting("recent.ids", ids.prefix(Catalog.recentLimit).map(String.init).joined(separator: ","))
    }

    /// Les plus récentes d'abord ; les photos retirées du catalogue sont ignorées.
    public func recentIds() -> [Int64] {
        (setting("recent.ids") ?? "").split(separator: ",").compactMap { Int64($0) }
    }

    public func recentPhotos() throws -> [Photo] { try photos(ids: recentIds()) }
    public func clearRecents() throws { try setSetting("recent.ids", nil) }
}

// MARK: - Annexes XMP

/// Contenu lisible d'une annexe XMP.
public struct XMPInfo: Equatable, Sendable {
    public var title = ""
    public var caption = ""
    public var keywords: [String] = []        // chemins « Lieux/France/Paris »
    public var rating: Int?
    public var color: Int?
    public init() {}
}

/// Annexes XMP (« sidecar ») : titre, légende, mots-clés hiérarchiques, note et étiquette dans un fichier à part.
/// Elles sont écrites dans `Metadonnees/` (jamais à côté des originaux, jamais écrasées sans le dire).
public enum XMPSidecar {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func unesc(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
    static let labels = ["", "Red", "Yellow", "Green", "Blue", "Purple"]

    public static func build(_ info: XMPInfo) -> String {
        var s = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Photothèque iOS">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
        """
        if let r = info.rating { s += "\n            xmp:Rating=\"\(max(0, min(5, r)))\"" }
        if let c = info.color, c > 0, c < labels.count { s += "\n            xmp:Label=\"\(labels[c])\"" }
        s += ">\n"
        if !info.title.isEmpty { s += "   <dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">\(esc(info.title))</rdf:li></rdf:Alt></dc:title>\n" }
        if !info.caption.isEmpty { s += "   <dc:description><rdf:Alt><rdf:li xml:lang=\"x-default\">\(esc(info.caption))</rdf:li></rdf:Alt></dc:description>\n" }
        let flat = Array(Set(info.keywords.flatMap { $0.split(separator: "/").map(String.init) })).sorted()
        if !flat.isEmpty { s += "   <dc:subject><rdf:Bag>" + flat.map { "<rdf:li>\(esc($0))</rdf:li>" }.joined() + "</rdf:Bag></dc:subject>\n" }
        if !info.keywords.isEmpty { s += "   <lr:hierarchicalSubject><rdf:Bag>" + info.keywords.map { "<rdf:li>\(esc($0.replacingOccurrences(of: "/", with: "|")))</rdf:li>" }.joined() + "</rdf:Bag></lr:hierarchicalSubject>\n" }
        s += "  </rdf:Description>\n </rdf:RDF>\n</x:xmpmeta>\n<?xpacket end=\"w\"?>\n"
        return s
    }

    /// Lecture tolérante (annexes de Lightroom, Bridge, de la version de bureau…). Les mots-clés hiérarchiques priment sur la liste plate.
    public static func parse(_ xmp: String) -> XMPInfo {
        var info = XMPInfo()
        func items(_ tag: String) -> [String] {
            guard let a = xmp.range(of: "<\(tag)"), let b = xmp.range(of: "</\(tag)>", range: a.upperBound..<xmp.endIndex) else { return [] }
            let body = String(xmp[a.upperBound..<b.lowerBound])
            var out: [String] = []
            var rest = body[...]
            while let o = rest.range(of: "<rdf:li"), let gt = rest.range(of: ">", range: o.upperBound..<rest.endIndex),
                  let c = rest.range(of: "</rdf:li>", range: gt.upperBound..<rest.endIndex) {
                out.append(unesc(String(rest[gt.upperBound..<c.lowerBound])).trimmingCharacters(in: .whitespacesAndNewlines))
                rest = rest[c.upperBound...]
            }
            return out
        }
        func attr(_ name: String) -> String? {
            guard let a = xmp.range(of: "\(name)=\"") , let b = xmp.range(of: "\"", range: a.upperBound..<xmp.endIndex) else { return nil }
            return unesc(String(xmp[a.upperBound..<b.lowerBound]))
        }
        info.title = items("dc:title").first ?? ""
        info.caption = items("dc:description").first ?? ""
        let hier = items("lr:hierarchicalSubject").map { $0.replacingOccurrences(of: "|", with: "/") }.filter { !$0.isEmpty }
        info.keywords = hier.isEmpty ? items("dc:subject").filter { !$0.isEmpty } : hier
        if let r = attr("xmp:Rating").flatMap({ Int($0) }), r >= 0 { info.rating = min(5, r) }
        if let l = attr("xmp:Label"), let i = labels.firstIndex(where: { $0.lowercased() == l.lowercased() }), i > 0 { info.color = i }
        return info
    }
}

/// Priorité en cas de conflit entre le catalogue et l'annexe XMP.
public enum MetadataPriority: String, Codable, CaseIterable, Sendable {
    case catalog, sidecar
    public var label: String { self == .catalog ? "Le catalogue prime (l'annexe ne remplit que les vides)" : "L'annexe prime (elle remplace le catalogue)" }
}

extension Catalog {
    public var sidecarsDir: URL { root.appendingPathComponent("Metadonnees", isDirectory: true) }

    public func metadataPriority() -> MetadataPriority { MetadataPriority(rawValue: setting("metadata.priority") ?? "") ?? .catalog }
    public func setMetadataPriority(_ p: MetadataPriority) throws { try setSetting("metadata.priority", p.rawValue) }

    public func xmpInfo(for p: Photo) throws -> XMPInfo {
        var i = XMPInfo()
        i.title = p.title; i.caption = p.caption; i.rating = p.rating; i.color = p.color
        i.keywords = try keywordsOf(p.id).map { try keywordPathName($0.id, separator: "/") }.sorted()
        return i
    }

    /// Nom de l'annexe d'une photo : « empreinte-nom.xmp » (unique même si deux photos portent le même nom).
    public func sidecarURL(for p: Photo) -> URL {
        sidecarsDir.appendingPathComponent(String(p.sha256.prefix(10)) + "-" + TextFold.safeFileName((p.fileName as NSString).deletingPathExtension) + ".xmp")
    }

    /// Écrit les annexes des photos données ; renvoie les fichiers écrits.
    @discardableResult
    public func writeSidecars(_ ids: [Int64]) throws -> [URL] {
        try FileManager.default.createDirectory(at: sidecarsDir, withIntermediateDirectories: true)
        var out: [URL] = []
        for p in try photos(ids: ids) {
            let url = sidecarURL(for: p)
            try XMPSidecar.build(try xmpInfo(for: p)).write(to: url, atomically: true, encoding: .utf8)
            out.append(url)
        }
        log("xmp", "\(out.count) annexe(s) écrite(s)")
        return out
    }

    /// Lit une annexe XMP et l'applique à la photo selon la priorité réglée. Renvoie les champs modifiés.
    @discardableResult
    public func applySidecar(_ xmp: String, to photoId: Int64, priority: MetadataPriority? = nil) throws -> [String] {
        guard let p = try photo(photoId) else { throw SQLiteError("Photo inconnue") }
        let info = XMPSidecar.parse(xmp)
        let prio = priority ?? metadataPriority()
        var changed: [String] = []
        func take<T: Equatable>(_ cur: T, _ new: T?, empty: (T) -> Bool) -> T? {
            guard let new, new != cur else { return nil }
            return prio == .sidecar || empty(cur) ? new : nil
        }
        try db.transaction {
            if let t = take(p.title, info.title.isEmpty ? nil : info.title, empty: { $0.isEmpty }) { try db.run("UPDATE photos SET title = ? WHERE id = ?", [.text(t), .int(p.id)]); changed.append("titre") }
            if let t = take(p.caption, info.caption.isEmpty ? nil : info.caption, empty: { $0.isEmpty }) { try db.run("UPDATE photos SET caption = ? WHERE id = ?", [.text(t), .int(p.id)]); changed.append("légende") }
            if let r = take(p.rating, info.rating, empty: { $0 == 0 }) { try db.run("UPDATE photos SET rating = ? WHERE id = ?", [.of(r), .int(p.id)]); changed.append("note") }
            if let c = take(p.color, info.color, empty: { $0 == 0 }) { try db.run("UPDATE photos SET color = ? WHERE id = ?", [.of(c), .int(p.id)]); changed.append("étiquette") }
            var added = 0
            let have = Set(try keywordsOf(p.id).map { try keywordPathName($0.id, separator: "/") }.map(TextFold.fold))
            for k in info.keywords where !have.contains(TextFold.fold(k)) {
                let kid = try keywordPath(k)
                try db.run("INSERT OR IGNORE INTO photo_keywords(photo_id, keyword_id) VALUES (?, ?)", [.int(p.id), .int(kid)]); added += 1
            }
            if added > 0 { changed.append("mots-clés") }
            try refreshSearchText([p.id])
        }
        return changed
    }
}
