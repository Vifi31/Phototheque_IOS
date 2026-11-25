import SwiftUI
import Charts
import PhotothequeCore

/// Tableau de bord : chiffres, répartitions cliquables, manques et volumes.
struct DashboardView: View {
    @EnvironmentObject var library: Library
    @State private var data: Dashboard?
    @State private var scoped = false
    @State private var csvURL: URL?

    var body: some View {
        List {
            Section {
                Toggle("Seulement les photos affichées", isOn: $scoped)
                    .onChange(of: scoped) { _, _ in load() }
            } footer: {
                Text(scoped ? "Le tableau de bord suit les filtres de l'écran Photos." : "Tout le catalogue.")
            }
            if let d = data {
                Section("Chiffres") {
                    LabeledContent("Photos", value: "\(d.photos)")
                    LabeledContent("Volume", value: Fmt.bytes(d.bytes))
                    LabeledContent("Mots-clés", value: "\(d.keywords)")
                    LabeledContent("Collections", value: "\(d.collections)")
                }
                if d.byYear.count > 0 {
                    Section("Par année") {
                        Chart(d.byYear) { BarMark(x: .value("Année", $0.label), y: .value("Photos", $0.count)) }
                            .frame(height: 150)
                    }
                }
                if d.byMonth.count > 1 {
                    Section("Par mois (36 derniers mois)") {
                        Chart(d.byMonth) { BarMark(x: .value("Mois", $0.label), y: .value("Photos", $0.count)) }
                            .chartXAxis(.hidden)
                            .frame(height: 130)
                    }
                }
                bars("Formats", d.byFormat) { label in { $0.formats = [label] } }
                bars("Appareils", d.byCamera.filter { $0.label != "Inconnu" }) { label in { $0.cameras = [label] } }
                bars("Objectifs", d.byLens.filter { $0.label != "Inconnu" }) { label in { $0.lens = label } }
                bars("Notes", d.byRating) { label in { $0.minRating = label.contains("★") ? label.count : nil } }
                bars("Orientation", d.byOrientation) { label in { $0.orientation = Orientation.allCases.first { $0.label == label } } }
                Section("Manques") {
                    ForEach(d.gaps) { g in
                        Button {
                            if let m = g.missing { open { $0.missing = m } }
                            else if g.noGPS { open { $0.hasGPS = false } }
                        } label: {
                            LabeledContent(g.label) { Text("\(g.count)").foregroundStyle(g.count > 0 ? Color.orange : .secondary) }
                        }
                        .disabled(g.count == 0 || (g.missing == nil && !g.noGPS))
                    }
                }
                if !d.largest.isEmpty {
                    Section("Les plus volumineuses") {
                        ForEach(d.largest) { p in
                            LabeledContent(p.fileName) { Text(Fmt.bytes(p.size)).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section {
                    Button { exportCSV(d) } label: { Label("Exporter en CSV", systemImage: "tablecells") }
                    if let csvURL { ShareLink(item: csvURL) { Label("Partager \(csvURL.lastPathComponent)", systemImage: "square.and.arrow.up") } }
                }
            }
        }
        .navigationTitle("Tableau de bord")
        .onAppear(perform: load)
        .onChange(of: library.revision) { _, _ in load() }
    }

    /// Répartition en barres : toucher une ligne affiche les photos correspondantes.
    @ViewBuilder private func bars(_ title: String, _ items: [DistributionItem], _ filter: @escaping (String) -> (inout SearchCriteria) -> Void) -> some View {
        let shown = items.filter { $0.count > 0 }
        if !shown.isEmpty {
            let peak = max(1, shown.map(\.count).max() ?? 1)
            Section(title) {
                ForEach(shown) { item in
                    Button { open(filter(item.label)) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.label).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                Text("\(item.count)").foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                Capsule().fill(Color.accentColor.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * CGFloat(item.count) / CGFloat(peak)), height: 6)
                            }.frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private func open(_ edit: (inout SearchCriteria) -> Void) {
        var c = SearchCriteria(sort: library.criteria.sort)
        edit(&c)
        library.criteria = c
        library.tab = .photos
    }

    private func load() {
        data = try? library.catalog.dashboard(scoped ? library.criteria : SearchCriteria())
    }

    private func exportCSV(_ d: Dashboard) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
        let url = library.catalog.exportsDir.appendingPathComponent("Tableau-de-bord-\(f.string(from: Date())).csv")
        do { try d.csv().data(using: .utf8)!.write(to: url); csvURL = url } catch { library.report(error) }
    }
}
