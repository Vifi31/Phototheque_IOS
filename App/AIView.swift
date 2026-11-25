import SwiftUI
import Vision
import PhotothequeCore

/// Analyse d'image faite SUR L'APPAREIL par le framework Vision d'Apple : aucune image ne quitte l'appareil.
enum AIAnalyzer {
    /// Étiquettes (identifiant anglais, confiance) des objets et scènes reconnus.
    static func labels(for url: URL) -> [(String, Double)] {
        guard let cg = ImageTools.thumbnail(of: url, maxPixel: 700) else { return [] }
        let req = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([req])) != nil, let obs = req.results else { return [] }
        return obs.filter { $0.confidence >= 0.15 }.sorted { $0.confidence > $1.confidence }.prefix(14).map { ($0.identifier, Double($0.confidence)) }
    }

    /// Empreinte de similarité (Vision), archivée telle quelle dans le catalogue.
    static func featurePrint(for url: URL) -> Data? {
        guard let cg = ImageTools.thumbnail(of: url, maxPixel: 600) else { return nil }
        let req = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([req])) != nil, let obs = req.results?.first else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
    }

    static func distance(_ a: Data, _ b: Data) -> Float? {
        guard let x = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: a),
              let y = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: b) else { return nil }
        var d: Float = 0
        return (try? x.computeDistance(&d, to: y)) != nil ? d : nil
    }
}

/// Assistant facultatif : suggestions de mots-clés (à valider), recherche par description, regroupements, photos proches.
struct AIView: View {
    @EnvironmentObject var library: Library
    @State private var stats: (analysed: Int, labels: Int, pending: Int) = (0, 0, 0)
    @State private var toAnalyse = 0
    @State private var running = false
    @State private var progress = ""
    @State private var cancel = false
    @State private var describe = ""

    var body: some View {
        List {
            Section {
                Text("Photothèque reconnaît le contenu des photos avec le moteur d'Apple, directement sur cet appareil : aucune image n'est envoyée nulle part. Rien n'est ajouté à vos photos sans votre accord.")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Photos analysées", value: "\(stats.analysed)")
                if toAnalyse > 0 {
                    Button { start() } label: {
                        if running { HStack { ProgressView(); Text(progress) } } else { Label("Analyser \(toAnalyse) photo(s)", systemImage: "sparkles") }
                    }.disabled(running)
                }
                if running { Button("Arrêter", role: .destructive) { cancel = true } }
            } header: { Text("Analyse") }

            Section("Chercher par description") {
                HStack {
                    TextField("montagne neige, chat, plage…", text: $describe).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(search)
                    Button("Chercher", action: search).disabled(describe.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Cherche dans le contenu reconnu des photos analysées (français ou anglais).").font(.caption).foregroundStyle(.secondary)
            }

            Section("À valider") {
                NavigationLink { AISuggestionsView() } label: { LabeledContent("Mots-clés suggérés", value: "\(stats.pending)") }
            }

            Section("Regroupements") {
                NavigationLink { EventsView() } label: { Label("Événements", systemImage: "calendar") }
                NavigationLink { PlacesView() } label: { Label("Lieux", systemImage: "mappin.and.ellipse") }
                NavigationLink { NearbyView() } label: { Label("Photos proches d'une photo", systemImage: "square.on.square.dashed") }
            }

            Section {
                Button(role: .destructive) { try? library.catalog.clearAI(); load() } label: { Label("Effacer les résultats de l'analyse", systemImage: "trash") }
            }
        }
        .navigationTitle("Assistant IA")
        .onAppear(perform: load)
        .onDisappear { cancel = true }
    }

    private func load() {
        stats = (try? library.catalog.aiStats()) ?? (0, 0, 0)
        toAnalyse = (try? library.catalog.photosWithoutAI(limit: 100_000).count) ?? 0
    }

    private func search() {
        let t = describe.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        library.criteria = SearchCriteria(sort: library.criteria.sort).with { $0.describe = t }
        library.tab = .photos
    }

    private func start() {
        running = true; cancel = false
        Task { @MainActor in
            let todo = (try? library.catalog.photosWithoutAI(limit: 100_000)) ?? []
            for (i, p) in todo.enumerated() {
                if cancel { break }
                progress = "\(i + 1) / \(todo.count)"
                let url = library.url(p)
                let labels = await Task.detached(priority: .utility) { AIAnalyzer.labels(for: url) }.value
                if labels.isEmpty { try? library.catalog.markAnalysed(p.id) } else { try? library.catalog.saveAILabels(p.id, labels: labels) }
            }
            running = false
            load()
        }
    }
}

/// Validation des suggestions : accepter, refuser, tout accepter au-dessus d'un seuil.
struct AISuggestionsView: View {
    @EnvironmentObject var library: Library
    @State private var items: [AISuggestion] = []
    @State private var viewer: Photo?

    var body: some View {
        List {
            if items.isEmpty { Text("Aucune suggestion en attente. Analysez d'abord vos photos.").foregroundStyle(.secondary) }
            else {
                Section {
                    Button { accept(0.8) } label: { Label("Tout accepter au-dessus de 80 %", systemImage: "checkmark.circle") }
                } footer: { Text("Vérifiez les suggestions : l'IA se trompe parfois. Un refus n'est jamais reproposé pour cette photo.") }
            }
            ForEach(items) { s in
                HStack(spacing: 12) {
                    if let p = try? library.catalog.photo(s.photoId) {
                        PhotoImage(photo: p, maxPixel: 200).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { viewer = p }
                    }
                    VStack(alignment: .leading) {
                        Text(s.keyword).font(.headline)
                        Text("\(Int(s.confidence * 100)) % de confiance").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { act { try library.catalog.rejectSuggestion(s.photoId, keyword: s.keyword) } } label: { Image(systemName: "xmark.circle").foregroundStyle(.red) }.buttonStyle(.borderless)
                    Button { act { try library.catalog.acceptSuggestion(s.photoId, keyword: s.keyword) } } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }.buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("Mots-clés suggérés")
        .onAppear(perform: load)
        .fullScreenCover(item: $viewer) { PhotoViewer(photos: [$0], startIndex: 0) }
    }

    private func load() { items = (try? library.catalog.pendingSuggestions(limit: 500)) ?? [] }
    private func act(_ body: () throws -> Void) { library.run(body); load() }
    private func accept(_ min: Double) { library.run { _ = try library.catalog.acceptSuggestions(minConfidence: min) }; load() }
}

/// Événements : photos prises à la suite.
struct EventsView: View {
    @EnvironmentObject var library: Library
    @State private var groups: [EventGroup] = []
    @State private var gap = 6.0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    Text("Écart maximal entre deux photos : \(Int(gap)) h").font(.subheadline)
                    Slider(value: $gap, in: 1...48, step: 1) { editing in if !editing { load() } }
                }
            }
            ForEach(groups) { g in
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(g.photoIds.prefix(12), id: \.self) { id in
                                if let p = try? library.catalog.photo(id) { PhotoImage(photo: p, maxPixel: 200).frame(width: 64, height: 64).clipped() }
                            }
                        }
                    }
                    Button { saveCollection(g) } label: { Label("Créer une collection", systemImage: "rectangle.stack.badge.plus") }
                } header: {
                    Text(title(g)) + Text(" · \(g.photoIds.count) photo(s)")
                }
            }
            if groups.isEmpty { Text("Aucun événement : il faut des photos datées, prises à la suite.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Événements")
        .onAppear(perform: load)
    }

    private func title(_ g: EventGroup) -> String {
        let a = ISODate.date(g.from), b = ISODate.date(g.to)
        var t = a.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? g.from
        if let a, let b, !Calendar.current.isDate(a, inSameDayAs: b) { t += " – " + b.formatted(date: .abbreviated, time: .omitted) }
        return g.place.isEmpty ? t : t + " · " + g.place
    }

    private func load() { groups = (try? library.catalog.eventGroups(gapHours: gap)) ?? [] }
    private func saveCollection(_ g: EventGroup) {
        library.run { _ = try library.catalog.createCollection(title(g), photoIds: g.photoIds) }
        library.inform("Collection « \(title(g)) » créée.")
    }
}

struct PlacesView: View {
    @EnvironmentObject var library: Library
    @State private var groups: [PlaceGroup] = []

    var body: some View {
        List {
            ForEach(groups) { g in
                Button {
                    library.criteria = SearchCriteria(sort: library.criteria.sort).with { $0.place = g.place }
                    library.tab = .photos
                } label: { LabeledContent(g.place) { Text("\(g.photoIds.count)").foregroundStyle(.secondary) } }
            }
            if groups.isEmpty { Text("Aucun lieu renseigné sur au moins 2 photos.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Lieux")
        .onAppear { groups = (try? library.catalog.placeGroups()) ?? [] }
    }
}

/// Photos proches d'une photo, d'après l'empreinte de similarité de Vision (calculée sur l'appareil).
struct NearbyView: View {
    @EnvironmentObject var library: Library
    @State private var chooser = false
    @State private var base: Photo?
    @State private var results: [(Photo, Float)] = []
    @State private var working = false
    @State private var viewer: ViewerRef?

    struct ViewerRef: Identifiable { let id = UUID(); let photos: [Photo]; let index: Int }

    var body: some View {
        List {
            Section {
                Button { chooser = true } label: { Label(base == nil ? "Choisir une photo…" : "Changer de photo…", systemImage: "photo") }
                if working { HStack { ProgressView(); Text("Calcul des empreintes…") } }
            } footer: { Text("Les empreintes de toutes les photos sont calculées une fois (sur l'appareil), puis comparées.") }
            if let base {
                Section("Photo de départ") { PhotoImage(photo: base, maxPixel: 400, contentMode: .fit).frame(height: 160) }
                Section("Les plus proches") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 4)], spacing: 4) {
                        ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                            VStack(spacing: 2) {
                                PhotoCell(photo: r.0).onTapGesture { viewer = ViewerRef(photos: results.map(\.0), index: i) }
                                Text(String(format: "%.2f", r.1)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Photos proches")
        .sheet(isPresented: $chooser) { PhotoChooser { id in if let p = try? library.catalog.photo(id) { base = p; compute(p) } } }
        .fullScreenCover(item: $viewer) { PhotoViewer(photos: $0.photos, startIndex: $0.index) }
    }

    private func compute(_ p: Photo) {
        working = true; results = []
        Task { @MainActor in
            let todo = (try? library.catalog.photosWithoutPrint(limit: 100_000)) ?? []
            for x in todo {
                let url = library.url(x)
                if let d = await Task.detached(priority: .utility, operation: { AIAnalyzer.featurePrint(for: url) }).value { try? library.catalog.saveAIPrint(x.id, data: d, engine: "vision") }
            }
            let prints = (try? library.catalog.aiPrints()) ?? []
            guard let mine = prints.first(where: { $0.photoId == p.id })?.data else { working = false; return }
            let ranked = prints.filter { $0.photoId != p.id }.compactMap { x -> (Int64, Float)? in AIAnalyzer.distance(mine, x.data).map { (x.photoId, $0) } }
                .sorted { $0.1 < $1.1 }.prefix(30)
            results = ranked.compactMap { r in (try? library.catalog.photo(r.0)).map { ($0, r.1) } }
            working = false
        }
    }
}
