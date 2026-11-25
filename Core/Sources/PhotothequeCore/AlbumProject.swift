import Foundation

// Fichier de projet d'album (« phototheque-album », version 1) : même structure que la version de bureau
// (docs/ARCHITECTURE.md §9 du dépôt de bureau). Un album exporté ici s'ouvre sur le bureau et inversement ;
// les photos sont retrouvées par leur empreinte SHA-256 (jamais par leur identifiant ni leur chemin).

public struct ProjectAnalysis: Equatable, Sendable {
    public var name: String
    public var pages: Int
    public var frames: Int
    public var matched: Int
    public var missing: [String]       // photos de l'album absentes de ce catalogue (nom ou chemin)
    public var format: String
    public var widthMM: Double
    public var heightMM: Double
}

extension Catalog {
    public static let projectFormat = "phototheque-album"
    public static let projectVersion = 1

    /// Projet d'un album, en JSON lisible.
    public func albumProject(_ id: Int64) throws -> Data {
        guard let a = try album(id) else { throw SQLiteError("Album inconnu") }
        let pgs = try pages(id)
        var photoIds = Set<Int64>()
        for p in pgs { for s in p.slots { if let s { photoIds.insert(s) } } }
        var photos: [String: Any] = [:]
        for ph in try self.photos(ids: Array(photoIds)) {
            photos[String(ph.id)] = ["path": ph.relPath, "sha256": ph.sha256, "title": ph.title,
                                     "width": ph.width.map { $0 as Any } ?? NSNull(), "height": ph.height.map { $0 as Any } ?? NSNull()] as [String: Any]
        }
        var layouts: [String: Any] = [:]
        for l in AlbumLayout.all {
            var d: [String: Any] = ["label": l.label, "frames": l.frames.map { ["x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h] }]
            if l.fullBleed { d["fullBleed"] = true }
            if l.spread { d["spread"] = true }
            layouts[l.id] = d
        }
        let pagesJSON: [[String: Any]] = pgs.map { p in
            let slotsJSON: [Any] = p.slots.map { (id: Int64?) -> Any in if let id { return id } else { return NSNull() } }
            let cropsJSON: [Any] = p.crops.map { (c: AlbumCrop?) -> Any in
                if let c { return ["x": c.x, "y": c.y, "zoom": c.zoom] as [String: Any] } else { return NSNull() }
            }
            var d: [String: Any] = ["page": p.position, "layout": p.layout, "background": p.background, "title": p.title, "caption": p.caption,
                                    "slots": slotsJSON, "crops": cropsJSON]
            var st: [String: Any] = ["border": ["width": p.style.borderWidth, "color": p.style.borderColor], "align": p.style.align]
            if let t = p.style.textColor { st["textColor"] = t }
            d["style"] = st
            return d
        }
        let root: [String: Any] = [
            "format": Catalog.projectFormat, "formatVersion": Catalog.projectVersion, "exportedAt": ISODate.now,
            "album": ["id": a.id, "name": a.name, "description": a.description, "format": a.format, "orientation": a.orientation,
                      "width_mm": a.widthMM, "height_mm": a.heightMM, "created_at": a.createdAt, "updated_at": a.updatedAt] as [String: Any],
            "layouts": layouts, "pages": pagesJSON, "photos": photos,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private struct Parsed {
        var name: String, description: String, format: String, w: Double, h: Double
        var pages: [(layout: String, background: String, title: String, caption: String, slots: [String?], crops: [AlbumCrop?], style: PageStyle)]
        var photos: [String: (sha: String, label: String)]
    }

    private func parseProject(_ data: Data) throws -> Parsed {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["format"] as? String == Catalog.projectFormat else {
            throw SQLiteError("Ce fichier n'est pas un projet d'album Photothèque.")
        }
        guard let v = (root["formatVersion"] as? NSNumber)?.intValue, v <= Catalog.projectVersion else {
            throw SQLiteError("Ce projet vient d'une version plus récente de Photothèque : mettez l'application à jour.")
        }
        let a = root["album"] as? [String: Any] ?? [:]
        func num(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }
        var photos: [String: (String, String)] = [:]
        for (k, val) in root["photos"] as? [String: Any] ?? [:] {
            if let d = val as? [String: Any], let sha = d["sha256"] as? String { photos[k] = (sha, (d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (d["path"] as? String) ?? k) }
        }
        var pages: [(String, String, String, String, [String?], [AlbumCrop?], PageStyle)] = []
        for p in root["pages"] as? [[String: Any]] ?? [] {
            let layout = (p["layout"] as? String).flatMap { AlbumLayout.named($0) != nil ? $0 : nil } ?? "une"
            let slots: [String?] = (p["slots"] as? [Any] ?? []).map { s in (s as? NSNumber).map { String($0.int64Value) } ?? (s as? String) }
            let crops: [AlbumCrop?] = (p["crops"] as? [Any] ?? []).map { c in
                guard let d = c as? [String: Any] else { return nil }
                return AlbumCrop(x: num(d["x"]) ?? 0.5, y: num(d["y"]) ?? 0.5, zoom: num(d["zoom"]) ?? 1).cleaned
            }
            var st = PageStyle()
            if let s = p["style"] as? [String: Any] {
                let b = s["border"] as? [String: Any] ?? [:]
                st.borderWidth = num(b["width"]) ?? 0; st.borderColor = b["color"] as? String ?? "#ffffff"
                st.textColor = s["textColor"] as? String; st.align = s["align"] as? String ?? "center"
            }
            pages.append((layout, PageStyle.hex(p["background"] as? String, "#ffffff"), (p["title"] as? String) ?? "", (p["caption"] as? String) ?? "", slots, crops, st.cleaned))
        }
        return Parsed(name: (a["name"] as? String) ?? "Album importé", description: (a["description"] as? String) ?? "", format: (a["format"] as? String) ?? "custom",
                      w: num(a["width_mm"]) ?? 210, h: num(a["height_mm"]) ?? 297, pages: pages.map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6) }, photos: photos)
    }

    /// Lecture d'un projet sans rien écrire : combien de photos sont retrouvées dans ce catalogue.
    public func analyseProject(_ data: Data) throws -> ProjectAnalysis {
        let p = try parseProject(data)
        var matched = Set<String>(), missing = Set<String>(), frames = 0
        for page in p.pages { for s in page.slots { guard let s else { continue }; frames += 1
            if let ref = p.photos[s], (try photo(sha256: ref.sha)) != nil { matched.insert(s) } else { missing.insert(p.photos[s]?.label ?? s) } } }
        return ProjectAnalysis(name: p.name, pages: p.pages.count, frames: frames, matched: matched.count, missing: missing.sorted(), format: p.format, widthMM: p.w, heightMM: p.h)
    }

    /// Crée un NOUVEL album d'après le projet (jamais de remplacement d'un album existant). Photos absentes : cadres laissés vides.
    @discardableResult
    public func importProject(_ data: Data, name: String? = nil) throws -> (album: Album, analysis: ProjectAnalysis) {
        let p = try parseProject(data)
        let analysis = try analyseProject(data)
        let fmt = AlbumFormat.named(p.format) != nil ? p.format : "custom"
        let album = try createAlbum(name: (name?.isEmpty == false ? name! : p.name), format: fmt, widthMM: p.w, heightMM: p.h, description: p.description)
        for page in p.pages {
            let slots: [Int64?] = page.slots.map { s in s.flatMap { p.photos[$0] }.flatMap { try? photo(sha256: $0.sha)?.id } }
            let created = try addPage(album.id, layout: page.layout, photoIds: [])
            try updatePage(created.id) { pg in
                pg.slots = slots; pg.crops = page.crops; pg.background = page.background; pg.title = page.title; pg.caption = page.caption; pg.style = page.style
            }
        }
        albumHistory.forget(album.id)
        log("album", "Import du projet « \(album.name) » : \(analysis.matched) photo(s) retrouvée(s), \(analysis.missing.count) absente(s)")
        return (try self.album(album.id)!, analysis)
    }
}
