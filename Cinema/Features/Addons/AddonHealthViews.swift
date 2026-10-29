import SwiftData
import SwiftUI

extension AddonHealthReport.Problem {
    /// A plain-language reason the addon isn't working.
    var reason: LocalizedStringKey {
        switch self {
        case .noResponse: return "Not responding — the server may be down or too slow."
        case .expired: return "Link expired — the addon was removed or its address changed. Reinstall it."
        case .httpError(let code): return "The server returned an error (code \(code))."
        case .invalidManifest: return "Not a valid Stremio addon."
        case .localOnly: return "Only works with the Stremio desktop app."
        case .needsSetup: return "Needs setup — configure it on its website (debrid or API key)."
        case .torrentOnly: return "Only gives torrent links — needs a debrid service to play here."
        case .noStreams: return "Works, but has no streams for the test film — normal for addons with a limited library."
        case .discontinued: return "Discontinued — its address now opens a web page instead of an addon."
        case .legacyProtocol: return "Uses Stremio's old protocol, which isn't supported. Install its newer version."
        case .streamsFailed: return "The manifest works, but fetching streams failed."
        }
    }
}

extension AddonHealthReport.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .catalogs: return "Catalogs"
        case .streams: return "Streams"
        case .subtitles: return "Subtitles"
        case .metadata: return "Metadata"
        }
    }

    var symbol: String {
        switch self {
        case .catalogs: return "square.grid.2x2.fill"
        case .streams: return "play.fill"
        case .subtitles: return "captions.bubble.fill"
        case .metadata: return "info.circle.fill"
        }
    }
}

extension AddonHealthChecker {
    @MainActor
    func check(_ addon: InstalledAddon) async -> AddonHealthReport {
        guard let url = addon.manifestURL else {
            var report = AddonHealthReport(addonID: addon.transportUrl, name: addon.name)
            report.problem = .invalidManifest
            return report
        }
        return await check(name: addon.name, manifestURL: url, storedManifest: addon.manifest)
    }
}

/// One addon's check result: a green or red mark, what it provides and the details.
struct AddonHealthResultView: View {
    let report: AddonHealthReport
    var showsName = true

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(statusColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 6) {
                if showsName {
                    Text(verbatim: report.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }

                if !report.kinds.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(report.kinds, id: \.self) { kind in
                            TagChip(text: kind.title, systemImage: kind.symbol, tint: Theme.accent)
                        }
                    }
                }

                if let problem = report.problem {
                    Text(problem.reason)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(report.isWarning ? .orange : .red)
                }

                facts
            }
        }
        .padding(.vertical, 4)
    }

    private var statusSymbol: String {
        if report.isWarning { return "exclamationmark.triangle.fill" }
        return report.isHealthy ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        if report.isWarning { return .orange }
        return report.isHealthy ? .green : .red
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 3) {
            factRow(
                ok: report.manifestOK,
                text: report.manifestOK ? Text("Manifest works") : Text("Manifest unreachable")
            )
            if report.manifestOK {
                Label {
                    Text("\(report.catalogCount) catalogs")
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            if let time = report.responseTime {
                Label {
                    Text("Response time: \(Int((time * 1000).rounded())) ms")
                } icon: {
                    Image(systemName: "stopwatch")
                }
            }
            if report.testedStreams {
                factRow(
                    ok: report.playableStreamCount > 0,
                    text: Text("Test film: \(report.streamCount) streams (\(report.playableStreamCount) playable)")
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private func factRow(ok: Bool, text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: ok ? "checkmark" : "xmark")
                .foregroundStyle(ok ? .green : .red)
        }
    }
}

/// "Check All Addons": runs every check in parallel and shows one sorted report.
@MainActor
struct AddonHealthReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InstalledAddon.sortIndex) private var addons: [InstalledAddon]

    @State private var reports: [String: AddonHealthReport] = [:]
    @State private var isRunning = false

    private let checker = AddonHealthChecker()

    private var finished: [AddonHealthReport] { Array(reports.values) }
    private var working: [AddonHealthReport] {
        // Fully working first, then those with a note.
        finished.filter(\.isHealthy).sorted {
            if $0.isWarning != $1.isWarning { return !$0.isWarning }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    private var failing: [AddonHealthReport] {
        finished.filter { !$0.isHealthy }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                }
                .listRowBackground(Color.clear)

                if !failing.isEmpty {
                    Section {
                        ForEach(failing) { AddonHealthResultView(report: $0) }
                    } header: {
                        Text("Not Working (\(failing.count))")
                    }
                }

                if !working.isEmpty {
                    Section {
                        ForEach(working) { AddonHealthResultView(report: $0) }
                    } header: {
                        Text("Working (\(working.count))")
                    }
                }

                let pending = addons.filter { reports[$0.transportUrl] == nil }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { addon in
                            HStack(spacing: Theme.Spacing.m) {
                                ProgressView()
                                Text(verbatim: addon.name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Checking…")
                    }
                }
            }
            .navigationTitle("Addon Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await runAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRunning)
                    .accessibilityLabel("Check Again")
                }
            }
            .animation(Theme.Motion.spring, value: reports.count)
        }
        .task { await runAll() }
        .sensoryFeedback(.success, trigger: isRunning) { old, new in old && !new }
    }

    private var summary: some View {
        HStack(spacing: Theme.Spacing.l) {
            summaryTile(count: working.count, label: Text("Working"), color: .green, symbol: "checkmark.circle.fill")
            summaryTile(count: failing.count, label: Text("Not Working"), color: .red, symbol: "xmark.circle.fill")
            summaryTile(
                count: addons.count - reports.count, label: Text("Checking"), color: .secondary, symbol: "hourglass"
            )
        }
        .listRowInsets(EdgeInsets())
    }

    private func summaryTile(count: Int, label: Text, color: Color, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(count, format: .number)
                .font(.rounded(.title, weight: .heavy))
                .contentTransition(.numericText())
            label
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        reports = [:]

        let jobs = addons.map { addon in
            (id: addon.transportUrl, name: addon.name, url: addon.manifestURL, manifest: addon.manifest)
        }
        let checker = checker
        await withTaskGroup(of: AddonHealthReport.self) { group in
            for job in jobs {
                group.addTask {
                    guard let url = job.url else {
                        var report = AddonHealthReport(addonID: job.id, name: job.name)
                        report.problem = .invalidManifest
                        return report
                    }
                    var report = await checker.check(name: job.name, manifestURL: url, storedManifest: job.manifest)
                    report.addonID = job.id
                    return report
                }
            }
            for await report in group {
                withAnimation(Theme.Motion.spring) { reports[report.addonID] = report }
            }
        }
    }
}

/// A sheet with the check result for a single addon.
@MainActor
struct AddonSingleCheckView: View {
    let addon: InstalledAddon

    @Environment(\.dismiss) private var dismiss
    @State private var report: AddonHealthReport?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let report {
                        AddonHealthResultView(report: report)
                    } else {
                        HStack(spacing: Theme.Spacing.m) {
                            ProgressView()
                            Text("Checking \(addon.name)…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Tests the manifest, response time, and a stream lookup for The Shawshank Redemption.")
                        .settingsFooter()
                }
            }
            .navigationTitle("Addon Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(Theme.Motion.spring, value: report?.isHealthy)
        }
        .presentationDetents([.medium, .large])
        .task {
            let result = await AddonHealthChecker().check(addon)
            report = result
        }
        .sensoryFeedback(trigger: report?.isHealthy) { _, new in
            guard let new else { return nil }
            return new ? .success : .error
        }
    }
}
