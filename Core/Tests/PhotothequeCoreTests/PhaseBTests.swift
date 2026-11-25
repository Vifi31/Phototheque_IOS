import Foundation
import XCTest
@testable import PhotothequeCore

final class EditParamsTests: XCTestCase {
    func testNeutralAndNormalize() {
        XCTAssertTrue(EditParams().isNeutral)
        var p = EditParams()
        p.exposure = 5; p.contrast = -500; p.sharpen = -3; p.straighten = 99; p.rotate = 450
        let n = p.normalized()
        XCTAssertEqual(n.exposure, 2); XCTAssertEqual(n.contrast, -100); XCTAssertEqual(n.sharpen, 0); XCTAssertEqual(n.straighten, 15)
        XCTAssertEqual(n.rotate, 90)
        p.rotate = -90
        XCTAssertEqual(p.normalized().rotate, 270)
        p = EditParams(); p.exposure = .nan
        XCTAssertEqual(p.normalized().exposure, 0, "valeur non numérique ramenée à zéro")
        p = EditParams(); p.exposure = 0.123456
        XCTAssertEqual(p.normalized().exposure, 0.123)
        XCTAssertFalse(p.isNeutral)
        // Un recadrage plein cadre ne compte pas.
        p = EditParams(); p.crop = CropRect(x: 0, y: 0, w: 1, h: 1)
        XCTAssertTrue(p.isNeutral)
        p.crop = CropRect(x: 0.9, y: 0.9, w: 0.5, h: 0.5)
        XCTAssertEqual(p.normalized().crop, CropRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5), "fenêtre ramenée dans l'image")
    }

    func testCodecIsTolerantAndRoundTrips() {
        var p = EditParams()
        p.exposure = 0.5; p.mono = .sepia; p.curve = Curves.all[1].points; p.crop = CropRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5); p.flipH = true
        let s = EditCodec.encode(p)
        XCTAssertEqual(EditCodec.decode(s), p.normalized())
        XCTAssertTrue(EditCodec.decode("{}").isNeutral)
        XCTAssertTrue(EditCodec.decode("pas du json").isNeutral)
        XCTAssertEqual(EditCodec.decode(#"{"exposure":1,"inconnu":42,"v":9}"#).exposure, 1, "clé inconnue ignorée")
    }

    func testPresetsReplaceToneButKeepGeometryAndNoise() {
        var p = EditParams(); p.rotate = 90; p.noise = 30; p.exposure = 1; p.crop = CropRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5)
        let nb = EditPreset.all.first { $0.id == "nb" }!.applying(to: p)
        XCTAssertEqual(nb.mono, .bw); XCTAssertEqual(nb.contrast, 10); XCTAssertEqual(nb.exposure, 0, "la lumière est remplacée")
        XCTAssertEqual(nb.rotate, 90); XCTAssertEqual(nb.noise, 30); XCTAssertNotNil(nb.crop)
        let film = EditPreset.all.first { $0.id == "film" }!.applying(to: nb)
        XCTAssertNil(film.mono, "le noir et blanc est retiré")
        XCTAssertEqual(film.curve?.count, 3)
        XCTAssertEqual(EditPreset.all.count, 9)
    }

    func testCurveLUT() {
        let id = CurveLUT.make(nil)
        XCTAssertEqual(id.count, 256); XCTAssertEqual(id[0], 0); XCTAssertEqual(id[128], 128); XCTAssertEqual(id[255], 255)
        XCTAssertNil(CurveLUT.validPoints([CurvePoint(0, 0), CurvePoint(255, 255)]), "droite identité = aucune courbe")
        XCTAssertNil(CurveLUT.validPoints([CurvePoint(10, 10)]))
        let s = CurveLUT.make(Curves.all[1].points)
        XCTAssertEqual(s[0], 0); XCTAssertEqual(s[255], 255)
        XCTAssertEqual(s[64], 56); XCTAssertEqual(s[192], 200)
        XCTAssertTrue(s[100] < 100 && s[160] > 160, "courbe en S : ombres plus sombres, lumières plus claires")
        for i in 1..<256 { XCTAssertGreaterThanOrEqual(s[i], s[i - 1], "monotone à \(i)") }
        let fondu = CurveLUT.make(Curves.all[3].points)
        XCTAssertEqual(fondu[0], 28); XCTAssertEqual(fondu[255], 245)
        for i in 1..<256 { XCTAssertGreaterThanOrEqual(fondu[i], fondu[i - 1]) }
        // Points désordonnés, doublons et hors bornes.
        let messy = CurveLUT.validPoints([CurvePoint(300, 300), CurvePoint(0, -5), CurvePoint(128, 100), CurvePoint(128, 50)])
        XCTAssertEqual(messy?.map(\.x), [0, 128, 255])
        XCTAssertEqual(messy?.first?.y, 0)
        // Une courbe plate ne déborde pas (pas de dépassement entre deux points de même hauteur).
        let flat = CurveLUT.make([CurvePoint(0, 100), CurvePoint(128, 100), CurvePoint(255, 100)])
        XCTAssertTrue(flat.allSatisfy { $0 == 100 })
    }

    func testGeometry() {
        var p = EditParams()
        XCTAssertTrue(EditGeometry.outputSize(width: 400, height: 300, params: p) == (400, 300))
        p.rotate = 90
        XCTAssertTrue(EditGeometry.outputSize(width: 400, height: 300, params: p) == (300, 400))
        p.crop = CropRect(x: 0, y: 0, w: 0.5, h: 0.25)
        XCTAssertTrue(EditGeometry.outputSize(width: 400, height: 300, params: p) == (150, 100))
        XCTAssertEqual(EditFields.all.count, 13)
        XCTAssertEqual(Set(EditFields.all.map(\.group)), Set(EditFields.groups))
    }
}

final class EditVersionsTests: CatalogTestCase {
    func photo() throws -> Photo { try add("a.jpg", "aaa") }

    func testSchemaIsV2AndMigratesFromV1() throws {
        XCTAssertEqual(try cat.db.scalarInt("PRAGMA user_version"), 2)
        // Base de la version 0.1 (schéma 1) : la migration ajoute la table des retouches sans toucher aux photos.
        let path = dir.appendingPathComponent("ancienne.sqlite").path
        let db = try Database(path: path)
        try db.execute(Schema.v1)
        try db.execute("PRAGMA user_version = 1")
        try db.run("INSERT INTO photos(file_name, rel_path, sha256, size, imported_at) VALUES ('x.jpg', 'x.jpg', 'abc', 1, '2024-01-01T00:00:00Z')")
        try Schema.migrate(db, fullText: false)
        XCTAssertEqual(try db.scalarInt("PRAGMA user_version"), 2)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM photos"), 1)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM edits"), 0)
        try Schema.migrate(db, fullText: false) // idempotente
    }

    func testCreateUpdateUndoRedo() throws {
        let p = try photo()
        XCTAssertNil(try cat.defaultEdit(p.id))
        let v1 = try cat.createEdit(photoId: p.id)
        XCTAssertEqual(v1.name, "Version 1"); XCTAssertTrue(v1.isDefault); XCTAssertTrue(v1.params.isNeutral)
        XCTAssertFalse(v1.canUndo)
        var prm = EditParams(); prm.exposure = 0.5
        var v = try cat.updateEdit(v1.id, params: prm)
        XCTAssertEqual(v.params.exposure, 0.5); XCTAssertTrue(v.canUndo); XCTAssertFalse(v.canRedo)
        prm.contrast = 20
        v = try cat.updateEdit(v1.id, params: prm)
        // Même réglages : aucune étape ajoutée.
        v = try cat.updateEdit(v1.id, params: prm)
        v = try cat.undoEdit(v1.id)
        XCTAssertEqual(v.params.contrast, 0); XCTAssertEqual(v.params.exposure, 0.5); XCTAssertTrue(v.canRedo)
        v = try cat.undoEdit(v1.id)
        XCTAssertTrue(v.params.isNeutral); XCTAssertFalse(v.canUndo)
        v = try cat.undoEdit(v1.id)
        XCTAssertTrue(v.params.isNeutral, "rien à annuler")
        v = try cat.redoEdit(v1.id); v = try cat.redoEdit(v1.id)
        XCTAssertEqual(v.params.contrast, 20); XCTAssertFalse(v.canRedo)
        // Une nouvelle modification efface l'avenir.
        v = try cat.undoEdit(v1.id)
        prm.saturation = 10; prm.contrast = 0
        v = try cat.updateEdit(v1.id, params: prm)
        XCTAssertFalse(v.canRedo)
        // Remise à zéro : annulable.
        v = try cat.resetEdit(v1.id)
        XCTAssertTrue(v.params.isNeutral)
        v = try cat.undoEdit(v1.id)
        XCTAssertEqual(v.params.saturation, 10)
        // L'historique est borné.
        for i in 0..<70 { var q = EditParams(); q.brightness = Double(i + 1); _ = try cat.updateEdit(v1.id, params: q) }
        var undos = 0
        while try cat.undoEdit(v1.id).canUndo { undos += 1 }
        XCTAssertLessThanOrEqual(undos + 1, EditCodec.maxHistory)
    }

    func testVersionsDefaultRenameDelete() throws {
        let p = try photo()
        let a = try cat.createEdit(photoId: p.id, name: "Noir et blanc")
        var prm = EditParams(); prm.mono = .bw
        _ = try cat.updateEdit(a.id, params: prm)
        let b = try cat.createEdit(photoId: p.id, from: a.id)
        XCTAssertEqual(b.name, "Version 2"); XCTAssertEqual(b.params.mono, .bw, "copie des réglages"); XCTAssertFalse(b.isDefault)
        XCTAssertEqual(try cat.defaultEdit(p.id)?.id, a.id)
        try cat.setDefaultEdit(b.id)
        XCTAssertEqual(try cat.defaultEdit(p.id)?.id, b.id)
        XCTAssertEqual(try cat.editVersions(p.id).filter(\.isDefault).count, 1)
        try cat.renameEdit(b.id, "  Portrait  ")
        XCTAssertEqual(try cat.editVersion(b.id)?.name, "Portrait")
        XCTAssertThrowsError(try cat.renameEdit(b.id, "   "))
        XCTAssertEqual(try cat.editCounts()[p.id], 2)
        try cat.deleteEdit(b.id)
        XCTAssertEqual(try cat.defaultEdit(p.id)?.id, a.id, "la version restante devient la version par défaut")
        try cat.deleteEdit(a.id)
        XCTAssertNil(try cat.defaultEdit(p.id)); XCTAssertTrue(try cat.editCounts().isEmpty)
        XCTAssertThrowsError(try cat.createEdit(photoId: 9999))
    }

    func testDeletingPhotoRemovesItsEdits() throws {
        let p = try photo()
        _ = try cat.createEdit(photoId: p.id)
        try cat.delete([p.id])
        XCTAssertEqual(try cat.db.scalarInt("SELECT COUNT(*) FROM edits"), 0)
    }

    func testBackupCarriesEdits() throws {
        let p = try photo()
        let a = try cat.createEdit(photoId: p.id, name: "A")
        var prm = EditParams(); prm.vibrance = 30; prm.curve = Curves.all[2].points
        _ = try cat.updateEdit(a.id, params: prm)
        let b = try cat.createEdit(photoId: p.id, name: "B")
        try cat.setDefaultEdit(b.id)
        let zip = try cat.backup(includePhotos: true)
        let other = try Catalog(root: dir.appendingPathComponent("autre"))
        let r = try other.restore(from: zip)
        XCTAssertEqual(r.editsAdded, 2)
        let q = try other.photo(sha256: p.sha256)!
        let vs = try other.editVersions(q.id)
        XCTAssertEqual(vs.map(\.name).sorted(), ["A", "B"])
        XCTAssertEqual(vs.first { $0.name == "A" }?.params.vibrance, 30)
        XCTAssertEqual(vs.first { $0.name == "A" }?.params.curve?.count, 4)
        XCTAssertEqual(try other.defaultEdit(q.id)?.name, "B")
        // Restaurer deux fois : pas de doublons.
        XCTAssertEqual(try other.restore(from: zip).editsAdded, 0)
        XCTAssertEqual(try other.editVersions(q.id).count, 2)
    }
}

final class ExportTests: CatalogTestCase {
    func testTargetSizeNeverEnlarges() {
        var o = ExportOptions(); o.maxSide = 1000
        XCTAssertTrue(o.targetSize(width: 4000, height: 3000) == (1000, 750))
        XCTAssertTrue(o.targetSize(width: 3000, height: 4000) == (750, 1000))
        XCTAssertTrue(o.targetSize(width: 800, height: 600) == (800, 600))
        o.maxSide = nil
        XCTAssertTrue(o.targetSize(width: 4000, height: 3000) == (4000, 3000))
        o.printSize = "10x15"; o.printDPI = 300
        XCTAssertEqual(o.targetLongSide, 1772)
        XCTAssertTrue(o.targetSize(width: 6000, height: 4000) == (1772, 1181))
        XCTAssertEqual(ExportOptions().with { $0.quality = 7; $0.maxSide = 3; $0.printDPI = 5 }.clamped.quality, 1)
        XCTAssertNil(ExportOptions().with { $0.maxSide = 3 }.clamped.maxSide)
        XCTAssertEqual(ExportOptions().with { $0.printDPI = 5 }.clamped.printDPI, 72)
    }

    func testPrintSizes() {
        let a4 = PrintSize.all.first { $0.id == "21x29.7" }!
        XCTAssertEqual(a4.pixels(dpi: 300).long, 3508)
        XCTAssertEqual(a4.pixels(dpi: 300).short, 2480)
        XCTAssertEqual(PrintSize.all.first { $0.id == "10x15" }!.effectiveDPI(width: 1800, height: 1200), 305)
        XCTAssertLessThan(a4.effectiveDPI(width: 1800, height: 1200), 150, "trop peu de pixels pour un A4")
    }

    func testNaming() throws {
        let p = try add("IMG 01.jpg", "a", PhotoMetadata(takenAt: ISODate.date("2024-07-14T10:00:00Z"), title: "Mer / plage", rating: 4))
        XCTAssertEqual(ExportNaming.fileName(pattern: "{nom}", photo: p, index: 1, ext: "jpg"), "IMG 01.jpg")
        XCTAssertEqual(ExportNaming.fileName(pattern: "{date}_{n}_{titre}", photo: p, index: 7, ext: "png"), "2024-07-14_007_Mer _ plage.png")
        XCTAssertEqual(ExportNaming.fileName(pattern: "", photo: p, index: 1, ext: "heic"), "IMG 01.heic")
        XCTAssertEqual(ExportNaming.fileName(pattern: "../{nom}:{note}", photo: p, index: 1, ext: "jpg"), "_IMG 01_4.jpg", "aucun séparateur de dossier")
        let q = try add("b.jpg", "b")
        XCTAssertEqual(ExportNaming.fileName(pattern: "{date}", photo: q, index: 1, ext: "jpg"), "sans-date.jpg")
    }

    func testPlanUniqueNamesAndEdits() throws {
        let a = try add("a.jpg", "a"), b = try add("a.png", "b"), c = try add("c.jpg", "c")
        let v = try cat.createEdit(photoId: a.id)
        var prm = EditParams(); prm.exposure = 1
        _ = try cat.updateEdit(v.id, params: prm)
        _ = try cat.createEdit(photoId: c.id) // version neutre : l'original est exporté
        var o = ExportOptions(); o.format = .jpeg; o.namePattern = "{nom}"
        let out = dir.appendingPathComponent("sortie")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: out.appendingPathComponent("c.jpg"))
        let plan = try cat.exportPlan([a.id, b.id, c.id], options: o, into: out)
        XCTAssertEqual(plan.map(\.fileName), ["a.jpg", "a (2).jpg", "c (2).jpg"], "même nom entre photos et fichier existant : numéro")
        XCTAssertEqual(plan.map { $0.editId != nil }, [true, false, false])
        o.useEdits = false
        XCTAssertNil(try cat.exportPlan([a.id], options: o, into: out)[0].editId)
        XCTAssertEqual(try cat.exportPlan([], options: o).count, 0)
    }
}

extension ExportOptions {
    func with(_ edit: (inout ExportOptions) -> Void) -> ExportOptions { var c = self; edit(&c); return c }
}

final class DefaultEditsTests: CatalogTestCase {
    func testOnlyNonNeutralDefaultsAreListed() throws {
        let a = try add("a.jpg", "a"), b = try add("b.jpg", "b"), c = try add("c.jpg", "c")
        let va = try cat.createEdit(photoId: a.id)
        var p = EditParams(); p.exposure = 1
        _ = try cat.updateEdit(va.id, params: p)
        _ = try cat.createEdit(photoId: b.id)                       // neutre : l'original reste affiché
        let vc1 = try cat.createEdit(photoId: c.id)
        let vc2 = try cat.createEdit(photoId: c.id, from: vc1.id)
        p.mono = .bw
        _ = try cat.updateEdit(vc2.id, params: p)
        let d = try cat.defaultEdits()
        XCTAssertEqual(Set(d.keys), [a.id], "c : la version par défaut (vc1) est neutre")
        try cat.setDefaultEdit(vc2.id)
        XCTAssertEqual(Set(try cat.defaultEdits().keys), [a.id, c.id])
        XCTAssertEqual(try cat.defaultEdits()[c.id]?.params.mono, .bw)
    }
}
