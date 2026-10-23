import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Search Is Coming",
                systemImage: "magnifyingglass",
                description: Text("Soon you'll be able to search every addon that supports it, all at once.")
            )
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Search")
        }
    }
}
