import Foundation

// Retouche non destructive : l'original n'est jamais touché. Les réglages sont rangés dans la base
// (table `edits`, une ligne par version de retouche) ; l'image retouchée se calcule à la demande côté application.
// Mêmes réglages et mêmes bornes que la version de bureau (lib/edits.mjs).

/// Point d'une courbe de tonalité (entrée → sortie, de 0 à 255).
public struct CurvePoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// Fenêtre de recadrage en fractions de l'image (0 à 1) : origine en haut à gauche.
public struct CropRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    /// Fenêtre ramenée dans l'image, d'au moins 2 % de côté.
    public var clamped: CropRect {
        let ww = min(1, max(0.02, w)), hh = min(1, max(0.02, h))
        return CropRect(x: min(1 - ww, max(0, x)), y: min(1 - hh, max(0, y)), w: ww, h: hh)
    }
    public var isFull: Bool { x <= 0.0005 && y <= 0.0005 && w >= 0.9995 && h >= 0.9995 }
}

public enum MonoMode: String, Codable, CaseIterable, Sendable {
    case bw, sepia
    public var label: String { self == .bw ? "Noir et blanc" : "Sépia" }
}

/// Réglages d'une version de retouche.
public struct EditParams: Codable, Equatable, Hashable, Sendable {
    public static let currentVersion = 1

    public var v: Int = EditParams.currentVersion
    public var rotate: Int = 0            // 0, 90, 180, 270 (sens horaire)
    public var flipH = false
    public var flipV = false
    public var straighten: Double = 0     // degrés, -15 à 15
    public var crop: CropRect?
    public var exposure: Double = 0       // IL, -2 à 2
    public var brightness: Double = 0
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var temperature: Double = 0
    public var tint: Double = 0
    public var vibrance: Double = 0
    public var saturation: Double = 0
    public var sharpen: Double = 0        // 0 à 100
    public var noise: Double = 0          // 0 à 100
    public var colorNoise: Double = 0     // 0 à 100
    public var mono: MonoMode?
    public var curve: [CurvePoint]?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case v, rotate, flipH, flipV, straighten, crop, exposure, brightness, contrast, highlights, shadows
        case temperature, tint, vibrance, saturation, sharpen, noise, colorNoise, mono, curve
    }

    /// Lecture tolérante : une clé absente garde sa valeur neutre (versions futures, anciens enregistrements).
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? v
        rotate = try c.decodeIfPresent(Int.self, forKey: .rotate) ?? 0
        flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        crop = try c.decodeIfPresent(CropRect.self, forKey: .crop)
        mono = try c.decodeIfPresent(MonoMode.self, forKey: .mono)
        curve = try c.decodeIfPresent([CurvePoint].self, forKey: .curve)
        straighten = try c.decodeIfPresent(Double.self, forKey: .straighten) ?? 0
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        sharpen = try c.decodeIfPresent(Double.self, forKey: .sharpen) ?? 0
        noise = try c.decodeIfPresent(Double.self, forKey: .noise) ?? 0
        colorNoise = try c.decodeIfPresent(Double.self, forKey: .colorNoise) ?? 0
    }

    /// Vrai si les réglages ne changent rien à l'image.
    public var isNeutral: Bool { self.normalized() == EditParams() }

    /// Réglages bornés comme sur le bureau : valeurs arrondies à 3 décimales, rotation multiple de 90°, courbe valide.
    public func normalized() -> EditParams {
        var p = self
        func r3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
        for f in EditFields.all { p[keyPath: f.keyPath] = r3(min(f.max, max(f.min, p[keyPath: f.keyPath].isFinite ? p[keyPath: f.keyPath] : 0))) }
        p.v = EditParams.currentVersion
        p.rotate = ((Int((Double(rotate) / 90).rounded()) % 4) + 4) % 4 * 90
        if let c = crop?.clamped, !c.isFull { p.crop = CropRect(x: r3(c.x), y: r3(c.y), w: r3(c.w), h: r3(c.h)) } else { p.crop = nil }
        p.curve = CurveLUT.validPoints(curve)
        return p
    }
}

/// Description d'un curseur de réglage.
public struct EditField: Identifiable, @unchecked Sendable {
    public let id: String
    public let label: String
    public let min: Double
    public let max: Double
    public let step: Double
    public let group: String
    public let keyPath: WritableKeyPath<EditParams, Double>
}

public enum EditFields {
    public static let all: [EditField] = [
        EditField(id: "exposure", label: "Exposition (IL)", min: -2, max: 2, step: 0.05, group: "Lumière", keyPath: \.exposure),
        EditField(id: "brightness", label: "Luminosité", min: -100, max: 100, step: 1, group: "Lumière", keyPath: \.brightness),
        EditField(id: "contrast", label: "Contraste", min: -100, max: 100, step: 1, group: "Lumière", keyPath: \.contrast),
        EditField(id: "highlights", label: "Hautes lumières", min: -100, max: 100, step: 1, group: "Lumière", keyPath: \.highlights),
        EditField(id: "shadows", label: "Ombres", min: -100, max: 100, step: 1, group: "Lumière", keyPath: \.shadows),
        EditField(id: "temperature", label: "Température (froid ↔ chaud)", min: -100, max: 100, step: 1, group: "Couleur", keyPath: \.temperature),
        EditField(id: "tint", label: "Teinte (vert ↔ magenta)", min: -100, max: 100, step: 1, group: "Couleur", keyPath: \.tint),
        EditField(id: "vibrance", label: "Vibrance", min: -100, max: 100, step: 1, group: "Couleur", keyPath: \.vibrance),
        EditField(id: "saturation", label: "Saturation", min: -100, max: 100, step: 1, group: "Couleur", keyPath: \.saturation),
        EditField(id: "sharpen", label: "Netteté", min: 0, max: 100, step: 1, group: "Détail", keyPath: \.sharpen),
        EditField(id: "noise", label: "Bruit (luminance)", min: 0, max: 100, step: 1, group: "Détail", keyPath: \.noise),
        EditField(id: "colorNoise", label: "Bruit (couleur)", min: 0, max: 100, step: 1, group: "Détail", keyPath: \.colorNoise),
        EditField(id: "straighten", label: "Redressement (°)", min: -15, max: 15, step: 0.1, group: "Géométrie", keyPath: \.straighten),
    ]
    public static let groups = ["Lumière", "Couleur", "Détail", "Géométrie"]
}

/// Courbes de tonalité prédéfinies.
public enum Curves {
    public static let all: [(id: String, label: String, points: [CurvePoint]?)] = [
        ("lineaire", "Linéaire (aucune)", nil),
        ("s-doux", "S doux (contraste léger)", [CurvePoint(0, 0), CurvePoint(64, 56), CurvePoint(192, 200), CurvePoint(255, 255)]),
        ("s-fort", "S marqué", [CurvePoint(0, 0), CurvePoint(64, 44), CurvePoint(192, 212), CurvePoint(255, 255)]),
        ("fondu", "Fondu (noirs relevés)", [CurvePoint(0, 28), CurvePoint(128, 132), CurvePoint(255, 245)]),
        ("eclaircir", "Éclaircir les tons moyens", [CurvePoint(0, 0), CurvePoint(128, 158), CurvePoint(255, 255)]),
        ("assombrir", "Assombrir les tons moyens", [CurvePoint(0, 0), CurvePoint(128, 100), CurvePoint(255, 255)]),
    ]
}

/// Préréglages (« filtres ») : ils remplacent les réglages de lumière et de couleur, pas la géométrie ni le bruit.
public struct EditPreset: Identifiable, Sendable {
    public let id: String
    public let label: String
    let edit: @Sendable (inout EditParams) -> Void

    public func applying(to p: EditParams) -> EditParams {
        var q = p
        for f in EditFields.all where EditPreset.toneIds.contains(f.id) { q[keyPath: f.keyPath] = 0 }
        q.mono = nil; q.curve = nil
        edit(&q)
        return q.normalized()
    }

    static let toneIds: Set<String> = ["exposure", "brightness", "contrast", "highlights", "shadows", "temperature", "tint", "vibrance", "saturation", "sharpen"]

    public static let all: [EditPreset] = [
        EditPreset(id: "nb", label: "Noir et blanc") { $0.mono = .bw; $0.contrast = 10 },
        EditPreset(id: "nb-contraste", label: "Noir et blanc contrasté") { $0.mono = .bw; $0.contrast = 35; $0.brightness = -5 },
        EditPreset(id: "sepia", label: "Sépia") { $0.mono = .sepia; $0.contrast = 5 },
        EditPreset(id: "chaud", label: "Chaud") { $0.temperature = 30; $0.saturation = 10 },
        EditPreset(id: "froid", label: "Froid") { $0.temperature = -30 },
        EditPreset(id: "vif", label: "Couleurs vives") { $0.vibrance = 35; $0.saturation = 10; $0.contrast = 15 },
        EditPreset(id: "doux", label: "Doux") { $0.contrast = -20; $0.brightness = 8; $0.saturation = -10 },
        EditPreset(id: "film", label: "Film (fondu)") { $0.curve = Curves.all[3].points; $0.vibrance = -10; $0.temperature = 8 },
        EditPreset(id: "hdr", label: "Détails dans les ombres") { $0.shadows = 45; $0.highlights = -35; $0.vibrance = 15 },
    ]
}

/// Table de correspondance 256 valeurs d'une courbe de tonalité (interpolation monotone, Fritsch-Carlson).
public enum CurveLUT {
    /// Points triés, bornés à 0…255, sans doublon d'abscisse ; au moins 2 points sinon `nil` (courbe linéaire).
    public static func validPoints(_ pts: [CurvePoint]?) -> [CurvePoint]? {
        guard let pts, pts.count >= 2 else { return nil }
        var seen = Set<Int>()
        let clean = pts.map { CurvePoint(min(255, max(0, $0.x.rounded())), min(255, max(0, $0.y.rounded()))) }
            .sorted { $0.x < $1.x }
            .filter { seen.insert(Int($0.x)).inserted }
        guard clean.count >= 2 else { return nil }
        if clean.count == 2, clean[0] == CurvePoint(0, 0), clean[1] == CurvePoint(255, 255) { return nil }
        return clean
    }

    public static func make(_ pts: [CurvePoint]?) -> [UInt8] {
        guard let p = validPoints(pts) else { return (0...255).map { UInt8($0) } }
        let n = p.count
        let xs = p.map(\.x), ys = p.map(\.y)
        var d = [Double](repeating: 0, count: n - 1), m = [Double](repeating: 0, count: n)
        for i in 0..<(n - 1) { d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) }
        m[0] = d[0]; m[n - 1] = d[n - 2]
        if n > 2 { for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 } }
        for i in 0..<(n - 1) {
            if d[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
            let a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b
            if s > 9 { let t = 3 / s.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
        }
        return (0...255).map { xi in
            let x = Double(xi)
            if x <= xs[0] { return UInt8(min(255, max(0, ys[0].rounded()))) }
            if x >= xs[n - 1] { return UInt8(min(255, max(0, ys[n - 1].rounded()))) }
            var k = 0
            while k < n - 2 && x > xs[k + 1] { k += 1 }
            let h = xs[k + 1] - xs[k], t = (x - xs[k]) / h
            let t2 = t * t, t3 = t2 * t
            let v = (2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h * m[k] + (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h * m[k + 1]
            return UInt8(min(255, max(0, v.rounded())))
        }
    }
}

/// Géométrie de sortie d'une retouche : rotation, retournements, recadrage.
public enum EditGeometry {
    /// Taille de l'image après rotation par pas de 90°, avant recadrage.
    public static func rotatedSize(_ w: Int, _ h: Int, rotate: Int) -> (Int, Int) {
        rotate % 180 == 0 ? (w, h) : (h, w)
    }

    /// Taille finale (pixels) : rotation, puis recadrage.
    public static func outputSize(width: Int, height: Int, params p: EditParams) -> (Int, Int) {
        let (rw, rh) = rotatedSize(width, height, rotate: p.rotate)
        guard let c = p.crop?.clamped else { return (rw, rh) }
        return (max(1, Int((Double(rw) * c.w).rounded())), max(1, Int((Double(rh) * c.h).rounded())))
    }
}

// MARK: - Versions de retouche en base

public struct EditVersion: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var photoId: Int64
    public var name: String
    public var params: EditParams
    public var isDefault: Bool
    public var createdAt: String
    public var updatedAt: String
    public var canUndo: Bool
    public var canRedo: Bool

    init(row r: Row) {
        id = r.int64("id") ?? 0
        photoId = r.int64("photo_id") ?? 0
        name = r.string("name") ?? ""
        params = EditCodec.decode(r.string("params"))
        isDefault = (r.int("is_default") ?? 0) == 1
        createdAt = r.string("created_at") ?? ""
        updatedAt = r.string("updated_at") ?? ""
        let h = EditCodec.history(r.string("history"))
        canUndo = !h.past.isEmpty
        canRedo = !h.future.isEmpty
    }
}

enum EditCodec {
    struct History: Codable { var past: [EditParams] = []; var future: [EditParams] = [] }
    static let maxHistory = 50

    static func encode(_ p: EditParams) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return (try? String(data: e.encode(p.normalized()), encoding: .utf8)) ?? "{}"
    }
    static func decode(_ s: String?) -> EditParams {
        guard let d = s?.data(using: .utf8), let p = try? JSONDecoder().decode(EditParams.self, from: d) else { return EditParams() }
        return p.normalized()
    }
    static func history(_ s: String?) -> History {
        guard let d = s?.data(using: .utf8), let h = try? JSONDecoder().decode(History.self, from: d) else { return History() }
        return h
    }
    static func encode(_ h: History) -> String {
        (try? String(data: JSONEncoder().encode(h), encoding: .utf8)) ?? "{}"
    }
}

extension Catalog {
    public func editVersions(_ photoId: Int64) throws -> [EditVersion] {
        try db.query("SELECT * FROM edits WHERE photo_id = ? ORDER BY id", [.int(photoId)]).map(EditVersion.init(row:))
    }

    public func editVersion(_ id: Int64) throws -> EditVersion? {
        try db.first("SELECT * FROM edits WHERE id = ?", [.int(id)]).map(EditVersion.init(row:))
    }

    /// Version de retouche utilisée par défaut (grille, visionneuse, exports, albums) ; `nil` : l'original.
    public func defaultEdit(_ photoId: Int64) throws -> EditVersion? {
        try db.first("SELECT * FROM edits WHERE photo_id = ? AND is_default = 1 ORDER BY id LIMIT 1", [.int(photoId)]).map(EditVersion.init(row:))
    }

    /// Photos qui ont au moins une version de retouche, avec leur nombre de versions.
    public func editCounts() throws -> [Int64: Int] {
        var out: [Int64: Int] = [:]
        for r in try db.query("SELECT photo_id, COUNT(*) AS n FROM edits GROUP BY photo_id") {
            if let id = r.int64("photo_id") { out[id] = r.int("n") ?? 0 }
        }
        return out
    }

    /// Crée une version (neutre, ou copie de `from`). La première version d'une photo devient la version par défaut.
    @discardableResult
    public func createEdit(photoId: Int64, name: String? = nil, from: Int64? = nil, params: EditParams? = nil) throws -> EditVersion {
        guard try photo(photoId) != nil else { throw SQLiteError("Photo inconnue") }
        let existing = try editVersions(photoId)
        var p = params ?? EditParams()
        if let from, let src = existing.first(where: { $0.id == from }) { p = src.params }
        let nm = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Version \(existing.count + 1)"
        let now = ISODate.now
        try db.run("INSERT INTO edits(photo_id, name, params, is_default, created_at, updated_at, history) VALUES (?, ?, ?, ?, ?, ?, ?)",
                   [.int(photoId), .text(nm), .text(EditCodec.encode(p)), .of(existing.isEmpty ? 1 : 0), .text(now), .text(now), .text(EditCodec.encode(EditCodec.History()))])
        let id = db.lastInsertId
        log("retouche", "\(nm) (photo \(photoId))")
        return try editVersion(id)!
    }

    /// Enregistre de nouveaux réglages : l'état précédent est gardé pour « annuler ».
    @discardableResult
    public func updateEdit(_ id: Int64, params: EditParams) throws -> EditVersion {
        guard let cur = try editVersion(id) else { throw SQLiteError("Version de retouche inconnue") }
        let new = params.normalized()
        if new == cur.params { return cur }
        var h = EditCodec.history(try db.first("SELECT history FROM edits WHERE id = ?", [.int(id)])?.string("history"))
        h.past.append(cur.params); if h.past.count > EditCodec.maxHistory { h.past.removeFirst(h.past.count - EditCodec.maxHistory) }
        h.future = []
        try db.run("UPDATE edits SET params = ?, history = ?, updated_at = ? WHERE id = ?",
                   [.text(EditCodec.encode(new)), .text(EditCodec.encode(h)), .text(ISODate.now), .int(id)])
        return try editVersion(id)!
    }

    @discardableResult
    public func undoEdit(_ id: Int64) throws -> EditVersion {
        guard let cur = try editVersion(id) else { throw SQLiteError("Version de retouche inconnue") }
        var h = EditCodec.history(try db.first("SELECT history FROM edits WHERE id = ?", [.int(id)])?.string("history"))
        guard let prev = h.past.popLast() else { return cur }
        h.future.append(cur.params)
        try db.run("UPDATE edits SET params = ?, history = ?, updated_at = ? WHERE id = ?",
                   [.text(EditCodec.encode(prev)), .text(EditCodec.encode(h)), .text(ISODate.now), .int(id)])
        return try editVersion(id)!
    }

    @discardableResult
    public func redoEdit(_ id: Int64) throws -> EditVersion {
        guard let cur = try editVersion(id) else { throw SQLiteError("Version de retouche inconnue") }
        var h = EditCodec.history(try db.first("SELECT history FROM edits WHERE id = ?", [.int(id)])?.string("history"))
        guard let next = h.future.popLast() else { return cur }
        h.past.append(cur.params)
        try db.run("UPDATE edits SET params = ?, history = ?, updated_at = ? WHERE id = ?",
                   [.text(EditCodec.encode(next)), .text(EditCodec.encode(h)), .text(ISODate.now), .int(id)])
        return try editVersion(id)!
    }

    /// Remet tous les réglages à zéro (annulable).
    @discardableResult
    public func resetEdit(_ id: Int64) throws -> EditVersion { try updateEdit(id, params: EditParams()) }

    public func renameEdit(_ id: Int64, _ name: String) throws {
        let t = name.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { throw SQLiteError("Le nom ne peut pas être vide") }
        try db.run("UPDATE edits SET name = ? WHERE id = ?", [.text(t), .int(id)])
    }

    public func setDefaultEdit(_ id: Int64) throws {
        guard let v = try editVersion(id) else { return }
        try db.transaction {
            try db.run("UPDATE edits SET is_default = 0 WHERE photo_id = ?", [.int(v.photoId)])
            try db.run("UPDATE edits SET is_default = 1 WHERE id = ?", [.int(id)])
        }
    }

    /// Supprime une version ; si c'était la version par défaut, la plus ancienne restante la remplace.
    public func deleteEdit(_ id: Int64) throws {
        guard let v = try editVersion(id) else { return }
        try db.transaction {
            try db.run("DELETE FROM edits WHERE id = ?", [.int(id)])
            if v.isDefault, let next = try db.first("SELECT id FROM edits WHERE photo_id = ? ORDER BY id LIMIT 1", [.int(v.photoId)])?.int64("id") {
                try db.run("UPDATE edits SET is_default = 1 WHERE id = ?", [.int(next)])
            }
        }
    }
}

extension Catalog {
    /// Versions de retouche par défaut qui changent vraiment l'image (réglages non neutres), par identifiant de photo.
    /// La grille, la visionneuse, les exports et les albums affichent cette version plutôt que l'original.
    public func defaultEdits() throws -> [Int64: EditVersion] {
        var out: [Int64: EditVersion] = [:]
        for r in try db.query("SELECT * FROM edits WHERE is_default = 1") {
            let v = EditVersion(row: r)
            if !v.params.isNeutral { out[v.photoId] = v }
        }
        return out
    }
}
