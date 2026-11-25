import Foundation
import XCTest
@testable import PhotothequeCore

private func date(_ s: String) -> Date { ISODate.date(s)! }

/// Filtres à choix multiples, ET / OU, formats, lieu, orientation.
final class MultiCriteriaTests: CatalogTestCase {
    func fill() throws -> [Photo] {
        [
            try add("a.jpg", "a", PhotoMetadata(width: 400, height: 300, format: "JPEG", takenAt: date("2021-05-01T10:00:00Z"), cameraMake: "Canon", cameraModel: "Canon EOS R6", lens: "RF 50mm", latitude: 1, longitude: 2, title: "Fête", keywords: ["Fête"], rating: 5)),
            try add("b.heic", "b", PhotoMetadata(width: 300, height: 400, format: "HEIC", takenAt: date("2022-06-01T10:00:00Z"), cameraMake: "Apple", cameraModel: "iPhone 13", keywords: ["Lieux/Bretagne"])),
            try add("c.png", "c", PhotoMetadata(width: 200, height: 200, format: "PNG", takenAt: date("2023-01-01T10:00:00Z"), cameraMake: "Apple", cameraModel: "iPhone 13")),
            try add("d.jpg", "d", PhotoMetadata(width: 500, height: 100, format: "JPEG", cameraMake: "Sony", cameraModel: "A7")),
        ]
    }

    func testMultiValuesAreOr() throws {
        let p = try fill()
        XCTAssertEqual(try cat.search(SearchCriteria(sort: .name)).count, 4)
        var c = SearchCriteria(sort: .name); c.years = [2021, 2023]
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[2].id])
        c = SearchCriteria(sort: .name); c.formats = ["jpeg", "png"]
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[2].id, p[3].id], "formats insensibles à la casse")
        c = SearchCriteria(sort: .name); c.cameras = ["Canon EOS R6", "Sony A7"]
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[3].id])
        // Plusieurs critères différents : ET.
        c = SearchCriteria(sort: .name); c.years = [2021, 2022, 2023]; c.formats = ["HEIC", "PNG"]
        XCTAssertEqual(try cat.search(c).map(\.id), [p[1].id, p[2].id])
    }

    func testMatchAny() throws {
        let p = try fill()
        var c = SearchCriteria(sort: .name)
        c.years = [2021]; c.formats = ["PNG"]
        XCTAssertEqual(try cat.count(c), 0, "ET : 2021 et PNG")
        c.matchAny = true
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[2].id], "OU : 2021 ou PNG")
        // Un seul critère : même résultat en ET et en OU.
        var one = SearchCriteria(); one.formats = ["PNG"]
        let et = try cat.ids(one); one.matchAny = true
        XCTAssertEqual(try cat.ids(one), et)
        // Le texte reste exigé en OU.
        c.text = "fete"
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id], "texte ET (2021 OU PNG)")
        c.text = "zzzintrouvable"
        XCTAssertEqual(try cat.count(c), 0)
        // Sans critère de filtre, le OU ne change rien.
        XCTAssertEqual(try cat.count(SearchCriteria(text: "", sort: .name).with { $0.matchAny = true }), 4)
    }

    func testKeywordsMultiAndHasKeywords() throws {
        let p = try fill()
        let fete = try cat.keywordPath("Fête"), bretagne = try cat.keywordPath("Lieux/Bretagne")
        var c = SearchCriteria(sort: .name); c.keywordIds = [fete, bretagne]
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[1].id], "deux mots-clés : OU")
        c = SearchCriteria(sort: .name); c.keywordIds = [try cat.keywordPath("Lieux")]
        XCTAssertEqual(try cat.search(c).map(\.id), [p[1].id], "sous-mots-clés inclus")
        c.includeSubKeywords = false
        XCTAssertEqual(try cat.count(c), 0)
        c = SearchCriteria(); c.hasKeywords = true
        XCTAssertEqual(try cat.count(c), 2)
        c.hasKeywords = false
        XCTAssertEqual(try cat.count(c), 2)
        // OU : « sans mot-clé » ou 2021.
        c = SearchCriteria(sort: .name); c.hasKeywords = false; c.years = [2021]; c.matchAny = true
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[2].id, p[3].id])
    }

    func testPlaceLensOrientation() throws {
        let p = try fill()
        try cat.setPlace([p[1].id], "Brest (Finistère)")
        var c = SearchCriteria(); c.place = "finist"
        XCTAssertEqual(try cat.search(c).map(\.id), [p[1].id], "sous-chaîne, majuscules ignorées")
        c.place = "Finistere"
        XCTAssertEqual(try cat.count(c), 0, "les accents ne sont pas repliés dans ce critère")
        c = SearchCriteria(); c.lens = "50mm"
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id])
        c = SearchCriteria(sort: .name); c.orientation = .landscape
        XCTAssertEqual(try cat.search(c).map(\.id), [p[0].id, p[3].id])
        c.orientation = .portrait
        XCTAssertEqual(try cat.search(c).map(\.id), [p[1].id])
        c.orientation = .square
        XCTAssertEqual(try cat.search(c).map(\.id), [p[2].id])
        // LIKE : caractères spéciaux neutralisés.
        c = SearchCriteria(); c.place = "%"
        XCTAssertEqual(try cat.count(c), 0)
    }

    func testFacetsAndCounts() throws {
        _ = try fill()
        XCTAssertEqual(try cat.formats().map(\.name), ["JPEG", "HEIC", "PNG"])
        XCTAssertEqual(try cat.formats().map(\.count), [2, 1, 1])
        XCTAssertEqual(try cat.lenses().map(\.name), ["RF 50mm"])
        var c = SearchCriteria(); c.years = [2021]; c.formats = ["PNG"]
        XCTAssertEqual(c.filterCount, 2)
        XCTAssertFalse(c.isEmpty)
        c.matchAny = true
        XCTAssertEqual(SearchCriteria().with { $0.matchAny = true }.isEmpty, true, "OU seul n'est pas un filtre")
    }

    func testOldSavedSearchesStillDecode() throws {
        // Recherche enregistrée par la version 0.1 : un seul an, appareil, mot-clé.
        let old = #"{"text":"mer","year":2022,"camera":"Canon EOS R6","keywordId":7,"includeSubKeywords":false,"minRating":3,"sort":"name"}"#
        let c = SearchCriteria.decode(old)
        XCTAssertEqual(c?.years, [2022])
        XCTAssertEqual(c?.cameras, ["Canon EOS R6"])
        XCTAssertEqual(c?.keywordIds, [7])
        XCTAssertEqual(c?.includeSubKeywords, false)
        XCTAssertEqual(c?.minRating, 3)
        XCTAssertEqual(c?.sort, .name)
        XCTAssertEqual(c?.matchAny, false)
        // Aller-retour du format actuel.
        var n = SearchCriteria(text: "x"); n.years = [2020, 2021]; n.matchAny = true; n.orientation = .portrait; n.hasKeywords = false
        XCTAssertEqual(SearchCriteria.decode(n.encoded()), n)
    }

    func testSmartCollectionWithMultiAndBackup() throws {
        let p = try fill()
        let fete = try cat.keywordPath("Fête"), bretagne = try cat.keywordPath("Lieux/Bretagne")
        var c = SearchCriteria(); c.keywordIds = [fete, bretagne]; c.formats = ["PNG"]; c.matchAny = true
        let cid = try cat.createSmartCollection("Mixte", criteria: c)
        XCTAssertEqual(try cat.search(SearchCriteria(collectionId: cid, sort: .name)).map(\.id), [p[0].id, p[1].id, p[2].id])
        let zip = try cat.backup(includePhotos: false)
        let other = try Catalog(root: dir.appendingPathComponent("autre"))
        _ = try other.restore(from: zip)
        let restored = try other.collections().first { $0.name == "Mixte" }
        XCTAssertEqual(restored?.criteria?.keywordIds.count, 2)
        XCTAssertEqual(restored?.criteria?.matchAny, true)
        XCTAssertEqual(restored?.criteria?.formats, ["PNG"])
    }
}

extension SearchCriteria {
    func with(_ edit: (inout SearchCriteria) -> Void) -> SearchCriteria { var c = self; edit(&c); return c }
}

/// Tableau de bord et rapports.
final class DashboardTests: CatalogTestCase {
    func testDashboard() throws {
        let a = try add("a.jpg", "aa", PhotoMetadata(width: 400, height: 300, format: "JPEG", takenAt: date("2021-05-01T10:00:00Z"), cameraMake: "Canon", cameraModel: "Canon EOS R6", lens: "RF 50mm", latitude: 1, longitude: 2, title: "Titre", keywords: ["K"], rating: 5))
        _ = try add("b.png", "bbb", PhotoMetadata(width: 100, height: 100, format: "PNG", takenAt: date("2021-06-01T10:00:00Z"), cameraMake: "Apple", cameraModel: "iPhone"))
        _ = try add("c.jpg", "cccc", PhotoMetadata(width: 100, height: 300, format: "JPEG"))
        try cat.setColor([a.id], ColorLabel.red.rawValue)
        let d = try cat.dashboard()
        XCTAssertEqual(d.photos, 3)
        XCTAssertEqual(d.bytes, 9)
        XCTAssertEqual(d.byYear.map(\.label), ["2021", "Sans date"])
        XCTAssertEqual(d.byYear.map(\.count), [2, 1])
        XCTAssertEqual(d.byMonth.map(\.label), ["2021-05", "2021-06"])
        XCTAssertEqual(d.byFormat.map(\.label), ["JPEG", "PNG"])
        XCTAssertEqual(d.byFormat.first?.bytes, 6)
        XCTAssertEqual(Set(d.byCamera.map(\.label)), ["Canon EOS R6", "Apple iPhone", "Inconnu"])
        XCTAssertEqual(d.byLens.first { $0.label == "RF 50mm" }?.count, 1)
        XCTAssertEqual(d.byRating.map(\.label), ["Sans note", "★★★★★"])
        XCTAssertEqual(d.byColor.map(\.label), ["Aucune", "Rouge"])
        XCTAssertEqual(Set(d.byOrientation.map(\.label)), ["Paysage", "Carré", "Portrait"])
        let gaps = Dictionary(uniqueKeysWithValues: d.gaps.map { ($0.label, $0.count) })
        XCTAssertEqual(gaps["Sans mot-clé"], 2)
        XCTAssertEqual(gaps["Sans titre"], 2)
        XCTAssertEqual(gaps["Sans date de prise de vue"], 1)
        XCTAssertEqual(gaps["Sans position GPS"], 2)
        XCTAssertEqual(gaps["Sans note"], 2)
        XCTAssertEqual(d.largest.first?.fileName, "c.jpg")
        // Tableau de bord d'une sélection.
        var c = SearchCriteria(); c.formats = ["JPEG"]
        let dj = try cat.dashboard(c)
        XCTAssertEqual(dj.photos, 2)
        XCTAssertEqual(dj.byFormat.map(\.label), ["JPEG"])
        // CSV
        let csv = d.csv()
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Rubrique;Libellé;Photos;Octets"))
        XCTAssertTrue(csv.contains("Format;JPEG;2;6"))
        XCTAssertTrue(csv.contains("Manque;Sans titre;2;"))
    }

    func testEmptyDashboard() throws {
        let d = try cat.dashboard()
        XCTAssertEqual(d.photos, 0)
        XCTAssertTrue(d.byYear.isEmpty)
        XCTAssertEqual(d.gaps.map(\.count), [0, 0, 0, 0, 0, 0])
    }

    func testReports() throws {
        let a = try add("a.jpg", "aa", PhotoMetadata(takenAt: date("2021-05-01T10:00:00Z"), title: "Titre", keywords: ["Lieux/Mer"]))
        let b = try add("b.jpg", "bb")
        var r = try cat.report(.inventory)
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.headers.first, "Nom")
        XCTAssertTrue(r.csv().contains("Lieux/Mer"))
        var c = SearchCriteria(); c.years = [2021]
        r = try cat.report(.inventory, criteria: c)
        XCTAssertEqual(r.rows.map { $0[0] }, ["a.jpg"])
        r = try cat.report(.documentation)
        XCTAssertEqual(r.rows.count, 2, "a.jpg n'a pas de lieu, b.jpg manque de tout")
        XCTAssertEqual(r.rows.first { $0[0] == "b.jpg" }, ["b.jpg", "oui", "oui", "oui", "oui"])
        XCTAssertEqual(r.rows.first { $0[0] == "a.jpg" }, ["a.jpg", "", "", "oui", ""])
        r = try cat.report(.missingFiles)
        XCTAssertTrue(r.rows.isEmpty)
        try FileManager.default.removeItem(at: cat.fileURL(b))
        r = try cat.report(.missingFiles)
        XCTAssertEqual(r.rows.map { $0[0] }, ["b.jpg"])
        r = try cat.report(.integrity)
        XCTAssertEqual(r.rows.first?[1], "Intègre")
        XCTAssertEqual(r.rows[1][1], "1 absent(s)")
        r = try cat.report(.backups)
        XCTAssertTrue(r.rows.isEmpty)
        XCTAssertTrue(r.notes.joined().contains("Aucune sauvegarde"))
        _ = try cat.backup(includePhotos: false)
        r = try cat.report(.backups)
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertTrue(r.notes.joined().contains("Dernière sauvegarde il y a 0 jour"))
        _ = a
        // CSV : séparateur et guillemets.
        let t = ReportTable(title: "t", subtitle: "", headers: ["a", "b"], rows: [["x;y", "z\"w"]])
        XCTAssertEqual(t.csv(), "\u{FEFF}a;b\n\"x;y\";\"z\"\"w\"\n")
    }
}

/// Versions et mise à jour.
final class UpdateTests: XCTestCase {
    func testCompare() {
        XCTAssertEqual(Version.compare("0.10.0", "0.9.0"), 1)
        XCTAssertEqual(Version.compare("v1.2.3", "1.2.3"), 0)
        XCTAssertEqual(Version.compare("0.2.0", "0.2.1"), -1)
        XCTAssertEqual(Version.compare("1.0", "1.0.0"), 0)
        XCTAssertEqual(Version.compare("1.0.0-beta", "1.0.0"), 0)
        XCTAssertTrue(Version.isValid("0.2.0"))
        XCTAssertTrue(Version.isValid("v1.0.0"))
        XCTAssertFalse(Version.isValid("latest"))
        XCTAssertFalse(Version.isValid("1.0"))
    }

    func testReleaseParsing() throws {
        let json = """
        {"tag_name":"v0.2.0","name":"Photothèque iOS v0.2.0","body":"Notes\\n- a","html_url":"https://github.com/Vifi31/Phototheque_IOS/releases/tag/v0.2.0",
         "assets":[{"name":"Phototheque-0.2.0-non-signee.ipa","browser_download_url":"https://github.com/x/y.ipa","size":1234},{"name":"SHA256SUMS","browser_download_url":"https://github.com/x/s","size":10}]}
        """
        let r = ReleaseInfo.parse(Data(json.utf8))
        XCTAssertEqual(r?.version, "0.2.0")
        XCTAssertEqual(r?.assets.count, 2)
        XCTAssertNil(ReleaseInfo.parse(Data("{\"message\":\"Not Found\"}".utf8)))
        XCTAssertNil(ReleaseInfo.parse(Data("pas du json".utf8)))
        XCTAssertNil(ReleaseInfo.parse(Data("{\"tag_name\":\"nightly\"}".utf8)))
        let s = UpdateStatus.evaluate(current: "0.1.0", release: r)
        XCTAssertTrue(s.newer)
        XCTAssertEqual(s.latest, "0.2.0")
        XCTAssertEqual(s.ipaURL, "https://github.com/x/y.ipa")
        XCTAssertFalse(UpdateStatus.evaluate(current: "0.2.0", release: r).newer)
        XCTAssertFalse(UpdateStatus.evaluate(current: "0.3.0", release: r).newer)
        XCTAssertNotNil(UpdateStatus.evaluate(current: "0.1.0", release: nil).error)
        XCTAssertEqual(s.ipaName, "Phototheque-0.2.0-non-signee.ipa")
        XCTAssertEqual(s.sumsURL, "https://github.com/x/s")
    }

    func testChecksumFile() {
        let data = Data("contenu".utf8)
        let sha = SHA256Hasher.hex(data)
        let zeros = String(repeating: "0", count: 64)
        let text = "\(sha) *Phototheque-0.2.0-non-signee.ipa\n\(zeros)  autre.txt\nligne invalide\n"
        XCTAssertEqual(ChecksumFile.parse(text).count, 2)
        XCTAssertTrue(ChecksumFile.verify(data, name: "Phototheque-0.2.0-non-signee.ipa", in: text))
        XCTAssertFalse(ChecksumFile.verify(Data("autre".utf8), name: "Phototheque-0.2.0-non-signee.ipa", in: text), "empreinte différente")
        XCTAssertFalse(ChecksumFile.verify(data, name: "absent.ipa", in: text), "nom absent de la liste")
    }
}
