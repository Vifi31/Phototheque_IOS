import SwiftUI
import PhotothequeCore

/// Analyse : tableau de bord, doublons, rapports (et, plus loin, assistant).
struct AnalyseView: View {
    @EnvironmentObject var library: Library

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { DashboardView() } label: { Label("Tableau de bord", systemImage: "chart.bar.xaxis") }
                NavigationLink { DuplicatesView() } label: { Label("Doublons et photos semblables", systemImage: "square.on.square") }
                NavigationLink { ReportsView() } label: { Label("Rapports", systemImage: "doc.text") }
            }
            .navigationTitle("Analyse")
        }
    }
}
