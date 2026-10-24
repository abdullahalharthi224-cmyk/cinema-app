import SwiftUI

/// Settings → Playback: how the Play button picks a stream, and subtitles.
struct PlaybackSettingsView: View {
    @State private var settings = PlaybackSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Preferred Quality", selection: $settings.quality) {
                    ForEach(PreferredQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                Toggle("Prefer Instant Links", isOn: $settings.preferCached)
            } header: {
                Text("Play Button")
            } footer: {
                Text("Play picks the best stream for you: your preferred quality, links already cached on your debrid service first, and a sensible file size. Use the list button to choose one yourself.")
            }

            Section {
                Picker("Subtitle Language", selection: $settings.subtitles) {
                    Text(verbatim: "العربية").tag(PlaybackSettings.SubtitleChoice.arabic)
                    Text(verbatim: "English").tag(PlaybackSettings.SubtitleChoice.english)
                    Text("Off").tag(PlaybackSettings.SubtitleChoice.off)
                }
                if settings.subtitles == .arabic {
                    Picker("If Arabic Isn't Available", selection: $settings.subtitleFallback) {
                        Text("No Subtitles").tag(PlaybackSettings.SubtitleFallback.off)
                        Text(verbatim: "English").tag(PlaybackSettings.SubtitleFallback.english)
                    }
                }
                Picker("Subtitle Size", selection: $settings.subtitleSize) {
                    ForEach(PlaybackSettings.SubtitleSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Subtitles in this language are turned on automatically — from the video itself or from subtitle addons like OpenSubtitles.")
            }

            Section {
                Toggle("Use Apple Player When Possible", isOn: $settings.useApplePlayer)
            } header: {
                Text("Player")
            } footer: {
                Text("MP4 and HLS streams play in Apple's player, with Picture in Picture and full AirPlay. Everything else (like MKV) plays in the built-in player, which handles any format. The controls are the same in both.")
            }
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension PreferredQuality {
    var title: LocalizedStringKey {
        switch self {
        case .auto: return "Best Available"
        case .uhd: return "4K"
        case .fullHD: return "1080p"
        case .hd: return "720p"
        }
    }
}

extension PlaybackSettings.SubtitleSize {
    var title: LocalizedStringKey {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}
