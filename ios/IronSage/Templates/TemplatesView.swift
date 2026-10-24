import SwiftUI

struct TemplatesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No templates yet",
                systemImage: "list.bullet.rectangle",
                description: Text("Built-in programs and your own templates will be listed here.")
            )
            .navigationTitle("Templates")
        }
    }
}

#Preview {
    TemplatesView()
}
