import SwiftUI
import UniformTypeIdentifiers
import PhotothequeCore

/// Visionneuse plein écran : balayage entre les photos, zoom (pincer, double toucher), informations.
struct PhotoViewer: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let photos: [Photo]
    @State private var index: Int
    @State private var showInfo = false
    @State private var chrome = true
    @State private var retouchePhoto: Photo?
    @State private var exportIds: [Int64]?

    init(photos: [Photo], startIndex: Int) {
        self.photos = photos
        _index = State(initialValue: min(max(0, startIndex), max(0, photos.count - 1)))
    }

    private var current: Photo? { photos.indices.contains(index) ? library.refreshed(photos[index]) : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                    ZoomableImage(photo: p)
                        .tag(i)
                        .onTapGesture { withAnimation { chrome.toggle() } }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if chrome, let p = current {
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.weight(.semibold)) }
                            .accessibilityLabel("Fermer")
                        Spacer()
                        Text("\(index + 1) / \(photos.count)").font(.footnote).monospacedDigit()
                        Spacer()
                        Button { retouchePhoto = p } label: { Image(systemName: "slider.horizontal.3").font(.title3) }
                            .accessibilityLabel("Retoucher")
                        Button { exportIds = [p.id] } label: { Image(systemName: "square.and.arrow.up.on.square").font(.title3) }
                            .padding(.leading, 12).accessibilityLabel("Exporter")
                        ShareLink(item: library.url(p)) { Image(systemName: "square.and.arrow.up").font(.title3) }
                            .padding(.leading, 12)
                        Button { showInfo = true } label: { Image(systemName: "info.circle").font(.title3) }
                            .padding(.leading, 12)
                            .accessibilityLabel("Informations")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    Spacer()
                    VStack(spacing: 8) {
                        if !p.title.isEmpty { Text(p.title).font(.headline) }
                        RatingPicker(rating: p.rating) { n in library.run { try library.catalog.setRating([p.id], n) } }
                        ColorPicker5(color: p.color) { c in library.run { try library.catalog.setColor([p.id], c) } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
            }
        }
        .statusBarHidden(!chrome)
        .background {
            // Clavier (iPad) : 0 à 5 = note, flèches = photo précédente / suivante, I = informations.
            ZStack {
                ForEach(0...5, id: \.self) { n in
                    Button("") { if let p = current { library.run { try library.catalog.setRating([p.id], n) } } }
                        .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: [])
                }
                Button("") { if index > 0 { index -= 1 } }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { if index < photos.count - 1 { index += 1 } }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { showInfo = true }.keyboardShortcut("i", modifiers: [])
            }
            .frame(width: 0, height: 0).opacity(0)
        }
        .onChange(of: index) { _, _ in if let p = current { library.catalog.noteViewed(p.id) } }
        .onAppear { if let p = current { library.catalog.noteViewed(p.id) } }
        .fullScreenCover(item: $retouchePhoto) { RetoucheView(photo: $0) }
        .sheet(isPresented: Binding(get: { exportIds != nil }, set: { if !$0 { exportIds = nil } })) { ExportSheet(ids: exportIds ?? []) }
        .sheet(isPresented: $showInfo) {
            if let p = current {
                NavigationStack { PhotoInfoView(photo: p) }
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Image zoomable : pincer pour agrandir (jusqu'à 8×), glisser pour se déplacer, double toucher pour basculer.
struct ZoomableImage: View {
    let photo: Photo
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            PhotoImage(photo: photo, maxPixel: scale > 1.5 ? 4096 : 2048, contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { v in scale = min(8, max(1, lastScale * v.magnification)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.01 { reset() }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { v in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset },
                    including: scale > 1 ? .all : .subviews
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                    }
                }
        }
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

/// Fiche d'une photo : titre, légende, note, étiquette, lieu, mots-clés, collections, informations techniques.
struct PhotoInfoView: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State var photo: Photo
    @State private var title = ""
    @State private var caption = ""
    @State private var place = ""
    @State private var keywords: [Keyword] = []
    @State private var collections: [PhotoCollection] = []
    @State private var addKeyword = false
    @State private var importXMP = false

    var body: some View {
        Form {
            Section("Description") {
                TextField("Titre", text: $title).onSubmit(save)
                TextField("Légende", text: $caption, axis: .vertical).lineLimit(1...6)
                TextField("Lieu", text: $place).onSubmit(save)
            }
            Section("Classement") {
                LabeledContent("Note") { RatingPicker(rating: photo.rating) { n in change { try library.catalog.setRating([photo.id], n) } } }
                LabeledContent("Étiquette") { ColorPicker5(color: photo.color) { c in change { try library.catalog.setColor([photo.id], c) } } }
            }
            Section("Mots-clés") {
                ForEach(keywords) { k in
                    Text((try? library.catalog.keywordPathName(k.id)) ?? k.name)
                        .swipeActions {
                            Button(role: .destructive) { change { try library.catalog.removeKeyword(k.id, from: [photo.id]) } } label: { Label("Retirer", systemImage: "minus.circle") }
                        }
                }
                Button { addKeyword = true } label: { Label("Ajouter un mot-clé…", systemImage: "plus") }
            }
            if !collections.isEmpty {
                Section("Collections") { ForEach(collections) { Text($0.name) } }
            }
            Section("Annexe XMP") {
                Button { importXMP = true } label: { Label("Lire une annexe XMP…", systemImage: "doc.badge.plus") }
                Button {
                    do { let u = try library.catalog.writeSidecars([photo.id]); library.inform("Annexe écrite : \(u.first?.lastPathComponent ?? "") (dossier Metadonnees).") } catch { library.report(error) }
                } label: { Label("Écrire l'annexe XMP", systemImage: "square.and.arrow.up") }
            }
            Section("Prise de vue") {
                LabeledContent("Date", value: Fmt.date(photo.takenAt))
                if !photo.camera.isEmpty { LabeledContent("Appareil", value: photo.camera) }
                if !photo.lens.isEmpty { LabeledContent("Objectif", value: photo.lens) }
                if let lat = photo.latitude, let lon = photo.longitude {
                    LabeledContent("Position", value: String(format: "%.5f, %.5f", lat, lon))
                    if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(photo.displayTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Photo")") {
                        Link(destination: url) { Label("Voir dans Plans", systemImage: "map") }
                    }
                }
            }
            Section("Fichier") {
                LabeledContent("Nom", value: photo.fileName)
                LabeledContent("Format", value: photo.format)
                if let w = photo.width, let h = photo.height { LabeledContent("Dimensions", value: "\(w) × \(h)") }
                LabeledContent("Taille", value: Fmt.bytes(photo.size))
                LabeledContent("Importée le", value: Fmt.date(photo.importedAt))
                LabeledContent("Provenance", value: photo.source == "photos" ? "App Photos" : "Fichiers")
                LabeledContent("Empreinte", value: String(photo.sha256.prefix(16)) + "…").font(.caption.monospaced())
            }
        }
        .navigationTitle(photo.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { save(); dismiss() } } }
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .fileImporter(isPresented: $importXMP, allowedContentTypes: [UTType(filenameExtension: "xmp") ?? .xml, .xml, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let changed = try library.catalog.applySidecar(text, to: photo.id)
                library.run {}; load()
                library.inform(changed.isEmpty ? "L'annexe n'apporte rien de nouveau (priorité : \(library.catalog.metadataPriority() == .catalog ? "catalogue" : "annexe"))." : "Appliqué : " + changed.joined(separator: ", ") + ".")
            } catch { library.report(error) }
        }
        .sheet(isPresented: $addKeyword) {
            KeywordPickerSheet(title: "Ajouter un mot-clé") { kid in change { try library.catalog.assignKeyword(kid, to: [photo.id]) } }
        }
    }

    private func load() {
        photo = library.refreshed(photo)
        title = photo.title
        caption = photo.caption
        place = photo.place
        keywords = (try? library.catalog.keywordsOf(photo.id)) ?? []
        collections = (try? library.catalog.collectionsOf(photo.id)) ?? []
    }

    private func save() {
        let p = library.refreshed(photo)
        guard title != p.title || caption != p.caption || place != p.place else { return }
        change {
            if title != p.title { try library.catalog.setTitle(p.id, title) }
            if caption != p.caption { try library.catalog.setCaption(p.id, caption) }
            if place != p.place { try library.catalog.setPlace([p.id], place) }
        }
    }

    private func change(_ body: () throws -> Void) {
        library.run(body)
        photo = library.refreshed(photo)
        keywords = (try? library.catalog.keywordsOf(photo.id)) ?? []
    }
}
