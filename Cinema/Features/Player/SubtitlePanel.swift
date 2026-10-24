import SwiftUI

/// A glass side panel in the player: choose subtitles by source, the audio
/// track, and adjust subtitle timing, size and position.
struct SubtitlePanel: View {
    @Bindable var model: PlayerViewModel
    var onClose: () -> Void

    @State private var tab: Tab = .subtitles

    enum Tab: Hashable { case subtitles, audio, sync, adjust }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Picker("Section", selection: $tab) {
                    Text("Subtitles").tag(Tab.subtitles)
                    if model.audioTracks.count > 1 {
                        Text("Audio").tag(Tab.audio)
                    }
                    Text("Sync").tag(Tab.sync)
                    Text("Adjust").tag(Tab.adjust)
                }
                .pickerStyle(.segmented)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    switch tab {
                    case .subtitles: subtitlesTab
                    case .audio: audioTab
                    case .sync: SubtitleSyncView(model: model)
                    case .adjust: adjustTab
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(Theme.Spacing.l)
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.large))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 30)
        .environment(\.colorScheme, .dark)
        .animation(Theme.Motion.spring, value: tab)
        .sensoryFeedback(.selection, trigger: tab)
    }

    // MARK: Subtitles

    @ViewBuilder
    private var subtitlesTab: some View {
        group(title: nil) {
            row(title: localized("Off"), detail: nil, checked: model.isSubtitleOff) {
                model.selectSubtitle(nil)
            }
        }

        if !model.embeddedSubtitles.isEmpty {
            group(title: localized("In the Video")) {
                ForEach(model.embeddedSubtitles) { track in
                    row(title: trackName(track), detail: track.codec?.uppercased(), checked: track.isSelected) {
                        model.selectSubtitle(track)
                    }
                }
            }
        }

        ForEach(model.subtitleSources) { source in
            group(title: source.addon.name) {
                ForEach(Array(source.items.prefix(40).enumerated()), id: \.offset) { index, item in
                    row(
                        title: languageName(item.lang),
                        detail: localized("Option %lld", index + 1),
                        checked: model.selectedSubtitleURL == item.url
                    ) {
                        model.selectExternalSubtitle(item)
                    }
                }
            }
        }

        if model.isLoadingSubtitles {
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("Looking for subtitles…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if model.subtitleSources.isEmpty && model.embeddedSubtitles.isEmpty {
            Text("No subtitles were found. Add a subtitles addon such as OpenSubtitles to get more.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Audio

    @ViewBuilder
    private var audioTab: some View {
        group(title: nil) {
            ForEach(model.audioTracks) { track in
                row(title: trackName(track), detail: track.codec?.uppercased(), checked: track.isSelected) {
                    model.selectAudio(track)
                }
            }
        }
    }

    // MARK: Adjust

    @ViewBuilder
    private var adjustTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Timing")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.m) {
                stepButton("minus") { model.adjustSubtitleDelay(by: -0.1) }
                VStack(spacing: 2) {
                    Text(verbatim: delayText)
                        .font(.rounded(.title3, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(delayHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                stepButton("plus") { model.adjustSubtitleDelay(by: 0.1) }
            }
            HStack(spacing: Theme.Spacing.s) {
                quickDelay(-1)
                quickDelay(-0.5)
                Button("Reset") { model.setSubtitleDelay(0) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(model.subtitleDelay == 0)
                quickDelay(0.5)
                quickDelay(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Size")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Size", selection: Binding(
                get: { PlaybackSettings.shared.subtitleSize },
                set: { model.setSubtitleSize($0) }
            )) {
                ForEach(PlaybackSettings.SubtitleSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Position")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "arrow.down.to.line")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { model.subtitleRaise },
                    set: { model.setSubtitleRaise($0) }
                ), in: 10...220)
                Image(systemName: "arrow.up.to.line")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))
    }

    private var delayText: String {
        let value = model.subtitleDelay
        if value == 0 { return "0.0s" }
        return String(format: "%+.2fs", value)
    }

    private var delayHint: LocalizedStringKey {
        if model.subtitleDelay > 0 { return "Subtitles appear later" }
        if model.subtitleDelay < 0 { return "Subtitles appear earlier" }
        return "In sync with the video"
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .sensoryFeedback(.selection, trigger: model.subtitleDelay)
    }

    private func quickDelay(_ seconds: Double) -> some View {
        Button {
            model.adjustSubtitleDelay(by: seconds)
        } label: {
            Text(verbatim: String(format: "%+g", seconds))
                .font(.rounded(.caption, weight: .semibold))
                .monospacedDigit()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    // MARK: Building blocks

    private func group<Content: View>(title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(verbatim: title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))
        }
    }

    private func row(title: String, detail: String?, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(checked ? 1 : 0)
                Text(verbatim: title)
                    .font(.subheadline.weight(checked ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                if let detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trackName(_ track: MPVTrack) -> String {
        var parts: [String] = []
        if let name = PlayerViewModel.languageName(SubtitleLanguage.code(for: track.language)) {
            parts.append(name)
        } else if let language = track.language {
            parts.append(language)
        }
        if let title = track.title, !parts.contains(title) { parts.append(title) }
        if parts.isEmpty { parts.append(localized("Track %lld", track.id)) }
        return parts.joined(separator: " · ")
    }

    private func languageName(_ raw: String?) -> String {
        PlayerViewModel.languageName(SubtitleLanguage.code(for: raw)) ?? raw ?? localized("Unknown")
    }
}
