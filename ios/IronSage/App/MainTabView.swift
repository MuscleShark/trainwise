import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "figure.strengthtraining.traditional") {
                TodayView()
            }
            Tab("History", systemImage: "calendar") {
                HistoryView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                ProgressTabView()
            }
            Tab("Templates", systemImage: "list.bullet.rectangle") {
                TemplatesView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}

#Preview {
    MainTabView()
}
