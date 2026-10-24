import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No workout in progress",
                systemImage: "dumbbell",
                description: Text("Workout logging arrives in the next update.")
            )
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
}
