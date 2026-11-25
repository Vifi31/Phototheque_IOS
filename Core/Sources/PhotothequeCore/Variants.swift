import Foundation

// Variantes (outil Doublons) : une photo de référence et ses variantes (même scène retouchée, recadrée, réenregistrée).
// Les variantes sont masquées de la grille par défaut ; rien n'est jamais supprimé automatiquement.

extension Catalog {
    /// Désigne `reference` comme photo de référence : `variants` en deviennent des variantes (masquées par défaut).
    public func setReference(_ reference: Int64, variants: [Int64]) throws {
        guard try photo(reference) != nil else { throw SQLiteError("Photo inconnue") }
        let ids = variants.filter { $0 != reference }
        try db.transaction {
            // Une photo de référence ne peut pas elle-même être une variante.
            try db.run("UPDATE photos SET variant_of = NULL WHERE id = ?", [.int(reference)])
            for v in ids {
                // Les variantes d'une photo qui devient variante passent à la nouvelle référence (pas de chaîne).
                try db.run("UPDATE photos SET variant_of = ? WHERE variant_of = ?", [.int(reference), .int(v)])
                try db.run("UPDATE photos SET variant_of = ? WHERE id = ?", [.int(reference), .int(v)])
            }
        }
        log("variantes", "Référence \(reference) : \(ids.count) variante(s)")
    }

    /// Une photo cesse d'être une variante.
    public func clearVariant(_ id: Int64) throws {
        try db.run("UPDATE photos SET variant_of = NULL WHERE id = ?", [.int(id)])
    }

    /// Toutes les variantes d'une référence deviennent des photos ordinaires.
    public func clearVariants(of reference: Int64) throws {
        try db.run("UPDATE photos SET variant_of = NULL WHERE variant_of = ?", [.int(reference)])
    }

    public func variants(of reference: Int64) throws -> [Photo] {
        try db.query("SELECT * FROM photos WHERE variant_of = ? ORDER BY id", [.int(reference)]).map(Photo.init(row:))
    }

    /// Nombre de variantes par photo de référence.
    public func variantCounts() throws -> [Int64: Int] {
        var out: [Int64: Int] = [:]
        for r in try db.query("SELECT variant_of AS ref, COUNT(*) AS n FROM photos WHERE variant_of IS NOT NULL GROUP BY variant_of") {
            if let id = r.int64("ref") { out[id] = r.int("n") ?? 0 }
        }
        return out
    }

    /// Photos de référence et de variantes d'un même groupe (la référence en premier).
    public func variantGroup(of id: Int64) throws -> [Photo] {
        guard let p = try photo(id) else { return [] }
        let ref = p.variantOf ?? p.id
        guard let r = try photo(ref) else { return [p] }
        return [r] + (try variants(of: ref))
    }
}
