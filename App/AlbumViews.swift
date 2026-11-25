import SwiftUI
import UniformTypeIdentifiers
import PhotothequeCore

// MARK: - Liste des albums

struct AlbumsView: View {
    @EnvironmentObject var library: Library
    @State private var albums: [Album] = []
    @State private var newAlbum = false
    @State private var importing = false
    @State private var importData: Data?
    @State private var analysis: ProjectAnalysis?
    @State private var toDelete: Album?
    @State private var prompt: TextPrompt?

    var body: some View {
        NavigationStack {
            List {
                if albums.isEmpty {
                    ContentUnavailableView("Aucun album", systemImage: "book.closed",
                                           description: Text("Un album met en page vos photos sur des pages à gabarits, avec recadrage et textes, puis s'exporte en PDF pour l'impression. Il ne copie aucune photo."))
                }
                ForEach(albums) { a in
                    NavigationLink { AlbumEditorView(albumId: a.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.headline)
                            Text("\(a.pageCount) page(s) · \(AlbumFormat.named(a.format)?.label ?? "\(Int(a.widthMM)) × \(Int(a.heightMM)) mm")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { toDelete = a } label: { Label("Supprimer", systemImage: "trash") }
                        Button { library.run { _ = try library.catalog.duplicateAlbum(a.id) }; load() } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }.tint(.blue)
                    }
                }
            }
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Ouvrir un projet d'album")
                    Button { newAlbum = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nouvel album")
                }
            }
            .onAppear(perform: load)
            .onChange(of: library.revision) { _, _ in load() }
            .sheet(isPresented: $newAlbum, onDismiss: load) { NewAlbumSheet() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let d = try Data(contentsOf: url)
                    analysis = try library.catalog.analyseProject(d); importData = d
                } catch { library.report(error) }
            }
            .confirmationDialog("Supprimer « \(toDelete?.name ?? "") » ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Supprimer l'album", role: .destructive) { if let a = toDelete { library.run { try library.catalog.deleteAlbum(a.id) }; load() }; toDelete = nil }
            } message: { Text("Les photos ne sont pas touchées.") }
            .alert("Ouvrir ce projet ?", isPresented: Binding(get: { analysis != nil }, set: { if !$0 { analysis = nil; importData = nil } })) {
                Button("Créer l'album") { if let d = importData { library.run { _ = try library.catalog.importProject(d) }; load() }; analysis = nil; importData = nil }
                Button("Annuler", role: .cancel) { analysis = nil; importData = nil }
            } message: {
                if let a = analysis {
                    Text("« \(a.name) » : \(a.pages) page(s), \(a.matched) photo(s) retrouvée(s) dans ce catalogue" + (a.missing.isEmpty ? "." : ", \(a.missing.count) absente(s) (cadres laissés vides) : " + a.missing.prefix(4).joined(separator: ", ") + ".") + "\nUn nouvel album est créé ; aucun album existant n'est modifié.")
                }
            }
        }
    }

    private func load() { albums = (try? library.catalog.albums()) ?? [] }
}

struct NewAlbumSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var format = "a4-portrait"
    @State private var width = 250.0
    @State private var height = 200.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom de l'album", text: $name)
                Picker("Format", selection: $format) {
                    ForEach(AlbumFormat.all) { Text($0.label).tag($0.id) }
                    Text("Format personnalisé").tag("custom")
                }
                if format == "custom" {
                    Stepper("Largeur : \(Int(width)) mm", value: $width, in: 50...1000, step: 10)
                    Stepper("Hauteur : \(Int(height)) mm", value: $height, in: 50...1000, step: 10)
                }
            }
            .navigationTitle("Nouvel album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        library.run { _ = try library.catalog.createAlbum(name: name, format: format, widthMM: width, heightMM: height) }
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Éditeur d'album

struct FrameRef: Identifiable, Equatable { let pageId: Int64; let slot: Int; var id: String { "\(pageId):\(slot)" } }

struct AlbumEditorView: View {
    @EnvironmentObject var library: Library
    let albumId: Int64

    @State private var album: Album?
    @State private var pages: [AlbumPage] = []
    @State private var selected = 0
    @State private var frameRef: FrameRef?
    @State private var chooser: FrameRef?
    @State private var showLayouts = false
    @State private var showStyles = false
    @State private var showChecks = false
    @State private var showExport = false
    @State private var showFill = false
    @State private var projectURL: URL?
    @State private var prompt: TextPrompt?
    @State private var editingText = false

    private var page: AlbumPage? { pages.indices.contains(selected) ? pages[selected] : nil }

    var body: some View {
        VStack(spacing: 0) {
            if let a = album, let p = page {
                ScrollView {
                    VStack(spacing: 12) {
                        AlbumPageCanvas(album: a, page: p, onTap: { frameRef = FrameRef(pageId: p.id, slot: $0) }, onSwap: { from, to in swap(from, to) })
                            .padding(.horizontal)
                        Text(Catalog.folios(pages)[selected].label + " sur \(Catalog.folios(pages).last.map { $0.folio + $0.span - 1 } ?? 1)")
                            .font(.caption).foregroundStyle(.secondary)
                        pageControls(p)
                    }.padding(.top, 8)
                }
                strip
            } else if album != nil {
                ContentUnavailableView {
                    Label("Album vide", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("Ajoutez une page, ou remplissez l'album avec vos photos.")
                } actions: {
                    Button("Ajouter une page") { mutate { _ = try library.catalog.addPage(albumId, layout: "quatre") } }.buttonStyle(.borderedProminent)
                    Button("Remplir avec des photos…") { showFill = true }
                }
            }
        }
        .navigationTitle(album?.name ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear(perform: reload)
        .sheet(item: $frameRef) { ref in FrameSheet(ref: ref, albumId: albumId, onChange: reload) }
        .sheet(isPresented: $showLayouts) { if let p = page { LayoutSheet(current: p.layout) { l in mutate { _ = try library.catalog.updatePage(p.id) { $0.layout = l } } } } }
        .sheet(isPresented: $showStyles) { StyleSheet(onPick: { preset, whole in mutate { try library.catalog.applyStyle(preset, album: albumId, page: whole ? nil : page?.id) } }, page: page, onChange: { edit in if let p = page { mutate { _ = try library.catalog.updatePage(p.id, edit) } } }) }
        .sheet(isPresented: $showChecks) { ChecksSheet(albumId: albumId) { n in selected = max(0, min(pages.count - 1, n - 1)) } }
        .sheet(isPresented: $showExport) { AlbumExportSheet(albumId: albumId) }
        .sheet(isPresented: $showFill) { FillSheet(albumId: albumId, onDone: reload) }
        .textPrompt($prompt)
    }

    // MARK: Contrôles de la page

    @ViewBuilder private func pageControls(_ p: AlbumPage) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button { showLayouts = true } label: { Label(AlbumLayout.named(p.layout)?.label ?? "Gabarit", systemImage: "rectangle.split.2x2") }
                Spacer()
                Button { showStyles = true } label: { Label("Style", systemImage: "paintpalette") }
            }.font(.subheadline).buttonStyle(.bordered)
            TextField("Titre de la page", text: Binding(get: { p.title }, set: { v in setText(p.id) { $0.title = v } })).textFieldStyle(.roundedBorder)
            TextField("Légende", text: Binding(get: { p.caption }, set: { v in setText(p.id) { $0.caption = v } }), axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal)
    }

    /// Texte tapé : enregistré à chaque frappe sans multiplier les étapes d'annulation (le catalogue ignore un état inchangé).
    private func setText(_ id: Int64, _ edit: (inout AlbumPage) -> Void) {
        do { _ = try library.catalog.updatePage(id, edit) } catch { library.report(error) }
        if let i = pages.firstIndex(where: { $0.id == id }) { var q = pages[i]; edit(&q); pages[i] = q }
    }

    // MARK: Bandeau des pages

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                        Button { selected = i } label: {
                            VStack(spacing: 2) {
                                if let a = album { AlbumPageCanvas(album: a, page: p, thumbnail: true).frame(width: p.isSpread ? 110 : 60) }
                                Text(Catalog.folios(pages)[i].label.replacingOccurrences(of: "Pages ", with: "").replacingOccurrences(of: "Page ", with: ""))
                                    .font(.caption2).foregroundStyle(i == selected ? Color.accentColor : .secondary)
                            }
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(i == selected ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .id(p.id)
                        .contextMenu {
                            Button { mutate { _ = try library.catalog.duplicatePage(p.id) } } label: { Label("Dupliquer la page", systemImage: "plus.square.on.square") }
                            Button { mutate { try library.catalog.movePage(p.id, to: i) } } label: { Label("Avancer", systemImage: "arrow.left") }.disabled(i == 0)
                            Button { mutate { try library.catalog.movePage(p.id, to: i + 2) } } label: { Label("Reculer", systemImage: "arrow.right") }.disabled(i == pages.count - 1)
                            Button(role: .destructive) { mutate { try library.catalog.deletePage(p.id) } } label: { Label("Supprimer la page", systemImage: "trash") }
                        }
                    }
                    Button { mutate { _ = try library.catalog.addPage(albumId, layout: page?.layout ?? "quatre", at: selected + 2) ; selected = min(pages.count, selected + 1) } } label: {
                        Image(systemName: "plus").frame(width: 44, height: 60).background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
            }
            .background(.bar)
            .onChange(of: selected) { _, i in if pages.indices.contains(i) { withAnimation { proxy.scrollTo(pages[i].id) } } }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { try? library.catalog.undoAlbum(albumId); reload() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!library.catalog.canUndoAlbum(albumId)).accessibilityLabel("Annuler")
            Button { try? library.catalog.redoAlbum(albumId); reload() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!library.catalog.canRedoAlbum(albumId)).accessibilityLabel("Rétablir")
            Menu {
                Button { showFill = true } label: { Label("Remplir avec des photos…", systemImage: "square.grid.3x3") }
                Button { showChecks = true } label: { Label("Contrôles avant impression", systemImage: "checkmark.shield") }
                Button { showExport = true } label: { Label("Exporter en PDF…", systemImage: "doc.richtext") }
                Button { exportProject() } label: { Label("Exporter le projet (.json)", systemImage: "square.and.arrow.up") }
                Divider()
                if let a = album {
                    Button { prompt = TextPrompt(title: "Renommer l'album", initial: a.name) { n in mutate { try library.catalog.updateAlbum(albumId, name: n) } } } label: { Label("Renommer…", systemImage: "pencil") }
                    Menu("Format") {
                        ForEach(AlbumFormat.all) { f in Button(f.label) { mutate { try library.catalog.updateAlbum(albumId, format: f.id) } } }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .bottomBar) { if let projectURL { ShareLink(item: projectURL) { Label("Partager le projet", systemImage: "square.and.arrow.up") } } }
    }

    // MARK: Données

    private func reload() {
        album = try? library.catalog.album(albumId)
        pages = (try? library.catalog.pages(albumId)) ?? []
        selected = min(selected, max(0, pages.count - 1))
    }

    private func mutate(_ body: () throws -> Void) {
        do { try body() } catch { library.report(error) }
        reload()
    }

    private func swap(_ from: FrameRef, _ to: FrameRef) {
        mutate { try library.catalog.swapSlots(page: from.pageId, slot: from.slot, with: to.pageId, slot: to.slot) }
    }

    private func exportProject() {
        do {
            let data = try library.catalog.albumProject(albumId)
            let name = TextFold.safeFileName((album?.name ?? "album")) + ".album.json"
            let url = library.catalog.exportsDir.appendingPathComponent(name)
            try data.write(to: url)
            projectURL = url
            library.inform("Projet enregistré : \(name). Il s'ouvre aussi dans la Photothèque de bureau (les photos sont retrouvées par leur empreinte).")
        } catch { library.report(error) }
    }
}

// MARK: - Page dessinée

/// Aperçu d'une page : fond, cadres à gabarit, photos recadrées, bordures, textes.
struct AlbumPageCanvas: View {
    @EnvironmentObject var library: Library
    let album: Album
    let page: AlbumPage
    var thumbnail = false
    var onTap: ((Int) -> Void)?
    var onSwap: ((FrameRef, FrameRef) -> Void)?

    var body: some View {
        let ratio = (album.widthMM * (page.isSpread ? 2 : 1)) / album.heightMM
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bg = Color(UIColor(hex: page.background))
            let textColor = page.style.textColor.map { Color(UIColor(hex: $0)) } ?? (UIColor(hex: page.background).luminance > 0.55 ? Color(white: 0.12) : Color(white: 0.96))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(bg)
                ForEach(Array(page.frames.enumerated()), id: \.offset) { i, f in
                    frameView(i, f, w, h)
                        .frame(width: CGFloat(f.w) * w, height: CGFloat(f.h) * h)
                        .offset(x: CGFloat(f.x) * w, y: CGFloat(f.y) * h)
                }
                if !thumbnail {
                    textOverlay(w, h, textColor)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .aspectRatio(CGFloat(ratio), contentMode: .fit)
        .shadow(color: .black.opacity(thumbnail ? 0.15 : 0.25), radius: thumbnail ? 1 : 4)
    }

    @ViewBuilder private func frameView(_ i: Int, _ f: FrameRect, _ w: CGFloat, _ h: CGFloat) -> some View {
        let fw = CGFloat(f.w) * w, fh = CGFloat(f.h) * h
        let ref = FrameRef(pageId: page.id, slot: i)
        let photo = i < page.slots.count ? page.slots[i].flatMap { try? library.catalog.photo($0) } : nil
        ZStack {
            if let photo {
                FramedPhoto(photo: photo, size: CGSize(width: fw, height: fh), crop: i < page.crops.count ? page.crops[i] : nil, maxPixel: thumbnail ? 200 : 1000)
                if page.style.borderWidth > 0, AlbumLayout.named(page.layout)?.fullBleed != true {
                    let bw = max(0.5, CGFloat(page.style.borderWidth) / CGFloat(album.widthMM * (page.isSpread ? 2 : 1)) * w)
                    Rectangle().strokeBorder(Color(UIColor(hex: page.style.borderColor)), lineWidth: bw)
                }
            } else if !thumbnail {
                Rectangle().fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: i < page.slots.count && page.slots[i] != nil ? "exclamationmark.triangle" : "plus").foregroundStyle(.secondary))
                    .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
            } else {
                Rectangle().fill(Color.secondary.opacity(0.2))
            }
        }
        .contentShape(Rectangle())
        .modifier(FrameInteraction(enabled: !thumbnail, payload: photo == nil ? nil : "\(ref.pageId):\(ref.slot)", onTap: { onTap?(i) },
                                   onDrop: { raw in
            let p = raw.split(separator: ":").compactMap { Int64($0) }
            if p.count == 2 { onSwap?(FrameRef(pageId: p[0], slot: Int(p[1])), ref) }
        }))
    }

    @ViewBuilder private func textOverlay(_ w: CGFloat, _ h: CGFloat, _ color: Color) -> some View {
        let align: Alignment = page.style.align == "left" ? .leading : page.style.align == "right" ? .trailing : .center
        let text: TextAlignment = page.style.align == "left" ? .leading : page.style.align == "right" ? .trailing : .center
        if page.layout == "titre" {
            VStack(spacing: h * 0.03) {
                Text(page.title).font(.system(size: h / 9, weight: .bold)).minimumScaleFactor(0.4)
                Text(page.caption).font(.system(size: h / 22))
            }
            .multilineTextAlignment(text).foregroundStyle(color).frame(width: w * 0.88, alignment: align)
            .frame(width: w, height: h, alignment: .center)
        } else {
            if !page.title.isEmpty {
                Text(page.title).font(.system(size: h / 26, weight: .bold)).multilineTextAlignment(text).foregroundStyle(color)
                    .frame(width: w * 0.88, alignment: align).offset(x: w * 0.06, y: h * 0.025)
            }
            if !page.caption.isEmpty, AlbumLayout.named(page.layout)?.fullBleed != true {
                Text(page.caption).font(.system(size: h / 34)).multilineTextAlignment(text).foregroundStyle(color)
                    .frame(width: w * 0.88, alignment: align).offset(x: w * 0.06, y: h * 0.905)
            }
        }
    }
}

/// Toucher, glisser-déposer (échange de deux cadres) sur un cadre de page.
private struct FrameInteraction: ViewModifier {
    let enabled: Bool
    let payload: String?
    let onTap: () -> Void
    let onDrop: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            if let payload {
                content.onTapGesture(perform: onTap).draggable(payload).dropDestination(for: String.self) { items, _ in
                    if let s = items.first { onDrop(s); return true }; return false
                }
            } else {
                content.onTapGesture(perform: onTap).dropDestination(for: String.self) { items, _ in
                    if let s = items.first { onDrop(s); return true }; return false
                }
            }
        } else { content }
    }
}

/// Photo recadrée dans son cadre : même calcul que le PDF (CropMath.window).
struct FramedPhoto: View {
    let photo: Photo
    let size: CGSize
    let crop: AlbumCrop?
    var maxPixel = 1000

    var body: some View {
        let iw = Double(photo.width ?? 4), ih = Double(photo.height ?? 3)
        let win = CropMath.window(imageW: iw, imageH: ih, frameW: Double(max(size.width, 1)), frameH: Double(max(size.height, 1)), crop: crop)
        let dw = size.width / CGFloat(win.width), dh = size.height / CGFloat(win.height)
        PhotoImage(photo: photo, maxPixel: maxPixel, contentMode: .fill)
            .frame(width: dw, height: dh)
            .offset(x: -CGFloat(win.left) * dw, y: -CGFloat(win.top) * dh)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }
}

// MARK: - Cadre : photo, recadrage

struct FrameSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let ref: FrameRef
    let albumId: Int64
    var onChange: () -> Void

    @State private var page: AlbumPage?
    @State private var album: Album?
    @State private var choose = false
    @State private var crop = AlbumCrop()

    private var photo: Photo? { page.flatMap { $0.slots.indices.contains(ref.slot) ? $0.slots[ref.slot] : nil }.flatMap { try? library.catalog.photo($0) } }

    var body: some View {
        NavigationStack {
            Form {
                if let p = photo, let page, let album, page.frames.indices.contains(ref.slot) {
                    let f = page.frames[ref.slot]
                    let pw = album.widthMM * (page.isSpread ? 2 : 1)
                    let fw = f.w * pw, fh = f.h * album.heightMM
                    Section("Recadrage") {
                        CropEditorView(photo: p, frameW: fw, frameH: fh, crop: $crop) { save() }
                            .frame(height: 260)
                        Slider(value: $crop.zoom, in: 1...AlbumCrop.zoomMax) { editing in if !editing { save() } }
                        Text("Pincez ou glissez l'image dans le cadre. Zoom \(String(format: "%.1f", crop.zoom)) ×").font(.caption).foregroundStyle(.secondary)
                        Button("Recadrage automatique (centré)") { crop = AlbumCrop(); save() }
                        if let dpi = effectiveDPI(p, fw, fh) {
                            Label("\(dpi) ppp à l'impression", systemImage: dpi < 150 ? "exclamationmark.triangle.fill" : dpi < 240 ? "exclamationmark.triangle" : "checkmark.circle")
                                .foregroundStyle(dpi < 150 ? .red : dpi < 240 ? .orange : .green)
                        }
                    }
                }
                Section {
                    Button { choose = true } label: { Label(photo == nil ? "Choisir une photo…" : "Changer de photo…", systemImage: "photo") }
                    if photo != nil { Button(role: .destructive) { setSlot(nil) } label: { Label("Vider ce cadre", systemImage: "xmark.circle") } }
                }
            }
            .navigationTitle("Cadre \(ref.slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .onAppear(perform: load)
            .sheet(isPresented: $choose) { PhotoChooser { id in setSlot(id) } }
        }
        .presentationDetents([.large])
    }

    private func load() {
        page = try? library.catalog.albumPage(ref.pageId)
        album = try? library.catalog.album(albumId)
        if let p = page, p.crops.indices.contains(ref.slot) { crop = p.crops[ref.slot] ?? AlbumCrop() }
    }

    private func save() {
        guard let p = page else { return }
        let c = crop
        _ = try? library.catalog.updatePage(p.id) { if $0.crops.indices.contains(ref.slot) { $0.crops[ref.slot] = c.cleaned } }
        onChange()
    }

    private func setSlot(_ id: Int64?) {
        guard let p = page else { return }
        do { _ = try library.catalog.updatePage(p.id) { if $0.slots.indices.contains(ref.slot) { $0.slots[ref.slot] = id } } } catch { library.report(error) }
        crop = AlbumCrop(); load(); onChange()
    }

    private func effectiveDPI(_ p: Photo, _ fw: Double, _ fh: Double) -> Int? {
        guard let w = p.width, let h = p.height else { return nil }
        let win = CropMath.window(imageW: Double(w), imageH: Double(h), frameW: fw, frameH: fh, crop: crop.cleaned)
        return Int(min(Double(w) * win.width / (fw / 25.4), Double(h) * win.height / (fh / 25.4)))
    }
}

/// Image que l'on déplace et zoome dans un cadre : modifie { x, y, zoom }.
struct CropEditorView: View {
    let photo: Photo
    let frameW: Double
    let frameH: Double
    @Binding var crop: AlbumCrop
    var onEnd: () -> Void
    @State private var start: AlbumCrop?
    @State private var startZoom: Double?

    var body: some View {
        GeometryReader { geo in
            let ratio = frameW / frameH
            let w = min(geo.size.width, geo.size.height * ratio), h = w / ratio
            FramedPhoto(photo: photo, size: CGSize(width: w, height: h), crop: crop.cleaned, maxPixel: 1200)
                .frame(width: w, height: h)
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(DragGesture()
                    .onChanged { v in
                        let s = start ?? crop; start = s
                        let iw = Double(photo.width ?? 4), ih = Double(photo.height ?? 3)
                        let win = CropMath.window(imageW: iw, imageH: ih, frameW: frameW, frameH: frameH, crop: s.cleaned)
                        // Glisser vers la droite montre la partie gauche de l'image.
                        crop.x = min(1, max(0, s.x - Double(v.translation.width) / Double(w) * win.width))
                        crop.y = min(1, max(0, s.y - Double(v.translation.height) / Double(h) * win.height))
                    }
                    .onEnded { _ in start = nil; onEnd() })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { v in let z = startZoom ?? crop.zoom; startZoom = z; crop.zoom = min(AlbumCrop.zoomMax, max(1, z * v.magnification)) }
                    .onEnded { _ in startZoom = nil; onEnd() })
        }
    }
}

/// Choix d'une photo du catalogue.
struct PhotoChooser: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    var onPick: (Int64) -> Void
    @State private var text = ""
    @State private var photos: [Photo] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 2)], spacing: 2) {
                    ForEach(photos) { p in
                        PhotoCell(photo: p).onTapGesture { onPick(p.id); dismiss() }
                    }
                }
            }
            .searchable(text: $text, prompt: "Mots-clés, titre, lieu…")
            .onChange(of: text) { _, _ in load() }
            .navigationTitle("Choisir une photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .onAppear(perform: load)
        }
    }

    private func load() { photos = (try? library.catalog.search(SearchCriteria(text: text), limit: 1500)) ?? [] }
}

// MARK: - Gabarits, styles, contrôles, remplissage, export

struct LayoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    var onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List(AlbumLayout.all) { l in
                Button { onPick(l.id); dismiss() } label: {
                    HStack(spacing: 12) {
                        LayoutGlyph(layout: l).frame(width: l.spread ? 70 : 38, height: 50)
                        Text(l.label).foregroundStyle(.primary)
                        Spacer()
                        if l.id == current { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
            }
            .navigationTitle("Gabarit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct LayoutGlyph: View {
    let layout: AlbumLayout
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.secondary.opacity(0.12))
                ForEach(Array(layout.frames.enumerated()), id: \.offset) { _, f in
                    Rectangle().fill(Color.accentColor.opacity(0.55))
                        .frame(width: CGFloat(f.w) * g.size.width, height: CGFloat(f.h) * g.size.height)
                        .offset(x: CGFloat(f.x) * g.size.width, y: CGFloat(f.y) * g.size.height)
                }
            }
        }
    }
}

struct StyleSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (StylePreset, Bool) -> Void
    var page: AlbumPage?
    var onChange: ((inout AlbumPage) -> Void) -> Void
    @State private var whole = true
    @State private var border = 0.0
    @State private var background = Color.white

    var body: some View {
        NavigationStack {
            Form {
                Section("Modèles graphiques") {
                    Picker("Appliquer à", selection: $whole) { Text("Tout l'album").tag(true); Text("Cette page").tag(false) }.pickerStyle(.segmented)
                    ForEach(StylePreset.all) { s in
                        Button { onPick(s, whole); dismiss() } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 4).fill(Color(UIColor(hex: s.background))).frame(width: 36, height: 26)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(UIColor(hex: s.style.borderColor)), lineWidth: max(1, s.style.borderWidth)))
                                Text(s.name).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if let p = page {
                    Section("Cette page") {
                        ColorPicker("Fond", selection: Binding(get: { Color(UIColor(hex: p.background)) }, set: { c in
                            let h = UIColor(c).hexString; onChange { $0.background = h }
                        }))
                        VStack(alignment: .leading) {
                            Text("Bordure des photos : \(String(format: "%.1f", p.style.borderWidth)) mm").font(.subheadline)
                            Slider(value: Binding(get: { p.style.borderWidth }, set: { v in onChange { $0.style.borderWidth = v } }), in: 0...PageStyle.borderMax, step: 0.5)
                        }
                        Picker("Alignement du texte", selection: Binding(get: { p.style.align }, set: { v in onChange { $0.style.align = v } })) {
                            Text("Centré").tag("center"); Text("À gauche").tag("left"); Text("À droite").tag("right")
                        }
                    }
                }
            }
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

extension UIColor {
    /// « #rrggbb »
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

struct ChecksSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let albumId: Int64
    var onGoTo: (Int) -> Void
    @State private var issues: [AlbumIssue] = []

    var body: some View {
        NavigationStack {
            List {
                if issues.isEmpty {
                    Label("Aucun problème : l'album est prêt pour l'impression.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                ForEach(issues) { i in
                    Button { onGoTo(i.page); dismiss() } label: {
                        Label(i.message, systemImage: i.blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(i.blocking ? Color.red : Color.orange).font(.footnote)
                    }
                }
            }
            .navigationTitle("Contrôles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .onAppear { issues = (try? library.catalog.albumChecks(albumId)) ?? [] }
        }
        .presentationDetents([.medium, .large])
    }
}

struct FillSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let albumId: Int64
    var onDone: () -> Void
    @State private var layout = "quatre"
    @State private var source = 0
    @State private var collections: [PhotoCollection] = []
    @State private var collectionId: Int64 = 0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Photos", selection: $source) {
                    Text("Photos affichées dans la grille").tag(0)
                    Text("Une collection").tag(1)
                }
                if source == 1 {
                    Picker("Collection", selection: $collectionId) { ForEach(collections) { Text($0.name).tag($0.id) } }
                }
                Picker("Gabarit des pages", selection: $layout) {
                    ForEach(AlbumLayout.all.filter { !$0.frames.isEmpty }) { Text($0.label).tag($0.id) }
                }
                Section { Text("Chaque page reçoit autant de photos que le gabarit a de cadres, dans l'ordre. L'ensemble s'annule d'un geste.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Remplir l'album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Remplir") { fill() } }
            }
            .onAppear { collections = (try? library.catalog.collections()) ?? []; collectionId = collections.first?.id ?? 0 }
        }
        .presentationDetents([.medium])
    }

    private func fill() {
        do {
            let ids = source == 0 ? library.photos.map(\.id) : try library.catalog.ids(SearchCriteria(collectionId: collectionId, sort: .takenAsc))
            guard !ids.isEmpty else { library.inform("Aucune photo à placer."); return }
            _ = try library.catalog.autoFill(albumId, photoIds: ids, layout: layout)
            onDone(); dismiss()
        } catch { library.report(error) }
    }
}

struct AlbumExportSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let albumId: Int64
    @State private var options = AlbumPDFOptions()
    @State private var running = false
    @State private var progress = 0.0
    @State private var result: URL?
    @State private var issues: [AlbumIssue] = []

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section("Terminé") {
                        ShareLink(item: result) { Label("Partager \(result.lastPathComponent)", systemImage: "square.and.arrow.up") }
                        Text("Fichier rangé dans Fichiers › Sur mon iPhone › Photothèque › Exports.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    if !issues.isEmpty {
                        Section("Contrôles") {
                            ForEach(issues.prefix(6)) { i in Label(i.message, systemImage: i.blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(i.blocking ? .red : .orange) }
                            if issues.count > 6 { Text("… et \(issues.count - 6) autre(s)").font(.footnote) }
                        }
                    }
                    Section("PDF") {
                        Picker("Qualité", selection: $options.quality) { ForEach(AlbumPDFOptions.Quality.allCases, id: \.self) { Text($0.label).tag($0) } }
                        Picker("Mise en page", selection: $options.layout) { ForEach(AlbumPDFOptions.Layout.allCases, id: \.self) { Text($0.label).tag($0) } }
                        Toggle("Fond perdu (3 mm)", isOn: $options.bleed)
                    }
                    Section {
                        Button { run() } label: { if running { HStack { ProgressView(value: progress); Text("\(Int(progress * 100)) %") } } else { Label("Créer le PDF", systemImage: "doc.richtext") } }.disabled(running)
                    }
                }
            }
            .navigationTitle("Exporter en PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Annuler" : "Fermer") { dismiss() } } }
            .onAppear { issues = (try? library.catalog.albumChecks(albumId)) ?? [] }
        }
        .presentationDetents([.medium, .large])
    }

    private func run() {
        guard let album = try? library.catalog.album(albumId), let pages = try? library.catalog.pages(albumId) else { return }
        var sources: [Int64: AlbumPhotoSource] = [:]
        for p in pages { for s in p.slots { if let id = s, sources[id] == nil, let ph = try? library.catalog.photo(id) {
            sources[id] = AlbumPhotoSource(url: library.url(ph), width: ph.width, height: ph.height, edit: (try? library.catalog.defaultEdit(id))?.params)
        } } }
        running = true; progress = 0
        let opts = options
        let name = TextFold.safeFileName(album.name) + (opts.layout == .spreads ? "-planches" : "") + ".pdf"
        let dest = library.catalog.exportsDir.appendingPathComponent(name)
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) {
                AlbumPDF.build(album: album, pages: pages, photos: sources, options: opts) { d, t in Task { @MainActor in progress = Double(d) / Double(max(1, t)) } }
            }.value
            running = false
            do { try data.write(to: dest); library.catalog.log("album-pdf", "\(album.name) : \(pages.count) page(s), \(Fmt.bytes(Int64(data.count)))"); result = dest }
            catch { library.report(error) }
        }
    }
}
