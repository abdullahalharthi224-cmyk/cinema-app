import SwiftUI

/// In a kids profile, opens a title only after checking its age rating; any
/// title that isn't rated for the profile's age (or has no rating) is blocked.
struct KidsGated<Content: View>: View {
    let id: String
    let type: String
    @ViewBuilder var content: () -> Content

    @State private var verdict: Bool?

    private var maxAge: Int? { ProfileSession.shared.kidsMaxAge }

    var body: some View {
        if maxAge == nil || verdict == true {
            content()
        } else {
            Group {
                if verdict == false {
                    ContentUnavailableView(
                        "Not for This Profile",
                        systemImage: "figure.and.child.holdinghands",
                        description: Text("This title isn't rated for this kids profile's age.")
                    )
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .task(id: "\(id)|\(maxAge ?? -1)") {
                guard let maxAge else { return }
                let allowed = await KidsRatings.shared.isAllowed(id: id, type: type, maxAge: maxAge)
                withAnimation(Theme.Motion.spring) { verdict = allowed }
            }
        }
    }
}
