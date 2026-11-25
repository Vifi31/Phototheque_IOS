import SwiftUI
import PhotothequeCore

/// Filtres à choix multiples. Plusieurs valeurs d'un même critère se combinent par « ou » ;
/// les critères entre eux se combinent par « et » (tous) ou « ou » (au moins un), au choix.
struct FiltersSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var c: SearchCriteria
    @State private var years: [(year: Int, count: Int)] = []
    @State private var cameras: [(name: String, count: Int)] = []
    @State private var formats: [(name: String, count: Int)] = []
    @State private var lenses: [(name: String, count: Int)] = []
    @State private var categories: [(name: String, count: Int)] = []
    @State private var keywordRows: [KeywordRow] = []

    struct KeywordRow: Identifiable { let id: Int64; let name: String; let depth: Int; let count: Int }

    init(initial: SearchCriteria) { _c = State(initialValue: initial) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Les photos doivent remplir", selection: $c.matchAny) {
                        Text("Tous les critères").tag(false)
                        Text("Au moins un").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(c.matchAny
                         ? "OU : une photo est affichée dès qu'elle remplit l'un des critères choisis. Le texte de la recherche reste exigé."
                         : "ET : une photo est affichée si elle remplit tous les critères choisis.")
                }

                Section("Mots-clés") {
                    Picker("Mots-clés", selection: Binding(get: { c.hasKeywords == nil ? 0 : (c.hasKeywords! ? 1 : 2) },
                                                        set: { c.hasKeywords = $0 == 0 ? nil : ($0 == 1) })) {
                        Text("Indifférent").tag(0)
                        Text("Avec au moins un").tag(1)
                        Text("Sans mot-clé").tag(2)
                    }
                    if !keywordRows.isEmpty {
                        DisclosureGroup("Un ou plusieurs mots-clés" + badge(c.keywordIds.count)) {
                            ForEach(keywordRows) { k in
                                checkRow(k.name, count: k.count, on: c.keywordIds.contains(k.id), indent: k.depth) { toggle(&c.keywordIds, k.id) }
                            }
                            Toggle("Inclure les sous-mots-clés", isOn: $c.includeSubKeywords)
                        }
                    }
                }

                if !years.isEmpty {
                    Section {
                        DisclosureGroup("Années" + badge(c.years.count)) {
                            ForEach(years, id: \.year) { y in
                                checkRow(String(y.year), count: y.count, on: c.years.contains(y.year)) { toggle(&c.years, y.year) }
                            }
                        }
                    }
                }
                if !cameras.isEmpty {
                    Section {
                        DisclosureGroup("Appareils" + badge(c.cameras.count)) {
                            ForEach(cameras, id: \.name) { x in
                                checkRow(x.name, count: x.count, on: c.cameras.contains(x.name)) { toggle(&c.cameras, x.name) }
                            }
                        }
                    }
                }
                if !formats.isEmpty {
                    Section {
                        DisclosureGroup("Formats" + badge(c.formats.count)) {
                            ForEach(formats, id: \.name) { x in
                                checkRow(x.name, count: x.count, on: c.formats.contains(x.name)) { toggle(&c.formats, x.name) }
                            }
                        }
                    }
                }

                Section("Autres critères") {
                    Picker("Note minimale", selection: Binding(get: { c.minRating ?? 0 }, set: { c.minRating = $0 == 0 ? nil : $0 })) {
                        Text("Toutes").tag(0)
                        ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0) + " et plus").tag($0) }
                    }
                    Picker("Étiquette", selection: Binding(get: { c.color ?? 0 }, set: { c.color = $0 == 0 ? nil : $0 })) {
                        Text("Toutes").tag(0)
                        ForEach(ColorLabel.allCases.filter { $0 != .none }, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                    }
                    Picker("Position GPS", selection: Binding(get: { c.hasGPS == nil ? 0 : (c.hasGPS! ? 1 : 2) },
                                                           set: { c.hasGPS = $0 == 0 ? nil : ($0 == 1) })) {
                        Text("Indifférent").tag(0); Text("Avec position").tag(1); Text("Sans position").tag(2)
                    }
                    Picker("Orientation", selection: Binding(get: { c.orientation?.rawValue ?? "" }, set: { c.orientation = Orientation(rawValue: $0) })) {
                        Text("Toutes").tag("")
                        ForEach(Orientation.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Manque", selection: Binding(get: { c.missing?.rawValue ?? "" }, set: { c.missing = MissingInfo(rawValue: $0) })) {
                        Text("Aucun").tag("")
                        ForEach(MissingInfo.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    if !lenses.isEmpty {
                        Picker("Objectif", selection: Binding(get: { c.lens ?? "" }, set: { c.lens = $0.isEmpty ? nil : $0 })) {
                            Text("Tous").tag("")
                            ForEach(lenses, id: \.name) { Text("\($0.name) (\($0.count))").tag($0.name) }
                        }
                    }
                    if !categories.isEmpty {
                        Picker("Catégorie de mot-clé", selection: Binding(get: { c.keywordCategory ?? "" }, set: { c.keywordCategory = $0.isEmpty ? nil : $0 })) {
                            Text("Toutes").tag("")
                            ForEach(categories, id: \.name) { Text("\($0.name) (\($0.count))").tag($0.name) }
                        }
                    }
                    Picker("Sauvegarde", selection: Binding(get: { c.uncoveredByBackup == nil ? 0 : (c.uncoveredByBackup! ? 1 : 2) }, set: { c.uncoveredByBackup = $0 == 0 ? nil : ($0 == 1) })) {
                        Text("Indifférent").tag(0); Text("Pas encore sauvegardées").tag(1); Text("Déjà sauvegardées").tag(2)
                    }
                    Picker("Variantes", selection: $c.variants) { ForEach(VariantMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                    HStack {
                        Text("Contenu (IA)")
                        TextField("montagne, neige…", text: $c.describe).multilineTextAlignment(.trailing).textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("Lieu")
                        TextField("Ville, région, pays…", text: Binding(get: { c.place ?? "" }, set: { c.place = $0.isEmpty ? nil : $0 }))
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Tri") {
                    Picker("Ordre", selection: $c.sort) { ForEach(PhotoSort.allCases, id: \.self) { Text($0.label).tag($0) } }
                }

                Section {
                    Text("\((try? library.catalog.count(c)) ?? 0) photo(s) correspondent à ces critères.").foregroundStyle(.secondary)
                    Button("Effacer tous les filtres", role: .destructive) {
                        c = SearchCriteria(text: c.text, collectionId: c.collectionId, sort: c.sort)
                    }
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Appliquer") { library.criteria = c; dismiss() } }
            }
            .onAppear(perform: load)
        }
    }

    private func badge(_ n: Int) -> String { n > 0 ? " · \(n)" : "" }

    private func toggle<T: Equatable>(_ list: inout [T], _ v: T) {
        if let i = list.firstIndex(of: v) { list.remove(at: i) } else { list.append(v) }
    }

    private func checkRow(_ label: String, count: Int, on: Bool, indent: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Color.accentColor : .secondary)
                Text(label).foregroundStyle(.primary).padding(.leading, CGFloat(indent) * 14)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func load() {
        years = (try? library.catalog.years()) ?? []
        cameras = (try? library.catalog.cameras()) ?? []
        formats = (try? library.catalog.formats()) ?? []
        lenses = (try? library.catalog.lenses()) ?? []
        categories = (try? library.catalog.keywordCategories()) ?? []
        var rows: [KeywordRow] = []
        func walk(_ nodes: [KeywordNode], _ depth: Int) {
            for n in nodes {
                rows.append(KeywordRow(id: n.keyword.id, name: n.keyword.name, depth: depth, count: n.keyword.photoCount))
                walk(n.children, depth + 1)
            }
        }
        walk((try? library.catalog.keywordTree()) ?? [], 0)
        keywordRows = rows
    }
}
