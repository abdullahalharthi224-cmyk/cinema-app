import SwiftUI

/// Completion shares for series cards, from the episode counts saved when
/// each series page was last opened.
enum SeriesCompletion {
    /// `metaID → 0…1` for the series in `metaIDs` the active profile has started.
    static func shares(for metaIDs: some Sequence<String>, progress: [PlaybackProgress]) -> [String: Double] {
        let profileID = ProfileSession.shared.activeID
        var watched: [String: [String]] = [:]
        for record in progress where record.watched && record.profileID == profileID {
            watched[record.metaID, default: []].append(record.videoID)
        }
        var shares: [String: Double] = [:]
        for metaID in Set(metaIDs) {
            guard let total = SeriesEpisodeCounts.count(for: metaID),
                  let share = SeriesProgress.fraction(watchedVideoIDs: watched[metaID] ?? [], total: total),
                  share > 0
            else { continue }
            shares[metaID] = share
        }
        return shares
    }
}

/// "12 of 26 episodes watched" with a bar, under a series' episode list.
struct SeriesCompletionBar: View {
    let watched: Int
    let total: Int

    private var share: Double { total > 0 ? min(1, Double(watched) / Double(total)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(watched) of \(total) episodes watched")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.rounded(.footnote, weight: .bold))
                    .foregroundStyle(share >= 1 ? Color.green : Theme.accent)
                    .contentTransition(.numericText(value: share))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill((share >= 1 ? Color.green : Theme.accent).gradient)
                        .frame(width: max(proxy.size.width * share, share > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
            .environment(\.layoutDirection, .leftToRight)
        }
        .animation(Theme.Motion.spring, value: watched)
        .accessibilityElement(children: .combine)
    }
}

/// A small ring with the percentage, on series cards.
struct CompletionBadge: View {
    let share: Double

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: share)
                    .stroke(share >= 1 ? Color.green : Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text(share, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(Text("\(Text(share, format: .percent.precision(.fractionLength(0)))) watched"))
    }
}
