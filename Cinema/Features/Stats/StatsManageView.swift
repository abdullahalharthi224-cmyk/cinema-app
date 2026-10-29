import SwiftData
import SwiftUI

/// Statistics → Most Watched → Edit: remove titles from the statistics (for
/// example ones only opened to try something), or clear them all.
struct StatsManageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var titles: [ViewingStats.TitleTotal] = []
    @State private var isConfirmingClear = false

    var body: some View {
        List {
            if titles.isEmpty {
                ContentUnavailableView(
                    "No Viewing Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Watch something and your statistics will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(titles) { title in
                        HStack(spacing: Theme.Spacing.m) {
                            PosterArtwork(url: title.poster?.asURL, title: title.name, id: title.metaID)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: title.name.isEmpty ? title.metaID : title.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(verbatim: Hours.text(title.seconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                remove(title)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Swipe a title to remove it from this profile's statistics and Wrapped. Your Library and Continue Watching aren't changed.")
                        .settingsFooter()
                }

                Section {
                    Button("Clear All Statistics", role: .destructive) {
                        isConfirmingClear = true
                    }
                }
            }
        }
        .navigationTitle("Edit Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .confirmationDialog("Clear all statistics for this profile?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear All Statistics", role: .destructive) {
                ViewingLogStore.deleteAll(in: context)
                withAnimation(Theme.Motion.spring) { titles = [] }
            }
        } message: {
            Text("Hours, streaks and Wrapped start again from zero. Other profiles keep theirs.")
        }
        .sensoryFeedback(.success, trigger: titles.count)
    }

    private func load() {
        let profileID = ProfileSession.shared.activeID
        let logs = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.profileID == profileID }))) ?? []
        titles = ViewingStats(entries: logs.map {
            ViewingEntry(day: $0.day, metaID: $0.metaID, type: $0.type, videoID: $0.videoID, name: $0.name,
                         poster: $0.poster, background: $0.background, seconds: $0.seconds)
        }).topTitles
    }

    private func remove(_ title: ViewingStats.TitleTotal) {
        ViewingLogStore.delete(metaID: title.metaID, in: context)
        withAnimation(Theme.Motion.spring) { titles.removeAll { $0.id == title.id } }
    }
}
