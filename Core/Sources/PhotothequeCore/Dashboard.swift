import Foundation

/// Une barre d'un graphique : libellé, nombre de photos, volume.
public struct DistributionItem: Identifiable, Hashable, Sendable {
    public var label: String
    public var count: Int
    public var bytes: Int64
    public var id: String { label }
}

/// Un manque documentaire : nombre de photos concernées (`missing` : critère de recherche correspondant, s'il existe).
public struct GapItem: Identifiable, Hashable, Sendable {
    public var label: String
    public var count: Int
    public var missing: MissingInfo?
    public var noGPS: Bool = false
    public var unrated: Bool = false
    public var id: String { label }
}

/// Tableau de bord : chiffres, répartitions, manques et volumes (même rubriques que la version de bureau).
public struct Dashboard: Sendable {
    public var photos = 0
    public var bytes: Int64 = 0
    public var keywords = 0
    public var collections = 0
    public var byYear: [DistributionItem] = []
    public var byMonth: [DistributionItem] = []
    public var byFormat: [DistributionItem] = []
    public var byCamera: [DistributionItem] = []
    public var byLens: [DistributionItem] = []
    public var byRating: [DistributionItem] = []
    public var byColor: [DistributionItem] = []
    public var byOrientation: [DistributionItem] = []
    public var gaps: [GapItem] = []
    public var largest: [Photo] = []

    /// Le tableau de bord sous forme de rapport tabulaire (CSV, PDF).
    public func table(title: String = "Tableau de bord", subtitle: String = "") -> ReportTable {
        var rows: [[String]] = [["Total", "Photos", String(photos), Dashboard.human(bytes)]]
        func add(_ name: String, _ items: [DistributionItem]) { for i in items { rows.append([name, i.label, String(i.count), Dashboard.human(i.bytes)]) } }
        add("Année", byYear); add("Mois", byMonth); add("Format", byFormat); add("Appareil", byCamera); add("Objectif", byLens)
        add("Note", byRating); add("Étiquette", byColor); add("Orientation", byOrientation)
        for g in gaps { rows.append(["Manque", g.label, String(g.count), ""]) }
        return ReportTable(title: title, subtitle: subtitle.isEmpty ? "\(photos) photo(s) — \(Dashboard.human(bytes))" : subtitle, headers: ["Rubrique", "Libellé", "Photos", "Volume"], rows: rows)
    }

    static func human(_ b: Int64) -> String {
        let units = ["o", "Ko", "Mo", "Go", "To"]
        var v = Double(b), i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(b) o" : String(format: "%.1f %@", v, units[i]).replacingOccurrences(of: ".", with: ",")
    }

    /// Tableau CSV (séparateur « ; », UTF-8 avec BOM) : une ligne par barre de chaque rubrique.
    public func csv() -> String {
        var rows = ["Rubrique;Libellé;Photos;Octets"]
        func cell(_ s: String) -> String { s.contains(";") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        func add(_ name: String, _ items: [DistributionItem]) { for i in items { rows.append("\(name);\(cell(i.label));\(i.count);\(i.bytes)") } }
        rows.append("Total;Photos;\(photos);\(bytes)")
        add("Année", byYear); add("Mois", byMonth); add("Format", byFormat); add("Appareil", byCamera); add("Objectif", byLens)
        add("Note", byRating); add("Étiquette", byColor); add("Orientation", byOrientation)
        for g in gaps { rows.append("Manque;\(cell(g.label));\(g.count);") }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }
}

extension Catalog {
    private func distribution(_ expr: String, _ w: String, _ params: [SQLValue], order: String = "n DESC", limit: Int = 100) throws -> [DistributionItem] {
        try db.query("SELECT \(expr) AS k, COUNT(*) AS n, IFNULL(SUM(p.size), 0) AS b FROM photos p WHERE \(w) GROUP BY k ORDER BY \(order) LIMIT ?",
                     params + [.of(limit)]).map { DistributionItem(label: $0.string("k") ?? "", count: $0.int("n") ?? 0, bytes: $0.int64("b") ?? 0) }
    }

    /// Tableau de bord des photos qui répondent aux critères (toute la photothèque par défaut).
    public func dashboard(_ criteria: SearchCriteria = SearchCriteria()) throws -> Dashboard {
        var c = criteria; c.sort = .takenDesc
        let (w, p) = whereClause(c)
        var d = Dashboard()
        let tot = try db.first("SELECT COUNT(*) AS n, IFNULL(SUM(p.size), 0) AS b FROM photos p WHERE \(w)", p)
        d.photos = tot?.int("n") ?? 0
        d.bytes = tot?.int64("b") ?? 0
        d.keywords = try db.scalarInt("SELECT COUNT(*) FROM keywords")
        d.collections = try db.scalarInt("SELECT COUNT(*) FROM collections")
        d.byYear = try distribution("IFNULL(NULLIF(substr(p.taken_at, 1, 4), ''), 'Sans date')", w, p, order: "k ASC")
        let months = try distribution("substr(p.taken_at, 1, 7)", "(\(w)) AND p.taken_at IS NOT NULL", p, order: "k DESC", limit: 36)
        d.byMonth = months.reversed()
        d.byFormat = try distribution("IFNULL(NULLIF(UPPER(p.format), ''), 'Inconnu')", w, p)
        d.byCamera = try distribution("CASE WHEN p.camera_model = '' AND p.camera_make = '' THEN 'Inconnu' WHEN p.camera_model LIKE p.camera_make || '%' THEN p.camera_model ELSE TRIM(p.camera_make || ' ' || p.camera_model) END", w, p, limit: 12)
        d.byLens = try distribution("IFNULL(NULLIF(p.lens, ''), 'Inconnu')", w, p, limit: 12)
        let rated = try distribution("p.rating", w, p, order: "k ASC")
        d.byRating = rated.map { DistributionItem(label: $0.label == "0" ? "Sans note" : String(repeating: "★", count: Int($0.label) ?? 0), count: $0.count, bytes: $0.bytes) }
        let colors = try distribution("p.color", w, p, order: "k ASC")
        d.byColor = colors.map { DistributionItem(label: ColorLabel(rawValue: Int($0.label) ?? 0)?.name ?? $0.label, count: $0.count, bytes: $0.bytes) }
        d.byOrientation = try distribution("CASE WHEN p.width IS NULL OR p.height IS NULL THEN 'Inconnue' WHEN p.width > p.height THEN 'Paysage' WHEN p.height > p.width THEN 'Portrait' ELSE 'Carré' END", w, p)
        func gap(_ label: String, _ cond: String, missing: MissingInfo? = nil, noGPS: Bool = false, unrated: Bool = false) throws {
            let n = try db.scalarInt("SELECT COUNT(*) FROM photos p WHERE (\(w)) AND (\(cond))", p)
            d.gaps.append(GapItem(label: label, count: n, missing: missing, noGPS: noGPS, unrated: unrated))
        }
        try gap("Sans mot-clé", "NOT EXISTS (SELECT 1 FROM photo_keywords pk WHERE pk.photo_id = p.id)", missing: .keywords)
        try gap("Sans titre", "p.title = ''", missing: .title)
        try gap("Sans lieu", "p.place = '' AND p.latitude IS NULL", missing: .place)
        try gap("Sans date de prise de vue", "p.taken_at IS NULL", missing: .date)
        try gap("Sans position GPS", "p.latitude IS NULL OR p.longitude IS NULL", noGPS: true)
        try gap("Sans note", "p.rating = 0", unrated: true)
        d.largest = try db.query("SELECT p.* FROM photos p WHERE \(w) ORDER BY p.size DESC LIMIT 10", p).map(Photo.init(row:))
        return d
    }
}
