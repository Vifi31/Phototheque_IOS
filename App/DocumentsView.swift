import SwiftUI
import PhotothequeCore

/// Documents PDF : planches-contact, fiches détaillées, catalogues thématiques, portfolios.
struct DocumentsView: View {
    @EnvironmentObject var library: Library
    @AppStorage("documents.options") private var saved = ""
    @State private var o = DocumentOptions()
    @State private var source = 0
    @State private var collections: [PhotoCollection] = []
    @State private var collectionId: Int64 = 0
    @State private var running = false
    @State private var progress = 0.0
    @State private var result: URL?
    @State private var count = 0

    var body: some View {
        Form {
            Section("Type de document") {
                Picker("Type", selection: $o.kind) { ForEach(DocumentKind.allCases) { Text($0.label).tag($0) } }
                Text(o.kind.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Photos") {
                Picker("Source", selection: $source) {
                    Text("Photos affichées (\(library.total))").tag(0)
                    Text("Une collection").tag(1)
                }
                if source == 1 { Picker("Collection", selection: $collectionId) { ForEach(collections) { Text($0.name).tag($0.id) } } }
            }
            Section("Page") {
                TextField("Titre", text: $o.title)
                TextField("Sous-titre", text: $o.subtitle)
                TextField("Auteur", text: $o.author)
                Picker("Format", selection: $o.pageSize) { ForEach(DocPageSize.allCases) { Text($0.label).tag($0) } }
                if o.kind == .contactSheet || o.kind == .catalog {
                    Stepper("Colonnes : \(o.columns)", value: $o.columns, in: 1...8)
                    Stepper("Lignes : \(o.rows)", value: $o.rows, in: 1...10)
                    Picker("Regroupement", selection: $o.groupBy) { ForEach(DocGroupBy.allCases) { Text($0.label).tag($0) } }
                    Toggle("Sommaire", isOn: $o.toc)
                    Toggle("Page de couverture", isOn: $o.cover)
                }
                Toggle("Appliquer les retouches", isOn: $o.useEdits)
            }
            if o.kind != .detailSheets {
                Section("Légendes") {
                    ForEach(DocField.allCases) { f in
                        Toggle(f.label, isOn: Binding(get: { o.fields.contains(f) }, set: { on in
                            if on { if !o.fields.contains(f) { o.fields.append(f) } } else { o.fields.removeAll { $0 == f } }
                        }))
                    }
                }
            }
            Section {
                Button { run() } label: {
                    if running { HStack { ProgressView(value: progress); Text("\(Int(progress * 100)) %") } } else { Label("Créer le PDF", systemImage: "doc.richtext") }
                }.disabled(running)
                if let result { ShareLink(item: result) { Label("Partager \(result.lastPathComponent)", systemImage: "square.and.arrow.up") } }
            } footer: { Text("Le PDF est rangé dans Fichiers › Sur mon iPhone › Photothèque › Exports.") }
        }
        .navigationTitle("Documents PDF")
        .onAppear {
            if let d = saved.data(using: .utf8), let v = try? JSONDecoder().decode(DocumentOptions.self, from: d) { o = v }
            collections = (try? library.catalog.collections()) ?? []; collectionId = collections.first?.id ?? 0
        }
    }

    private func run() {
        o = o.clamped
        if let d = try? JSONEncoder().encode(o), let s = String(data: d, encoding: .utf8) { saved = s }
        do {
            let ids = source == 0 ? try library.catalog.ids(library.criteria) : try library.catalog.ids(SearchCriteria(collectionId: collectionId, sort: .takenAsc))
            guard !ids.isEmpty else { library.inform("Aucune photo à mettre en page."); return }
            guard ids.count <= 3000 else { library.inform("Trop de photos (\(ids.count)) : affinez la sélection (3 000 au plus)."); return }
            let plan = try library.catalog.documentPlan(ids, options: o)
            var info: [Int64: DocPhoto] = [:]
            let edits = try library.catalog.defaultEdits()
            for p in try library.catalog.photos(ids: ids) {
                let kws = try library.catalog.keywordsOf(p.id).map { (try? library.catalog.keywordPathName($0.id, separator: "/")) ?? $0.name }.sorted().joined(separator: ", ")
                info[p.id] = DocPhoto(photo: p, url: library.url(p), edit: edits[p.id]?.params,
                                      lines: try library.catalog.docLines(p, fields: o.fields), keywords: kws, colorName: p.color > 0 ? (ColorLabel(rawValue: p.color)?.name ?? "") : "")
            }
            running = true; progress = 0; result = nil
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
            let name = TextFold.safeFileName((o.title.isEmpty ? o.kind.label : o.title) + "-" + f.string(from: Date())) + ".pdf"
            let dest = library.catalog.exportsDir.appendingPathComponent(name)
            Task { @MainActor in
                let data = await Task.detached(priority: .userInitiated) {
                    DocumentPDF.build(plan: plan, photos: info) { d, t in Task { @MainActor in progress = Double(d) / Double(max(1, t)) } }
                }.value
                running = false
                do { try data.write(to: dest); library.catalog.log("document", "\(o.kind.label) : \(plan.pages.count) page(s)"); result = dest }
                catch { library.report(error) }
            }
        } catch { library.report(error) }
    }
}
