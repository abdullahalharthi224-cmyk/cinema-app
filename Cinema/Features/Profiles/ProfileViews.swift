import SwiftData
import SwiftUI

/// A round, gradient avatar with the profile's symbol.
struct ProfileAvatar: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 96

    private var color: Color { Color(hex: colorHex) ?? Theme.accent }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.75))
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.35), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

extension ProfileAvatar {
    init(profile: Profile, size: CGFloat = 96) {
        self.init(symbol: profile.symbol, colorHex: profile.colorHex, size: size)
    }
}

/// "Who's watching?" — shown at launch when there's more than one profile,
/// and from the avatar button on Home.
@MainActor
struct ProfilePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]

    @State private var session = ProfileSession.shared
    @State private var isEditing = false
    @State private var editing: ProfileEditorTarget?
    @State private var auth: ProfileAuth?

    /// Opening a profile, editing it, or leaving a kids profile, after the passcode.
    enum ProfileAuth: Identifiable {
        case open(Profile)
        case edit(Profile)
        case leaveKids(Profile)

        var id: String {
            switch self {
            case .open(let profile): return "open" + profile.id.uuidString
            case .edit(let profile): return "edit" + profile.id.uuidString
            case .leaveKids(let profile): return "kids" + profile.id.uuidString
            }
        }
    }

    /// Kids can switch between profiles but not add or change them.
    private var isKidsMode: Bool { session.isKids }

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.xl)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    Text(isEditing ? LocalizedStringKey("Edit Profiles") : "Who's Watching?")
                        .font(.display(.largeTitle))
                        .padding(.top, Theme.Spacing.xxl)
                        .contentTransition(.opacity)

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                        ForEach(profiles) { profile in
                            Button {
                                if isEditing {
                                    beginEditing(profile)
                                } else {
                                    select(profile)
                                }
                            } label: {
                                profileTile(profile)
                            }
                            .buttonStyle(.cardPress)
                        }

                        if profiles.count < Profile.maxCount && !isKidsMode {
                            Button {
                                editing = .new
                            } label: {
                                addTile
                            }
                            .buttonStyle(.cardPress)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    Text("Up to \(Profile.maxCount) profiles. Each has its own Continue Watching and Library.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xxl)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                if !isKidsMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? LocalizedStringKey("Done") : "Edit") {
                            withAnimation(Theme.Motion.spring) { isEditing.toggle() }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $editing) { target in
                ProfileEditorView(target: target)
            }
            .sheet(item: $auth) { request in
                authSheet(request)
            }
        }
        .sensoryFeedback(.selection, trigger: session.activeID)
    }

    private func profileTile(_ profile: Profile) -> some View {
        let isActive = profile.id == session.activeID
        return VStack(spacing: Theme.Spacing.m) {
            ProfileAvatar(profile: profile, size: 104)
                .overlay {
                    if isEditing {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .overlay {
                                Image(systemName: "pencil")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .transition(.opacity)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: isActive && !isEditing ? 3 : 0)
                        .padding(-6)
                }
            .overlay(alignment: .bottomTrailing) {
                if profile.isKids || (profile.isLocked && SecuritySettings.shared.hasPasscode) {
                    Image(systemName: profile.isKids ? "figure.and.child.holdinghands" : "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(profile.isKids ? Color.orange : Color.black.opacity(0.7), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2.5))
                        .offset(x: 4, y: 4)
                }
            }
            Text(verbatim: profile.name)
                .font(.headline)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: profile.name))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var addTile: some View {
        VStack(spacing: Theme.Spacing.m) {
            Circle()
                .strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .frame(width: 104, height: 104)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            Text("Add Profile")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ profile: Profile) {
        let hasPasscode = SecuritySettings.shared.hasPasscode
        if profile.id == session.activeID {
            dismiss()
        } else if hasPasscode && session.isKids && !profile.isKids {
            // Leaving a kids profile always takes the passcode itself, never Face ID.
            auth = .leaveKids(profile)
        } else if hasPasscode && profile.isLocked && !LockGate.shared.recentlyUnlocked {
            auth = .open(profile)
        } else {
            activate(profile)
        }
    }

    private func activate(_ profile: Profile) {
        withAnimation(Theme.Motion.spring) { session.activate(profile) }
        dismiss()
    }

    private func beginEditing(_ profile: Profile) {
        if SecuritySettings.shared.hasPasscode && profile.isLocked && !LockGate.shared.recentlyUnlocked {
            auth = .edit(profile)
        } else {
            editing = .edit(profile)
        }
    }

    @ViewBuilder
    private func authSheet(_ request: ProfileAuth) -> some View {
        switch request {
        case .open(let profile):
            PasscodeView(mode: .unlock(allowsBiometrics: true), title: "Unlock \(profile.name)", onCancel: { auth = nil }) {
                LockGate.shared.noteUnlocked()
                auth = nil
                activate(profile)
            }
            .interactiveDismissDisabled()
        case .edit(let profile):
            PasscodeView(mode: .unlock(allowsBiometrics: true), title: "Unlock \(profile.name)", onCancel: { auth = nil }) {
                LockGate.shared.noteUnlocked()
                auth = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    editing = .edit(profile)
                }
            }
            .interactiveDismissDisabled()
        case .leaveKids(let profile):
            PasscodeView(
                mode: .unlock(allowsBiometrics: false),
                title: "Enter Passcode",
                message: "A grown-up's passcode is needed to leave the kids profile.",
                onCancel: { auth = nil }
            ) {
                auth = nil
                activate(profile)
            }
            .interactiveDismissDisabled()
        }
    }
}

enum ProfileEditorTarget: Identifiable {
    case new
    case edit(Profile)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let profile): return profile.id.uuidString
        }
    }
}

/// Create or edit a profile: name, avatar symbol and colour.
@MainActor
struct ProfileEditorView: View {
    let target: ProfileEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    @State private var name = ""
    @State private var symbol = Profile.symbols[0]
    @State private var colorHex = Profile.colors[0]
    @State private var isConfirmingDelete = false
    @State private var isKids = false
    @State private var kidsMaxAge = 7
    @State private var isLocked = false
    /// Set while a new passcode is being created for the lock or the kids profile.
    @State private var pendingPasscode: PendingPasscode?

    enum PendingPasscode: String, Identifiable {
        case kids, lock
        var id: String { rawValue }
    }

    /// At least one grown-up profile must stay, or nobody could leave the kids profiles.
    private var canBeKids: Bool {
        isKids || profiles.contains { !$0.isKids && $0.id != editedProfile?.id }
    }

    private let symbolColumns = [GridItem(.adaptive(minimum: 52), spacing: Theme.Spacing.m)]

    private var editedProfile: Profile? {
        if case .edit(let profile) = target { return profile }
        return nil
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.l) {
                        ProfileAvatar(symbol: symbol, colorHex: colorHex, size: 112)
                            .animation(Theme.Motion.spring, value: symbol)
                            .animation(Theme.Motion.spring, value: colorHex)
                        TextField("Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.s)
                }
                .listRowBackground(Color.clear)

                Section("Color") {
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(Profile.colors, id: \.self) { hex in
                                Button {
                                    colorHex = hex
                                } label: {
                                    Circle()
                                        .fill((Color(hex: hex) ?? .gray).gradient)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: hex == colorHex ? 2.5 : 0)
                                                .padding(-4)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .scrollIndicators(.hidden)
                }

                Section("Avatar") {
                    LazyVGrid(columns: symbolColumns, spacing: Theme.Spacing.m) {
                        ForEach(Profile.symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 52, height: 52)
                                    .foregroundStyle(item == symbol ? Color.black : Color.primary)
                                    .background(
                                        item == symbol ? AnyShapeStyle(Color(hex: colorHex) ?? .white) : AnyShapeStyle(Theme.surface),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                Section {
                    Toggle(isOn: Binding(get: { isKids }, set: { setKids($0) })) {
                        Label {
                            Text("Kids Profile")
                        } icon: {
                            SettingsIcon(systemName: "figure.and.child.holdinghands", color: .orange)
                        }
                    }
                    .disabled(!canBeKids)
                    if isKids {
                        Picker("Age Limit", selection: $kidsMaxAge) {
                            ForEach(Profile.kidsAges, id: \.self) { age in
                                Text(Self.ageTitle(age)).tag(age)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    if !canBeKids {
                        Text("Keep at least one grown-up profile so the passcode can be used to leave kids profiles.")
                    } else if isKids {
                        Text("Shows only titles rated for this age on TMDB; titles without a rating are hidden. No Settings or addons, and leaving needs your passcode.")
                    } else {
                        Text("A kids profile shows only titles suitable for the age you choose.")
                    }
                }

                if !isKids {
                    Section {
                        Toggle(isOn: Binding(get: { isLocked }, set: { setLocked($0) })) {
                            Label {
                                Text("Lock Profile")
                            } icon: {
                                SettingsIcon(systemName: "lock.fill", color: .gray)
                            }
                        }
                    } footer: {
                        Text("Opening this profile needs Face ID or your passcode.")
                    }
                }

                if editedProfile != nil, profiles.count > 1 {
                    Section {
                        Button("Delete Profile", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } footer: {
                        Text("Deleting a profile also deletes its Continue Watching and Library.")
                    }
                }
            }
            .navigationTitle(editedProfile == nil ? LocalizedStringKey("New Profile") : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete this profile?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Profile", role: .destructive) {
                    if let editedProfile { ProfileStore.delete(editedProfile, in: context) }
                    dismiss()
                }
            }
            .sensoryFeedback(.selection, trigger: symbol)
            .sensoryFeedback(.selection, trigger: colorHex)
            .sheet(item: $pendingPasscode) { pending in
                PasscodeView(mode: .create, onCancel: { pendingPasscode = nil }) {
                    pendingPasscode = nil
                    withAnimation(Theme.Motion.spring) {
                        switch pending {
                        case .kids: isKids = true
                        case .lock: isLocked = true
                        }
                    }
                }
                .interactiveDismissDisabled()
            }
        }
        .onAppear {
            if let editedProfile {
                name = editedProfile.name
                symbol = editedProfile.symbol
                colorHex = editedProfile.colorHex
                isKids = editedProfile.isKids
                kidsMaxAge = editedProfile.kidsMaxAge
                isLocked = editedProfile.isLocked
            } else {
                // Suggest a colour and avatar not already taken.
                colorHex = Profile.colors.first { hex in !profiles.contains { $0.colorHex == hex } } ?? Profile.colors[0]
                symbol = Profile.symbols.first { item in !profiles.contains { $0.symbol == item } } ?? Profile.symbols[0]
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let editedProfile {
            editedProfile.name = trimmedName
            editedProfile.symbol = symbol
            editedProfile.colorHex = colorHex
            apply(to: editedProfile)
            try? context.save()
            ProfileSession.shared.sync(editedProfile)
        } else if let profile = ProfileStore.add(name: trimmedName, symbol: symbol, colorHex: colorHex, in: context) {
            apply(to: profile)
            try? context.save()
        }
        dismiss()
    }

    private func apply(to profile: Profile) {
        profile.isKids = isKids
        profile.kidsMaxAge = kidsMaxAge
        profile.isLocked = isLocked && !isKids
    }

    /// Kids profiles and locks need a passcode; the first time, one is created.
    private func setKids(_ on: Bool) {
        if on && !SecuritySettings.shared.hasPasscode {
            pendingPasscode = .kids
        } else {
            withAnimation(Theme.Motion.spring) { isKids = on }
        }
    }

    private func setLocked(_ on: Bool) {
        if on && !SecuritySettings.shared.hasPasscode {
            pendingPasscode = .lock
        } else {
            withAnimation(Theme.Motion.spring) { isLocked = on }
        }
    }

    static func ageTitle(_ age: Int) -> LocalizedStringKey {
        age == 0 ? "All Ages" : "\(age)+"
    }
}

/// The small avatar button on Home that opens the profile picker.
struct ProfileButton: View {
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]
    @State private var session = ProfileSession.shared
    @State private var isPicking = false

    private var active: Profile? { profiles.first { $0.id == session.activeID } ?? profiles.first }

    var body: some View {
        Button {
            isPicking = true
        } label: {
            if let active {
                ProfileAvatar(profile: active, size: 38)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
            }
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Switch Profile")
        .fullScreenCover(isPresented: $isPicking) {
            ProfilePickerView()
        }
    }
}
