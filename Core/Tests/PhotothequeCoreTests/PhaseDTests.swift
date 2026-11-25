import Foundation
import XCTest
@testable import PhotothequeCore

final class CryptoTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("crypto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func file(_ name: String, _ data: Data) throws -> URL { let u = dir.appendingPathComponent(name); try data.write(to: u); return u }
    func bytes(_ n: Int) -> Data { Data((0..<n).map { UInt8(($0 * 31 + 7) % 251) }) }

    func testRoundTripAcrossChunks() throws {
        for size in [0, 1, 99, 100, 101, 250, 1000] {
            let plain = bytes(size)
            let src = try file("p\(size)", plain), enc = dir.appendingPathComponent("p\(size).enc"), out = dir.appendingPathComponent("o\(size)")
            try BackupCrypto.encrypt(src, to: enc, password: "secret", iterations: 50, chunkSize: 100)
            XCTAssertTrue(BackupCrypto.isEncrypted(enc))
            XCTAssertFalse(BackupCrypto.isEncrypted(src))
            try BackupCrypto.decrypt(enc, to: out, password: "secret")
            XCTAssertEqual(try Data(contentsOf: out), plain, "taille \(size)")
        }
    }

    func testEncryptedFileHidesContentAndIsRandomised() throws {
        let plain = Data(repeating: 65, count: 500)
        let src = try file("a", plain)
        let e1 = dir.appendingPathComponent("1.enc"), e2 = dir.appendingPathComponent("2.enc")
        try BackupCrypto.encrypt(src, to: e1, password: "x", iterations: 10)
        try BackupCrypto.encrypt(src, to: e2, password: "x", iterations: 10)
        let a = try Data(contentsOf: e1), b = try Data(contentsOf: e2)
        XCTAssertNotEqual(a, b, "sel et nonces aléatoires")
        XCTAssertNil(a.range(of: Data(repeating: 65, count: 20)), "le contenu n'apparaît pas en clair")
        XCTAssertEqual(a.count, 32 + 4 + 12 + 500 + 16)
    }

    func testWrongPasswordAndTampering() throws {
        let src = try file("a", bytes(450))
        let enc = dir.appendingPathComponent("a.enc"), out = dir.appendingPathComponent("out")
        try BackupCrypto.encrypt(src, to: enc, password: "bon", iterations: 20, chunkSize: 100)
        XCTAssertThrowsError(try BackupCrypto.decrypt(enc, to: out, password: "mauvais")) { XCTAssertEqual($0 as? BackupCryptoError, .wrongPasswordOrCorrupt) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "aucun fichier partiel laissé")
        XCTAssertThrowsError(try BackupCrypto.decrypt(src, to: out, password: "bon")) { XCTAssertEqual($0 as? BackupCryptoError, .notEncrypted) }
        let good = try Data(contentsOf: enc)
        // Un octet modifié dans un bloc.
        var bad = good; bad[32 + 4 + 12 + 5] ^= 1
        XCTAssertThrowsError(try BackupCrypto.decrypt(try file("bad", bad), to: out, password: "bon")) { XCTAssertEqual($0 as? BackupCryptoError, .wrongPasswordOrCorrupt) }
        // Archive tronquée (dernier bloc manquant) : détectée même si les blocs restants sont valides.
        let blockLen = 4 + 12 + 100 + 16
        let cut = good.prefix(32 + 2 * blockLen)
        XCTAssertThrowsError(try BackupCrypto.decrypt(try file("cut", Data(cut)), to: out, password: "bon")) { XCTAssertEqual($0 as? BackupCryptoError, .truncated) }
        // Moitié de bloc.
        XCTAssertThrowsError(try BackupCrypto.decrypt(try file("half", Data(good.dropLast(10))), to: out, password: "bon"))
        // Blocs permutés.
        var swapped = good
        let b0 = 32, b1 = 32 + blockLen
        swapped.replaceSubrange(b0..<(b0 + blockLen), with: good.subdata(in: b1..<(b1 + blockLen)))
        swapped.replaceSubrange(b1..<(b1 + blockLen), with: good.subdata(in: b0..<(b0 + blockLen)))
        XCTAssertThrowsError(try BackupCrypto.decrypt(try file("swap", swapped), to: out, password: "bon"))
        // Octets ajoutés après la fin.
        XCTAssertThrowsError(try BackupCrypto.decrypt(try file("extra", good + Data([1, 2, 3])), to: out, password: "bon"))
        // Mot de passe vide refusé.
        XCTAssertThrowsError(try BackupCrypto.encrypt(src, to: enc, password: "", iterations: 1))
    }

    func testPBKDF2KnownVector() {
        // RFC 6070-like pour HMAC-SHA256 : P="password", S="salt", c=1, dkLen=32 → 120fb6cf…
        let k = BackupCrypto.deriveKey(password: "password", salt: Data("salt".utf8), iterations: 1)
        let hex = k.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        let k2 = BackupCrypto.deriveKey(password: "password", salt: Data("salt".utf8), iterations: 2)
        let hex2 = k2.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
    }
}

final class BackupPolicyTests: CatalogTestCase {
    func populate() throws -> [Photo] {
        [try add("a.jpg", "AAAA", PhotoMetadata(width: 10, height: 10, title: "Alpha", keywords: ["Lieux/Mer"], rating: 3)),
         try add("b.jpg", "BBBB", PhotoMetadata(width: 10, height: 10, title: "Beta"))]
    }

    func testPolicyDefaultsAndClamp() throws {
        XCTAssertEqual(cat.backupPolicy(), BackupPolicy())
        var p = BackupPolicy(); p.everyDays = 9999; p.keep = 0; p.encrypt = true
        try cat.setBackupPolicy(p)
        XCTAssertEqual(cat.backupPolicy().everyDays, 365); XCTAssertEqual(cat.backupPolicy().keep, 1); XCTAssertTrue(cat.backupPolicy().encrypt)
        let d = BackupDestination(name: "iCloud Drive", bookmark: Data([1, 2, 3]))
        try cat.setBackupDestinations([d])
        XCTAssertEqual(cat.backupDestinations(), [d])
    }

    func testStatusAndAlerts() throws {
        XCTAssertEqual(try cat.backupStatus().alerts, [], "catalogue vide : rien à protéger")
        XCTAssertFalse(try cat.backupStatus().due)
        _ = try populate()
        var s = try cat.backupStatus()
        XCTAssertEqual(s.alerts, [.never]); XCTAssertTrue(s.due); XCTAssertEqual(s.uncovered, 2); XCTAssertNil(s.lastAt)
        _ = try cat.protectedBackup(includePhotos: false, password: nil)
        s = try cat.backupStatus()
        XCTAssertEqual(s.alerts, []); XCTAssertFalse(s.due); XCTAssertEqual(s.daysSince, 0)
        // Une photo importée après la sauvegarde n'est pas couverte (horodatage à la seconde : on attend qu'elle change).
        Thread.sleep(forTimeInterval: 1.2)
        _ = try add("c.jpg", "CCCC")
        s = try cat.backupStatus()
        XCTAssertEqual(s.alerts, [.uncovered(photos: 1)]); XCTAssertEqual(s.uncovered, 1)
        // Sauvegarde ancienne.
        let later = Date().addingTimeInterval(86400 * 40)
        s = try cat.backupStatus(now: later)
        XCTAssertTrue(s.alerts.contains(.old(days: 40))); XCTAssertTrue(s.due)
        var p = BackupPolicy(); p.everyDays = 0
        try cat.setBackupPolicy(p)
        XCTAssertFalse(try cat.backupStatus(now: later).due, "0 jour : manuel seulement")
        XCTAssertTrue(BackupAlert.never.message.contains("Aucune sauvegarde"))
    }

    func testEncryptedBackupVerifyRestoreAndDescribe() throws {
        let ph = try populate()
        _ = try cat.createCollection("Favoris", photoIds: [ph[0].id])
        let enc = try cat.protectedBackup(includePhotos: true, password: "motdepasse", iterations: 30)
        XCTAssertEqual(enc.pathExtension, "enc")
        XCTAssertTrue(BackupCrypto.isEncrypted(enc))
        XCTAssertEqual(cat.backups().count, 1, "l'archive en clair n'est pas conservée")
        let raw = try Data(contentsOf: enc)
        XCTAssertNil(raw.range(of: Data("Alpha".utf8)), "le titre n'apparaît pas en clair")
        XCTAssertThrowsError(try Catalog.verifyArchive(enc), "mot de passe requis")
        XCTAssertThrowsError(try Catalog.verifyArchive(enc, password: "faux"))
        let c = try Catalog.verifyArchive(enc, password: "motdepasse")
        XCTAssertTrue(c.ok); XCTAssertEqual(c.photos, 2); XCTAssertEqual(c.files, 2)
        let info = try Catalog.describeArchive(enc, password: "motdepasse")
        XCTAssertTrue(info.encrypted); XCTAssertEqual(info.photos, 2); XCTAssertEqual(info.collections, 1); XCTAssertTrue(info.includesPhotos)
        let other = try Catalog(root: dir.appendingPathComponent("autre"))
        XCTAssertThrowsError(try other.restore(from: enc))
        let r = try other.restore(from: enc, password: "motdepasse")
        XCTAssertEqual(r.photosAdded, 2)
        XCTAssertEqual(try other.search(SearchCriteria(text: "alpha")).count, 1)
        // Sans mot de passe : archive en clair.
        let plain = try cat.protectedBackup(includePhotos: false, password: nil)
        XCTAssertEqual(plain.pathExtension, "zip")
        XCTAssertFalse(try Catalog.describeArchive(plain).encrypted)
    }

    func testRotation() throws {
        _ = try populate()
        var names: [String] = []
        for i in 0..<5 {
            let u = try cat.backup(includePhotos: false, to: cat.backupsDir.appendingPathComponent("Phototheque-test-\(i).zip"))
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(-i) * 100)], ofItemAtPath: u.path)
            names.append(u.lastPathComponent)
        }
        try Data("autre".utf8).write(to: cat.backupsDir.appendingPathComponent("notes.zip"))
        XCTAssertEqual(cat.rotateBackups(keep: 2), 3)
        let left = Set(cat.backups().map { $0.url.lastPathComponent })
        XCTAssertTrue(left.contains("Phototheque-test-0.zip") && left.contains("Phototheque-test-1.zip"))
        XCTAssertTrue(left.contains("notes.zip"), "un fichier étranger n'est jamais supprimé")
        XCTAssertEqual(cat.rotateBackups(keep: 0), 1, "au moins une archive est toujours gardée")
        // Dossier de destination.
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for i in 0..<3 { try Data("x".utf8).write(to: dest.appendingPathComponent("Phototheque-d\(i).zip")) }
        XCTAssertEqual(cat.rotateBackups(keep: 1, in: dest), 2)
    }

    func testRestoreTest() throws {
        let ph = try populate()
        let e = try cat.createEdit(photoId: ph[0].id)
        var prm = EditParams(); prm.exposure = 1
        _ = try cat.updateEdit(e.id, params: prm)
        let alb = try cat.createAlbum(name: "Album")
        _ = try cat.addPage(alb.id, layout: "deux-cote", photoIds: ph.map(\.id))
        let zip = try cat.backup(includePhotos: true)
        let t = try Catalog.testRestore(zip)
        XCTAssertTrue(t.ok, t.problems.joined(separator: " ; "))
        XCTAssertEqual(t.photos, 2); XCTAssertEqual(t.files, 2); XCTAssertEqual(t.albums, 1); XCTAssertEqual(t.edits, 1)
        // Le catalogue réel n'est pas touché.
        XCTAssertEqual(try cat.stats().photos, 2)
        // Archive abîmée : le test le dit.
        var bytes = try Data(contentsOf: zip)
        let r = bytes.range(of: Data("BBBB".utf8))!
        bytes.replaceSubrange(r, with: Data("BBBC".utf8))
        let bad = dir.appendingPathComponent("abimee.zip"); try bytes.write(to: bad)
        XCTAssertThrowsError(try Catalog.testRestore(bad))
        // Archive du catalogue seul : cohérente aussi.
        let light = try cat.backup(includePhotos: false)
        let t2 = try Catalog.testRestore(light)
        XCTAssertTrue(t2.ok, t2.problems.joined(separator: " ; "))
        XCTAssertEqual(t2.photos, 0)
        // Archive chiffrée.
        let enc = try cat.protectedBackup(includePhotos: true, password: "pw", iterations: 10)
        XCTAssertTrue(try Catalog.testRestore(enc, password: "pw").ok)
        XCTAssertThrowsError(try Catalog.testRestore(enc))
    }

    func testSelectiveRestore() throws {
        let ph = try populate()
        _ = try cat.createCollection("Favoris", photoIds: [ph[0].id])
        let e = try cat.createEdit(photoId: ph[0].id)
        var prm = EditParams(); prm.contrast = 20
        _ = try cat.updateEdit(e.id, params: prm)
        let alb = try cat.createAlbum(name: "Album"); _ = try cat.addPage(alb.id, layout: "une", photoIds: [ph[0].id])
        let zip = try cat.backup(includePhotos: true)

        // Catalogue de destination : les photos existent déjà, sans leurs informations.
        func fresh(_ name: String) throws -> Catalog {
            let c = try Catalog(root: dir.appendingPathComponent(name))
            _ = try c.importFile(at: try makeFile("a.jpg", "AAAA"), metadata: PhotoMetadata(width: 10, height: 10)).photo
            _ = try c.importFile(at: try makeFile("b.jpg", "BBBB"), metadata: PhotoMetadata(width: 10, height: 10)).photo
            return c
        }
        let onlyMeta = try fresh("m")
        let r1 = try onlyMeta.restore(from: zip, parts: [.metadata])
        XCTAssertEqual(try onlyMeta.search(SearchCriteria(text: "alpha")).count, 1, "titre restauré")
        XCTAssertEqual(try onlyMeta.keywords().count, 0, "mots-clés non restaurés")
        XCTAssertEqual(try onlyMeta.collections().count, 0)
        XCTAssertEqual(try onlyMeta.albums().count, 0)
        XCTAssertEqual(try onlyMeta.db.scalarInt("SELECT COUNT(*) FROM edits"), 0)
        XCTAssertEqual(r1.collectionsAdded + r1.albumsAdded + r1.editsAdded, 0)

        let kwOnly = try fresh("k")
        _ = try kwOnly.restore(from: zip, parts: [.keywords])
        XCTAssertEqual(try kwOnly.keywords().count, 2)
        XCTAssertEqual(try kwOnly.search(SearchCriteria(text: "alpha")).count, 0, "titre non restauré")
        XCTAssertEqual(try kwOnly.search(SearchCriteria(text: "mer")).count, 1, "mot-clé affecté")

        let others = try fresh("o")
        let r3 = try others.restore(from: zip, parts: [.collections, .edits, .albums])
        XCTAssertEqual(r3.collectionsAdded, 1); XCTAssertEqual(r3.editsAdded, 1); XCTAssertEqual(r3.albumsAdded, 1)
        XCTAssertEqual(try others.keywords().count, 0)

        // Sans « fichiers » : une photo absente n'est pas recopiée.
        let empty = try Catalog(root: dir.appendingPathComponent("vide"))
        let r4 = try empty.restore(from: zip, parts: [.metadata, .keywords])
        XCTAssertEqual(r4.photosAdded, 0); XCTAssertEqual(r4.photosWithoutFile, 2); XCTAssertEqual(try empty.stats().photos, 0)
        let r5 = try empty.restore(from: zip, parts: .all)
        XCTAssertEqual(r5.photosAdded, 2)
        XCTAssertEqual(RestoreParts.all.rawValue, 63)
    }
}
