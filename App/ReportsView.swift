import SwiftUI
import PhotothequeCore

/// Rapports : inventaire, fichiers manquants, intégrité, sauvegardes, photos à documenter.
struct ReportsView: View {
    @EnvironmentObject var library: Library

    var body: some View {
        List(ReportKind.allCases) { kind in
            NavigationLink {
                ReportDetail(kind: kind)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                    Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Rapports")
    }
}

struct ReportDetail: View {
    @EnvironmentObject var library: Library
    let kind: ReportKind
    @State private var table: ReportTable?
    @State private var csvURL: URL?
    @State private var pdfURL: URL?

    var body: some View {
        List {
            if let t = table {
                Section {
                    Text(t.subtitle).foregroundStyle(.secondary)
                    ForEach(t.notes, id: \.self) { Text($0).font(.footnote) }
                }
                Section {
                    if let csvURL { ShareLink(item: csvURL) { Label("Partager le CSV", systemImage: "tablecells") } }
                    if let pdfURL { ShareLink(item: pdfURL) { Label("Partager le PDF", systemImage: "doc.richtext") } }
                }
                Section("Aperçu (\(min(t.rows.count, 100)) sur \(t.rows.count) ligne(s))") {
                    ForEach(Array(t.rows.prefix(100).enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.first ?? "").font(.subheadline).lineLimit(1)
                            Text(summary(t.headers, row))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: build)
    }

    /// « Colonne : valeur · … » pour les 4 premières colonnes renseignées (après la première).
    private func summary(_ headers: [String], _ row: [String]) -> String {
        var parts: [String] = []
        for (i, h) in headers.enumerated() where i > 0 && i < row.count && !row[i].isEmpty {
            parts.append(h + " : " + row[i])
            if parts.count == 4 { break }
        }
        return parts.joined(separator: " · ")
    }

    private func build() {
        do {
            let t = try library.catalog.report(kind, criteria: kind == .inventory ? library.criteria : SearchCriteria())
            table = t
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
            let base = library.catalog.exportsDir.appendingPathComponent("\(kind.rawValue)-\(f.string(from: Date()))")
            let csv = base.appendingPathExtension("csv")
            try t.csv().data(using: .utf8)!.write(to: csv)
            csvURL = csv
            let pdf = base.appendingPathExtension("pdf")
            try PDFDocumentBuilder.table(t).write(to: pdf)
            pdfURL = pdf
        } catch { library.report(error) }
    }
}
