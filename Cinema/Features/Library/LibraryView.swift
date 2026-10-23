import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your Library Is Empty",
                systemImage: "rectangle.stack",
                description: Text("Titles you save and the ones you're watching will appear here.")
            )
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Library")
        }
    }
}
