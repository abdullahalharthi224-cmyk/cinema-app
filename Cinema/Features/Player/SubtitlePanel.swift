import SwiftUI

/// A glass side panel in the player: choose subtitles by source, the audio
/// track, and adjust subtitle timing, size and position.
struct SubtitlePanel: View {
    @Bindable var model: PlayerViewModel
    var onClose: () -> Void

    @State private var tab: Tab = .subtitles
    /// The addon-subtitle language whose options are showing.
    @State private var expandedLanguage: String?

    enum Tab: Hashable { case subtitles, audio, sync, adjust }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Picker("Section", selection: $tab) {
                    Text("Subtitles").tag(Tab.subtitles)
                    Text("Audio").tag(Tab.audio)
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

            if tab == .sync {
                // The sync list scrolls by itself, following the video.
                SubtitleSyncView(model: model)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        switch tab {
                        case .subtitles: subtitlesTab
                        case .audio: audioTab
                        case .sync, .adjust: adjustTab
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(.adaptiveMaterial, in: .continuous(Theme.Radius.large))
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

        let groups = languageGroups
        if !groups.isEmpty {
            group(title: localized("From Addons")) {
                ForEach(groups) { language in
                    languageRow(language)
                    if expandedLanguage == language.id && language.options.count > 1 {
                        ForEach(language.options) { option in
                            row(
                                title: option.source,
                                detail: localized("Option %lld", option.number),
                                checked: model.selectedSubtitleURL == option.item.url
                            ) {
                                model.selectExternalSubtitle(option.item)
                            }
                            .padding(.leading, Theme.Spacing.l)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .animation(Theme.Motion.snappy, value: expandedLanguage)
            .onAppear {
                // Open the language that's showing, so its choice is visible.
                if expandedLanguage == nil, let url = model.selectedSubtitleURL {
                    expandedLanguage = groups.first { $0.options.contains { $0.item.url == url } }?.id
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

    /// Addon subtitles grouped by language: one entry per language (Arabic
    /// first, then the other preferred languages, then the rest by name), each
    /// opening its options from every addon.
    private struct LanguageGroup: Identifiable {
        struct Option: Identifiable {
            var item: SubtitleItem
            var source: String
            var number: Int
            var id: String { item.url }
        }
        var id: String
        var name: String
        var options: [Option]
    }

    private var languageGroups: [LanguageGroup] {
        var groups: [String: LanguageGroup] = [:]
        for source in model.subtitleSources {
            var counts: [String: Int] = [:]
            for item in source.items {
                let key = SubtitleLanguage.code(for: item.lang) ?? item.lang?.lowercased() ?? "unknown"
                counts[key, default: 0] += 1
                let option = LanguageGroup.Option(item: item, source: source.addon.name, number: counts[key]!)
                guard !(groups[key]?.options.contains { $0.id == option.id } ?? false) else { continue }
                groups[key, default: LanguageGroup(id: key, name: languageName(item.lang), options: [])].options.append(option)
            }
        }
        let preferred = ["ar"] + PlaybackSettings.shared.subtitleLanguages.filter { $0 != "ar" }
        return groups.values.sorted { lhs, rhs in
            let left = preferred.firstIndex(of: lhs.id) ?? preferred.count
            let right = preferred.firstIndex(of: rhs.id) ?? preferred.count
            if left != right { return left < right }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private func languageRow(_ language: LanguageGroup) -> some View {
        let isSelected = language.options.contains { $0.item.url == model.selectedSubtitleURL }
        let isExpanded = expandedLanguage == language.id
        return Button {
            if language.options.count == 1, let only = language.options.first {
                model.selectExternalSubtitle(only.item)
            } else {
                expandedLanguage = isExpanded ? nil : language.id
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                Text(verbatim: language.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                Text(verbatim: language.options.count == 1
                     ? language.options[0].source
                     : localized("%lld options", language.options.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if language.options.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Audio

    @ViewBuilder
    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(get: { PlaybackSettings.shared.nightMode }, set: { model.setNightMode($0) })) {
                Label("Night Mode", systemImage: "moon.stars.fill")
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
            Divider().padding(.leading, Theme.Spacing.m)
            Toggle(isOn: Binding(get: { PlaybackSettings.shared.dialogueBoost }, set: { model.setDialogueBoost($0) })) {
                Label("Dialogue Boost", systemImage: "waveform.badge.plus")
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
        }
        .font(.subheadline)
        .tint(Theme.accent)
        .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))

        Text("Night mode evens out loud and quiet moments; dialogue boost lifts voices. Both use the built-in player.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

        if model.audioTracks.count > 1 {
            audioTracksGroup
        }
    }

    private var audioTracksGroup: some View {
        group(title: localized("Audio Track")) {
            ForEach(model.audioTracks) { track in
                row(title: trackName(track), detail: track.codec?.uppercased(), checked: track.isSelected) {
                    model.selectAudio(track)
                }
            }
        }
    }

    // MARK: Adjust

    /// Smart sync: line the subtitle up with the dialogue, now or automatically.
    private var dialogueSyncCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                model.syncToDialogue()
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    if model.dialogueSync == .listening {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.dialogueSync == .listening ? LocalizedStringKey("Listening for the dialogue…") : LocalizedStringKey("Sync to the Dialogue"))
                            .font(.subheadline.weight(.semibold))
                        Text(dialogueSyncDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedSubtitleURL == nil || model.dialogueSync == .listening)

            Divider()
            Toggle(isOn: Binding(
                get: { PlaybackSettings.shared.smartSubtitleSync },
                set: { PlaybackSettings.shared.smartSubtitleSync = $0 }
            )) {
                Text("Sync Automatically")
                    .font(.subheadline)
            }
            .tint(Theme.accent)
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.06), in: .continuous(Theme.Radius.medium))
    }

    private var dialogueSyncDetail: String {
        guard model.selectedSubtitleURL != nil else {
            return localized("Works with subtitles from addons.")
        }
        switch model.dialogueSync {
        case .idle, .listening:
            return localized("Listens for the first voices and moves the subtitle to match. Credits and titles are ignored.")
        case .done(let delay):
            return delay == 0 ? localized("Already matches the dialogue.") : localized("Moved by %@.", String(format: "%+.1fs", delay))
        case .failed:
            return localized("Couldn't hear enough dialogue. Try again later in the episode.")
        }
    }

    @ViewBuilder
    private var adjustTab: some View {
        dialogueSyncCard
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

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Color")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.m) {
                ForEach(PlaybackSettings.subtitleColors, id: \.self) { hex in
                    let selected = PlaybackSettings.shared.subtitleColorHex == hex
                    Button {
                        model.setSubtitleColor(hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .white)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: selected ? 2.5 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: PlaybackSettings.shared.subtitleColorHex)

            Text("Background")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.xs)
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "textformat")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { PlaybackSettings.shared.subtitleBackground },
                    set: { model.setSubtitleBackground($0) }
                ), in: 0...0.85)
                Image(systemName: "rectangle.fill")
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trackName(_ track: PlayerTrack) -> String {
        var parts: [String] = []
        if let name = PlayerViewModel.languageName(SubtitleLanguage.code(for: track.language)) {
            parts.append(name)
        } else if let language = track.language {
            parts.append(language)
        }
        if let title = track.title, !parts.contains(title) { parts.append(title) }
        if parts.isEmpty { parts.append(localized("Track %lld", track.id)) }
        return Bidi.join(parts)
    }

    private func languageName(_ raw: String?) -> String {
        PlayerViewModel.languageName(SubtitleLanguage.code(for: raw)) ?? raw ?? localized("Unknown")
    }
}
