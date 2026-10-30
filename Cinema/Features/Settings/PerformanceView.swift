import SwiftUI
import UIKit

/// The hidden Performance screen (tap the version in Settings five times):
/// launch timings, memory, caches, network and background work, live.
struct PerformanceView: View {
    @State private var sizes: CacheMaintenance.Sizes?
    @State private var copied = false

    private var monitor: PerformanceMonitor { PerformanceMonitor.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            List {
                Section {
                    row("App Launch", seconds(monitor.firstFrame))
                    row("Home Ready", seconds(monitor.homeReady), detail: monitor.homeReady == nil ? nil
                        : Text(monitor.homeFromCache ? LocalizedStringKey("from saved copy") : "from network"))
                } header: {
                    Text("This Launch")
                } footer: {
                    Text("Measured from the moment iOS starts Cinema.")
                        .settingsFooter()
                }

                if monitor.history.count > 1 {
                    Section("Recent Launches") {
                        ForEach(monitor.history, id: \.self) { launch in
                            LabeledContent {
                                Text(verbatim: "\(secondsText(launch.firstFrame)) · \(secondsText(launch.homeReady))")
                                    .monospacedDigit()
                            } label: {
                                Text(launch.date, format: .dateTime.day().month().hour().minute())
                            }
                        }
                    }
                }

                Section("Now") {
                    row("Memory", bytes(PerformanceMonitor.memoryFootprint().map(Int64.init)))
                    let network = NetworkStats.shared.snapshot
                    row("Network Requests", Text(verbatim: "\(network.total)"))
                    row("Running Now", Text(verbatim: "\(network.active)"))
                    row("Avoided (Shared)", Text(verbatim: "\(network.shared)"))
                    row("Performance Mode", Text(PerformanceSettings.shared.isActive ? LocalizedStringKey("On") : "Off"))
                    row("Thermal State", Text(verbatim: thermalState))
                }

                Section {
                    let activities = BackgroundActivity.shared.current
                    let downloads = DownloadManager.shared.pendingVideoIDs.count
                    if activities.isEmpty && downloads == 0 {
                        Text("Nothing")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activities, id: \.name) { activity in
                        row(LocalizedStringKey(activity.name), Text(verbatim: activity.count > 1 ? "×\(activity.count)" : "●"))
                    }
                    if downloads > 0 {
                        row("Downloads", Text(verbatim: "\(downloads)"))
                    }
                } header: {
                    Text("Working in the Background")
                }

                Section("Cache") {
                    if let sizes {
                        row("Artwork", bytes(sizes.images))
                        row("Responses", bytes(sizes.responses))
                        row("Saved Home Rows", bytes(sizes.homeRows))
                        row("Temporary Files", bytes(sizes.temporary))
                        row("Total", bytes(sizes.total))
                    } else {
                        ProgressView()
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = report
                        copied.toggle()
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text("Paste the report in a message to share these numbers.")
                        .settingsFooter()
                }
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
        .task {
            // Cache sizes need the disk, so they refresh every few seconds rather than every second.
            while !Task.isCancelled {
                sizes = await CacheMaintenance.sizes()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Text, detail: Text? = nil) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                value.monospacedDigit()
                if let detail {
                    detail.font(.caption2).foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(title)
        }
    }

    private func seconds(_ value: TimeInterval?) -> Text {
        Text(verbatim: secondsText(value))
    }

    private func secondsText(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f s", value)
    }

    private func bytes(_ value: Int64?) -> Text {
        Text(verbatim: value.map { AppFormat.bytes($0, .memory) } ?? "—")
    }

    private var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// The same numbers as plain text, to send.
    private var report: String {
        let network = NetworkStats.shared.snapshot
        let memory = PerformanceMonitor.memoryFootprint().map { AppFormat.bytes(Int64($0), .memory) } ?? "—"
        var lines = [
            "Cinema \(Bundle.main.appVersion) · iOS \(UIDevice.current.systemVersion)",
            "Launch: \(secondsText(monitor.firstFrame)) · Home: \(secondsText(monitor.homeReady))\(monitor.homeFromCache ? " (saved)" : "")",
            "Memory: \(memory)",
            "Requests: \(network.total) (running \(network.active), shared \(network.shared))",
            "Thermal: \(thermalState) · Performance mode: \(PerformanceSettings.shared.isActive)",
        ]
        if let sizes {
            lines.append("Cache: \(AppFormat.bytes(sizes.total, .file))")
        }
        let activities = BackgroundActivity.shared.current.map { "\($0.name)×\($0.count)" }
        lines.append("Background: " + (activities.isEmpty ? "none" : activities.joined(separator: ", ")))
        for launch in monitor.history.prefix(5) {
            lines.append("· \(launch.date.formatted(date: .numeric, time: .shortened)): \(secondsText(launch.firstFrame)) / \(secondsText(launch.homeReady))")
        }
        return lines.joined(separator: "\n")
    }
}
