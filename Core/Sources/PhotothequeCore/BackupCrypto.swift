import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum BackupCryptoError: LocalizedError, Equatable {
    case notEncrypted, wrongPasswordOrCorrupt, truncated, unsupported
    public var errorDescription: String? {
        switch self {
        case .notEncrypted: return "Ce fichier n'est pas une archive chiffrée par Photothèque."
        case .wrongPasswordOrCorrupt: return "Mot de passe incorrect, ou archive abîmée."
        case .truncated: return "L'archive chiffrée est incomplète (copie interrompue ?)."
        case .unsupported: return "Archive chiffrée par une version plus récente de Photothèque."
        }
    }
}

/// Chiffrement des sauvegardes : mot de passe → clé (PBKDF2-HMAC-SHA256), puis AES-256-GCM par blocs de 1 Mio.
///
/// Format (« .enc ») : `PTHQENC1` · sel (16 o) · itérations (4 o) · taille de bloc (4 o), puis pour chaque bloc :
/// longueur en clair (4 o) · nonce (12 o) · texte chiffré · étiquette GCM (16 o). Chaque bloc authentifie son rang
/// et s'il est le dernier : un bloc déplacé, retiré ou une archive tronquée sont détectés, pas seulement un octet modifié.
/// Le mot de passe n'est jamais écrit ; sans lui l'archive est illisible (aucune récupération possible).
public enum BackupCrypto {
    public static let magic = Data("PTHQENC1".utf8)
    public static let defaultIterations = 200_000
    public static let defaultChunkSize = 1 << 20
    public static let fileExtension = "enc"

    public static func isEncrypted(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        return (try? h.read(upToCount: magic.count)) == magic
    }

    /// Clé de 32 octets (PBKDF2-HMAC-SHA256, un seul bloc de sortie).
    static func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let key = SymmetricKey(data: Data(password.utf8))
        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + Data([0, 0, 0, 1]), using: key))
        var t = [UInt8](u)
        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                let bytes = [UInt8](u)
                for i in 0..<32 { t[i] ^= bytes[i] }
            }
        }
        return SymmetricKey(data: Data(t))
    }

    private static func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]) }
    private static func read32(_ d: Data) -> UInt32 { d.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
    private static func aad(_ counter: UInt64, last: Bool) -> Data {
        var d = Data(); var c = counter.bigEndian
        withUnsafeBytes(of: &c) { d.append(contentsOf: $0) }
        d.append(last ? 1 : 0)
        return d
    }

    public static func encrypt(_ src: URL, to dest: URL, password: String, iterations: Int = defaultIterations, chunkSize: Int = defaultChunkSize) throws {
        guard !password.isEmpty else { throw SQLiteError("Le mot de passe ne peut pas être vide.") }
        let fm = FileManager.default
        let tmp = dest.deletingLastPathComponent().appendingPathComponent("." + dest.lastPathComponent + ".tmp")
        try? fm.removeItem(at: tmp)
        fm.createFile(atPath: tmp.path, contents: nil)
        let input = try FileHandle(forReadingFrom: src), output = try FileHandle(forWritingTo: tmp)
        defer { try? input.close(); try? output.close() }
        do {
            var salt = Data(count: 16)
            for i in 0..<16 { salt[i] = UInt8.random(in: 0...255) }
            let key = deriveKey(password: password, salt: salt, iterations: iterations)
            try output.write(contentsOf: magic + salt + be32(UInt32(iterations)) + be32(UInt32(chunkSize)))
            var counter: UInt64 = 0
            var current = try input.read(upToCount: chunkSize) ?? Data()
            while true {
                let next = current.isEmpty ? Data() : (try input.read(upToCount: chunkSize) ?? Data())
                let last = next.isEmpty
                var nonceBytes = Data(count: 12)
                for i in 0..<12 { nonceBytes[i] = UInt8.random(in: 0...255) }
                let box = try AES.GCM.seal(current, using: key, nonce: try AES.GCM.Nonce(data: nonceBytes), authenticating: aad(counter, last: last))
                try output.write(contentsOf: be32(UInt32(current.count)) + nonceBytes + box.ciphertext + box.tag)
                counter += 1
                if last { break }
                current = next
            }
            try output.close()
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    public static func decrypt(_ src: URL, to dest: URL, password: String) throws {
        let fm = FileManager.default
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        guard let head = try input.read(upToCount: 8 + 16 + 4 + 4), head.count == 32, head.prefix(8) == magic else { throw BackupCryptoError.notEncrypted }
        let salt = head.subdata(in: 8..<24)
        let iterations = Int(read32(head.subdata(in: 24..<28))), chunk = Int(read32(head.subdata(in: 28..<32)))
        guard iterations > 0, iterations <= 10_000_000, chunk > 0, chunk <= 64 << 20 else { throw BackupCryptoError.unsupported }
        let key = deriveKey(password: password, salt: salt, iterations: iterations)
        let tmp = dest.deletingLastPathComponent().appendingPathComponent("." + dest.lastPathComponent + ".tmp")
        try? fm.removeItem(at: tmp)
        fm.createFile(atPath: tmp.path, contents: nil)
        let output = try FileHandle(forWritingTo: tmp)
        defer { try? output.close() }
        do {
            var counter: UInt64 = 0
            var sawLast = false
            while !sawLast {
                guard let lenData = try input.read(upToCount: 4), lenData.count == 4 else { throw BackupCryptoError.truncated }
                let n = Int(read32(lenData))
                guard n <= chunk else { throw BackupCryptoError.wrongPasswordOrCorrupt }
                guard let body = try input.read(upToCount: 12 + n + 16), body.count == 12 + n + 16 else { throw BackupCryptoError.truncated }
                let nonce = try AES.GCM.Nonce(data: body.prefix(12))
                let cipher = body.subdata(in: 12..<(12 + n)), tag = body.suffix(16)
                let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag)
                var plain: Data?
                if let p = try? AES.GCM.open(box, using: key, authenticating: aad(counter, last: false)) { plain = p }
                else if let p = try? AES.GCM.open(box, using: key, authenticating: aad(counter, last: true)) { plain = p; sawLast = true }
                guard let p = plain else { throw BackupCryptoError.wrongPasswordOrCorrupt }
                try output.write(contentsOf: p)
                counter += 1
            }
            // Rien ne doit suivre le dernier bloc.
            if let extra = try input.read(upToCount: 1), !extra.isEmpty { throw BackupCryptoError.wrongPasswordOrCorrupt }
            try output.close()
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}
