import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import PhotothequeCore

// MARK: - Réglages de sauvegarde

struct BackupSettingsView: View {
    @EnvironmentObject var library: Library
    @State private var policy = BackupPolicy()
    @State private var destinations: [BackupDestination] = []
    @State private var password = ""
    @State private var hasPassword = false
    @State private var addFolder = false

    var body: some View {
        Form {
            Section {
                Picker("Rappel", selection: $policy.everyDays) {
                    Text("Jamais (manuel)").tag(0); Text("Chaque jour").tag(1); Text("Chaque semaine").tag(7); Text("Tous les 15 jours").tag(15); Text("Chaque mois").tag(30)
                }
                Toggle("Sauvegarder automatiquement à l'ouverture", isOn: $policy.automatic).disabled(policy.everyDays == 0)
                Toggle("Inclure les photos (sauvegarde complète)", isOn: $policy.includePhotos)
                Stepper("Archives gardées sur l'appareil : \(policy.keep)", value: $policy.keep, in: 1...50)
            } header: { Text("Planification") } footer: {
                Text("iOS ne permet pas de tâche planifiée fiable en arrière-plan : la sauvegarde est proposée (ou faite, si vous l'activez) à l'ouverture de l'application quand la dernière est trop ancienne.")
            }

            Section {
                Toggle("Chiffrer les sauvegardes", isOn: $policy.encrypt)
                if policy.encrypt {
                    SecureField(hasPassword ? "Nouveau mot de passe (laisser vide : inchangé)" : "Mot de passe", text: $password)
                    if hasPassword { Label("Un mot de passe est enregistré dans le trousseau de cet appareil.", systemImage: "key.fill").font(.footnote).foregroundStyle(.secondary) }
                }
            } header: { Text("Chiffrement") } footer: {
                Text("AES-256 : l'archive est illisible sans le mot de passe. **Notez-le ailleurs** : s'il est perdu, la sauvegarde ne peut pas être ouverte, personne ne peut la récupérer.")
            }

            Section {
                ForEach(destinations) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                        if let e = d.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                        else if let t = d.lastCopyAt { Text("Dernière copie : \(Fmt.date(t))").font(.caption).foregroundStyle(.secondary) }
                        else { Text("Aucune copie pour l'instant").font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions { Button(role: .destructive) { destinations.removeAll { $0.id == d.id } } label: { Label("Retirer", systemImage: "trash") } }
                }
                Button { addFolder = true } label: { Label("Ajouter un dossier de copie…", systemImage: "plus") }
                Toggle("Copier chaque sauvegarde dans ces dossiers", isOn: $policy.copyToDestinations)
            } header: { Text("Copies hors de l'appareil") } footer: {
                Text("Choisissez un dossier d'iCloud Drive, d'un disque ou d'un serveur (app Fichiers). Une sauvegarde qui reste sur l'appareil ne protège pas d'une perte de l'appareil.")
            }
        }
        .navigationTitle("Réglages de sauvegarde")
        .onAppear {
            policy = library.catalog.backupPolicy(); destinations = library.catalog.backupDestinations(); hasPassword = Keychain.load() != nil
        }
        .onDisappear(perform: save)
        .fileImporter(isPresented: $addFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let bm = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                destinations.append(BackupDestination(name: url.lastPathComponent, bookmark: bm))
            } catch { library.report(error) }
        }
    }

    private func save() {
        if policy.encrypt, !password.isEmpty { hasPassword = Keychain.save(password); password = "" }
        if policy.encrypt && !hasPassword { policy.encrypt = false }          // pas de chiffrement sans mot de passe
        try? library.catalog.setBackupPolicy(policy)
        try? library.catalog.setBackupDestinations(destinations)
        library.refreshBackupStatus()
    }
}

// MARK: - Restauration

/// Choix des parties à restaurer, test de restauration, mot de passe d'une archive chiffrée.
struct RestoreSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var onDone: () -> Void

    @State private var password = ""
    @State private var info: ArchiveInfo?
    @State private var error: String?
    @State private var parts: [Int: Bool] = [1: true, 2: true, 4: true, 8: true, 16: true, 32: true]
    @State private var testResult: RestoreTest?
    @State private var working = false

    private static let labels: [(Int, String)] = [(1, "Titres, légendes, notes, étiquettes, lieux"), (2, "Mots-clés"), (4, "Collections"),
                                                  (8, "Versions de retouche"), (16, "Albums"), (32, "Photos absentes (recopiées depuis l'archive)")]
    private var encrypted: Bool { BackupCrypto.isEncrypted(url) }

    var body: some View {
        NavigationStack {
            Form {
                if encrypted {
                    Section {
                        SecureField("Mot de passe de l'archive", text: $password)
                        Button("Lire l'archive") { load() }.disabled(password.isEmpty)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                if let i = info {
                    Section("Contenu") {
                        LabeledContent("Créée le", value: Fmt.date(i.createdAt))
                        LabeledContent("Photos", value: "\(i.photos)" + (i.includesPhotos ? " (fichiers inclus)" : " (catalogue seul)"))
                        LabeledContent("Mots-clés", value: "\(i.keywords)"); LabeledContent("Collections", value: "\(i.collections)")
                        LabeledContent("Retouches", value: "\(i.edits)"); LabeledContent("Albums", value: "\(i.albums)")
                    }
                    Section {
                        ForEach(Self.labels, id: \.0) { code, label in
                            Toggle(label, isOn: Binding(get: { parts[code] ?? false }, set: { parts[code] = $0 }))
                        }
                    } header: { Text("Parties à restaurer") } footer: {
                        Text("La restauration fusionne : rien n'est supprimé. Une sauvegarde de sécurité du catalogue actuel est faite d'abord.")
                    }
                    Section {
                        Button { test() } label: { Label("Tester la restauration (sans rien modifier)", systemImage: "checkmark.shield") }.disabled(working)
                        if let t = testResult {
                            if t.ok { Label("Test réussi : \(t.photos) photo(s), \(t.files) fichier(s) vérifié(s) par empreinte, \(t.albums) album(s), \(t.edits) retouche(s).", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.footnote) }
                            else { ForEach(t.problems.prefix(6), id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.footnote) } }
                        }
                    } footer: { Text("Le test restaure l'archive dans un catalogue temporaire, effacé ensuite : c'est la seule preuve qu'une sauvegarde est utilisable.") }
                    Section {
                        Button { restore() } label: { Label("Restaurer", systemImage: "arrow.counterclockwise") }.disabled(working || selected.isEmpty)
                    }
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onAppear { if !encrypted { load() } }
        }
    }

    private var selected: RestoreParts {
        var p = RestoreParts()
        for (c, on) in parts where on { p.insert(RestoreParts(rawValue: c)) }
        return p
    }

    private func access<T>(_ body: () throws -> T) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    private func load() {
        do { info = try access { try Catalog.describeArchive(url, password: password.isEmpty ? nil : password) }; error = nil }
        catch { info = nil; self.error = error.localizedDescription }
    }

    private func test() {
        working = true; testResult = nil
        let pw = password.isEmpty ? nil : password, u = url
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { () -> Result<RestoreTest, Error> in
                let scoped = u.startAccessingSecurityScopedResource(); defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                return Result { try Catalog.testRestore(u, password: pw) }
            }.value
            working = false
            switch r { case .success(let t): testResult = t; case .failure(let e): error = e.localizedDescription }
        }
    }

    private func restore() {
        working = true
        library.busy = "Restauration…"
        let pw = password.isEmpty ? nil : password, p = selected
        Task { @MainActor in
            await Task.yield()
            do {
                let r = try access { try library.catalog.restore(from: url, progress: { d, t in library.busy = "Restauration \(d) / \(t)…" }, password: pw, parts: p) }
                library.busy = nil; working = false
                library.run {}
                var text = "\(r.photosAdded) photo(s) ajoutée(s), \(r.photosUpdated) mise(s) à jour, \(r.collectionsAdded) collection(s), \(r.albumsAdded) album(s), \(r.editsAdded) retouche(s) ajoutés."
                if r.photosWithoutFile > 0 { text += "\n\(r.photosWithoutFile) photo(s) absente(s) non recopiée(s)." }
                if let s = r.safetyBackup { text += "\nSauvegarde de sécurité : \(s)" }
                library.inform(text); onDone(); dismiss()
                await library.computeMissingHashes()
            } catch {
                library.busy = nil; working = false; self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Verrouillage

/// Écran de verrouillage : Face ID / Touch ID, ou code de l'appareil.
struct LockScreen: View {
    @EnvironmentObject var library: Library

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 54)).foregroundStyle(.secondary)
                Text("Photothèque est verrouillée").font(.headline)
                Button { Task { await library.unlock() } } label: { Label("Déverrouiller", systemImage: "faceid") }.buttonStyle(.borderedProminent)
            }
        }
        .task { await library.unlock() }
    }
}

enum Biometrics {
    /// Vrai si l'utilisateur s'identifie (biométrie, ou code de l'appareil à défaut).
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
}
