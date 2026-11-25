import SwiftUI
import PhotothequeCore

/// À propos : version installée, recherche de mise à jour sur GitHub.
struct AboutView: View {
    @EnvironmentObject var library: Library
    @State private var tab = 0

    var body: some View {
        List {
            Section {
                Picker("Rubrique", selection: $tab) {
                    Text("Version").tag(0)
                    Text("Mise à jour").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if tab == 0 { VersionSection() } else { UpdateSection() }
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VersionSection: View {
    @EnvironmentObject var library: Library

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "photo.stack.fill").font(.system(size: 38)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("Photothèque").font(.title3.bold())
                    Text("Gestion d'un fonds photographique personnel").font(.footnote).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Version installée", value: Catalog.appVersion)
            LabeledContent("Compilation", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
        }
        Section("Système") {
            LabeledContent("iOS", value: UIDevice.current.systemVersion)
            LabeledContent("Appareil", value: UIDevice.current.model)
            LabeledContent("SQLite", value: Database.libraryVersion + (library.catalog.hasFullText ? " (FTS5)" : ""))
        }
        Section("Données") {
            LabeledContent("Photos", value: "\((try? library.catalog.stats().photos) ?? 0)")
            Text(library.catalog.root.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Section {
            Text("Photothèque garde ses données dans l'appareil : aucun compte, aucun serveur. Les originaux importés depuis Photos ou Fichiers ne sont jamais modifiés.")
                .font(.footnote).foregroundStyle(.secondary)
            Link("Page du projet sur GitHub", destination: URL(string: "https://github.com/Vifi31/Phototheque_IOS")!)
        }
    }
}

private struct UpdateSection: View {
    @EnvironmentObject var library: Library
    @State private var status: UpdateStatus?
    @State private var checking = false
    @State private var downloading = false
    @State private var downloaded: URL?
    @State private var checkedAt: Date?

    static let releasesAPI = URL(string: "https://api.github.com/repos/Vifi31/Phototheque_IOS/releases/latest")!

    var body: some View {
        Section {
            LabeledContent("Version installée", value: Catalog.appVersion)
            Text("La recherche interroge GitHub (Vifi31/Phototheque_IOS) uniquement quand vous touchez le bouton. Aucune donnée personnelle n'est envoyée.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                Task { await check() }
            } label: {
                if checking { HStack { ProgressView(); Text("Recherche…") } } else { Label("Rechercher une mise à jour", systemImage: "arrow.triangle.2.circlepath") }
            }
            .disabled(checking)
        }
        if let s = status {
            Section {
                if let e = s.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if s.newer {
                    Label("Version \(s.latest ?? "") disponible", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor).font(.headline)
                } else {
                    Label("Photothèque est à jour (version \(s.latest ?? s.current))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let d = checkedAt { Text("Recherche faite le \(d.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            if s.newer {
                if !s.notes.isEmpty {
                    Section("Nouveautés") { Text(s.notes).font(.footnote) }
                }
                Section {
                    Text("Apple n'autorise pas une app installée hors App Store à se mettre à jour toute seule. Téléchargez la nouvelle version, puis installez-la par-dessus l'ancienne (Sideloadly, AltStore, TestFlight…) : vos photos et votre catalogue sont conservés.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if s.ipaURL != nil, s.sumsURL != nil {
                        Button { Task { await download(s) } } label: {
                            if downloading { HStack { ProgressView(); Text("Téléchargement…") } } else { Label("Télécharger l'installateur (.ipa)", systemImage: "square.and.arrow.down") }
                        }
                        .disabled(downloading)
                    }
                    if let downloaded {
                        ShareLink(item: downloaded) { Label("Partager \(downloaded.lastPathComponent)", systemImage: "square.and.arrow.up") }
                        Text("Empreinte SHA-256 vérifiée. Fichier rangé dans Fichiers › Sur mon iPhone › Photothèque › Exports.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let u = URL(string: s.pageURL), !s.pageURL.isEmpty { Link("Voir la page de la version", destination: u) }
                }
            }
        }
    }

    private func check() async {
        checking = true; defer { checking = false }
        var req = URLRequest(url: Self.releasesAPI, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Phototheque-update", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                status = UpdateStatus(current: Catalog.appVersion, latest: nil, newer: false, notes: "", pageURL: "", ipaURL: nil, ipaName: nil, sumsURL: nil,
                                      error: "Aucune version n'est encore publiée sur GitHub.")
            } else if code != 200 {
                status = UpdateStatus(current: Catalog.appVersion, latest: nil, newer: false, notes: "", pageURL: "", ipaURL: nil, ipaName: nil, sumsURL: nil,
                                      error: "GitHub a répondu \(code).")
            } else {
                status = UpdateStatus.evaluate(current: Catalog.appVersion, release: ReleaseInfo.parse(data))
            }
        } catch {
            status = UpdateStatus(current: Catalog.appVersion, latest: nil, newer: false, notes: "", pageURL: "", ipaURL: nil, ipaName: nil, sumsURL: nil,
                                  error: "Connexion à GitHub impossible : \(error.localizedDescription)")
        }
        checkedAt = Date()
        downloaded = nil
    }

    /// Télécharge l'.ipa publiée et ne la garde que si son empreinte SHA-256 est celle de SHA256SUMS.
    private func download(_ s: UpdateStatus) async {
        guard let ipa = s.ipaURL.flatMap(URL.init(string:)), let sums = s.sumsURL.flatMap(URL.init(string:)), let name = s.ipaName else { return }
        downloading = true; defer { downloading = false }
        do {
            let (sumsData, _) = try await URLSession.shared.data(from: sums)
            let (fileURL, _) = try await URLSession.shared.download(from: ipa)
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard ChecksumFile.verify(data, name: name, in: String(decoding: sumsData, as: UTF8.self)) else {
                try? FileManager.default.removeItem(at: fileURL)
                library.message = .init(text: "L'empreinte SHA-256 du fichier téléchargé ne correspond pas à celle publiée : fichier rejeté.", isError: true)
                return
            }
            let dest = library.catalog.exportsDir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: fileURL, to: dest)
            downloaded = dest
        } catch {
            library.report(error)
        }
    }
}
