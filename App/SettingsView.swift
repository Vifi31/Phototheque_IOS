import SwiftUI
import UniformTypeIdentifiers
import PhotothequeCore

/// Réglages : chiffres, sauvegardes (planifier, chiffrer, copier hors de l'appareil, tester, restaurer), sécurité, exports, entretien, À propos.
struct SettingsView: View {
    @EnvironmentObject var library: Library
    @AppStorage("lock.enabled") private var lockEnabled = false
    @State private var stats: CatalogStats?
    @State private var backups: [(url: URL, size: Int64, date: Date)] = []
    @State private var showRestorePicker = false
    @State private var restoreURL: URL?
    @State private var csvURL: URL?
    @State private var cacheSize: Int64 = 0
    @State private var verifyTarget: URL?
    @State private var verifyPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                if let s = stats {
                    Section("Catalogue") {
                        LabeledContent("Photos", value: "\(s.photos)")
                        LabeledContent("Volume", value: Fmt.bytes(s.bytes))
                        LabeledContent("Mots-clés", value: "\(s.keywords)")
                        LabeledContent("Collections", value: "\(s.collections)")
                        manque("Sans mot-clé", s.withoutKeywords, .keywords)
                        manque("Sans titre", s.withoutTitle, .title)
                        LabeledContent("Avec position GPS", value: "\(s.withGPS)")
                        LabeledContent("Notées", value: "\(s.rated)")
                    }
                }

                Section {
                    if let st = library.backupStatus {
                        ForEach(Array(st.alerts.enumerated()), id: \.offset) { _, a in
                            Label(a.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote)
                        }
                        if st.alerts.isEmpty, let d = st.lastAt {
                            Label("Dernière sauvegarde : \(d.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.shield.fill").foregroundStyle(.green).font(.footnote)
                        }
                    }
                    Button { library.runBackup(includePhotos: false) } label: { Label("Sauvegarder le catalogue", systemImage: "doc.zipper") }
                    Button { library.runBackup(includePhotos: true) } label: { Label("Sauvegarde complète (avec les photos)", systemImage: "externaldrive.badge.plus") }
                    NavigationLink { BackupSettingsView() } label: { Label("Planification, chiffrement, copies…", systemImage: "gearshape.2") }
                    Button { showRestorePicker = true } label: { Label("Restaurer ou tester une sauvegarde…", systemImage: "arrow.counterclockwise") }
                    ForEach(backups, id: \.url) { b in
                        HStack {
                            VStack(alignment: .leading) {
                                HStack(spacing: 4) {
                                    if BackupCrypto.isEncrypted(b.url) { Image(systemName: "lock.fill").font(.caption2) }
                                    Text(b.url.lastPathComponent).font(.footnote).lineLimit(1)
                                }
                                Text("\(b.date.formatted(date: .abbreviated, time: .shortened)) · \(Fmt.bytes(b.size))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: b.url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                try? FileManager.default.removeItem(at: b.url); load()
                            } label: { Label("Supprimer", systemImage: "trash") }
                            Button { restoreURL = b.url } label: { Label("Tester / restaurer", systemImage: "checkmark.shield") }.tint(.green)
                            Button { askVerify(b.url) } label: { Label("Vérifier", systemImage: "checkmark.seal") }.tint(.blue)
                        }
                    }
                } header: {
                    Text("Sauvegardes")
                } footer: {
                    Text("Les archives sont rangées dans Fichiers › Sur mon iPhone › Photothèque › Sauvegardes. Une sauvegarde qui reste sur l'appareil ne protège pas d'une perte de l'appareil : ajoutez un dossier de copie (iCloud Drive, disque…) ou partagez-la. Balayez une archive pour la vérifier ou tester sa restauration.")
                }

                Section {
                    Toggle("Verrouiller avec Face ID ou le code", isOn: $lockEnabled)
                        .disabled(!Biometrics.available)
                } header: { Text("Sécurité") } footer: {
                    Text(Biometrics.available ? "Photothèque se verrouille quand vous la quittez. Le code de l'appareil sert de secours." : "Aucun code ni Face ID n'est configuré sur cet appareil (Réglages iOS).")
                }

                Section("Exports") {
                    Button { exportCSV() } label: { Label("Catalogue CSV (photos affichées)", systemImage: "tablecells") }
                    if let csvURL {
                        ShareLink(item: csvURL) { Label("Partager \(csvURL.lastPathComponent)", systemImage: "square.and.arrow.up") }
                    }
                }

                Section("Entretien") {
                    Button { checkIntegrity() } label: { Label("Contrôler l'intégrité", systemImage: "stethoscope") }
                    Button {
                        ImageCache.shared.clear(); cacheSize = 0
                    } label: { Label("Vider le cache des vignettes (\(Fmt.bytes(cacheSize)))", systemImage: "trash") }
                    NavigationLink { HistoryView() } label: { Label("Journal", systemImage: "clock") }
                }

                Section("À propos") {
                    NavigationLink { AboutView() } label: { LabeledContent("Version et mise à jour", value: Catalog.appVersion) }
                    Text("Photothèque garde ses données dans l'appareil (aucun compte, aucun serveur). Les originaux importés depuis Photos ou Fichiers ne sont jamais modifiés.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .onAppear(perform: load)
            .onChange(of: library.revision) { _, _ in load() }
            .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.zip, .data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result { restoreURL = urls.first }
                if case .failure(let e) = result { library.report(e) }
            }
            .sheet(item: Binding(get: { restoreURL.map { IdentifiedURL(url: $0) } }, set: { if $0 == nil { restoreURL = nil } })) { item in
                RestoreSheet(url: item.url) { load() }
            }
            .alert("Mot de passe de l'archive", isPresented: Binding(get: { verifyTarget != nil }, set: { if !$0 { verifyTarget = nil; verifyPassword = "" } })) {
                SecureField("Mot de passe", text: $verifyPassword)
                Button("Vérifier") { if let u = verifyTarget { verify(u, password: verifyPassword) }; verifyTarget = nil; verifyPassword = "" }
                Button("Annuler", role: .cancel) { verifyTarget = nil; verifyPassword = "" }
            }
        }
    }

    private struct IdentifiedURL: Identifiable, Equatable { let url: URL; var id: String { url.path } }

    private func manque(_ label: String, _ n: Int, _ m: MissingInfo) -> some View {
        Button {
            library.criteria = SearchCriteria(missing: m)
            library.tab = .photos
        } label: {
            LabeledContent(label) { Text("\(n)").foregroundStyle(n > 0 ? Color.orange : Color.secondary) }
        }
        .disabled(n == 0)
    }

    private func load() {
        stats = try? library.catalog.stats()
        backups = library.catalog.backups()
        cacheSize = ImageCache.shared.diskSize
        library.refreshBackupStatus()
    }

    private func askVerify(_ url: URL) {
        if BackupCrypto.isEncrypted(url) { verifyTarget = url } else { verify(url, password: nil) }
    }

    private func verify(_ url: URL, password: String?) {
        library.busy = "Vérification…"
        let pw = (password?.isEmpty ?? true) ? nil : password
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ArchiveCheck, Error> in
                Result { try Catalog.verifyArchive(url, password: pw) }
            }.value
            library.busy = nil
            switch result {
            case .success(let c) where c.ok:
                library.inform("Archive intacte : \(c.photos) fiche(s), \(c.files) photo(s) vérifiée(s) par empreinte, \(c.keywords) mot(s)-clé(s), \(c.collections) collection(s).")
            case .success(let c):
                library.message = .init(text: "Archive abîmée :\n" + c.problems.prefix(10).joined(separator: "\n"), isError: true)
            case .failure(let e):
                library.report(e)
            }
        }
    }

    private func exportCSV() {
        do {
            let csv = try library.catalog.catalogCSV(library.criteria)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
            let url = library.catalog.exportsDir.appendingPathComponent("Catalogue-\(f.string(from: Date())).csv")
            try csv.data(using: .utf8)!.write(to: url)
            csvURL = url
        } catch { library.report(error) }
    }

    private func checkIntegrity() {
        do {
            let problems = try Schema.integrity(library.catalog.db)
            let missing = try library.catalog.missingFiles()
            if problems.isEmpty && missing.isEmpty {
                library.inform("Base intègre ; tous les fichiers des photos sont présents.")
            } else {
                var t = problems.joined(separator: "\n")
                if !missing.isEmpty { t += (t.isEmpty ? "" : "\n") + "\(missing.count) fichier(s) absent(s) : " + missing.prefix(5).map(\.relPath).joined(separator: ", ") }
                library.message = .init(text: t, isError: true)
            }
        } catch { library.report(error) }
    }
}

struct HistoryView: View {
    @EnvironmentObject var library: Library

    var body: some View {
        List(Array(((try? library.catalog.history()) ?? []).enumerated()), id: \.offset) { _, h in
            VStack(alignment: .leading, spacing: 2) {
                Text(h.action.capitalized).font(.subheadline)
                if !h.detail.isEmpty { Text(h.detail).font(.caption).foregroundStyle(.secondary) }
                Text(Fmt.date(h.at)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Journal")
    }
}
