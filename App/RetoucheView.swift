import SwiftUI
import PhotothequeCore

/// Retouche non destructive d'une photo : versions, préréglages, curseurs, courbe, géométrie, annuler / rétablir.
/// L'original n'est jamais modifié : les réglages sont rangés dans le catalogue.
struct RetoucheView: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let photo: Photo

    @State private var versions: [EditVersion] = []
    @State private var current: EditVersion?
    @State private var params = EditParams()
    @State private var base: CGImage?
    @State private var preview: UIImage?
    @State private var showOriginal = false
    @State private var renderTask: Task<Void, Never>?
    @State private var cropSheet = false
    @State private var prompt: TextPrompt?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if showOriginal, let base { Image(uiImage: UIImage(cgImage: base)).resizable().scaledToFit() }
                    else if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                    else { ProgressView().tint(.white) }
                }
                .frame(maxHeight: 330)
                .overlay(alignment: .topLeading) {
                    if showOriginal { Text("Original").font(.caption.bold()).padding(6).background(.ultraThinMaterial, in: Capsule()).padding(8) }
                }

                Form {
                    versionSection
                    presetSection
                    ForEach(EditFields.groups, id: \.self) { group in
                        Section(group) {
                            ForEach(EditFields.all.filter { $0.group == group }) { f in slider(f) }
                            if group == "Couleur" { monoPicker }
                            if group == "Géométrie" { geometryButtons }
                        }
                    }
                    curveSection
                    Section {
                        Button(role: .destructive) { change { try library.catalog.resetEdit($0) } } label: { Label("Remettre tous les réglages à zéro", systemImage: "arrow.counterclockwise") }
                            .disabled(current == nil || params.isNeutral)
                    } footer: {
                        Text("L'original n'est jamais modifié : la retouche est un ensemble de réglages gardé dans le catalogue, appliqué à l'affichage et aux exports. Chaque réglage peut être annulé.")
                    }
                }
            }
            .navigationTitle("Retouche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Terminé") { commit(); dismiss() } }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { change { try library.catalog.undoEdit($0) } } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!(current?.canUndo ?? false)).accessibilityLabel("Annuler")
                    Button { change { try library.catalog.redoEdit($0) } } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!(current?.canRedo ?? false)).accessibilityLabel("Rétablir")
                    Image(systemName: "eye").foregroundStyle(showOriginal ? Color.accentColor : .secondary)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in showOriginal = true }.onEnded { _ in showOriginal = false })
                        .accessibilityLabel("Maintenir pour voir l'original")
                }
            }
            .task { await prepare() }
            .sheet(isPresented: $cropSheet) { CropSheet(params: $params, photo: photo) { commit(); schedulePreview() } }
            .textPrompt($prompt)
            .confirmationDialog("Supprimer cette version ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer la version", role: .destructive) {
                    if let c = current { library.run { try library.catalog.deleteEdit(c.id) }; reloadVersions() }
                }
            } message: { Text("L'original n'est pas touché.") }
        }
    }

    // MARK: - Sections

    private var versionSection: some View {
        Section("Version") {
            if versions.isEmpty {
                Text("Aucune retouche : la photo est affichée telle qu'elle a été importée. Un réglage crée la première version.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Picker("Version", selection: Binding(get: { current?.id ?? 0 }, set: { id in select(versions.first { $0.id == id }) })) {
                    ForEach(versions) { Text($0.name + ($0.isDefault ? " ★" : "")).tag($0.id) }
                }
            }
            HStack {
                Button { newVersion() } label: { Label("Nouvelle", systemImage: "plus") }
                if let c = current {
                    Button { prompt = TextPrompt(title: "Renommer la version", initial: c.name) { n in library.run { try library.catalog.renameEdit(c.id, n) }; reloadVersions() } } label: { Image(systemName: "pencil") }
                    if !c.isDefault { Button { library.run { try library.catalog.setDefaultEdit(c.id) }; reloadVersions() } label: { Label("Par défaut", systemImage: "star") } }
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                }
            }
            .buttonStyle(.borderless)
            if let c = current, c.isDefault { Text("★ Version affichée dans la grille, la visionneuse, les exports et les albums.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var presetSection: some View {
        Section("Préréglages") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(EditPreset.all) { pr in
                        Button(pr.label) { params = pr.applying(to: params); commit(); schedulePreview() }
                            .buttonStyle(.bordered).font(.footnote)
                    }
                }
            }
        }
    }

    private var monoPicker: some View {
        Picker("Monochrome", selection: Binding(get: { params.mono?.rawValue ?? "" }, set: { params.mono = MonoMode(rawValue: $0); commit(); schedulePreview() })) {
            Text("Couleur").tag("")
            ForEach(MonoMode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
        }
    }

    private var geometryButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { params.rotate = (params.rotate + 270) % 360; commit(); schedulePreview() } label: { Label("Gauche", systemImage: "rotate.left") }
                Button { params.rotate = (params.rotate + 90) % 360; commit(); schedulePreview() } label: { Label("Droite", systemImage: "rotate.right") }
                Button { params.flipH.toggle(); commit(); schedulePreview() } label: { Label("Miroir", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                Button { params.flipV.toggle(); commit(); schedulePreview() } label: { Label("Retourner", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
            }
            .labelStyle(.iconOnly).buttonStyle(.bordered)
            Button { cropSheet = true } label: { Label(params.crop == nil ? "Recadrer…" : "Modifier le recadrage…", systemImage: "crop") }
            if params.crop != nil { Button("Retirer le recadrage", role: .destructive) { params.crop = nil; commit(); schedulePreview() } }
        }
    }

    private var curveSection: some View {
        Section("Courbe de tonalité") {
            Picker("Préréglage", selection: Binding(get: { Curves.all.first { $0.points == params.curve }?.id ?? "perso" },
                                                   set: { id in if let c = Curves.all.first(where: { $0.id == id }) { params.curve = c.points; commit(); schedulePreview() } })) {
                ForEach(Curves.all, id: \.id) { Text($0.label).tag($0.id) }
                Text("Personnalisée").tag("perso")
            }
            CurveEditor(points: Binding(get: { params.curve }, set: { params.curve = $0 }), onChange: { schedulePreview() }, onEnd: { commit() })
                .frame(height: 220).padding(.vertical, 4)
            Text("Touchez pour ajouter un point, glissez pour le déplacer, sortez-le du cadre pour le retirer.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func slider(_ f: EditField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(f.label).font(.subheadline)
                Spacer()
                Text(f.step < 1 ? String(format: "%.2f", params[keyPath: f.keyPath]) : String(Int(params[keyPath: f.keyPath].rounded())))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if params[keyPath: f.keyPath] != 0 {
                    Button { params[keyPath: f.keyPath] = 0; commit(); schedulePreview() } label: { Image(systemName: "arrow.counterclockwise.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("Remettre à zéro")
                }
            }
            Slider(value: Binding(get: { params[keyPath: f.keyPath] }, set: { params[keyPath: f.keyPath] = $0; schedulePreview() }),
                   in: f.min...f.max, step: f.step, onEditingChanged: { editing in if !editing { commit() } })
        }
    }

    // MARK: - Données

    private func prepare() async {
        reloadVersions()
        let url = library.url(photo)
        base = await Task.detached(priority: .userInitiated) { ImageTools.thumbnail(of: url, maxPixel: 1400) }.value
        schedulePreview()
    }

    private func reloadVersions() {
        versions = (try? library.catalog.editVersions(photo.id)) ?? []
        if let c = current, let fresh = versions.first(where: { $0.id == c.id }) { current = fresh }
        else { current = versions.first { $0.isDefault } ?? versions.first }
        params = current?.params ?? EditParams()
        schedulePreview()
    }

    private func select(_ v: EditVersion?) {
        commit()
        current = v
        params = v?.params ?? EditParams()
        schedulePreview()
    }

    private func newVersion() {
        commit()
        do {
            let v = try library.catalog.createEdit(photoId: photo.id, from: current?.id)
            versions = try library.catalog.editVersions(photo.id); current = v; params = v.params
            library.run {}
        } catch { library.report(error) }
    }

    /// Enregistre les réglages courants (crée la première version au besoin).
    private func commit() {
        let p = params.normalized()
        do {
            if let c = current {
                guard p != c.params else { return }
                current = try library.catalog.updateEdit(c.id, params: p)
            } else {
                if p.isNeutral { return }
                current = try library.catalog.createEdit(photoId: photo.id, params: p)
            }
            versions = try library.catalog.editVersions(photo.id)
            library.run {}
        } catch { library.report(error) }
    }

    private func change(_ body: (Int64) throws -> EditVersion) {
        guard let c = current else { return }
        do {
            let v = try body(c.id)
            current = v; params = v.params
            versions = try library.catalog.editVersions(photo.id)
            library.run {}
            schedulePreview()
        } catch { library.report(error) }
    }

    private func schedulePreview() {
        renderTask?.cancel()
        guard let base else { return }
        let p = params
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
            let img = await Task.detached(priority: .userInitiated) { EditRenderer.render(base: base, params: p) }.value
            if !Task.isCancelled { preview = img }
        }
    }
}

/// Éditeur de courbe : toucher = ajouter un point, glisser = déplacer, sortir du cadre = retirer.
struct CurveEditor: View {
    @Binding var points: [CurvePoint]?
    var onChange: () -> Void
    var onEnd: () -> Void
    @State private var dragging: Int?

    private var pts: [CurvePoint] { points ?? [CurvePoint(0, 0), CurvePoint(255, 255)] }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.secondary.opacity(0.1))
                Path { p in
                    for i in 1..<4 {
                        let v = s * CGFloat(i) / 4
                        p.move(to: CGPoint(x: v, y: 0)); p.addLine(to: CGPoint(x: v, y: s))
                        p.move(to: CGPoint(x: 0, y: v)); p.addLine(to: CGPoint(x: s, y: v))
                    }
                }.stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                Path { p in
                    let lut = CurveLUT.make(points)
                    for x in 0..<256 {
                        let pt = CGPoint(x: CGFloat(x) / 255 * s, y: s - CGFloat(lut[x]) / 255 * s)
                        x == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }.stroke(Color.accentColor, lineWidth: 2)
                ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                    Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                        .position(x: CGFloat(pt.x) / 255 * s, y: s - CGFloat(pt.y) / 255 * s)
                }
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let x0 = (geo.size.width - s) / 2
                    let loc = CGPoint(x: v.location.x - x0, y: v.location.y)
                    var list = pts
                    if dragging == nil {
                        let start = CGPoint(x: v.startLocation.x - x0, y: v.startLocation.y)
                        if let i = list.indices.min(by: { dist(list[$0], start, s) < dist(list[$1], start, s) }), dist(list[i], start, s) < 24 {
                            dragging = i
                        } else {
                            list.append(CurvePoint(Double(start.x / s * 255), Double((s - start.y) / s * 255)))
                            list.sort { $0.x < $1.x }
                            dragging = list.firstIndex { abs($0.x - Double(start.x / s * 255)) < 0.01 }
                        }
                    }
                    guard let i = dragging, list.indices.contains(i) else { return }
                    list[i] = CurvePoint(min(255, max(0, Double(loc.x / s * 255))), min(255, max(0, Double((s - loc.y) / s * 255))))
                    list.sort { $0.x < $1.x }
                    dragging = list.firstIndex { abs($0.x - Double(loc.x / s * 255)) < 0.51 } ?? i
                    points = list
                    onChange()
                }
                .onEnded { v in
                    let x0 = (geo.size.width - s) / 2
                    let loc = CGPoint(x: v.location.x - x0, y: v.location.y)
                    // Sorti du cadre : le point est retiré (au moins deux points restent).
                    if let i = dragging, var list = points, list.count > 2, (loc.x < -30 || loc.x > s + 30 || loc.y < -30 || loc.y > s + 30), list.indices.contains(i) {
                        list.remove(at: i); points = list
                    }
                    dragging = nil
                    onEnd()
                })
        }
    }

    private func dist(_ p: CurvePoint, _ q: CGPoint, _ s: CGFloat) -> CGFloat {
        let px = CGFloat(p.x) / 255 * s, py = s - CGFloat(p.y) / 255 * s
        return hypot(px - q.x, py - q.y)
    }
}

/// Recadrage : rapport d'aspect et fenêtre réglés par curseurs.
struct CropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var params: EditParams
    let photo: Photo
    var onDone: () -> Void

    @State private var ratio = "free"
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var w = 1.0
    @State private var h = 1.0

    private var size: (Double, Double) {
        let (rw, rh) = EditGeometry.rotatedSize(photo.width ?? 4, photo.height ?? 3, rotate: params.rotate)
        return (Double(rw), Double(rh))
    }
    private static let ratios: [(String, String, Double?)] = [("free", "Libre", nil), ("orig", "Original", -1), ("1:1", "1:1", 1), ("4:3", "4:3", 4.0 / 3),
                                                              ("3:2", "3:2", 1.5), ("16:9", "16:9", 16.0 / 9), ("5:4", "5:4", 1.25), ("4:5", "4:5", 0.8)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Rapport", selection: $ratio) { ForEach(Self.ratios, id: \.0) { Text($0.1).tag($0.0) } }
                        .onChange(of: ratio) { _, _ in applyRatio() }
                }
                Section("Fenêtre") {
                    row("Largeur", $w, 0.1...1) { applyRatio() }
                    if ratio == "free" { row("Hauteur", $h, 0.1...1) { clamp() } }
                    row("Position horizontale", $x, 0...1) { clamp() }
                    row("Position verticale", $y, 0...1) { clamp() }
                    Text("\(Int((w * size.0).rounded())) × \(Int((h * size.1).rounded())) pixels").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recadrer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        let c = CropRect(x: x, y: y, w: w, h: h).clamped
                        params.crop = c.isFull ? nil : c
                        onDone(); dismiss()
                    }
                }
            }
            .onAppear {
                if let c = params.crop { x = c.x; y = c.y; w = c.w; h = c.h }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(_ title: String, _ v: Binding<Double>, _ range: ClosedRange<Double>, changed: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            Text("\(title) : \(Int(v.wrappedValue * 100)) %").font(.subheadline)
            Slider(value: v, in: range) { editing in if !editing { changed() } }
        }
    }

    /// Hauteur déduite de la largeur et du rapport choisi.
    private func applyRatio() {
        let (W, H) = size
        if let r = Self.ratios.first(where: { $0.0 == ratio })?.2 {
            let target = r < 0 ? W / H : r
            h = w * W / (target * H)
            if h > 1 { h = 1; w = target * H / W }
        }
        clamp()
    }

    private func clamp() {
        w = min(1, max(0.1, w)); h = min(1, max(0.1, h))
        x = min(1 - w, max(0, x)); y = min(1 - h, max(0, y))
    }
}
