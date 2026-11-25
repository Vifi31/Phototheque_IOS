import SwiftUI
import PhotothequeCore

/// Export de photos : format, taille ou tirage, retouches, métadonnées, filigrane, profil, noms.
/// Les fichiers sont écrits dans Exports/ (jamais à côté des originaux, jamais écrasés).
struct ExportSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let ids: [Int64]

    @AppStorage("export.options") private var saved = ""
    @State private var o = ExportOptions()
    @State private var sizeChoice = "orig"
    @State private var running = false
    @State private var progress = 0.0
    @State private var result: (urls: [URL], errors: [String], folder: URL)?

    private static let sizes: [(String, String, Int?)] = [("orig", "Taille d'origine", nil), ("3000", "3000 px (grand côté)", 3000), ("2048", "2048 px", 2048),
                                                          ("1600", "1600 px", 1600), ("1080", "1080 px (réseaux sociaux)", 1080), ("800", "800 px (e-mail)", 800), ("print", "Tirage…", nil)]

    var body: some View {
        NavigationStack {
            Form {
                if let r = result {
                    Section("Terminé") {
                        Text("\(r.urls.count) fichier(s) exporté(s) dans Exports/\(r.folder.lastPathComponent).")
                        if !r.urls.isEmpty { ShareLink(items: r.urls) { Label("Partager les fichiers", systemImage: "square.and.arrow.up") } }
                        ForEach(r.errors, id: \.self) { Text($0).foregroundStyle(.red).font(.footnote) }
                    }
                } else {
                    Section("Fichier") {
                        Picker("Format", selection: $o.format) { ForEach(ExportFormat.allCases, id: \.self) { Text($0.label).tag($0) } }
                        if o.format.supportsQuality {
                            VStack(alignment: .leading) {
                                Text("Qualité : \(Int(o.quality * 100)) %").font(.subheadline)
                                Slider(value: $o.quality, in: 0.3...1)
                            }
                        }
                        Picker("Taille", selection: $sizeChoice) { ForEach(Self.sizes, id: \.0) { Text($0.1).tag($0.0) } }
                            .onChange(of: sizeChoice) { _, v in
                                o.maxSide = Self.sizes.first { $0.0 == v }?.2
                                o.printSize = v == "print" ? (o.printSize ?? PrintSize.all[0].id) : nil
                            }
                        if sizeChoice == "print" {
                            Picker("Tirage", selection: Binding(get: { o.printSize ?? PrintSize.all[0].id }, set: { o.printSize = $0 })) {
                                ForEach(PrintSize.all) { Text($0.label).tag($0.id) }
                            }
                            Picker("Définition", selection: $o.printDPI) { Text("200 ppp").tag(200); Text("300 ppp").tag(300); Text("360 ppp").tag(360) }
                            if let id = o.printSize, let ps = PrintSize.all.first(where: { $0.id == id }) {
                                Text("\(ps.pixels(dpi: o.printDPI).long) × \(ps.pixels(dpi: o.printDPI).short) pixels").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Appliquer les retouches", isOn: $o.useEdits)
                        Picker("Profil colorimétrique", selection: $o.profile) { ForEach(ColorProfile.allCases, id: \.self) { Text($0.label).tag($0) } }
                    }
                    Section("Métadonnées") {
                        Picker("Informations", selection: $o.metadata) { ForEach(MetadataMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                    }
                    Section("Filigrane") {
                        TextField("Texte (laisser vide : aucun)", text: $o.watermark)
                        if !o.watermark.isEmpty {
                            Picker("Position", selection: $o.watermarkPosition) { ForEach(WatermarkPosition.allCases, id: \.self) { Text($0.label).tag($0) } }
                            VStack(alignment: .leading) {
                                Text("Opacité : \(Int(o.watermarkOpacity * 100)) %").font(.subheadline)
                                Slider(value: $o.watermarkOpacity, in: 0.1...1)
                            }
                        }
                    }
                    Section {
                        TextField("{nom}", text: $o.namePattern).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Nom des fichiers") } footer: {
                        Text("Variables : {nom} {n} (numéro) {date} {titre} {note}. Un nom déjà pris est suivi de (2), (3)… : aucun fichier n'est écrasé.")
                    }
                    Section {
                        Button { run() } label: {
                            if running { HStack { ProgressView(value: progress); Text("\(Int(progress * 100)) %") } }
                            else { Label("Exporter \(ids.count) photo(s)", systemImage: "square.and.arrow.up") }
                        }
                        .disabled(running || ids.isEmpty)
                    }
                }
            }
            .navigationTitle("Exporter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Annuler" : "Fermer") { dismiss() } } }
            .onAppear {
                if let d = saved.data(using: .utf8), let v = try? JSONDecoder().decode(ExportOptions.self, from: d) { o = v }
                sizeChoice = o.printSize != nil ? "print" : (Self.sizes.first { $0.2 == o.maxSide && $0.2 != nil }?.0 ?? "orig")
            }
        }
    }

    private func run() {
        o = o.clamped
        if let d = try? JSONEncoder().encode(o), let s = String(data: d, encoding: .utf8) { saved = s }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = library.catalog.exportsDir.appendingPathComponent("Export-\(f.string(from: Date()))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let jobs = try library.catalog.exportPlan(ids, options: o, into: folder)
            let items = jobs.map { j in
                ExportItem(source: library.url(j.photo), dest: folder.appendingPathComponent(j.fileName),
                           params: j.editId.flatMap { try? library.catalog.editVersion($0)?.params })
            }
            running = true; progress = 0
            let opts = o
            Task { @MainActor in
                let out = await Task.detached(priority: .userInitiated) {
                    Exporter.run(items, options: opts) { done, total in
                        Task { @MainActor in progress = total == 0 ? 1 : Double(done) / Double(total) }
                    }
                }.value
                running = false
                library.catalog.log("export", "\(out.done.count) photo(s) → \(folder.lastPathComponent)")
                result = (out.done, out.errors, folder)
            }
        } catch { library.report(error) }
    }
}
