import Foundation

/// Ordre d'affichage.
public enum PhotoSort: String, Codable, CaseIterable, Sendable {
    case takenDesc, takenAsc, importedDesc, name, ratingDesc

    public var label: String {
        switch self {
        case .takenDesc: return "Plus récentes"
        case .takenAsc: return "Plus anciennes"
        case .importedDesc: return "Dernières importées"
        case .name: return "Nom de fichier"
        case .ratingDesc: return "Meilleures notes"
        }
    }

    var sql: String {
        switch self {
        case .takenDesc: return "IFNULL(p.taken_at, p.imported_at) DESC, p.id DESC"
        case .takenAsc: return "IFNULL(p.taken_at, p.imported_at) ASC, p.id ASC"
        case .importedDesc: return "p.imported_at DESC, p.id DESC"
        case .name: return "p.file_name COLLATE NOCASE ASC, p.id ASC"
        case .ratingDesc: return "p.rating DESC, IFNULL(p.taken_at, p.imported_at) DESC, p.id DESC"
        }
    }
}

/// Manques documentaires (même vocabulaire que le tableau de bord de bureau).
public enum MissingInfo: String, Codable, CaseIterable, Sendable {
    case keywords, title, place, date

    public var label: String {
        switch self {
        case .keywords: return "Sans mot-clé"
        case .title: return "Sans titre"
        case .place: return "Sans lieu"
        case .date: return "Sans date de prise de vue"
        }
    }
}

/// Orientation d'une photo (d'après ses dimensions).
public enum Orientation: String, Codable, CaseIterable, Sendable {
    case landscape, portrait, square

    public var label: String {
        switch self {
        case .landscape: return "Paysage"
        case .portrait: return "Portrait"
        case .square: return "Carré"
        }
    }
}

/// Affichage des variantes (photos désignées comme variantes d'une photo de référence, outil Doublons).
public enum VariantMode: String, Codable, CaseIterable, Sendable {
    case hide, show, only
    public var label: String { switch self { case .hide: return "Masquer les variantes"; case .show: return "Afficher les variantes"; case .only: return "Seulement les variantes" } }
}

/// Critères de recherche. Sérialisables : une recherche enregistrée est une collection dynamique.
///
/// Par défaut tous les critères doivent être remplis (ET). Avec `matchAny` (OU), une photo est retenue dès
/// qu'elle remplit au moins un des critères de filtre. Le texte saisi et la collection restent toujours exigés.
/// Plusieurs valeurs d'un même critère (années, appareils, formats, mots-clés) sont combinées par OU.
public struct SearchCriteria: Codable, Equatable, Hashable, Sendable {
    public var text: String = ""
    public var years: [Int] = []
    public var cameras: [String] = []
    public var formats: [String] = []
    public var keywordIds: [Int64] = []
    public var includeSubKeywords: Bool = true
    public var minRating: Int?
    public var color: Int?
    public var hasGPS: Bool?
    /// Vrai : au moins un mot-clé. (« Sans mot-clé » : `missing = .keywords`.)
    public var hasKeywords: Bool?
    public var missing: MissingInfo?
    public var place: String?
    public var lens: String?
    public var orientation: Orientation?
    /// Mots-clés d'une catégorie (avec ceux rangés dessous).
    public var keywordCategory: String?
    /// Vrai : photos importées depuis la dernière sauvegarde (non protégées) ; faux : déjà couvertes par une sauvegarde.
    public var uncoveredByBackup: Bool?
    /// Description en mots (« montagne neige ») : cherchée dans les étiquettes de l'IA locale.
    public var describe: String = ""
    public var variants: VariantMode = .hide
    public var collectionId: Int64?
    public var matchAny: Bool = false
    public var sort: PhotoSort = .takenDesc

    // Accès à une seule valeur (compatibilité avec la version 0.1 et les recherches déjà enregistrées).
    public var year: Int? {
        get { years.first }
        set { years = newValue.map { [$0] } ?? [] }
    }
    public var camera: String? {
        get { cameras.first }
        set { cameras = newValue.map { [$0] } ?? [] }
    }
    public var keywordId: Int64? {
        get { keywordIds.first }
        set { keywordIds = newValue.map { [$0] } ?? [] }
    }

    public init(text: String = "", year: Int? = nil, minRating: Int? = nil, color: Int? = nil, keywordId: Int64? = nil,
                includeSubKeywords: Bool = true, camera: String? = nil, hasGPS: Bool? = nil, missing: MissingInfo? = nil,
                collectionId: Int64? = nil, sort: PhotoSort = .takenDesc) {
        self.text = text; self.minRating = minRating; self.color = color
        self.includeSubKeywords = includeSubKeywords; self.hasGPS = hasGPS; self.missing = missing
        self.collectionId = collectionId; self.sort = sort
        self.year = year; self.camera = camera; self.keywordId = keywordId
    }

    private enum CodingKeys: String, CodingKey {
        case text, years, cameras, formats, keywordIds, includeSubKeywords, minRating, color, hasGPS, hasKeywords, missing
        case place, lens, orientation, collectionId, matchAny, sort
        case keywordCategory, uncoveredByBackup, describe, variants
        case year, camera, keywordId // anciens noms (une seule valeur)
    }

    /// Lecture tolérante : les recherches enregistrées par la version 0.1 (un seul an, appareil, mot-clé) restent lisibles.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        years = try c.decodeIfPresent([Int].self, forKey: .years) ?? []
        cameras = try c.decodeIfPresent([String].self, forKey: .cameras) ?? []
        formats = try c.decodeIfPresent([String].self, forKey: .formats) ?? []
        keywordIds = try c.decodeIfPresent([Int64].self, forKey: .keywordIds) ?? []
        if years.isEmpty, let y = try c.decodeIfPresent(Int.self, forKey: .year) { years = [y] }
        if cameras.isEmpty, let v = try c.decodeIfPresent(String.self, forKey: .camera) { cameras = [v] }
        if keywordIds.isEmpty, let v = try c.decodeIfPresent(Int64.self, forKey: .keywordId) { keywordIds = [v] }
        includeSubKeywords = try c.decodeIfPresent(Bool.self, forKey: .includeSubKeywords) ?? true
        minRating = try c.decodeIfPresent(Int.self, forKey: .minRating)
        color = try c.decodeIfPresent(Int.self, forKey: .color)
        hasGPS = try c.decodeIfPresent(Bool.self, forKey: .hasGPS)
        hasKeywords = try c.decodeIfPresent(Bool.self, forKey: .hasKeywords)
        missing = try c.decodeIfPresent(MissingInfo.self, forKey: .missing)
        place = try c.decodeIfPresent(String.self, forKey: .place)
        lens = try c.decodeIfPresent(String.self, forKey: .lens)
        orientation = try c.decodeIfPresent(Orientation.self, forKey: .orientation)
        keywordCategory = try c.decodeIfPresent(String.self, forKey: .keywordCategory)
        uncoveredByBackup = try c.decodeIfPresent(Bool.self, forKey: .uncoveredByBackup)
        describe = try c.decodeIfPresent(String.self, forKey: .describe) ?? ""
        variants = try c.decodeIfPresent(VariantMode.self, forKey: .variants) ?? .hide
        collectionId = try c.decodeIfPresent(Int64.self, forKey: .collectionId)
        matchAny = try c.decodeIfPresent(Bool.self, forKey: .matchAny) ?? false
        sort = try c.decodeIfPresent(PhotoSort.self, forKey: .sort) ?? .takenDesc
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(years, forKey: .years)
        try c.encode(cameras, forKey: .cameras)
        try c.encode(formats, forKey: .formats)
        try c.encode(keywordIds, forKey: .keywordIds)
        try c.encode(includeSubKeywords, forKey: .includeSubKeywords)
        try c.encodeIfPresent(minRating, forKey: .minRating)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(hasGPS, forKey: .hasGPS)
        try c.encodeIfPresent(hasKeywords, forKey: .hasKeywords)
        try c.encodeIfPresent(missing, forKey: .missing)
        try c.encodeIfPresent(place, forKey: .place)
        try c.encodeIfPresent(lens, forKey: .lens)
        try c.encodeIfPresent(orientation, forKey: .orientation)
        try c.encodeIfPresent(keywordCategory, forKey: .keywordCategory)
        try c.encodeIfPresent(uncoveredByBackup, forKey: .uncoveredByBackup)
        try c.encode(describe, forKey: .describe)
        try c.encode(variants, forKey: .variants)
        try c.encodeIfPresent(collectionId, forKey: .collectionId)
        try c.encode(matchAny, forKey: .matchAny)
        try c.encode(sort, forKey: .sort)
    }

    /// Nombre de critères de filtre actifs (hors texte, collection et tri).
    public var filterCount: Int {
        var n = 0
        if !years.isEmpty { n += 1 }
        if !cameras.isEmpty { n += 1 }
        if !formats.isEmpty { n += 1 }
        if !keywordIds.isEmpty { n += 1 }
        if let r = minRating, r > 0 { n += 1 }
        if let c = color, c > 0 { n += 1 }
        if hasGPS != nil { n += 1 }
        if hasKeywords != nil { n += 1 }
        if missing != nil { n += 1 }
        if let p = place, !p.isEmpty { n += 1 }
        if let l = lens, !l.isEmpty { n += 1 }
        if orientation != nil { n += 1 }
        if let k = keywordCategory, !k.isEmpty { n += 1 }
        if uncoveredByBackup != nil { n += 1 }
        return n
    }

    /// Vrai si aucun filtre n'est actif (le tri et le mode ET / OU ne comptent pas).
    public var isEmpty: Bool {
        var c = self; c.sort = .takenDesc; c.matchAny = false; c.variants = .hide
        return c == SearchCriteria()
    }

    public func encoded() -> String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{}"
    }

    public static func decode(_ s: String?) -> SearchCriteria? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SearchCriteria.self, from: d)
    }
}

extension Catalog {
    /// Requête FTS5 sûre : chaque mot devient un préfixe entre guillemets (jamais de syntaxe brute).
    static func ftsQuery(_ text: String) -> String? {
        let words = TextFold.tokens(text)
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }.joined(separator: " AND ")
    }

    private static func likeEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    func whereClause(_ c: SearchCriteria) -> (String, [SQLValue]) {
        // Toujours exigés (ET) : texte et collection. Critères de filtre : ET, ou OU si `matchAny`.
        var must: [String] = [], mustParams: [SQLValue] = []
        var filters: [(String, [SQLValue])] = []
        func filter(_ sql: String, _ p: [SQLValue] = []) { filters.append(("(" + sql + ")", p)) }

        if !TextFold.tokens(c.text).isEmpty {
            if hasFullText, let q = Catalog.ftsQuery(c.text) {
                must.append("p.id IN (SELECT rowid FROM photos_fts WHERE photos_fts MATCH ?)")
                mustParams.append(.text(q))
            } else {
                for w in TextFold.tokens(c.text) {
                    must.append("(' ' || p.search_text) LIKE ? ESCAPE '\\'")
                    mustParams.append(.text("% \(Catalog.likeEscaped(w))%"))
                }
            }
        }
        if !c.years.isEmpty {
            filter("substr(IFNULL(p.taken_at, ''), 1, 4) IN (\(Array(repeating: "?", count: c.years.count).joined(separator: ",")))",
                   c.years.map { .text(String(format: "%04d", $0)) })
        }
        if let r = c.minRating, r > 0 { filter("p.rating >= ?", [.of(r)]) }
        if let col = c.color, col > 0 { filter("p.color = ?", [.of(col)]) }
        if !c.keywordIds.isEmpty {
            let marks = Array(repeating: "?", count: c.keywordIds.count).joined(separator: ",")
            if c.includeSubKeywords {
                filter("""
                    p.id IN (SELECT pk.photo_id FROM photo_keywords pk WHERE pk.keyword_id IN (
                      WITH RECURSIVE sub(id) AS (SELECT id FROM keywords WHERE id IN (\(marks)) UNION SELECT kk.id FROM keywords kk JOIN sub ON kk.parent_id = sub.id) SELECT id FROM sub))
                    """, c.keywordIds.map { .int($0) })
            } else {
                filter("p.id IN (SELECT photo_id FROM photo_keywords WHERE keyword_id IN (\(marks)))", c.keywordIds.map { .int($0) })
            }
        }
        if let h = c.hasKeywords {
            filter((h ? "" : "NOT ") + "EXISTS (SELECT 1 FROM photo_keywords pk WHERE pk.photo_id = p.id)")
        }
        if !c.cameras.isEmpty {
            let one = "TRIM(p.camera_make || ' ' || p.camera_model) = ? OR p.camera_model = ?"
            filter(Array(repeating: "(" + one + ")", count: c.cameras.count).joined(separator: " OR "),
                   c.cameras.flatMap { [.text($0), .text($0)] })
        }
        if !c.formats.isEmpty {
            filter("UPPER(p.format) IN (\(Array(repeating: "?", count: c.formats.count).joined(separator: ",")))", c.formats.map { .text($0.uppercased()) })
        }
        if let l = c.lens, !l.isEmpty { filter("p.lens LIKE ? ESCAPE '\\'", [.text("%" + Catalog.likeEscaped(l) + "%")]) }
        if let pl = c.place, !pl.isEmpty { filter("p.place LIKE ? ESCAPE '\\'", [.text("%" + Catalog.likeEscaped(pl) + "%")]) }
        if let cat = c.keywordCategory, !cat.isEmpty {
            filter("""
                p.id IN (SELECT pk.photo_id FROM photo_keywords pk WHERE pk.keyword_id IN (
                  WITH RECURSIVE sub(id) AS (SELECT id FROM keywords WHERE category = ? COLLATE NOCASE UNION SELECT kk.id FROM keywords kk JOIN sub ON kk.parent_id = sub.id) SELECT id FROM sub))
                """, [.text(cat)])
        }
        if let u = c.uncoveredByBackup {
            if let last = lastBackupDate() {
                filter(u ? "p.imported_at > ?" : "p.imported_at <= ?", [.text(ISODate.string(last))])
            } else { filter(u ? "1" : "0") }      // aucune sauvegarde : toutes les photos sont non couvertes
        }
        if let o = c.orientation {
            switch o {
            case .landscape: filter("p.width > p.height")
            case .portrait: filter("p.height > p.width")
            case .square: filter("p.width = p.height")
            }
        }
        if let g = c.hasGPS {
            filter(g ? "p.latitude IS NOT NULL AND p.longitude IS NOT NULL" : "p.latitude IS NULL OR p.longitude IS NULL")
        }
        switch c.missing {
        case .keywords?: filter("NOT EXISTS (SELECT 1 FROM photo_keywords pk WHERE pk.photo_id = p.id)")
        case .title?: filter("p.title = ''")
        case .place?: filter("p.place = '' AND p.latitude IS NULL")
        case .date?: filter("p.taken_at IS NULL")
        case nil: break
        }
        switch c.variants {
        case .hide: must.append("p.variant_of IS NULL")
        case .only: must.append("p.variant_of IS NOT NULL")
        case .show: break
        }
        if !TextFold.tokens(c.describe).isEmpty {
            for w in TextFold.tokens(c.describe) {
                must.append("p.id IN (SELECT photo_id FROM ai_labels WHERE label LIKE ? ESCAPE '\\')")
                mustParams.append(.text("%" + Catalog.likeEscaped(w) + "%"))
            }
        }
        if let col = c.collectionId {
            if let coll = try? collection(col), coll.kind == .smart, let sub = coll.criteria {
                var inner = sub; inner.collectionId = nil
                let (w, p) = whereClause(inner)
                must.append("p.id IN (SELECT p.id FROM photos p WHERE \(w))")
                mustParams.append(contentsOf: p)
            } else {
                must.append("p.id IN (SELECT photo_id FROM collection_photos WHERE collection_id = ?)")
                mustParams.append(.int(col))
            }
        }
        if c.matchAny, !filters.isEmpty {
            must.append("(" + filters.map(\.0).joined(separator: " OR ") + ")")
            mustParams.append(contentsOf: filters.flatMap(\.1))
        } else {
            must.append(contentsOf: filters.map(\.0))
            mustParams.append(contentsOf: filters.flatMap(\.1))
        }
        return (must.isEmpty ? "1" : must.joined(separator: " AND "), mustParams)
    }

    public func search(_ c: SearchCriteria, limit: Int = 500, offset: Int = 0) throws -> [Photo] {
        let (w, params) = whereClause(c)
        var order = c.sort.sql
        if c.collectionId != nil, (try? collection(c.collectionId!))?.kind == .static, c.sort == .takenDesc {
            order = "(SELECT position FROM collection_photos cp WHERE cp.photo_id = p.id AND cp.collection_id = \(c.collectionId!)) ASC, " + order
        }
        return try db.query("SELECT p.* FROM photos p WHERE \(w) ORDER BY \(order) LIMIT ? OFFSET ?",
                            params + [.of(limit), .of(offset)]).map(Photo.init(row:))
    }

    public func count(_ c: SearchCriteria) throws -> Int {
        let (w, params) = whereClause(c)
        return try db.scalarInt("SELECT COUNT(*) AS n FROM photos p WHERE \(w)", params)
    }

    public func ids(_ c: SearchCriteria) throws -> [Int64] {
        let (w, params) = whereClause(c)
        return try db.query("SELECT p.id FROM photos p WHERE \(w) ORDER BY \(c.sort.sql)", params).compactMap { $0.int64("id") }
    }

    /// Années de prise de vue et nombre de photos.
    public func years() throws -> [(year: Int, count: Int)] {
        try db.query("SELECT substr(taken_at, 1, 4) AS y, COUNT(*) AS n FROM photos WHERE taken_at IS NOT NULL GROUP BY y ORDER BY y DESC")
            .compactMap { r in r.int("y").map { ($0, r.int("n") ?? 0) } }
    }

    public func cameras() throws -> [(name: String, count: Int)] {
        try db.query("""
            SELECT CASE WHEN camera_model LIKE camera_make || '%' THEN camera_model ELSE TRIM(camera_make || ' ' || camera_model) END AS cam,
                   COUNT(*) AS n FROM photos WHERE camera_model <> '' OR camera_make <> '' GROUP BY cam ORDER BY n DESC
            """).map { ($0.string("cam") ?? "", $0.int("n") ?? 0) }
    }

    /// Formats de fichier présents (JPEG, HEIC, PNG…) et nombre de photos.
    public func formats() throws -> [(name: String, count: Int)] {
        try db.query("SELECT UPPER(format) AS f, COUNT(*) AS n FROM photos WHERE format <> '' GROUP BY f ORDER BY n DESC, f ASC")
            .map { ($0.string("f") ?? "", $0.int("n") ?? 0) }
    }

    /// Objectifs présents et nombre de photos.
    public func lenses() throws -> [(name: String, count: Int)] {
        try db.query("SELECT lens AS l, COUNT(*) AS n FROM photos WHERE lens <> '' GROUP BY l ORDER BY n DESC")
            .map { ($0.string("l") ?? "", $0.int("n") ?? 0) }
    }
}
