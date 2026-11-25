import Foundation
import XCTest
@testable import PhotothequeCore

final class BackupV5Tests: CatalogTestCase {
    func testBackupCarriesCategoriesAndVariants() throws {
        let a = try add("a.jpg", "AAAA", PhotoMetadata(keywords: ["Lieux/Mer"])), b = try add("b.jpg", "BBBB")
        try cat.setCategory(try cat.keywordPath("Lieux"), "Géographie")
        try cat.setReference(a.id, variants: [b.id])
        let zip = try cat.backup(includePhotos: true)
        let other = try Catalog(root: dir.appendingPathComponent("autre"))
        _ = try other.restore(from: zip)
        XCTAssertEqual(try other.keyword(try other.keywordPath("Lieux"))?.category, "Géographie")
        let ra = try other.photo(sha256: a.sha256)!, rb = try other.photo(sha256: b.sha256)!
        XCTAssertEqual(rb.variantOf, ra.id); XCTAssertNil(ra.variantOf)
        // Restaurer sur un catalogue où une variante est déjà désignée : pas d'écrasement.
        let third = try Catalog(root: dir.appendingPathComponent("tiers"))
        let ta = try third.importFile(at: try makeFile("a.jpg", "AAAA"), metadata: PhotoMetadata()).photo
        let tb = try third.importFile(at: try makeFile("b.jpg", "BBBB"), metadata: PhotoMetadata()).photo
        let tc = try third.importFile(at: try makeFile("c.jpg", "CCCC"), metadata: PhotoMetadata()).photo
        try third.setReference(tc.id, variants: [tb.id])
        _ = try third.restore(from: zip)
        XCTAssertEqual(try third.photo(tb.id)?.variantOf, tc.id, "la désignation existante est conservée")
        _ = ta
        // Parties : sans « métadonnées », les variantes ne sont pas rétablies.
        let fourth = try Catalog(root: dir.appendingPathComponent("quatre"))
        _ = try fourth.importFile(at: try makeFile("a.jpg", "AAAA"), metadata: PhotoMetadata())
        let fb = try fourth.importFile(at: try makeFile("b.jpg", "BBBB"), metadata: PhotoMetadata()).photo
        _ = try fourth.restore(from: zip, parts: [.keywords])
        XCTAssertNil(try fourth.photo(fb.id)?.variantOf)
    }

    func testDashboardTable() throws {
        _ = try add("a.jpg", "aa", PhotoMetadata(width: 400, height: 300, format: "JPEG", takenAt: ISODate.date("2021-05-01T10:00:00Z"), cameraMake: "Canon", cameraModel: "Canon EOS R6", rating: 5))
        _ = try add("b.png", "bbb", PhotoMetadata(width: 100, height: 100, format: "PNG"))
        let t = try cat.dashboard().table()
        XCTAssertEqual(t.headers, ["Rubrique", "Libellé", "Photos", "Volume"])
        XCTAssertEqual(t.rows.first, ["Total", "Photos", "2", "5 o"])
        XCTAssertTrue(t.rows.contains(["Format", "JPEG", "1", "2 o"]))
        XCTAssertTrue(t.rows.contains { $0[0] == "Manque" && $0[1] == "Sans titre" && $0[2] == "2" })
        XCTAssertTrue(t.csv().contains("Format;PNG;1;3 o"))
        XCTAssertEqual(t.subtitle, "2 photo(s) — 5 o")
    }
}
