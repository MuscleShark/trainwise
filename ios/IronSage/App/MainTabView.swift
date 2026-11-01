import SwiftUI

enum AppTab: Hashable {
    case today, history, progress, templates, me
}

extension EnvironmentValues {
    /// Switches to another tab, for links between tabs (Me → Progress).
    @Entry var selectTab: (AppTab) -> Void = { _ in }
}

struct MainTabView: View {
    @State private var tab = Self.lastTab
    /// The open tab, so it stays open when the views are rebuilt in another language
    /// (picked on Me). A new launch starts on Today.
    private static var lastTab = AppTab.today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "figure.strengthtraining.traditional", value: .today) {
                TodayView()
            }
            Tab("History", systemImage: "calendar", value: .history) {
                HistoryView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
                ProgressTabView()
            }
            Tab("Templates", systemImage: "list.bullet.rectangle", value: .templates) {
                TemplatesView()
            }
            Tab("Me", systemImage: "person.crop.circle", value: .me) {
                MeView()
            }
        }
        .environment(\.selectTab) { tab = $0 }
        .onChange(of: tab) { Self.lastTab = tab }
    }
}

#Preview {
    MainTabView()
}
