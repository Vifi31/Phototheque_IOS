import Foundation

// Documents PDF : planches-contact, fiches détaillées, catalogues thématiques, portfolios.
// Le plan du document (regroupements, sections, pagination, sommaire) est calculé ici et testé sous Linux ;
// l'application dessine ensuite chaque page (UIGraphicsPDFRenderer).

public enum DocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case contactSheet, detailSheets, catalog, portfolio
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .contactSheet: return "Planche-contact"
        case .detailSheets: return "Fiches détaillées"
        case .catalog: return "Catalogue thématique"
        case .portfolio: return "Portfolio"
        }
    }
    public var detail: String {
        switch self {
        case .contactSheet: return "Vignettes en grille avec légendes."
        case .detailSheets: return "Une photo par page avec toutes ses informations."
        case .catalog: return "Vignettes regroupées par année, mois, mot-clé, lieu, appareil ou note, avec sommaire."
        case .portfolio: return "Couverture, une photo par page, page de fin."
        }
    }
}

public enum DocGroupBy: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, year, month, keyword, place, camera, rating
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "Aucun regroupement"
        case .year: return "Par année"
        case .month: return "Par mois"
        case .keyword: return "Par mot-clé (premier niveau)"
        case .place: return "Par lieu"
        case .camera: return "Par appareil"
        case .rating: return "Par note"
        }
    }
}

public enum DocField: String, Codable, CaseIterable, Identifiable, Sendable {
    case name, title, date, rating, keywords, camera, place
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .name: return "Nom du fichier"
        case .title: return "Titre"
        case .date: return "Date de prise de vue"
        case .rating: return "Note"
        case .keywords: return "Mots-clés"
        case .camera: return "Appareil"
        case .place: return "Lieu"
        }
    }
}

public enum DocPageSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case a4Portrait, a4Landscape
    public var id: String { rawValue }
    public var label: String { self == .a4Portrait ? "A4 portrait" : "A4 paysage" }
    /// Points PDF (1/72 pouce).
    public var size: (w: Double, h: Double) { self == .a4Portrait ? (595.28, 841.89) : (841.89, 595.28) }
}

public struct DocumentOptions: Codable, Equatable, Sendable {
    public var kind: DocumentKind = .contactSheet
    public var title: String = ""
    public var subtitle: String = ""
    public var author: String = ""
    public var pageSize: DocPageSize = .a4Portrait
    public var columns: Int = 4
    public var rows: Int = 5
    public var fields: [DocField] = [.name]
    public var groupBy: DocGroupBy = .none
    public var toc: Bool = true
    public var cover: Bool = false
    public var useEdits: Bool = true
    public var background: String = "#ffffff"

    public init() {}

    public var clamped: DocumentOptions {
        var o = self
        o.columns = min(8, max(1, columns)); o.rows = min(10, max(1, rows))
        return o
    }
}

public struct DocSection: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var photoIds: [Int64]
}

public enum DocPage: Equatable, Sendable {
    case cover
    case toc
    case grid(section: String?, photoIds: [Int64], number: Int, of: Int)
    case detail(photoId: Int64)
    case portfolio(photoId: Int64)
    case colophon
}

public struct DocTocEntry: Equatable, Sendable { public var title: String; public var page: Int; public var count: Int }

public struct DocumentPlan: Sendable {
    public var options: DocumentOptions
    public var sections: [DocSection]
    public var pages: [DocPage]
    public var toc: [DocTocEntry]
    public var photoCount: Int
}

extension Catalog {
    /// Photos regroupées selon `by` ; les sections sont ordonnées (chronologique, puis alphabétique ; « Sans … » à la fin).
    public func docSections(_ ids: [Int64], by: DocGroupBy) throws -> [DocSection] {
        let photos = try self.photos(ids: ids)
        if by == .none { return [DocSection(title: "", photoIds: photos.map(\.id))] }
        var groups: [String: [Int64]] = [:]
        let none: String
        switch by {
        case .year, .month: none = "Sans date"
        case .keyword: none = "Sans mot-clé"
        case .place: none = "Sans lieu"
        case .camera: none = "Appareil inconnu"
        case .rating: none = "Sans note"
        case .none: none = ""
        }
        for p in photos {
            var key = none
            switch by {
            case .year: if let y = p.takenAt?.prefix(4), y.count == 4 { key = String(y) }
            case .month: if let m = p.takenAt?.prefix(7), m.count == 7 { key = String(m) }
            case .keyword:
                let roots = try keywordsOf(p.id).map { k -> String in
                    var cur = k; var guardN = 0
                    while let pid = cur.parentId, let parent = try keyword(pid), guardN < 32 { cur = parent; guardN += 1 }
                    return cur.name
                }
                if let first = roots.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }).first { key = first }
            case .place: if !p.place.isEmpty { key = p.place }
            case .camera: if !p.camera.isEmpty { key = p.camera }
            case .rating: key = p.rating > 0 ? String(repeating: "★", count: p.rating) : none
            case .none: break
            }
            groups[key, default: []].append(p.id)
        }
        var keys = groups.keys.filter { $0 != none }
        switch by {
        case .year, .month: keys.sort()
        case .rating: keys.sort { $0.count > $1.count }
        default: keys.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        if groups[none] != nil { keys.append(none) }
        return keys.map { DocSection(title: $0, photoIds: groups[$0] ?? []) }
    }

    /// Plan du document : pages dans l'ordre, sommaire avec numéros de page.
    public func documentPlan(_ ids: [Int64], options: DocumentOptions) throws -> DocumentPlan {
        let o = options.clamped
        let sections = try docSections(ids, by: o.kind == .catalog ? (o.groupBy) : (o.kind == .contactSheet ? o.groupBy : .none))
        var pages: [DocPage] = []
        var toc: [DocTocEntry] = []
        let withToc = o.toc && sections.count > 1 && (o.kind == .catalog || o.kind == .contactSheet)
        if o.cover || o.kind == .portfolio { pages.append(.cover) }
        let tocIndex = pages.count
        if withToc { pages.append(.toc) }
        let all = sections.flatMap(\.photoIds)
        switch o.kind {
        case .contactSheet, .catalog:
            let per = o.columns * o.rows
            for s in sections where !s.photoIds.isEmpty {
                let chunks = stride(from: 0, to: s.photoIds.count, by: per).map { Array(s.photoIds[$0..<min($0 + per, s.photoIds.count)]) }
                toc.append(DocTocEntry(title: s.title, page: pages.count + 1, count: s.photoIds.count))
                for (i, c) in chunks.enumerated() { pages.append(.grid(section: s.title.isEmpty ? nil : s.title, photoIds: c, number: i + 1, of: chunks.count)) }
            }
        case .detailSheets:
            for id in all { pages.append(.detail(photoId: id)) }
        case .portfolio:
            for id in all { pages.append(.portfolio(photoId: id)) }
            pages.append(.colophon)
        }
        _ = tocIndex
        return DocumentPlan(options: o, sections: sections, pages: pages, toc: toc, photoCount: all.count)
    }

    /// Lignes de légende d'une photo pour les champs demandés (sans ligne vide).
    public func docLines(_ p: Photo, fields: [DocField]) throws -> [String] {
        var out: [String] = []
        for f in fields {
            switch f {
            case .name: out.append(p.fileName)
            case .title: if !p.title.isEmpty { out.append(p.title) }
            case .date: if let d = p.takenAt { out.append(String(d.prefix(10))) }
            case .rating: if p.rating > 0 { out.append(String(repeating: "★", count: p.rating)) }
            case .keywords:
                let k = try keywordsOf(p.id).map { try keywordPathName($0.id, separator: "/") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                if !k.isEmpty { out.append(k.joined(separator: ", ")) }
            case .camera: if !p.camera.isEmpty { out.append(p.camera) }
            case .place: if !p.place.isEmpty { out.append(p.place) }
            }
        }
        return out
    }
}
