import Foundation
import XCTest
@testable import PhotothequeCore

final class AlbumLayoutTests: XCTestCase {
    func testLayoutsMatchDesktop() {
        XCTAssertEqual(AlbumLayout.all.map(\.id), ["titre", "plein", "une", "deux-cote", "deux-pile", "trois", "quatre", "six",
                                                   "double-plein", "double-marges", "double-face", "double-bandeau"])
        XCTAssertEqual(AlbumLayout.named("quatre")?.frames.count, 4)
        XCTAssertEqual(AlbumLayout.named("six")?.frames.count, 6)
        XCTAssertEqual(AlbumLayout.named("trois")?.frames.count, 3)
        XCTAssertEqual(AlbumLayout.named("double-bandeau")?.frames.count, 5)
        XCTAssertEqual(AlbumLayout.named("titre")?.frames.count, 0)
        XCTAssertEqual(AlbumLayout.all.filter(\.spread).count, 4)
        // Valeurs de la version de bureau (marge 6 %, gouttière 3 %, légende 6 %).
        XCTAssertEqual(AlbumLayout.named("une")?.frames, [FrameRect(0.06, 0.06, 0.88, 0.82)])
        XCTAssertEqual(AlbumLayout.named("deux-cote")?.frames, [FrameRect(0.06, 0.06, 0.425, 0.82), FrameRect(0.515, 0.06, 0.425, 0.82)])
        XCTAssertEqual(AlbumLayout.named("plein")?.fullBleed, true)
        XCTAssertEqual(AlbumLayout.named("double-marges")?.frames, [FrameRect(0.03, 0.06, 0.94, 0.82)])
        // Aucun cadre ne sort de la page ni ne chevauche un autre.
        for l in AlbumLayout.all {
            for f in l.frames { XCTAssertTrue(f.x >= 0 && f.y >= 0 && f.x + f.w <= 1.0001 && f.y + f.h <= 1.0001, l.id) }
            for i in l.frames.indices { for j in l.frames.indices where j > i {
                let a = l.frames[i], b = l.frames[j]
                XCTAssertFalse(a.x < b.x + b.w - 0.0001 && b.x < a.x + a.w - 0.0001 && a.y < b.y + b.h - 0.0001 && b.y < a.y + a.h - 0.0001, "\(l.id) : cadres \(i) et \(j)")
            } }
        }
    }

    func testFormatsAndStyle() {
        XCTAssertEqual(AlbumFormat.all.count, 6)
        XCTAssertEqual(AlbumFormat.named("a4-paysage")?.widthMM, 297)
        XCTAssertNil(AlbumFormat.named("custom"))
        var s = PageStyle(); s.borderWidth = 99; s.borderColor = "rouge"; s.textColor = "#ABCDEF"; s.align = "haut"
        let c = s.cleaned
        XCTAssertEqual(c.borderWidth, 10); XCTAssertEqual(c.borderColor, "#ffffff"); XCTAssertEqual(c.textColor, "#abcdef"); XCTAssertEqual(c.align, "center")
        s.textColor = "pas une couleur"
        XCTAssertNil(s.cleaned.textColor)
        XCTAssertEqual(StylePreset.all.count, 5)
        XCTAssertEqual(StylePreset.all.first { $0.id == "nuit" }?.background, "#141414")
    }

    func testCropWindowMatchesDesktop() {
        // Image 4000×3000 dans un cadre carré : on voit les 3/4 de la largeur, centrés.
        let w = CropMath.window(imageW: 4000, imageH: 3000, frameW: 100, frameH: 100, crop: nil)
        XCTAssertEqual(w.width, 0.75, accuracy: 1e-9); XCTAssertEqual(w.height, 1, accuracy: 1e-9)
        XCTAssertEqual(w.left, 0.125, accuracy: 1e-9); XCTAssertEqual(w.top, 0, accuracy: 1e-9)
        // Zoom 2 centré sur le coin : le centre est ramené dans l'image (jamais de vide).
        let z = CropMath.window(imageW: 4000, imageH: 3000, frameW: 100, frameH: 100, crop: AlbumCrop(x: 0, y: 0, zoom: 2))
        XCTAssertEqual(z.left, 0, accuracy: 1e-9); XCTAssertEqual(z.top, 0, accuracy: 1e-9)
        XCTAssertEqual(z.width, 0.375, accuracy: 1e-9); XCTAssertEqual(z.height, 0.5, accuracy: 1e-9)
        XCTAssertNil(AlbumCrop(x: 0.5, y: 0.5, zoom: 1).cleaned)
        XCTAssertEqual(AlbumCrop(x: 7, y: -1, zoom: 99).cleaned, AlbumCrop(x: 1, y: 0, zoom: 5))
    }
}

final class AlbumTests: CatalogTestCase {
    func photos(_ n: Int, width: Int = 3000, height: Int = 2000) throws -> [Photo] {
        try (0..<n).map { try add("p\($0).jpg", "contenu \($0)", PhotoMetadata(width: width, height: height, format: "JPEG")) }
    }

    func testAlbumsCrud() throws {
        let a = try cat.createAlbum(name: "  Vacances  ", format: "carre-30")
        XCTAssertEqual(a.name, "Vacances"); XCTAssertEqual(a.widthMM, 300); XCTAssertEqual(a.orientation, "square")
        XCTAssertThrowsError(try cat.createAlbum(name: "  "))
        XCTAssertThrowsError(try cat.createAlbum(name: "x", format: "custom"), "dimensions obligatoires")
        XCTAssertThrowsError(try cat.createAlbum(name: "x", format: "custom", widthMM: 10, heightMM: 300))
        let c = try cat.createAlbum(name: "Perso", format: "custom", widthMM: 250, heightMM: 180)
        XCTAssertEqual(c.format, "custom"); XCTAssertEqual(c.orientation, "landscape")
        try cat.updateAlbum(a.id, name: "Été", description: "Corse", format: "a4-paysage")
        let u = try cat.album(a.id)!
        XCTAssertEqual(u.name, "Été"); XCTAssertEqual(u.widthMM, 297); XCTAssertEqual(u.description, "Corse")
        XCTAssertEqual(try cat.albums().count, 2)
        try cat.deleteAlbum(c.id)
        XCTAssertEqual(try cat.albums().map(\.name), ["Été"])
    }

    func testPagesAndSlots() throws {
        let ph = try photos(4)
        let a = try cat.createAlbum(name: "A")
        let p1 = try cat.addPage(a.id, layout: "quatre", photoIds: ph.map(\.id))
        XCTAssertEqual(p1.slots, ph.map { Optional($0.id) })
        XCTAssertEqual(p1.crops.count, 4)
        let p2 = try cat.addPage(a.id, layout: "une")
        XCTAssertEqual(p2.slots, [nil])
        let p0 = try cat.addPage(a.id, layout: "titre", at: 1)
        XCTAssertEqual(try cat.pages(a.id).map(\.layout), ["titre", "quatre", "une"])
        XCTAssertEqual(try cat.pages(a.id).map(\.position), [1, 2, 3])
        XCTAssertThrowsError(try cat.addPage(a.id, layout: "inconnu"))
        // Changer de gabarit adapte les cadres (les photos en trop sont retirées de la page, pas du catalogue).
        let q = try cat.updatePage(p1.id) { $0.layout = "deux-cote" }
        XCTAssertEqual(q.slots, [ph[0].id, ph[1].id])
        let r = try cat.updatePage(p1.id) { $0.layout = "six" }
        XCTAssertEqual(r.slots.count, 6)
        XCTAssertEqual(r.slots.prefix(2).compactMap { $0 }, [ph[0].id, ph[1].id])
        // Un cadre perd son recadrage quand sa photo change.
        _ = try cat.updatePage(p2.id) { $0.slots = [ph[0].id]; $0.crops = [AlbumCrop(x: 0.2, y: 0.3, zoom: 2)] }
        XCTAssertEqual(try cat.albumPage(p2.id)?.crops[0], AlbumCrop(x: 0.2, y: 0.3, zoom: 2))
        _ = try cat.updatePage(p2.id) { $0.slots = [ph[1].id] }
        XCTAssertNil(try cat.albumPage(p2.id)?.crops[0])
        // Textes et style nettoyés.
        let t = try cat.updatePage(p0.id) { $0.title = "  Titre  "; $0.background = "bleu"; $0.style.borderWidth = 50 }
        XCTAssertEqual(t.title, "Titre"); XCTAssertEqual(t.background, "#ffffff"); XCTAssertEqual(t.style.borderWidth, 10)
        // Déplacer, dupliquer, supprimer.
        try cat.movePage(p0.id, to: 3)
        XCTAssertEqual(try cat.pages(a.id).map(\.layout), ["six", "une", "titre"])
        let d = try cat.duplicatePage(p2.id)
        XCTAssertEqual(try cat.pages(a.id).map(\.id), [p1.id, p2.id, d.id, p0.id])
        XCTAssertEqual(d.slots, [ph[1].id])
        try cat.deletePage(d.id)
        XCTAssertEqual(try cat.pages(a.id).map(\.position), [1, 2, 3])
        // Album copié : pages identiques, indépendantes.
        let copy = try cat.duplicateAlbum(a.id)
        XCTAssertEqual(try cat.pages(copy.id).map(\.layout), ["six", "une", "titre"])
        try cat.deleteAlbum(a.id)
        XCTAssertEqual(try cat.pages(copy.id).count, 3)
        XCTAssertEqual(try cat.db.scalarInt("SELECT COUNT(*) FROM album_pages WHERE album_id = ?", [.int(a.id)]), 0, "pages supprimées avec l'album")
    }

    func testSwapSlots() throws {
        let ph = try photos(3)
        let a = try cat.createAlbum(name: "A")
        let p = try cat.addPage(a.id, layout: "trois", photoIds: ph.map(\.id))
        _ = try cat.updatePage(p.id) { $0.crops[0] = AlbumCrop(x: 0.1, y: 0.1, zoom: 3) }
        let q = try cat.addPage(a.id, layout: "une", photoIds: [ph[2].id])
        try cat.swapSlots(page: p.id, slot: 0, with: q.id, slot: 0)
        XCTAssertEqual(try cat.albumPage(p.id)?.slots, [ph[2].id, ph[1].id, ph[2].id])
        XCTAssertEqual(try cat.albumPage(q.id)?.slots, [ph[0].id])
        XCTAssertEqual(try cat.albumPage(q.id)?.crops[0], AlbumCrop(x: 0.1, y: 0.1, zoom: 3), "le recadrage suit la photo")
        try cat.swapSlots(page: p.id, slot: 0, with: p.id, slot: 1)
        XCTAssertEqual(try cat.albumPage(p.id)?.slots.prefix(2).map { $0 }, [ph[1].id, ph[2].id])
        XCTAssertThrowsError(try cat.swapSlots(page: p.id, slot: 9, with: q.id, slot: 0))
        // Une étape annulable pour tout l'échange.
        try cat.undoAlbum(a.id)
        XCTAssertEqual(try cat.albumPage(p.id)?.slots.prefix(2).map { $0 }, [ph[2].id, ph[1].id])
        try cat.undoAlbum(a.id)
        XCTAssertEqual(try cat.albumPage(q.id)?.slots, [ph[2].id])
    }

    func testUndoRedo() throws {
        let ph = try photos(2)
        let a = try cat.createAlbum(name: "A")
        XCTAssertFalse(cat.canUndoAlbum(a.id))
        let p = try cat.addPage(a.id, layout: "deux-cote", photoIds: ph.map(\.id))
        XCTAssertTrue(cat.canUndoAlbum(a.id)); XCTAssertFalse(cat.canRedoAlbum(a.id))
        _ = try cat.updatePage(p.id) { $0.title = "Un" }
        _ = try cat.updatePage(p.id) { $0.title = "Un" }                      // inchangé : aucune étape
        try cat.updateAlbum(a.id, name: "Deux")
        try cat.undoAlbum(a.id)
        XCTAssertEqual(try cat.album(a.id)?.name, "A")
        try cat.undoAlbum(a.id)
        XCTAssertEqual(try cat.albumPage(p.id).map { $0.title }, "")
        try cat.undoAlbum(a.id)
        XCTAssertEqual(try cat.pages(a.id).count, 0)
        XCTAssertFalse(cat.canUndoAlbum(a.id)); XCTAssertTrue(cat.canRedoAlbum(a.id))
        try cat.redoAlbum(a.id); try cat.redoAlbum(a.id); try cat.redoAlbum(a.id)
        XCTAssertEqual(try cat.album(a.id)?.name, "Deux")
        XCTAssertEqual(try cat.pages(a.id).first?.title, "Un")
        XCTAssertFalse(cat.canRedoAlbum(a.id))
        // Une nouvelle modification efface l'avenir.
        try cat.undoAlbum(a.id)
        try cat.updateAlbum(a.id, description: "x")
        XCTAssertFalse(cat.canRedoAlbum(a.id))
        // Pile bornée.
        for i in 0..<70 { try cat.updateAlbum(a.id, description: "d\(i)") }
        var n = 0
        while cat.canUndoAlbum(a.id) { try cat.undoAlbum(a.id); n += 1 }
        XCTAssertEqual(n, AlbumHistory.limit)
    }

    func testAutoFillAndStyles() throws {
        let ph = try photos(10)
        let a = try cat.createAlbum(name: "A")
        let pages = try cat.autoFill(a.id, photoIds: ph.map(\.id), layout: "quatre")
        XCTAssertEqual(pages.map(\.layout), ["quatre", "quatre", "deux-cote"], "dernière page : gabarit à 2 cadres")
        XCTAssertEqual(try cat.pages(a.id).flatMap { $0.slots }.compactMap { $0 }, ph.map(\.id))
        XCTAssertTrue(try cat.albumChecks(a.id).filter { $0.kind == .emptyFrame }.isEmpty)
        try cat.undoAlbum(a.id)
        XCTAssertEqual(try cat.pages(a.id).count, 0, "tout le remplissage est une seule étape annulable")
        XCTAssertThrowsError(try cat.autoFill(a.id, photoIds: [1], layout: "titre"))
        try cat.redoAlbum(a.id)
        let nuit = StylePreset.all.first { $0.id == "nuit" }!
        try cat.applyStyle(nuit, album: a.id)
        XCTAssertTrue(try cat.pages(a.id).allSatisfy { $0.background == "#141414" && $0.style.textColor == "#f5f5f5" })
        let first = try cat.pages(a.id)[0]
        try cat.applyStyle(StylePreset.all[0], album: a.id, page: first.id)
        XCTAssertEqual(try cat.pages(a.id).map(\.background), ["#ffffff", "#141414", "#141414"])
        XCTAssertEqual(AlbumLayout.fitting(1, spread: false), "une"); XCTAssertEqual(AlbumLayout.fitting(5, spread: false), "six")
    }

    func testFoliosAndChecks() throws {
        let ph = try photos(2, width: 600, height: 400)        // petite image : résolution faible
        let a = try cat.createAlbum(name: "A", format: "a4-paysage")
        _ = try cat.addPage(a.id, layout: "une", photoIds: [ph[0].id])
        let d = try cat.addPage(a.id, layout: "double-marges", photoIds: [ph[1].id])     // pages 2–3 : bien placée
        _ = try cat.addPage(a.id, layout: "une")                                          // page 4 : cadre vide
        var fol = Catalog.folios(try cat.pages(a.id))
        XCTAssertEqual(fol.map(\.folio), [1, 2, 4]); XCTAssertEqual(fol.map(\.span), [1, 2, 1])
        XCTAssertEqual(fol[1].label, "Pages 2–3"); XCTAssertEqual(fol[0].label, "Page 1")
        XCTAssertFalse(fol[1].misaligned)
        var issues = try cat.albumChecks(a.id)
        XCTAssertTrue(issues.contains { $0.kind == .lowResolution && $0.page == 1 && $0.blocking }, "600 px sur ~25 cm = moins de 150 ppp")
        XCTAssertTrue(issues.contains { $0.kind == .emptyFrame && $0.page == 3 })
        XCTAssertFalse(issues.contains { $0.kind == .spreadAlignment })
        // Double page en page 1 : mal placée.
        try cat.movePage(d.id, to: 1)
        fol = Catalog.folios(try cat.pages(a.id))
        XCTAssertTrue(fol[0].misaligned)
        XCTAssertTrue(try cat.albumChecks(a.id).contains { $0.kind == .spreadAlignment && $0.page == 1 })
        // Photo retirée du catalogue, fichier absent.
        try cat.delete([ph[0].id])
        issues = try cat.albumChecks(a.id)
        XCTAssertTrue(issues.contains { $0.kind == .missingPhoto && $0.blocking })
        try FileManager.default.removeItem(at: cat.fileURL(ph[1]))
        XCTAssertTrue(try cat.albumChecks(a.id).contains { $0.kind == .unavailableFile })
        // Grande image : aucune alerte de résolution.
        let big = try add("grande.jpg", "grande", PhotoMetadata(width: 6000, height: 4000))
        let b = try cat.createAlbum(name: "B", format: "a4-portrait")
        _ = try cat.addPage(b.id, layout: "une", photoIds: [big.id])
        XCTAssertTrue(try cat.albumChecks(b.id).isEmpty)
        // Un zoom fort baisse la résolution effective.
        let pg = try cat.pages(b.id)[0]
        _ = try cat.updatePage(pg.id) { $0.crops = [AlbumCrop(x: 0.5, y: 0.5, zoom: 5)] }
        XCTAssertFalse(try cat.albumChecks(b.id).isEmpty)
    }

    func testProjectRoundTripAndDesktopFormat() throws {
        let ph = try photos(3)
        let a = try cat.createAlbum(name: "Corse", format: "a4-portrait", description: "été")
        let p = try cat.addPage(a.id, layout: "trois", photoIds: ph.map(\.id))
        _ = try cat.updatePage(p.id) { $0.title = "Plage"; $0.caption = "Calvi"; $0.crops[1] = AlbumCrop(x: 0.3, y: 0.6, zoom: 1.5); $0.background = "#f4efe6"; $0.style.borderWidth = 2 }
        let data = try cat.albumProject(a.id)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["format"] as? String, "phototheque-album"); XCTAssertEqual(json["formatVersion"] as? Int, 1)
        XCTAssertEqual((json["layouts"] as? [String: Any])?.count, 12)
        XCTAssertEqual((json["photos"] as? [String: Any])?.count, 3)
        let page = (json["pages"] as! [[String: Any]])[0]
        XCTAssertEqual(page["layout"] as? String, "trois"); XCTAssertEqual(page["title"] as? String, "Plage"); XCTAssertEqual((page["slots"] as? [Any])?.count, 3)
        // Réimport dans le même catalogue : un nouvel album, jamais un remplacement.
        let (b, an) = try cat.importProject(data)
        XCTAssertNotEqual(b.id, a.id); XCTAssertEqual(an.matched, 3); XCTAssertTrue(an.missing.isEmpty)
        let q = try cat.pages(b.id)[0]
        XCTAssertEqual(q.slots, ph.map { Optional($0.id) }); XCTAssertEqual(q.title, "Plage"); XCTAssertEqual(q.crops[1], AlbumCrop(x: 0.3, y: 0.6, zoom: 1.5))
        XCTAssertEqual(q.background, "#f4efe6"); XCTAssertEqual(q.style.borderWidth, 2)
        XCTAssertFalse(cat.canUndoAlbum(b.id), "l'import n'est pas une étape annulable")
        // Autre catalogue qui ne possède qu'une photo.
        let other = try Catalog(root: dir.appendingPathComponent("autre"))
        _ = try other.importFile(at: try makeFile("p1.jpg", "contenu 1"), metadata: PhotoMetadata(width: 3000, height: 2000)).photo
        let an2 = try other.analyseProject(data)
        XCTAssertEqual(an2.matched, 1); XCTAssertEqual(an2.missing.count, 2); XCTAssertEqual(an2.pages, 1); XCTAssertEqual(an2.frames, 3)
        let (c, _) = try other.importProject(data, name: "Importé")
        XCTAssertEqual(c.name, "Importé")
        XCTAssertEqual(try other.pages(c.id)[0].slots.compactMap { $0 }.count, 1)
        // Fichiers invalides.
        XCTAssertThrowsError(try cat.analyseProject(Data("pas du json".utf8)))
        XCTAssertThrowsError(try cat.analyseProject(Data(#"{"format":"autre"}"#.utf8)))
        XCTAssertThrowsError(try cat.analyseProject(Data(#"{"format":"phototheque-album","formatVersion":99}"#.utf8)))
        // Un projet venu du bureau (photos désignées par leur empreinte, identifiants différents).
        let sha = ph[0].sha256
        let desktop = """
        {"format":"phototheque-album","formatVersion":1,"album":{"name":"Bureau","format":"carre-20","width_mm":200,"height_mm":200},
         "pages":[{"page":1,"layout":"une","background":"#ffffff","title":"T","caption":"","slots":["ph-77"],"crops":[{"x":0.4,"y":0.5,"zoom":2}]}],
         "photos":{"ph-77":{"path":"2020/a.jpg","sha256":"\(sha)","title":"","width":3000,"height":2000}}}
        """
        let (d, an3) = try cat.importProject(Data(desktop.utf8))
        XCTAssertEqual(an3.matched, 1)
        XCTAssertEqual(try cat.pages(d.id)[0].slots, [ph[0].id]); XCTAssertEqual(d.format, "carre-20")
        XCTAssertEqual(try cat.pages(d.id)[0].crops[0], AlbumCrop(x: 0.4, y: 0.5, zoom: 2))
    }

    func testBackupCarriesAlbums() throws {
        let ph = try photos(2)
        let a = try cat.createAlbum(name: "Album sauvegardé", format: "carre-20")
        let p = try cat.addPage(a.id, layout: "deux-cote", photoIds: ph.map(\.id))
        _ = try cat.updatePage(p.id) { $0.title = "Duo"; $0.crops[0] = AlbumCrop(x: 0.2, y: 0.5, zoom: 2) }
        let zip = try cat.backup(includePhotos: true)
        let other = try Catalog(root: dir.appendingPathComponent("autre"))
        let r = try other.restore(from: zip)
        XCTAssertEqual(r.albumsAdded, 1)
        let b = try other.albums()[0]
        XCTAssertEqual(b.name, "Album sauvegardé"); XCTAssertEqual(b.format, "carre-20")
        let q = try other.pages(b.id)[0]
        XCTAssertEqual(q.title, "Duo"); XCTAssertEqual(q.slots.compactMap { $0 }.count, 2); XCTAssertEqual(q.crops[0], AlbumCrop(x: 0.2, y: 0.5, zoom: 2))
        XCTAssertEqual(try other.restore(from: zip).albumsAdded, 0, "pas de doublon")
        XCTAssertEqual(try other.albums().count, 1)
    }
}

final class DocumentTests: CatalogTestCase {
    func fill() throws -> [Photo] {
        [
            try add("a.jpg", "a", PhotoMetadata(takenAt: ISODate.date("2021-05-01T10:00:00Z"), cameraMake: "Canon", cameraModel: "Canon EOS R6", title: "Plage", keywords: ["Lieux/Corse", "Famille"], rating: 5)),
            try add("b.jpg", "b", PhotoMetadata(takenAt: ISODate.date("2021-06-01T10:00:00Z"), cameraMake: "Apple", cameraModel: "iPhone 13", keywords: ["Famille"])),
            try add("c.jpg", "c", PhotoMetadata(takenAt: ISODate.date("2022-01-01T10:00:00Z"), cameraMake: "Apple", cameraModel: "iPhone 13")),
            try add("d.jpg", "d"),
        ]
    }

    func testSectionsGrouping() throws {
        let p = try fill()
        let ids = p.map(\.id)
        XCTAssertEqual(try cat.docSections(ids, by: .none).map(\.photoIds), [ids])
        let y = try cat.docSections(ids, by: .year)
        XCTAssertEqual(y.map(\.title), ["2021", "2022", "Sans date"])
        XCTAssertEqual(y.map { $0.photoIds.count }, [2, 1, 1])
        XCTAssertEqual(try cat.docSections(ids, by: .month).map(\.title), ["2021-05", "2021-06", "2022-01", "Sans date"])
        let k = try cat.docSections(ids, by: .keyword)
        XCTAssertEqual(k.map(\.title), ["Famille", "Sans mot-clé"], "une photo n'est dans qu'une section : le premier mot-clé racine par ordre alphabétique")
        XCTAssertEqual(k.map { $0.photoIds.count }, [2, 2])
        XCTAssertEqual(try cat.docSections(ids, by: .camera).map(\.title), ["Apple iPhone 13", "Canon EOS R6", "Appareil inconnu"])
        XCTAssertEqual(try cat.docSections(ids, by: .rating).map(\.title), ["★★★★★", "Sans note"])
        XCTAssertEqual(try cat.docSections(ids, by: .place).map(\.title), ["Sans lieu"])
        XCTAssertEqual(try cat.docSections([], by: .year).count, 0)
        // Toutes les photos sont placées une seule fois.
        for by in DocGroupBy.allCases { XCTAssertEqual(try cat.docSections(ids, by: by).flatMap(\.photoIds).sorted(), ids.sorted(), by.rawValue) }
    }

    func testPlanContactSheetPagination() throws {
        let p = try fill()
        var o = DocumentOptions(); o.kind = .contactSheet; o.columns = 2; o.rows = 1; o.groupBy = .year; o.toc = true; o.cover = true
        let plan = try cat.documentPlan(p.map(\.id), options: o)
        // couverture, sommaire, 2021 (2 photos = 1 page), 2022 (1 page), sans date (1 page)
        XCTAssertEqual(plan.pages.count, 5)
        XCTAssertEqual(plan.pages[0], .cover); XCTAssertEqual(plan.pages[1], .toc)
        XCTAssertEqual(plan.toc.map(\.title), ["2021", "2022", "Sans date"])
        XCTAssertEqual(plan.toc.map(\.page), [3, 4, 5])
        XCTAssertEqual(plan.toc.map(\.count), [2, 1, 1])
        // Une seule colonne et ligne : une photo par page.
        o.columns = 1; o.rows = 1; o.cover = false; o.toc = false; o.groupBy = .none
        let plan2 = try cat.documentPlan(p.map(\.id), options: o)
        XCTAssertEqual(plan2.pages.count, 4)
        if case .grid(_, let ids, let n, let of) = plan2.pages[3] { XCTAssertEqual(ids.count, 1); XCTAssertEqual(n, 4); XCTAssertEqual(of, 4) } else { XCTFail("grille attendue") }
        // Sans regroupement le sommaire est inutile.
        o.toc = true
        XCTAssertFalse(try cat.documentPlan(p.map(\.id), options: o).pages.contains(.toc))
        XCTAssertEqual(DocumentOptions().with { $0.columns = 99; $0.rows = 0 }.clamped.columns, 8)
        XCTAssertEqual(DocumentOptions().with { $0.columns = 99; $0.rows = 0 }.clamped.rows, 1)
    }

    func testPlanOtherKinds() throws {
        let p = try fill(), ids = p.map(\.id)
        var o = DocumentOptions(); o.kind = .detailSheets
        let d = try cat.documentPlan(ids, options: o)
        XCTAssertEqual(d.pages, ids.map { DocPage.detail(photoId: $0) })
        o.kind = .portfolio
        let pf = try cat.documentPlan(ids, options: o)
        XCTAssertEqual(pf.pages.first, .cover); XCTAssertEqual(pf.pages.last, .colophon); XCTAssertEqual(pf.pages.count, 6)
        o.kind = .catalog; o.groupBy = .keyword; o.columns = 3; o.rows = 3; o.toc = true; o.cover = false
        let c = try cat.documentPlan(ids, options: o)
        XCTAssertEqual(c.pages.first, .toc)
        XCTAssertEqual(c.toc.map(\.title), ["Famille", "Lieux", "Sans mot-clé"].filter { t in c.sections.contains { $0.title == t && !$0.photoIds.isEmpty } })
        XCTAssertEqual(c.photoCount, 4)
        XCTAssertEqual(try cat.documentPlan([], options: o).pages, [], "aucune photo : aucune page")
    }

    func testCaptionLines() throws {
        let p = try fill()
        let a = try cat.photo(p[0].id)!
        XCTAssertEqual(try cat.docLines(a, fields: [.name, .title, .date, .rating, .keywords, .camera, .place]),
                       ["a.jpg", "Plage", "2021-05-01", "★★★★★", "Famille, Lieux/Corse", "Canon EOS R6"])
        XCTAssertEqual(try cat.docLines(p[3], fields: [.title, .date, .rating]), [], "champs vides omis")
        XCTAssertEqual(DocField.allCases.count, 7)
    }
}

extension DocumentOptions {
    func with(_ edit: (inout DocumentOptions) -> Void) -> DocumentOptions { var c = self; edit(&c); return c }
}
