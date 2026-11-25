import Foundation

// Sauvegardes et sécurité : archives chiffrées, rotation, destinations, test de restauration, restauration sélective, alertes.
// iOS ne permet pas de tâche planifiée fiable en arrière-plan : la sauvegarde « automatique » est proposée (ou faite)
// à l'ouverture de l'application quand la dernière est trop ancienne (`backupStatus().due`).

/// Parties d'une sauvegarde que l'on peut restaurer séparément.
public struct RestoreParts: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let metadata = RestoreParts(rawValue: 1)      // titres, légendes, notes, étiquettes, lieux
    public static let keywords = RestoreParts(rawValue: 2)      // mots-clés et leur affectation
    public static let collections = RestoreParts(rawValue: 4)
    public static let edits = RestoreParts(rawValue: 8)         // versions de retouche
    public static let albums = RestoreParts(rawValue: 16)
    public static let files = RestoreParts(rawValue: 32)        // photos absentes, recopiées depuis l'archive
    public static let all: RestoreParts = [.metadata, .keywords, .collections, .edits, .albums, .files]
}

/// Réglages de sauvegarde (le mot de passe n'y figure jamais : il reste dans le trousseau de l'appareil).
public struct BackupPolicy: Codable, Equatable, Sendable {
    public var everyDays = 7                 // 0 : sauvegarde manuelle seulement
    public var includePhotos = false
    public var keep = 5                      // nombre d'archives gardées dans Sauvegardes/
    public var encrypt = false
    public var copyToDestinations = true
    public var automatic = false             // à l'ouverture de l'application, si la sauvegarde est due
    public init() {}

    public var clamped: BackupPolicy {
        var p = self
        p.everyDays = min(365, max(0, everyDays)); p.keep = min(100, max(1, keep))
        return p
    }
}

/// Dossier de copie des sauvegardes (iCloud Drive, disque, serveur… choisi dans Fichiers). `bookmark` : signet de sécurité fourni par l'application.
public struct BackupDestination: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bookmark: Data
    public var lastCopyAt: String?
    public var lastError: String?
    public init(id: String = UUID().uuidString, name: String, bookmark: Data, lastCopyAt: String? = nil, lastError: String? = nil) {
        self.id = id; self.name = name; self.bookmark = bookmark; self.lastCopyAt = lastCopyAt; self.lastError = lastError
    }
}

public enum BackupAlert: Equatable, Sendable {
    case never                       // photos mais aucune sauvegarde
    case old(days: Int)              // dernière sauvegarde trop ancienne
    case uncovered(photos: Int)      // photos importées depuis la dernière sauvegarde
    public var message: String {
        switch self {
        case .never: return "Aucune sauvegarde : le catalogue n'est pas protégé."
        case .old(let d): return "La dernière sauvegarde date de \(d) jours."
        case .uncovered(let n): return "\(n) photo(s) importée(s) depuis la dernière sauvegarde."
        }
    }
}

public struct BackupStatus: Equatable, Sendable {
    public var lastAt: Date?
    public var daysSince: Int?
    public var due: Bool
    public var uncovered: Int
    public var alerts: [BackupAlert]
}

/// Contenu d'une archive, sans rien restaurer.
public struct ArchiveInfo: Equatable, Sendable {
    public var createdAt: String
    public var appVersion: String
    public var encrypted: Bool
    public var includesPhotos: Bool
    public var photos: Int
    public var keywords: Int
    public var collections: Int
    public var edits: Int
    public var albums: Int
}

/// Résultat d'un test de restauration (dans un catalogue temporaire, sans toucher au catalogue réel).
public struct RestoreTest: Equatable, Sendable {
    public var ok: Bool
    public var problems: [String]
    public var photos: Int
    public var files: Int
    public var keywords: Int
    public var collections: Int
    public var edits: Int
    public var albums: Int
}

extension Catalog {
    // MARK: - Réglages

    public func backupPolicy() -> BackupPolicy {
        guard let s = setting("backup.policy")?.data(using: .utf8), let p = try? JSONDecoder().decode(BackupPolicy.self, from: s) else { return BackupPolicy() }
        return p.clamped
    }

    public func setBackupPolicy(_ p: BackupPolicy) throws {
        try setSetting("backup.policy", String(data: try JSONEncoder().encode(p.clamped), encoding: .utf8))
    }

    public func backupDestinations() -> [BackupDestination] {
        guard let s = setting("backup.destinations")?.data(using: .utf8), let d = try? JSONDecoder().decode([BackupDestination].self, from: s) else { return [] }
        return d
    }

    public func setBackupDestinations(_ d: [BackupDestination]) throws {
        try setSetting("backup.destinations", String(data: try JSONEncoder().encode(d), encoding: .utf8))
    }

    // MARK: - État et alertes

    /// Date de la dernière sauvegarde : la plus récente entre les archives présentes et la dernière notée (copie hors appareil comprise).
    public func lastBackupDate() -> Date? {
        let noted = setting("backup.last").flatMap { ISODate.date($0) }
        let local = backups().first?.date
        return [noted, local].compactMap { $0 }.max()
    }

    public func noteBackup(at date: Date = Date()) throws { try setSetting("backup.last", ISODate.string(date)) }

    public func backupStatus(now: Date = Date()) throws -> BackupStatus {
        let last = lastBackupDate()
        let total = try stats().photos
        let uncovered: Int
        if let last { uncovered = try db.scalarInt("SELECT COUNT(*) FROM photos WHERE imported_at > ?", [.text(ISODate.string(last))]) } else { uncovered = total }
        let days = last.map { max(0, Int(now.timeIntervalSince($0) / 86400)) }
        let policy = backupPolicy()
        var alerts: [BackupAlert] = []
        if total > 0 {
            if last == nil { alerts.append(.never) }
            else if let d = days, d > Catalog.backupAlertDays { alerts.append(.old(days: d)) }
            if last != nil, uncovered > 0 { alerts.append(.uncovered(photos: uncovered)) }
        }
        let due = total > 0 && policy.everyDays > 0 && (last == nil || (days ?? 0) >= policy.everyDays)
        return BackupStatus(lastAt: last, daysSince: days, due: due, uncovered: uncovered, alerts: alerts)
    }

    // MARK: - Archives protégées

    /// Sauvegarde, chiffrée si un mot de passe est donné (l'archive en clair n'est alors pas conservée).
    @discardableResult
    public func protectedBackup(includePhotos: Bool, password: String?, iterations: Int = BackupCrypto.defaultIterations, progress: ((Int, Int) -> Void)? = nil) throws -> URL {
        let zip = try backup(includePhotos: includePhotos, progress: progress)
        defer { try? noteBackup() }
        guard let password, !password.isEmpty else { return zip }
        let enc = zip.appendingPathExtension(BackupCrypto.fileExtension)
        do { try BackupCrypto.encrypt(zip, to: enc, password: password, iterations: iterations) } catch { try? FileManager.default.removeItem(at: enc); throw error }
        try FileManager.default.removeItem(at: zip)
        log("sauvegarde chiffrée", enc.lastPathComponent)
        return enc
    }

    /// Ne garde que les `keep` archives les plus récentes de `dir` (par défaut Sauvegardes/). Renvoie le nombre supprimé.
    @discardableResult
    public func rotateBackups(keep: Int, in dir: URL? = nil) -> Int {
        let target = dir ?? backupsDir
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: target, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let mine = urls.filter { $0.lastPathComponent.hasPrefix("Phototheque-") && !$0.lastPathComponent.hasPrefix(".") && ["zip", BackupCrypto.fileExtension].contains($0.pathExtension.lowercased()) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        var removed = 0
        for (u, _) in mine.dropFirst(max(1, keep)) { if (try? fm.removeItem(at: u)) != nil { removed += 1 } }
        return removed
    }

    /// Décrit une archive (chiffrée ou non) sans rien restaurer.
    public static func describeArchive(_ url: URL, password: String? = nil) throws -> ArchiveInfo {
        let enc = BackupCrypto.isEncrypted(url)
        return try withPlainArchive(url, password: password) { plain in
            let m = try readManifest(try ZipReader(url: plain))
            return ArchiveInfo(createdAt: m.createdAt, appVersion: m.appVersion, encrypted: enc, includesPhotos: m.includesPhotos, photos: m.photos.count,
                               keywords: m.keywords.count, collections: m.collections.count, edits: m.edits?.count ?? 0, albums: m.albums?.count ?? 0)
        }
    }

    /// Ouvre l'archive en clair (déchiffrée dans un fichier temporaire, effacé ensuite).
    static func withPlainArchive<T>(_ url: URL, password: String?, _ body: (URL) throws -> T) throws -> T {
        guard BackupCrypto.isEncrypted(url) else { return try body(url) }
        guard let pw = password, !pw.isEmpty else { throw SQLiteError("Cette archive est chiffrée : saisissez son mot de passe.") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dechiffre-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try BackupCrypto.decrypt(url, to: tmp, password: pw)
        return try body(tmp)
    }

    public static func verifyArchive(_ url: URL, password: String? = nil) throws -> ArchiveCheck {
        try withPlainArchive(url, password: password) { try verifyPlain($0) }
    }

    public func restore(from url: URL, progress: ((Int, Int) -> Void)? = nil, password: String? = nil, parts: RestoreParts = .all) throws -> RestoreReport {
        try Catalog.withPlainArchive(url, password: password) { plain in try restorePlain(from: plain, progress: progress, parts: parts) }
    }

    /// Test de restauration : l'archive est restaurée dans un catalogue temporaire (effacé ensuite) puis comparée à son contenu.
    /// Le catalogue réel n'est pas touché. C'est la seule preuve qu'une sauvegarde est vraiment utilisable.
    public static func testRestore(_ url: URL, password: String? = nil) throws -> RestoreTest {
        let info = try describeArchive(url, password: password)
        let check = try verifyArchive(url, password: password)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-restauration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var problems = check.problems
        let cat = try Catalog(root: tmp)
        _ = try cat.restore(from: url, password: password)
        let got = try cat.stats()
        if info.includesPhotos, got.photos != info.photos { problems.append("Photos restaurées : \(got.photos) sur \(info.photos).") }
        if !info.includesPhotos, got.photos != 0 { problems.append("Une archive du catalogue seul ne doit pas créer de photo.") }
        let albums = try cat.albums().count, colls = try cat.collections().count
        let edits = try cat.db.scalarInt("SELECT COUNT(*) FROM edits")
        if albums != info.albums { problems.append("Albums restaurés : \(albums) sur \(info.albums).") }
        if edits != info.edits && info.includesPhotos { problems.append("Versions de retouche restaurées : \(edits) sur \(info.edits).") }
        let integrity = try Schema.integrity(cat.db)
        problems.append(contentsOf: integrity)
        return RestoreTest(ok: problems.isEmpty, problems: problems, photos: got.photos, files: check.files, keywords: got.keywords, collections: colls, edits: edits, albums: albums)
    }
}
