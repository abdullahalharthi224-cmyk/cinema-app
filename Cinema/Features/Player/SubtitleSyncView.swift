import SwiftUI

/// Tap-to-sync: the subtitle's lines scroll along with the video, and tapping
/// the one you just heard lines the whole subtitle up with the audio.
struct SubtitleSyncView: View {
    @Bindable var model: PlayerViewModel

    @State private var lastInteraction = Date.distantPast
    @State private var syncedCueID: Int?
    @State private var syncCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
            switch model.sync {
            case .idle, .loading:
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                    Text("Reading the subtitle…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .ready(_, let cues):
                cueList(cues)
            case .embeddedOnly:
                message("captions.bubble", "Smart sync works with subtitles from addons. Pick one in the Subtitles tab, or use the timing buttons in Adjust.")
            case .noSubtitle:
                message("captions.bubble", "Turn on a subtitle first, then come back here to sync it.")
            case .failed:
                message("exclamationmark.triangle", "This subtitle couldn't be read. Try another option, or use the timing buttons in Adjust.")
            }
        }
        .task(id: model.selectedSubtitleURL) { await model.prepareSync() }
        .sensoryFeedback(.success, trigger: syncCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Smart Sync", systemImage: "waveform.badge.magnifyingglass")
                .font(.subheadline.weight(.semibold))
            Text("Tap a line the moment you hear it. The rest of the subtitle follows.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.s) {
                Text(verbatim: String(format: "%+.2fs", model.subtitleDelay))
                    .font(.rounded(.footnote, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.22), in: Capsule())
                Spacer()
                if model.subtitleDelay != 0 {
                    Button("Reset") {
                        model.setSubtitleDelay(0)
                        syncedCueID = nil
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .animation(Theme.Motion.spring, value: model.subtitleDelay)
        }
    }

    private func cueList(_ cues: [SubtitleCue]) -> some View {
        // The cue the subtitle is showing (or about to show) with the current delay.
        let current = cues.nearestIndex(to: model.position - model.subtitleDelay) ?? 0
        let range = max(current - 40, 0)..<min(current + 60, cues.count)

        return ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(cues[range]) { cue in
                    cueRow(cue, isCurrent: cue.id == current)
                        .id(cue.id)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in lastInteraction = .now })
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, index in
                // Follow the video, unless the viewer is looking around.
                guard Date.now.timeIntervalSince(lastInteraction) > 4 else { return }
                withAnimation(.smooth) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func cueRow(_ cue: SubtitleCue, isCurrent: Bool) -> some View {
        Button {
            model.syncSubtitle(to: cue)
            syncedCueID = cue.id
            syncCount += 1
            lastInteraction = .distantPast
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Text(verbatim: PlayerViewModel.format(cue.start))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .leading)
                Text(verbatim: cue.text)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if syncedCueID == cue.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
            .background(
                isCurrent ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(Color.clear),
                in: .continuous(Theme.Radius.medium)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: isCurrent)
    }

    private func message(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))
    }
}
