import Foundation
import XCTest
@testable import PhotothequeCore

private func date(_ s: String) -> Date { ISODate.date(s)! }

final class SchemaV4Tests: CatalogTestCase {
    func testMigratesFromV3() throws {
        XCTAssertEqual(try cat.db.scalarInt("PRAGMA user_version"), 4)
        let db = try Database(path: dir.appendingPathComponent("v3.sqlite").path)
        try db.execute(Schema.v1); try db.execute(Schema.v2); try db.execute(Schema.v3)
        try db.execute("PRAGMA user_version = 3")
        try db.run("INSERT INTO photos(file_name, rel_path, sha256, size, imported_at) VALUES ('x.jpg', 'x.jpg', 'abc', 1, '2024-01-01T00:00:00Z')")
        try db.run("INSERT INTO keywords(name, name_key) VALUES ('Mer', 'mer')")
        try Schema.migrate(db, fullText: false)
        XCTAssertEqual(try db.scalarInt("PRAGMA user_version"), 4)
        XCTAssertEqual(try db.first("SELECT category FROM keywords")?.string("category"), "")
        XCTAssertNil(try db.first("SELECT variant_of FROM photos")?.int("variant_of"))
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM ai_labels"), 0)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM meta_batches"), 0)
    }
}

final class VariantAndCategoryTests: CatalogTestCase {
    func testVariants() throws {
        let a = try add("a.jpg", "a"), b = try add("b.jpg", "b"), c = try add("c.jpg", "c"), d = try add("d.jpg", "d")
        XCTAssertEqual(try cat.count(SearchCriteria()), 4)
        try cat.setReference(a.id, variants: [b.id, c.id, a.id])
        XCTAssertEqual(try cat.photo(b.id)?.variantOf, a.id); XCTAssertNil(try cat.photo(a.id)?.variantOf)
        XCTAssertEqual(try cat.variantCounts(), [a.id: 2])
        XCTAssertEqual(try cat.search(SearchCriteria(sort: .name)).map(\.fileName), ["a.jpg", "d.jpg"], "variantes masquées par défaut")
        var crit = SearchCriteria(sort: .name); crit.variants = .show
        XCTAssertEqual(try cat.count(crit), 4)
        crit.variants = .only
        XCTAssertEqual(try cat.search(crit).map(\.fileName), ["b.jpg", "c.jpg"])
        XCTAssertEqual(try cat.variantGroup(of: c.id).map(\.fileName), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(try cat.variantGroup(of: d.id).map(\.fileName), ["d.jpg"])
        // Une nouvelle référence reprend les variantes de l'ancienne (pas de chaîne).
        try cat.setReference(d.id, variants: [a.id])
        XCTAssertEqual(Set(try cat.variants(of: d.id).map(\.fileName)), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(try cat.variants(of: a.id).count, 0)
        try cat.clearVariant(b.id)
        XCTAssertNil(try cat.photo(b.id)?.variantOf)
        try cat.clearVariants(of: d.id)
        XCTAssertEqual(try cat.variantCounts(), [:])
        // Retirer la référence du catalogue fait réapparaître ses variantes.
        try cat.setReference(a.id, variants: [b.id])
        try cat.delete([a.id])
        XCTAssertNil(try cat.photo(b.id)?.variantOf)
        XCTAssertEqual(try cat.count(SearchCriteria()), 3)
        XCTAssertThrowsError(try cat.setReference(9999, variants: [b.id]))
        // Le critère se range dans une recherche enregistrée.
        var s = SearchCriteria(); s.variants = .only
        XCTAssertEqual(SearchCriteria.decode(s.encoded())?.variants, .only)
        XCTAssertTrue(SearchCriteria().isEmpty)
        XCTAssertTrue(SearchCriteria().with { $0.variants = .show }.isEmpty, "l'affichage des variantes n'est pas un filtre")
    }

    func testKeywordCategories() throws {
        let p = try add("a.jpg", "a", PhotoMetadata(keywords: ["Lieux/Bretagne/Brest"])), q = try add("b.jpg", "b", PhotoMetadata(keywords: ["Famille"]))
        let lieux = try cat.keywordPath("Lieux"), famille = try cat.keywordPath("Famille")
        try cat.setCategory(lieux, "  Géographie "); try cat.setCategory(famille, "Personnes")
        XCTAssertEqual(try cat.keyword(lieux)?.category, "Géographie")
        XCTAssertEqual(try cat.keywordCategories().map(\.name), ["Géographie", "Personnes"])
        var c = SearchCriteria(); c.keywordCategory = "géographie"
        XCTAssertEqual(try cat.search(c).map(\.id), [p.id], "catégorie sans casse, sous-mots-clés inclus")
        c.keywordCategory = "Personnes"
        XCTAssertEqual(try cat.search(c).map(\.id), [q.id])
        c.keywordCategory = "Inconnue"
        XCTAssertEqual(try cat.count(c), 0)
        XCTAssertEqual(SearchCriteria().with { $0.keywordCategory = "x" }.filterCount, 1)
    }

    func testUncoveredByBackup() throws {
        _ = try add("a.jpg", "a")
        var c = SearchCriteria(); c.uncoveredByBackup = true
        XCTAssertEqual(try cat.count(c), 1, "aucune sauvegarde : tout est non couvert")
        c.uncoveredByBackup = false
        XCTAssertEqual(try cat.count(c), 0)
        _ = try cat.backup(includePhotos: false); try cat.noteBackup()
        Thread.sleep(forTimeInterval: 1.2)
        _ = try add("b.jpg", "b")
        c.uncoveredByBackup = true
        XCTAssertEqual(try cat.search(c).map(\.fileName), ["b.jpg"])
        c.uncoveredByBackup = false
        XCTAssertEqual(try cat.search(c).map(\.fileName), ["a.jpg"])
    }
}

final class BulkMetadataTests: CatalogTestCase {
    func fill() throws -> [Photo] {
        [try add("IMG_1.jpg", "1", PhotoMetadata(takenAt: date("2024-07-14T10:00:00Z"), title: "Un", keywords: ["Famille"], rating: 2)),
         try add("IMG_2.jpg", "2", PhotoMetadata(takenAt: date("2024-07-14T11:00:00Z"))),
         try add("IMG_3.jpg", "3")]
    }

    func testPreviewDoesNotWrite() throws {
        let p = try fill(); let ids = p.map(\.id)
        var c = BulkChange(); c.title = "Été {n}"; c.addKeywords = ["Famille", "Lieux/Corse"]; c.rating = 4
        let rows = try cat.bulkPreview(ids, c)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].changes.map(\.field), ["Titre", "Note", "Mots-clés ajoutés"])
        XCTAssertEqual(rows[0].changes.first { $0.field == "Mots-clés ajoutés" }?.after, "Lieux/Corse", "Famille déjà présent")
        XCTAssertEqual(rows[1].changes.first { $0.field == "Titre" }?.after, "Été 002")
        XCTAssertEqual(try cat.photo(ids[0])?.title, "Un", "l'aperçu n'écrit rien")
        XCTAssertEqual(try cat.bulkPreview(ids, BulkChange()).count, 0)
        var same = BulkChange(); same.rating = 2
        XCTAssertEqual(try cat.bulkPreview([ids[0]], same).count, 0, "valeur identique : aucun changement")
    }

    func testApplyAndUndo() throws {
        let p = try fill(); let ids = p.map(\.id)
        var c = BulkChange(); c.title = "{nom} ({date})"; c.place = "Corse"; c.color = 3; c.addKeywords = ["Lieux/Corse"]; c.removeKeywords = ["famille"]; c.rating = 5
        let r = try cat.applyBulk(ids, c)
        XCTAssertEqual(r.changed, 3); XCTAssertNotNil(r.batch)
        let a = try cat.photo(ids[0])!
        XCTAssertEqual(a.title, "IMG_1 (2024-07-14)"); XCTAssertEqual(a.place, "Corse"); XCTAssertEqual(a.color, 3); XCTAssertEqual(a.rating, 5)
        XCTAssertEqual(try cat.keywordsOf(ids[0]).map(\.name), ["Corse"], "Famille retiré (insensible à la casse), Corse ajouté")
        XCTAssertEqual(try cat.search(SearchCriteria(text: "corse")).count, 3, "recherche à jour")
        XCTAssertEqual(try cat.metaBatches().count, 1)
        XCTAssertEqual(try cat.undoBulk(r.batch!), 3)
        let b = try cat.photo(ids[0])!
        XCTAssertEqual(b.title, "Un"); XCTAssertEqual(b.place, ""); XCTAssertEqual(b.rating, 2); XCTAssertEqual(b.color, 0)
        XCTAssertEqual(try cat.keywordsOf(ids[0]).map(\.name), ["Famille"])
        XCTAssertEqual(try cat.search(SearchCriteria(text: "corse")).count, 0)
        XCTAssertEqual(try cat.metaBatches().first?.undone, true)
        XCTAssertThrowsError(try cat.undoBulk(r.batch!), "déjà annulé")
        XCTAssertThrowsError(try cat.undoBulk(9999))
        XCTAssertNil(try cat.applyBulk(ids, BulkChange()).batch)
    }

    func testClearKeywordsAndDateShift() throws {
        let p = try fill()
        var c = BulkChange(); c.clearKeywords = true; c.takenAtShiftSeconds = 3600
        let r = try cat.applyBulk(p.map(\.id), c)
        XCTAssertEqual(r.changed, 2, "la 3e photo n'a ni mot-clé ni date : rien à changer")
        XCTAssertEqual(try cat.keywordsOf(p[0].id).count, 0)
        XCTAssertEqual(try cat.photo(p[0].id)?.takenAt, "2024-07-14T11:00:00Z")
        XCTAssertNil(try cat.photo(p[2].id)?.takenAt)
        try cat.undoBulk(r.batch!)
        XCTAssertEqual(try cat.photo(p[0].id)?.takenAt, "2024-07-14T10:00:00Z")
        XCTAssertEqual(try cat.keywordsOf(p[0].id).map(\.name), ["Famille"])
    }

    func testUndoIgnoresDeletedPhotos() throws {
        let p = try fill()
        var c = BulkChange(); c.rating = 5
        let r = try cat.applyBulk(p.map(\.id), c)
        try cat.delete([p[0].id])
        XCTAssertEqual(try cat.undoBulk(r.batch!), 2)
    }

    func testRecents() throws {
        let p = try fill()
        XCTAssertEqual(cat.recentIds(), [])
        cat.noteViewed(p[0].id); cat.noteViewed(p[1].id); cat.noteViewed(p[2].id); cat.noteViewed(p[0].id)
        XCTAssertEqual(cat.recentIds(), [p[0].id, p[2].id, p[1].id])
        XCTAssertEqual(try cat.recentPhotos().map(\.id), [p[0].id, p[2].id, p[1].id])
        try cat.delete([p[2].id])
        XCTAssertEqual(try cat.recentPhotos().map(\.id), [p[0].id, p[1].id], "photo retirée : ignorée")
        for i in 0..<80 { cat.noteViewed(Int64(1000 + i)) }
        XCTAssertEqual(cat.recentIds().count, Catalog.recentLimit)
        try cat.clearRecents()
        XCTAssertEqual(cat.recentIds(), [])
    }
}

final class XMPTests: CatalogTestCase {
    func testBuildParseRoundTrip() {
        var i = XMPInfo(); i.title = "Plage & <soleil>"; i.caption = "Calvi \"été\""; i.rating = 4; i.color = 3
        i.keywords = ["Lieux/Corse/Calvi", "Famille"]
        let xml = XMPSidecar.build(i)
        XCTAssertTrue(xml.contains("xmp:Rating=\"4\"")); XCTAssertTrue(xml.contains("xmp:Label=\"Green\""))
        XCTAssertTrue(xml.contains("Plage &amp; &lt;soleil&gt;"))
        XCTAssertTrue(xml.contains("<lr:hierarchicalSubject>")); XCTAssertTrue(xml.contains("Lieux|Corse|Calvi"))
        let back = XMPSidecar.parse(xml)
        XCTAssertEqual(back.title, i.title); XCTAssertEqual(back.caption, i.caption); XCTAssertEqual(back.rating, 4); XCTAssertEqual(back.color, 3)
        XCTAssertEqual(back.keywords.sorted(), ["Famille", "Lieux/Corse/Calvi"])
        XCTAssertEqual(XMPSidecar.parse("pas du xmp"), XMPInfo())
        XCTAssertEqual(XMPSidecar.parse(XMPSidecar.build(XMPInfo())), XMPInfo())
    }

    func testParsesFlatSubjectsFromOtherSoftware() {
        let xmp = """
        <x:xmpmeta><rdf:RDF><rdf:Description xmp:Rating="9" xmp:Label="Rouge">
        <dc:subject><rdf:Bag><rdf:li>chat</rdf:li><rdf:li>jardin</rdf:li></rdf:Bag></dc:subject>
        <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Minou</rdf:li></rdf:Alt></dc:title></rdf:Description></rdf:RDF></x:xmpmeta>
        """
        let i = XMPSidecar.parse(xmp)
        XCTAssertEqual(i.keywords, ["chat", "jardin"]); XCTAssertEqual(i.title, "Minou"); XCTAssertEqual(i.rating, 5, "note bornée"); XCTAssertNil(i.color, "étiquette inconnue")
    }

    func testWriteSidecarsAndApplyWithPriority() throws {
        let a = try add("IMG 1.jpg", "a", PhotoMetadata(title: "Catalogue", keywords: ["Famille"], rating: 3)), b = try add("IMG 1.jpg", "b")
        let urls = try cat.writeSidecars([a.id, b.id])
        XCTAssertEqual(urls.count, 2); XCTAssertNotEqual(urls[0], urls[1], "même nom de fichier : annexes distinctes")
        XCTAssertTrue(urls.allSatisfy { $0.path.hasPrefix(cat.sidecarsDir.path) }, "jamais à côté des originaux")
        let text = try String(contentsOf: urls[0], encoding: .utf8)
        XCTAssertEqual(XMPSidecar.parse(text).title, "Catalogue")
        // Annexe venue d'ailleurs.
        var other = XMPInfo(); other.title = "Annexe"; other.caption = "Légende annexe"; other.rating = 5; other.keywords = ["Lieux/Mer"]
        let xmp = XMPSidecar.build(other)
        // Le catalogue prime : seuls les champs vides sont remplis, les mots-clés s'ajoutent.
        XCTAssertEqual(cat.metadataPriority(), .catalog)
        let ch1 = try cat.applySidecar(xmp, to: a.id)
        XCTAssertEqual(Set(ch1), ["légende", "mots-clés"])
        XCTAssertEqual(try cat.photo(a.id)?.title, "Catalogue"); XCTAssertEqual(try cat.photo(a.id)?.rating, 3)
        XCTAssertEqual(Set(try cat.keywordsOf(a.id).map(\.name)), ["Famille", "Mer"])
        // L'annexe prime : elle remplace.
        try cat.setMetadataPriority(.sidecar)
        let ch2 = try cat.applySidecar(xmp, to: a.id)
        XCTAssertTrue(ch2.contains("titre") && ch2.contains("note"))
        XCTAssertEqual(try cat.photo(a.id)?.title, "Annexe"); XCTAssertEqual(try cat.photo(a.id)?.rating, 5)
        XCTAssertEqual(try cat.search(SearchCriteria(text: "annexe")).count, 1, "recherche à jour")
        XCTAssertEqual(try cat.applySidecar(xmp, to: a.id), [], "second passage : rien de neuf")
        XCTAssertThrowsError(try cat.applySidecar(xmp, to: 9999))
    }
}

final class AITests: CatalogTestCase {
    func testTranslator() {
        XCTAssertEqual(AILabelTranslator.french("mountain"), "montagne")
        XCTAssertEqual(AILabelTranslator.french("Swimming_Pool"), "piscine")
        XCTAssertNil(AILabelTranslator.french("zzz"))
        XCTAssertEqual(AILabelTranslator.display("hot_air_balloon"), "hot air balloon")
        XCTAssertEqual(AILabelTranslator.display("cat"), "chat")
    }

    func testLabelsSearchAndSuggestions() throws {
        let a = try add("a.jpg", "a", PhotoMetadata(keywords: ["Chat"])), b = try add("b.jpg", "b")
        try cat.saveAILabels(a.id, labels: [("cat", 0.9), ("indoor", 0.6), ("sofa", 0.3), ("noise", 0.05)])
        try cat.saveAILabels(b.id, labels: [("mountain", 0.8), ("snow", 0.5), ("sky", 0.2)])
        XCTAssertEqual(Set(try cat.aiLabels(b.id).map(\.label)), ["mountain", "montagne", "snow", "neige", "sky", "ciel"])
        // Recherche par description, en français ou en anglais, plusieurs mots = ET.
        XCTAssertEqual(try cat.search(SearchCriteria().with { $0.describe = "montagne" }).map(\.id), [b.id])
        XCTAssertEqual(try cat.search(SearchCriteria().with { $0.describe = "mountain" }).map(\.id), [b.id])
        XCTAssertEqual(try cat.search(SearchCriteria().with { $0.describe = "montagne neige" }).map(\.id), [b.id])
        XCTAssertEqual(try cat.count(SearchCriteria().with { $0.describe = "montagne chat" }), 0)
        XCTAssertEqual(try cat.count(SearchCriteria().with { $0.describe = "noise" }), 0, "confiance trop faible : étiquette non gardée")
        XCTAssertEqual(try cat.search(SearchCriteria().with { $0.describe = "INTÉRIEUR" }).map(\.id), [a.id], "insensible aux accents")
        // Suggestions : confiance suffisante, pas de mot-clé déjà présent.
        let s = try cat.pendingSuggestions()
        XCTAssertEqual(s.map(\.keyword), ["Montagne", "Intérieur", "Neige"], "triées par confiance ; « Chat » déjà affecté ; « sofa » trop faible")
        XCTAssertEqual(try cat.pendingSuggestionCount(), 3)
        try cat.acceptSuggestion(b.id, keyword: "Montagne", asPath: "Nature/Montagne")
        XCTAssertEqual(try cat.keywordsOf(b.id).map { try self.cat.keywordPathName($0.id, separator: "/") }, ["Nature/Montagne"])
        try cat.rejectSuggestion(a.id, keyword: "Intérieur")
        XCTAssertEqual(try cat.pendingSuggestionCount(), 1)
        // Une nouvelle analyse ne repropose ni l'accepté ni le refusé.
        try cat.saveAILabels(a.id, labels: [("cat", 0.9), ("indoor", 0.7)])
        try cat.saveAILabels(b.id, labels: [("mountain", 0.8), ("snow", 0.5)])
        XCTAssertEqual(try cat.pendingSuggestions().map(\.keyword), ["Neige"])
        XCTAssertEqual(try cat.acceptSuggestions(minConfidence: 0.9), 0)
        XCTAssertEqual(try cat.acceptSuggestions(minConfidence: 0.4), 1)
        XCTAssertEqual(try cat.pendingSuggestionCount(), 0)
        XCTAssertEqual(try cat.aiStats().analysed, 2)
        XCTAssertThrowsError(try cat.saveAILabels(9999, labels: []))
        try cat.clearAI()
        XCTAssertEqual(try cat.aiStats().analysed, 0)
    }

    func testPhotosToAnalyse() throws {
        let a = try add("a.jpg", "a"), b = try add("b.jpg", "b")
        XCTAssertEqual(try cat.photosWithoutAI().count, 2)
        try cat.saveAILabels(a.id, labels: [("sky", 0.2)])
        try cat.markAnalysed(b.id)
        XCTAssertEqual(try cat.photosWithoutAI().count, 0, "analysée sans résultat : notée, pas réanalysée")
        XCTAssertEqual(try cat.pendingSuggestionCount(), 0)
    }

    func testPrints() throws {
        let a = try add("a.jpg", "a"), b = try add("b.jpg", "b")
        XCTAssertEqual(try cat.photosWithoutPrint().count, 2)
        try cat.saveAIPrint(a.id, data: Data([1, 2, 3, 0, 255]), engine: "vision-1")
        try cat.saveAIPrint(a.id, data: Data([9, 9]), engine: "vision-1")
        XCTAssertEqual(try cat.aiPrints().map(\.photoId), [a.id])
        XCTAssertEqual(try cat.aiPrints().first?.data, Data([9, 9]))
        XCTAssertEqual(try cat.photosWithoutPrint().map(\.id), [b.id])
        try cat.delete([a.id])
        XCTAssertEqual(try cat.aiPrints().count, 0, "supprimées avec la photo")
    }

    func testEventsAndPlaces() throws {
        let t = { (s: String) in PhotoMetadata(takenAt: ISODate.date(s)!) }
        let a = try add("a.jpg", "a", t("2024-07-14T09:00:00Z")), b = try add("b.jpg", "b", t("2024-07-14T10:00:00Z")), c = try add("c.jpg", "c", t("2024-07-14T12:30:00Z"))
        let d = try add("d.jpg", "d", t("2024-07-20T09:00:00Z")), e = try add("e.jpg", "e", t("2024-07-20T09:30:00Z")), f = try add("f.jpg", "f", t("2024-08-01T09:00:00Z"))
        _ = try add("g.jpg", "g")
        try cat.setPlace([a.id, b.id, d.id], "Calvi")
        try cat.setPlace([c.id], "Ajaccio")
        let ev = try cat.eventGroups(gapHours: 6, minPhotos: 2)
        XCTAssertEqual(ev.map { $0.photoIds.count }, [2, 3], "le plus récent d'abord ; la photo seule du 1er août et la photo sans date sont écartées")
        XCTAssertEqual(ev[1].photoIds, [a.id, b.id, c.id]); XCTAssertEqual(ev[1].place, "Calvi", "lieu le plus fréquent")
        XCTAssertEqual(ev[0].place, "Calvi")
        XCTAssertEqual(ev[1].from, "2024-07-14T09:00:00Z"); XCTAssertEqual(ev[1].to, "2024-07-14T12:30:00Z")
        XCTAssertEqual(try cat.eventGroups(gapHours: 1, minPhotos: 2).map { $0.photoIds.count }, [2, 2], "écart de 1 h : 9h-10h, puis 20 juillet 9h-9h30")
        XCTAssertEqual(try cat.eventGroups(gapHours: 24 * 30, minPhotos: 1).count, 1)
        XCTAssertEqual(try cat.placeGroups().map(\.place), ["Calvi"], "Ajaccio n'a qu'une photo")
        XCTAssertEqual(try cat.placeGroups(minPhotos: 1).map { $0.photoIds.count }, [3, 1])
        _ = e; _ = f
    }
}
