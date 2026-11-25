import Foundation

// Assistant facultatif et local : l'application analyse les photos AVEC LE MOTEUR D'APPLE SUR L'APPAREIL (framework Vision) ;
// aucune image ne quitte l'appareil. Le cœur range les étiquettes trouvées, propose des mots-clés (à valider un par un),
// permet de chercher par description et regroupe les photos en événements et en lieux. Rien n'est affecté sans accord.

/// Traduction des étiquettes anglaises de Vision en français (les plus courantes ; les autres restent en anglais).
public enum AILabelTranslator {
    public static let table: [String: String] = [
        "mountain": "montagne", "snow": "neige", "sky": "ciel", "cloud": "nuage", "sunset": "coucher de soleil", "sunrise": "lever de soleil",
        "beach": "plage", "sea": "mer", "ocean": "océan", "water": "eau", "lake": "lac", "river": "rivière", "waterfall": "cascade", "island": "île",
        "forest": "forêt", "tree": "arbre", "flower": "fleur", "plant": "plante", "grass": "herbe", "field": "champ", "garden": "jardin", "park": "parc",
        "sand": "sable", "rock": "rocher", "cliff": "falaise", "desert": "désert", "hill": "colline", "valley": "vallée", "volcano": "volcan",
        "cat": "chat", "dog": "chien", "bird": "oiseau", "horse": "cheval", "cow": "vache", "sheep": "mouton", "fish": "poisson", "insect": "insecte",
        "butterfly": "papillon", "animal": "animal", "wildlife": "faune", "pet": "animal de compagnie", "puppy": "chiot", "kitten": "chaton",
        "people": "personnes", "person": "personne", "adult": "adulte", "child": "enfant", "baby": "bébé", "crowd": "foule", "portrait": "portrait",
        "man": "homme", "woman": "femme", "boy": "garçon", "girl": "fille", "family": "famille", "wedding": "mariage", "party": "fête", "celebration": "célébration",
        "city": "ville", "building": "bâtiment", "house": "maison", "street": "rue", "road": "route", "bridge": "pont", "tower": "tour", "castle": "château",
        "church": "église", "monument": "monument", "architecture": "architecture", "skyscraper": "gratte-ciel", "village": "village", "market": "marché",
        "car": "voiture", "vehicle": "véhicule", "bicycle": "vélo", "bike": "vélo", "motorcycle": "moto", "boat": "bateau", "ship": "navire", "airplane": "avion",
        "aircraft": "avion", "train": "train", "bus": "bus", "truck": "camion", "railway": "voie ferrée",
        "food": "nourriture", "meal": "repas", "dessert": "dessert", "cake": "gâteau", "fruit": "fruit", "vegetable": "légume", "coffee": "café", "wine": "vin",
        "drink": "boisson", "bread": "pain", "pizza": "pizza", "restaurant": "restaurant", "kitchen": "cuisine",
        "indoor": "intérieur", "outdoor": "extérieur", "room": "pièce", "furniture": "meuble", "table": "table", "chair": "chaise", "bed": "lit", "sofa": "canapé",
        "night": "nuit", "light": "lumière", "fire": "feu", "firework": "feu d'artifice", "candle": "bougie", "sun": "soleil", "moon": "lune", "star": "étoile",
        "rain": "pluie", "fog": "brouillard", "storm": "orage", "rainbow": "arc-en-ciel", "ice": "glace", "autumn": "automne", "winter": "hiver", "summer": "été", "spring": "printemps",
        "sport": "sport", "ball": "ballon", "football": "football", "tennis": "tennis", "ski": "ski", "swimming": "natation", "cycling": "cyclisme", "running": "course", "hiking": "randonnée",
        "music": "musique", "concert": "concert", "guitar": "guitare", "piano": "piano", "book": "livre", "art": "art", "painting": "peinture", "museum": "musée", "sculpture": "sculpture",
        "toy": "jouet", "game": "jeu", "camera": "appareil photo", "computer": "ordinateur", "phone": "téléphone", "screen": "écran", "document": "document", "text": "texte",
        "sign": "panneau", "map": "carte", "clothing": "vêtement", "hat": "chapeau", "shoe": "chaussure", "bag": "sac", "jewelry": "bijou", "glasses": "lunettes",
        "landscape": "paysage", "scenery": "paysage", "nature": "nature", "panorama": "panorama", "horizon": "horizon", "coast": "côte", "harbor": "port", "pier": "jetée",
        "lighthouse": "phare", "farm": "ferme", "barn": "grange", "vineyard": "vignoble", "camping": "camping", "tent": "tente", "campfire": "feu de camp", "swimming pool": "piscine",
        "zoo": "zoo", "aquarium": "aquarium", "airport": "aéroport", "station": "gare", "stadium": "stade", "school": "école", "hospital": "hôpital", "shop": "magasin",
        "macro": "macro", "closeup": "gros plan", "selfie": "selfie", "statue": "statue", "fountain": "fontaine", "window": "fenêtre", "door": "porte", "wall": "mur", "roof": "toit",
    ]

    /// Français d'une étiquette Vision (identifiants du type « mountain », « hot_air_balloon »), `nil` si inconnue.
    public static func french(_ identifier: String) -> String? {
        let key = identifier.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return table[key]
    }

    /// Nom présentable : français si connu, sinon l'étiquette d'origine lisible.
    public static func display(_ identifier: String) -> String {
        french(identifier) ?? identifier.replacingOccurrences(of: "_", with: " ")
    }
}

public struct AISuggestion: Identifiable, Equatable, Sendable {
    public var photoId: Int64
    public var keyword: String
    public var confidence: Double
    public var id: String { "\(photoId)-\(keyword)" }
}

/// Un événement : photos prises à la suite (écart maximal entre deux photos), avec le lieu le plus fréquent.
public struct EventGroup: Identifiable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var place: String
    public var photoIds: [Int64]
    public var id: String { from + "#" + (photoIds.first.map(String.init) ?? "") }
}

public struct PlaceGroup: Identifiable, Equatable, Sendable {
    public var place: String
    public var photoIds: [Int64]
    public var id: String { place }
}

extension Catalog {
    public static let aiMinLabel = 0.15
    public static let aiSuggestMin = 0.45

    /// Range les étiquettes d'une photo (remplace les précédentes) et prépare les suggestions de mots-clés.
    /// `labels` : identifiants Vision et confiance (0 à 1). Chaque étiquette est rangée en anglais ET en français (recherche dans les deux langues).
    public func saveAILabels(_ photoId: Int64, labels: [(label: String, confidence: Double)]) throws {
        guard try photo(photoId) != nil else { throw SQLiteError("Photo inconnue") }
        let kept = labels.filter { $0.confidence >= Catalog.aiMinLabel }
        let have = Set(try keywordsOf(photoId).map { TextFold.fold($0.name) })
        let rejected = Set(try db.query("SELECT keyword FROM ai_suggestions WHERE photo_id = ? AND status = 'rejected'", [.int(photoId)]).compactMap { $0.string("keyword") })
        try db.transaction {
            try db.run("DELETE FROM ai_labels WHERE photo_id = ?", [.int(photoId)])
            try db.run("DELETE FROM ai_suggestions WHERE photo_id = ? AND status = 'pending'", [.int(photoId)])
            for l in kept {
                let en = TextFold.fold(l.label.replacingOccurrences(of: "_", with: " "))
                try db.run("INSERT OR REPLACE INTO ai_labels(photo_id, label, confidence) VALUES (?, ?, ?)", [.int(photoId), .text(en), .of(l.confidence)])
                if let fr = AILabelTranslator.french(l.label) {
                    try db.run("INSERT OR REPLACE INTO ai_labels(photo_id, label, confidence) VALUES (?, ?, ?)", [.int(photoId), .text(TextFold.fold(fr)), .of(l.confidence)])
                }
                if l.confidence >= Catalog.aiSuggestMin {
                    let name = AILabelTranslator.display(l.label)
                    let nice = name.prefix(1).uppercased() + name.dropFirst()
                    if !have.contains(TextFold.fold(nice)), !rejected.contains(nice) {
                        try db.run("INSERT OR IGNORE INTO ai_suggestions(photo_id, keyword, confidence, status) VALUES (?, ?, ?, 'pending')", [.int(photoId), .text(nice), .of(l.confidence)])
                    }
                }
            }
        }
    }

    public func aiLabels(_ photoId: Int64) throws -> [(label: String, confidence: Double)] {
        try db.query("SELECT label, confidence FROM ai_labels WHERE photo_id = ? ORDER BY confidence DESC", [.int(photoId)])
            .map { ($0.string("label") ?? "", $0.double("confidence") ?? 0) }
    }

    /// Photos jamais analysées.
    public func photosWithoutAI(limit: Int = 500) throws -> [Photo] {
        try db.query("""
            SELECT p.* FROM photos p WHERE NOT EXISTS (SELECT 1 FROM ai_labels l WHERE l.photo_id = p.id)
              AND NOT EXISTS (SELECT 1 FROM ai_suggestions s WHERE s.photo_id = p.id) ORDER BY p.id LIMIT ?
            """, [.of(limit)]).map(Photo.init(row:))
    }

    /// Une photo « analysée sans résultat » est notée par une suggestion refusée vide : on ne la réanalyse pas à chaque fois.
    public func markAnalysed(_ photoId: Int64) throws {
        try db.run("INSERT OR IGNORE INTO ai_suggestions(photo_id, keyword, confidence, status) VALUES (?, '', 0, 'rejected')", [.int(photoId)])
    }

    public func pendingSuggestions(limit: Int = 300) throws -> [AISuggestion] {
        try db.query("SELECT photo_id, keyword, confidence FROM ai_suggestions WHERE status = 'pending' ORDER BY confidence DESC, photo_id LIMIT ?", [.of(limit)])
            .map { AISuggestion(photoId: $0.int64("photo_id") ?? 0, keyword: $0.string("keyword") ?? "", confidence: $0.double("confidence") ?? 0) }
    }

    public func pendingSuggestionCount() throws -> Int { try db.scalarInt("SELECT COUNT(*) FROM ai_suggestions WHERE status = 'pending'") }

    /// Accepte une suggestion : le mot-clé (éventuellement sous un chemin « Lieux/Mer ») est affecté à la photo.
    public func acceptSuggestion(_ photoId: Int64, keyword: String, asPath path: String? = nil) throws {
        let kid = try keywordPath((path?.isEmpty == false) ? path! : keyword)
        try assignKeyword(kid, to: [photoId])
        try db.run("UPDATE ai_suggestions SET status = 'accepted' WHERE photo_id = ? AND keyword = ?", [.int(photoId), .text(keyword)])
    }

    /// Refuse une suggestion : elle ne sera plus reproposée pour cette photo.
    public func rejectSuggestion(_ photoId: Int64, keyword: String) throws {
        try db.run("UPDATE ai_suggestions SET status = 'rejected' WHERE photo_id = ? AND keyword = ?", [.int(photoId), .text(keyword)])
    }

    /// Accepte toutes les suggestions dont la confiance atteint `minConfidence`.
    @discardableResult
    public func acceptSuggestions(minConfidence: Double) throws -> Int {
        var n = 0
        for s in try pendingSuggestions(limit: 100_000) where s.confidence >= minConfidence { try acceptSuggestion(s.photoId, keyword: s.keyword); n += 1 }
        return n
    }

    public func aiStats() throws -> (analysed: Int, labels: Int, pending: Int) {
        (try db.scalarInt("SELECT COUNT(DISTINCT photo_id) FROM ai_labels"), try db.scalarInt("SELECT COUNT(*) FROM ai_labels"), try pendingSuggestionCount())
    }

    public func clearAI() throws {
        try db.run("DELETE FROM ai_labels"); try db.run("DELETE FROM ai_suggestions"); try db.run("DELETE FROM ai_prints")
    }

    // MARK: Empreintes de similarité (Vision) — rangées telles quelles, comparées côté application

    public func saveAIPrint(_ photoId: Int64, data: Data, engine: String) throws {
        try db.run("INSERT OR REPLACE INTO ai_prints(photo_id, print, engine) VALUES (?, ?, ?)", [.int(photoId), .blob(data), .text(engine)])
    }

    public func aiPrints() throws -> [(photoId: Int64, data: Data)] {
        try db.query("SELECT photo_id, print FROM ai_prints ORDER BY photo_id").compactMap { r in
            guard let id = r.int64("photo_id"), let d = r.blob("print") else { return nil }
            return (id, d)
        }
    }

    public func photosWithoutPrint(limit: Int = 500) throws -> [Photo] {
        try db.query("SELECT p.* FROM photos p WHERE NOT EXISTS (SELECT 1 FROM ai_prints a WHERE a.photo_id = p.id) ORDER BY p.id LIMIT ?", [.of(limit)]).map(Photo.init(row:))
    }

    // MARK: Regroupements

    /// Événements : photos datées, consécutives, séparées par moins de `gapHours`. Les groupes de moins de `minPhotos` photos sont écartés.
    public func eventGroups(gapHours: Double = 6, minPhotos: Int = 3) throws -> [EventGroup] {
        let rows = try db.query("SELECT id, taken_at, place FROM photos WHERE taken_at IS NOT NULL ORDER BY taken_at, id")
        var groups: [[(id: Int64, at: Date, iso: String, place: String)]] = []
        for r in rows {
            guard let id = r.int64("id"), let iso = r.string("taken_at"), let at = ISODate.date(iso) else { continue }
            let item = (id, at, iso, r.string("place") ?? "")
            if let last = groups.last?.last, at.timeIntervalSince(last.at) <= gapHours * 3600 { groups[groups.count - 1].append(item) } else { groups.append([item]) }
        }
        return groups.filter { $0.count >= max(1, minPhotos) }.map { g in
            let places = Dictionary(grouping: g.map(\.place).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
            let place = places.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? ""
            return EventGroup(from: g.first!.iso, to: g.last!.iso, place: place, photoIds: g.map(\.id))
        }.reversed()
    }

    /// Photos regroupées par lieu renseigné, les plus fournis d'abord.
    public func placeGroups(minPhotos: Int = 2) throws -> [PlaceGroup] {
        var map: [String: [Int64]] = [:]
        for r in try db.query("SELECT id, place FROM photos WHERE place <> '' ORDER BY id") { if let id = r.int64("id") { map[r.string("place") ?? "", default: []].append(id) } }
        return map.filter { $0.value.count >= minPhotos }.map { PlaceGroup(place: $0.key, photoIds: $0.value) }
            .sorted { $0.photoIds.count == $1.photoIds.count ? $0.place < $1.place : $0.photoIds.count > $1.photoIds.count }
    }
}

extension Row {
    public func blob(_ name: String) -> Data? { if case .blob(let d) = self[name] { return d }; return nil }
}
