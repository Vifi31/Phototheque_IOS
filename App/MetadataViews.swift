import SwiftUI
import UniformTypeIdentifiers
import PhotothequeCore

/// Modification en masse : titre (modèle), légende, lieu, note, étiquette, mots-clés, décalage de date ; aperçu avant d'appliquer ; annulation.
struct BulkMetadataSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let ids: [Int64]

    @State private var title = ""
    @State private var caption = ""
    @State private var place = ""
    @State private var setRating = false
    @State private var rating = 3
    @State private var setColor = false
    @State private var color = 0
    @State private var add = ""
    @State private var remove = ""
    @State private var clearKeywords = false
    @State private var shiftHours = 0
    @State private var preview: [BulkPreviewRow] = []
    @State private var batches: [MetaBatch] = []

    private var change: BulkChange {
        var c = BulkChange()
        if !title.isEmpty { c.title = title }
        if !caption.isEmpty { c.caption = caption }
        if !place.isEmpty { c.place = place }
        if setRating { c.rating = rating }
        if setColor { c.color = color }
        c.addKeywords = list(add); c.removeKeywords = list(remove); c.clearKeywords = clearKeywords
        if shiftHours != 0 { c.takenAtShiftSeconds = shiftHours * 3600 }
        return c
    }

    private func list(_ s: String) -> [String] { s.split(whereSeparator: { $0 == ";" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Texte") {
                    TextField("Titre ({nom} {n} {date})", text: $title)
                    TextField("Légende", text: $caption)
                    TextField("Lieu", text: $place)
                }
                Section("Classement") {
                    Toggle("Changer la note", isOn: $setRating)
                    if setRating { Stepper("Note : \(rating) ★", value: $rating, in: 0...5) }
                    Toggle("Changer l'étiquette", isOn: $setColor)
                    if setColor { Picker("Étiquette", selection: $color) { ForEach(ColorLabel.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) } } }
                }
                Section {
                    TextField("Ajouter (Lieux/France; Famille)", text: $add).textInputAutocapitalization(.never)
                    TextField("Retirer (même syntaxe)", text: $remove).textInputAutocapitalization(.never)
                    Toggle("Retirer tous les mots-clés", isOn: $clearKeywords)
                } header: { Text("Mots-clés") }
                Section {
                    Stepper(shiftHours == 0 ? "Aucun décalage" : "Décalage : \(shiftHours > 0 ? "+" : "")\(shiftHours) h", value: $shiftHours, in: -48...48)
                } header: { Text("Date de prise de vue") } footer: { Text("Pour corriger une horloge d'appareil mal réglée.") }

                Section {
                    Button { preview = (try? library.catalog.bulkPreview(ids, change)) ?? [] } label: { Label("Aperçu des changements", systemImage: "eye") }
                    if !preview.isEmpty {
                        ForEach(preview.prefix(40)) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.fileName).font(.subheadline)
                                ForEach(Array(r.changes.enumerated()), id: \.offset) { _, c in
                                    Text("\(c.field) : \(c.before.isEmpty ? "—" : c.before) → \(c.after.isEmpty ? "—" : c.after)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if preview.count > 40 { Text("… et \(preview.count - 40) autre(s) photo(s)").font(.footnote) }
                    }
                } header: { Text("Aperçu (\(ids.count) photo(s) choisie(s))") }

                Section {
                    Button { apply() } label: { Label("Appliquer à \(ids.count) photo(s)", systemImage: "checkmark.circle") }.disabled(change.isEmpty)
                } footer: { Text("L'application est une seule étape : elle s'annule ensuite en un geste.") }

                if !batches.isEmpty {
                    Section("Dernières modifications en masse") {
                        ForEach(batches.prefix(5)) { b in
                            HStack {
                                VStack(alignment: .leading) { Text(b.summary); Text(Fmt.date(b.at)).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if b.undone { Text("annulée").font(.caption).foregroundStyle(.secondary) }
                                else { Button("Annuler") { undo(b) }.buttonStyle(.bordered) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Modifier en masse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onAppear { batches = (try? library.catalog.metaBatches()) ?? [] }
        }
    }

    private func apply() {
        do {
            let r = try library.catalog.applyBulk(ids, change)
            library.run {}
            batches = (try? library.catalog.metaBatches()) ?? []
            preview = []
            library.inform(r.changed == 0 ? "Rien à modifier." : "\(r.changed) photo(s) modifiée(s). Vous pouvez annuler cette modification.")
        } catch { library.report(error) }
    }

    private func undo(_ b: MetaBatch) {
        do { let n = try library.catalog.undoBulk(b.id); library.run {}; batches = (try? library.catalog.metaBatches()) ?? []; library.inform("\(n) photo(s) rétablie(s).") }
        catch { library.report(error) }
    }
}

/// Photos récemment ouvertes dans la visionneuse.
struct RecentsSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [Photo] = []
    @State private var viewer: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                if photos.isEmpty { Text("Aucune photo consultée pour le moment.").foregroundStyle(.secondary).padding(40) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 2)], spacing: 2) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in PhotoCell(photo: p).onTapGesture { viewer = i } }
                }
            }
            .navigationTitle("Récemment vues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) { Button("Effacer", role: .destructive) { try? library.catalog.clearRecents(); photos = [] }.disabled(photos.isEmpty) }
            }
            .onAppear { photos = (try? library.catalog.recentPhotos()) ?? [] }
            .fullScreenCover(item: Binding(get: { viewer.map { ViewerIndex(i: $0) } }, set: { if $0 == nil { viewer = nil } })) { v in PhotoViewer(photos: photos, startIndex: v.i) }
        }
    }

    private struct ViewerIndex: Identifiable { let i: Int; var id: Int { i } }
}

/// Comparaison de 2 à 4 photos côte à côte, avec leurs informations clés.
struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [Photo]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let cols = photos.count <= 2 ? photos.count : 2
                let rows = Int((Double(photos.count) / Double(max(1, cols))).rounded(.up))
                let w = geo.size.width / CGFloat(max(1, cols)), h = geo.size.height / CGFloat(max(1, rows))
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<cols, id: \.self) { c in
                                if r * cols + c < photos.count { cell(photos[r * cols + c]).frame(width: w, height: h) }
                            }
                        }
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Comparaison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func cell(_ p: Photo) -> some View {
        ZStack(alignment: .bottom) {
            ZoomableImage(photo: p)
            VStack(spacing: 1) {
                Text(p.displayTitle).font(.caption.bold()).lineLimit(1)
                Text([p.width.map { "\($0)×\(p.height ?? 0)" }, Fmt.bytes(p.size), p.rating > 0 ? String(repeating: "★", count: p.rating) : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption2)
            }
            .foregroundStyle(.white).padding(4).frame(maxWidth: .infinity).background(.black.opacity(0.5))
        }
    }
}
