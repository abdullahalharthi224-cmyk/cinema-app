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
                Toggle("Play Next Episode Automatically", isOn: $settings.autoPlayNext)
                Toggle("Skip Intros Automatically", isOn: $settings.autoSkipIntro)
            } header: {
                Text("Play Button")
            } footer: {
                Text("Play picks the best stream for you: your preferred quality, links already cached on your debrid service first, and a sensible file size. Use the list button to choose one yourself.")
                    .settingsFooter()
            }

            Section {
                Toggle("Double-Tap to Skip", isOn: $settings.gestureDoubleTap)
                if settings.gestureDoubleTap {
                    Picker("Skip Step", selection: $settings.seekStep) {
                        ForEach(PlaybackSettings.seekSteps, id: \.self) { step in
                            Text("\(step) seconds").tag(step)
                        }
                    }
                }
                Toggle("Hold for 2× Speed", isOn: $settings.gestureLongPress)
                Toggle("Swipe Left Side for Brightness", isOn: $settings.gestureBrightness)
                Toggle("Swipe Right Side for Volume", isOn: $settings.gestureVolume)
                Toggle("Swipe Sideways to Seek", isOn: $settings.gestureScrub)
            } header: {
                Text("Player Gestures")
            } footer: {
                Text("Gestures ignore the very edges of the screen, so Control Center and notifications still open normally. They pause while a menu is open.")
                    .settingsFooter()
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
                    .settingsFooter()
            }

            Section {
                Toggle("Smart Subtitle Sync", isOn: $settings.smartSubtitleSync)
            } footer: {
                Text("Before each episode starts, Cinema listens for the first voices — not music — and lines subtitles from addons up with them. The translator's name, the episode title and links at the start are ignored. Everything happens on this iPhone.")
                    .settingsFooter()
            }

            Section {
                Picker("Preferred Audio", selection: $settings.audioPreference) {
                    Text("Original Audio").tag(PlaybackSettings.AudioPreference.original)
                    Text("Arabic When Available").tag(PlaybackSettings.AudioPreference.arabic)
                }
                Toggle("Night Mode", isOn: $settings.nightMode)
                Toggle("Dialogue Boost", isOn: $settings.dialogueBoost)
            } header: {
                Text("Audio")
            } footer: {
                Text("Night mode evens out loud and quiet moments; dialogue boost lifts voices. Both use the built-in player.")
                    .settingsFooter()
            }

            Section {
                HStack(spacing: Theme.Spacing.m) {
                    Text("Color")
                    Spacer()
                    ForEach(PlaybackSettings.subtitleColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .white)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: settings.subtitleColorHex == hex ? 2.5 : 0).padding(-4))
                            .onTapGesture { settings.subtitleColorHex = hex }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Background")
                    Slider(value: $settings.subtitleBackground, in: 0...0.85)
                }
                SubtitleStylePreview(settings: settings)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Subtitle Style")
            }

            Section {
                Toggle("Use Apple Player When Possible", isOn: $settings.useApplePlayer)
            } header: {
                Text("Player")
            } footer: {
                Text("MP4 and HLS streams play in Apple's player, with Picture in Picture and full AirPlay. Everything else (like MKV) plays in the built-in player, which handles any format. The controls are the same in both.")
                    .settingsFooter()
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

/// A sample subtitle line over a dark scene, in the chosen colour and background.
private struct SubtitleStylePreview: View {
    let settings: PlaybackSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(white: 0.25), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            Text("This is how subtitles will look.")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: settings.subtitleColorHex) ?? .white)
                .shadow(color: .black.opacity(settings.subtitleBackground > 0.01 ? 0 : 0.9), radius: 2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(settings.subtitleBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.bottom, Theme.Spacing.l)
        }
        .frame(height: 110)
        .animation(Theme.Motion.snappy, value: settings.subtitleColorHex)
    }
}
