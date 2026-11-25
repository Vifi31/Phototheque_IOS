import Foundation

/// Rapport tabulaire (inventaire, fichiers manquants, intégrité, sauvegardes, documentation).
/// Il s'exporte en CSV ici et en PDF côté application (même tableau).
public struct ReportTable: Sendable {
    public var title: String
    public var subtitle: String
    public var headers: [String]
    public var rows: [[String]]
    public var notes: [String] = []

    /// CSV (séparateur « ; », UTF-8 avec BOM, comme le catalogue).
    public func csv() -> String {
        func cell(_ s: String) -> String { s.contains(";") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        var lines = [headers.map(cell).joined(separator: ";")]
        for r in rows { lines.append(r.map(cell).joined(separator: ";")) }
        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }
}

public enum ReportKind: String, CaseIterable, Identifiable, Sendable {
    case inventory, missingFiles, integrity, backups, documentation
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inventory: return "Inventaire des photos"
        case .missingFiles: return "Fichiers manquants"
        case .integrity: return "Intégrité de la base"
        case .backups: return "État des sauvegardes"
        case .documentation: return "Photos à documenter"
        }
    }

    public var detail: String {
        switch self {
        case .inventory: return "Toutes les photos affichées : nom, taille, format, date, appareil, mots-clés, empreinte."
        case .missingFiles: return "Fiches dont le fichier a disparu du dossier de Photothèque."
        case .integrity: return "Contrôle de la base SQLite et des références, présence des fichiers."
        case .backups: return "Archives de sauvegarde, âge de la dernière, photos non couvertes."
        case .documentation: return "Photos sans mot-clé, titre, lieu ou date de prise de vue."
        }
    }
}

extension Catalog {
    /// Nombre de jours avant lequel une sauvegarde est jugée ancienne (alerte de la version de bureau : 30 jours).
    public static let backupAlertDays = 30

    private static func human(_ bytes: Int64) -> String {
        let units = ["o", "Ko", "Mo", "Go", "To"]
        var v = Double(bytes), i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(bytes) o" : String(format: "%.1f %@", v, units[i]).replacingOccurrences(of: ".", with: ",")
    }

    public func report(_ kind: ReportKind, criteria: SearchCriteria = SearchCriteria()) throws -> ReportTable {
        let now = ISODate.string(Date())
        switch kind {
        case .inventory:
            let photos = try search(criteria, limit: 1_000_000)
            let rows = try photos.map { p -> [String] in
                let kws = try keywordsOf(p.id).map { (try? keywordPathName($0.id, separator: "/")) ?? $0.name }.joined(separator: ", ")
                return [p.fileName, p.relPath, Catalog.human(p.size), p.format, p.takenAt ?? "", p.camera, p.place, p.title, String(p.rating), kws, p.sha256]
            }
            return ReportTable(title: kind.label, subtitle: "\(photos.count) photo(s) — \(now)",
                               headers: ["Nom", "Chemin", "Taille", "Format", "Prise de vue", "Appareil", "Lieu", "Titre", "Note", "Mots-clés", "Empreinte SHA-256"], rows: rows)
        case .missingFiles:
            let missing = try missingFiles()
            return ReportTable(title: kind.label, subtitle: missing.isEmpty ? "Tous les fichiers sont présents — \(now)" : "\(missing.count) fichier(s) absent(s) — \(now)",
                               headers: ["Nom", "Chemin attendu", "Taille", "Importée le"],
                               rows: missing.map { [$0.fileName, $0.relPath, Catalog.human($0.size), $0.importedAt] },
                               notes: missing.isEmpty ? [] : ["Restaurez une sauvegarde complète pour retrouver ces fichiers : l'original importé n'est jamais supprimé de l'app Photos ou Fichiers."])
        case .integrity:
            let problems = try Schema.integrity(db)
            let missing = try missingFiles()
            var rows: [[String]] = [["Base SQLite", problems.isEmpty ? "Intègre" : problems.joined(separator: " ; ")]]
            rows.append(["Fichiers des photos", missing.isEmpty ? "Tous présents" : "\(missing.count) absent(s)"])
            rows.append(["Index plein texte (FTS5)", hasFullText ? "Actif" : "Absent (recherche par LIKE)"])
            rows.append(["Photos", String(try stats().photos)])
            return ReportTable(title: kind.label, subtitle: now, headers: ["Contrôle", "Résultat"], rows: rows)
        case .backups:
            let list = backups()
            let rows = list.map { [$0.url.lastPathComponent, ISODate.string($0.date), Catalog.human($0.size)] }
            var notes: [String] = []
            if let last = list.first?.date {
                let days = Int(Date().timeIntervalSince(last) / 86400)
                notes.append("Dernière sauvegarde il y a \(days) jour(s).")
                if days > Catalog.backupAlertDays { notes.append("⚠︎ Elle date de plus de \(Catalog.backupAlertDays) jours : faites-en une nouvelle.") }
            } else {
                notes.append("⚠︎ Aucune sauvegarde : le catalogue n'est pas protégé.")
            }
            notes.append("Une sauvegarde reste sur l'appareil : copiez-la ailleurs (iCloud Drive, ordinateur, disque) avec le bouton Partager.")
            return ReportTable(title: kind.label, subtitle: "\(list.count) archive(s) — \(now)", headers: ["Archive", "Date", "Taille"], rows: rows, notes: notes)
        case .documentation:
            let photos = try db.query("""
                SELECT * FROM photos p WHERE NOT EXISTS (SELECT 1 FROM photo_keywords pk WHERE pk.photo_id = p.id)
                  OR p.title = '' OR (p.place = '' AND p.latitude IS NULL) OR p.taken_at IS NULL ORDER BY p.id
                """).map(Photo.init(row:))
            let rows = try photos.map { p -> [String] in
                let nokw = try db.scalarInt("SELECT COUNT(*) FROM photo_keywords WHERE photo_id = ?", [.int(p.id)]) == 0
                return [p.fileName, nokw ? "oui" : "", p.title.isEmpty ? "oui" : "", p.place.isEmpty && p.latitude == nil ? "oui" : "", p.takenAt == nil ? "oui" : ""]
            }
            return ReportTable(title: kind.label, subtitle: "\(photos.count) photo(s) à compléter — \(now)",
                               headers: ["Nom", "Sans mot-clé", "Sans titre", "Sans lieu", "Sans date"], rows: rows)
        }
    }
}
