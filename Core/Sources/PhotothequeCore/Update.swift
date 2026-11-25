import Foundation

/// Numéros de version « x.y.z » (comparaison numérique : 0.10.0 > 0.9.0).
public enum Version {
    public static func parts(_ s: String) -> [Int] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("v") { t.removeFirst() }
        let core = t.split(separator: "-", maxSplits: 1).first.map(String.init) ?? t
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// -1, 0 ou 1.
    public static func compare(_ a: String, _ b: String) -> Int {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count, 3) {
            let d = (i < x.count ? x[i] : 0) - (i < y.count ? y[i] : 0)
            if d != 0 { return d < 0 ? -1 : 1 }
        }
        return 0
    }

    public static func isValid(_ s: String) -> Bool {
        let p = parts(s)
        return p.count >= 3 && s.trimmingCharacters(in: .whitespaces).range(of: #"^v?\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    }
}

/// Dernière version publiée (« release » GitHub) et ses fichiers.
public struct ReleaseInfo: Equatable, Sendable {
    public struct Asset: Equatable, Sendable { public var name: String; public var url: String; public var size: Int64 }
    public var version: String
    public var name: String
    public var notes: String
    public var pageURL: String
    public var assets: [Asset]

    /// Lit la réponse de `GET /repos/<dépôt>/releases/latest`. `nil` si elle n'a pas la forme attendue.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String, Version.isValid(tag) else { return nil }
        let assets = (o["assets"] as? [[String: Any]] ?? []).compactMap { a -> Asset? in
            guard let n = a["name"] as? String, let u = a["browser_download_url"] as? String else { return nil }
            return Asset(name: n, url: u, size: (a["size"] as? NSNumber)?.int64Value ?? 0)
        }
        var v = tag; if v.lowercased().hasPrefix("v") { v.removeFirst() }
        return ReleaseInfo(version: v, name: o["name"] as? String ?? tag, notes: (o["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           pageURL: o["html_url"] as? String ?? "", assets: assets)
    }
}

/// Résultat d'une recherche de mise à jour.
public struct UpdateStatus: Equatable, Sendable {
    public var current: String
    public var latest: String?
    public var newer: Bool
    public var notes: String
    public var pageURL: String
    public var ipaURL: String?
    public var ipaName: String?
    public var sumsURL: String?
    public var error: String?

    public init(current: String, latest: String? = nil, newer: Bool = false, notes: String = "", pageURL: String = "",
                ipaURL: String? = nil, ipaName: String? = nil, sumsURL: String? = nil, error: String? = nil) {
        self.current = current; self.latest = latest; self.newer = newer; self.notes = notes; self.pageURL = pageURL
        self.ipaURL = ipaURL; self.ipaName = ipaName; self.sumsURL = sumsURL; self.error = error
    }

    /// Compare la version installée à la dernière release.
    public static func evaluate(current: String, release: ReleaseInfo?) -> UpdateStatus {
        guard let r = release else {
            return UpdateStatus(current: current, latest: nil, newer: false, notes: "", pageURL: "", ipaURL: nil, ipaName: nil, sumsURL: nil, error: "Aucune version publiée sur GitHub.")
        }
        let ipa = r.assets.first { $0.name.lowercased().hasSuffix(".ipa") }
        let sums = r.assets.first { $0.name == "SHA256SUMS" }
        return UpdateStatus(current: current, latest: r.version, newer: Version.compare(r.version, current) > 0, notes: r.notes,
                            pageURL: r.pageURL, ipaURL: ipa?.url, ipaName: ipa?.name, sumsURL: sums?.url, error: nil)
    }
}

/// Fichier SHA256SUMS (une ligne « empreinte *nom » par fichier), comme publié avec chaque version.
public enum ChecksumFile {
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count > 66 else { continue }
            let hash = String(t.prefix(64)).lowercased()
            guard hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var name = String(t.dropFirst(64)).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            if !name.isEmpty { out[name] = hash }
        }
        return out
    }

    /// Vrai si l'empreinte publiée pour `name` est celle de `data`.
    public static func verify(_ data: Data, name: String, in text: String) -> Bool {
        guard let expected = parse(text)[name] else { return false }
        return SHA256Hasher.hex(data) == expected
    }
}
