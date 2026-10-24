import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No workouts yet",
                systemImage: "calendar",
                description: Text("Finished workouts will be listed here by week.")
            )
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
