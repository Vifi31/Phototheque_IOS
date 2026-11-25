import Foundation

// Exports de photos : format, taille, métadonnées, filigrane, profil colorimétrique, noms de fichiers, tirages.
// Le calcul des noms, des tailles et du plan d'export est ici (testé sous Linux) ;
// le rendu des pixels (CoreImage, ImageIO) est dans l'application.

public enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case jpeg, png, heic
    public var label: String { switch self { case .jpeg: return "JPEG"; case .png: return "PNG"; case .heic: return "HEIC" } }
    public var fileExtension: String { switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic: return "heic" } }
    public var supportsQuality: Bool { self != .png }
}

public enum MetadataMode: String, Codable, CaseIterable, Sendable {
    case keepAll, withoutLocation, none
    public var label: String {
        switch self {
        case .keepAll: return "Conserver (EXIF, lieu, mots-clés)"
        case .withoutLocation: return "Retirer la position GPS"
        case .none: return "Tout retirer"
        }
    }
}

public enum WatermarkPosition: String, Codable, CaseIterable, Sendable {
    case bottomRight, bottomLeft, topRight, topLeft, center
    public var label: String {
        switch self {
        case .bottomRight: return "Bas à droite"
        case .bottomLeft: return "Bas à gauche"
        case .topRight: return "Haut à droite"
        case .topLeft: return "Haut à gauche"
        case .center: return "Au centre"
        }
    }
}

public enum ColorProfile: String, Codable, CaseIterable, Sendable {
    case sRGB, displayP3, keep
    public var label: String {
        switch self {
        case .sRGB: return "sRGB (écran, web, impression courante)"
        case .displayP3: return "Display P3 (gamut large)"
        case .keep: return "Conserver celui de l'image"
        }
    }
}

/// Dimensions d'un tirage : pixels nécessaires pour une impression nette.
public struct PrintSize: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let widthCm: Double
    public let heightCm: Double

    public static let all: [PrintSize] = [
        PrintSize(id: "10x15", label: "10 × 15 cm", widthCm: 10, heightCm: 15),
        PrintSize(id: "13x18", label: "13 × 18 cm", widthCm: 13, heightCm: 18),
        PrintSize(id: "15x21", label: "15 × 21 cm (A5)", widthCm: 15, heightCm: 21),
        PrintSize(id: "20x30", label: "20 × 30 cm", widthCm: 20, heightCm: 30),
        PrintSize(id: "21x29.7", label: "21 × 29,7 cm (A4)", widthCm: 21, heightCm: 29.7),
        PrintSize(id: "30x45", label: "30 × 45 cm", widthCm: 30, heightCm: 45),
    ]

    /// Pixels du tirage (grand côté, petit côté) à `dpi` points par pouce.
    public func pixels(dpi: Int) -> (long: Int, short: Int) {
        let l = max(widthCm, heightCm), s = min(widthCm, heightCm)
        return (Int((l / 2.54 * Double(dpi)).rounded()), Int((s / 2.54 * Double(dpi)).rounded()))
    }

    /// Définition effective (points par pouce) d'une photo de `width`×`height` imprimée à cette taille, sans recadrage.
    public func effectiveDPI(width: Int, height: Int) -> Int {
        let l = max(widthCm, heightCm) / 2.54, s = min(widthCm, heightCm) / 2.54
        let pl = Double(max(width, height)), ps = Double(min(width, height))
        return Int(min(pl / l, ps / s).rounded())
    }
}

/// Réglages d'un export.
public struct ExportOptions: Codable, Equatable, Sendable {
    public var format: ExportFormat = .jpeg
    public var quality: Double = 0.85            // 0,1 à 1
    public var maxSide: Int?                     // grand côté en pixels ; jamais d'agrandissement
    public var useEdits = true                   // version de retouche par défaut, si la photo en a une
    public var metadata: MetadataMode = .keepAll
    public var watermark: String = ""
    public var watermarkPosition: WatermarkPosition = .bottomRight
    public var watermarkOpacity: Double = 0.6
    public var profile: ColorProfile = .sRGB
    public var namePattern: String = "{nom}"     // {nom} {n} {date} {titre} {note}
    public var printSize: String?                // id d'un PrintSize : impose le grand côté pour `printDPI`
    public var printDPI: Int = 300

    public init() {}

    /// Grand côté demandé (taille de tirage prioritaire sur `maxSide`).
    public var targetLongSide: Int? {
        if let id = printSize, let p = PrintSize.all.first(where: { $0.id == id }) { return p.pixels(dpi: max(72, printDPI)).long }
        if let m = maxSide, m > 0 { return m }
        return nil
    }

    public var clamped: ExportOptions {
        var o = self
        o.quality = min(1, max(0.1, quality))
        o.watermarkOpacity = min(1, max(0.05, watermarkOpacity))
        o.printDPI = min(1200, max(72, printDPI))
        if let m = maxSide { o.maxSide = (m >= 16 && m <= 20000) ? m : nil }
        return o
    }

    /// Taille finale d'une image de `w`×`h` : le grand côté est ramené à la cible, jamais agrandi.
    public func targetSize(width w: Int, height h: Int) -> (Int, Int) {
        guard let t = targetLongSide, max(w, h) > t else { return (w, h) }
        let k = Double(t) / Double(max(w, h))
        return (max(1, Int((Double(w) * k).rounded())), max(1, Int((Double(h) * k).rounded())))
    }
}

/// Un fichier à produire.
public struct ExportJob: Identifiable, Sendable {
    public var id: Int64 { photo.id }
    public var photo: Photo
    public var fileName: String
    public var editId: Int64?
}

public enum ExportNaming {
    /// Nom de fichier d'après le modèle : {nom} {n} {date} {titre} {note}. Sûr pour tout système de fichiers.
    public static func fileName(pattern: String, photo: Photo, index: Int, ext: String) -> String {
        let base = (photo.fileName as NSString).deletingPathExtension
        let date = photo.takenAt.map { String($0.prefix(10)) } ?? "sans-date"
        var s = pattern.isEmpty ? "{nom}" : pattern
        s = s.replacingOccurrences(of: "{nom}", with: base)
            .replacingOccurrences(of: "{n}", with: String(format: "%03d", index))
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{titre}", with: photo.title.isEmpty ? base : photo.title)
            .replacingOccurrences(of: "{note}", with: String(photo.rating))
        let safe = TextFold.safeFileName(s)
        return safe + "." + ext
    }
}

extension Catalog {
    /// Plan d'export : un nom unique par photo (jamais d'écrasement, ni entre photos, ni avec un fichier déjà présent dans `dir`).
    public func exportPlan(_ ids: [Int64], options: ExportOptions, into dir: URL? = nil) throws -> [ExportJob] {
        let o = options.clamped
        var used = Set<String>()
        var jobs: [ExportJob] = []
        let target = dir ?? exportsDir
        for (i, p) in try photos(ids: ids).enumerated() {
            var name = ExportNaming.fileName(pattern: o.namePattern, photo: p, index: i + 1, ext: o.format.fileExtension)
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            var n = 2
            while used.contains(name.lowercased()) || FileManager.default.fileExists(atPath: target.appendingPathComponent(name).path) {
                name = "\(base) (\(n)).\(ext)"; n += 1
            }
            used.insert(name.lowercased())
            let edit = o.useEdits ? try defaultEdit(p.id) : nil
            jobs.append(ExportJob(photo: p, fileName: name, editId: edit.flatMap { $0.params.isNeutral ? nil : $0.id }))
        }
        return jobs
    }
}
