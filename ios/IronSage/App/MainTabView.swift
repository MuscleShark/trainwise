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
