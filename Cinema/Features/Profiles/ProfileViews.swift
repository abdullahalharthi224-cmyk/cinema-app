import PhotosUI
import SwiftData
import SwiftUI

/// "Who's watching?" — shown at launch when there's more than one profile,
/// and from the avatar button on Home.
@MainActor
struct ProfilePickerView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]

    @State private var session = ProfileSession.shared
    @State private var isEditing = false
    @State private var editing: ProfileEditorTarget?
    @State private var auth: ProfileAuth?
    /// The profile picked: it lifts to the middle, glowing, then flies to Home's avatar button.
    @State private var chosen: Profile?
    @State private var lifted = false
    @State private var flying = false
    @State private var tileFrames: [UUID: CGRect] = [:]

    /// Opening a profile, editing it, or leaving a kids profile, after the passcode.
    enum ProfileAuth: Identifiable {
        case open(Profile, PasscodeScope)
        case edit(Profile, PasscodeScope)
        /// Leaving the kids profile for `Profile` needs the kids profile's own code.
        case leaveKids(Profile, PasscodeScope)

        var id: String {
            switch self {
            case .open(let profile, _): return "open" + profile.id.uuidString
            case .edit(let profile, _): return "edit" + profile.id.uuidString
            case .leaveKids(let profile, _): return "kids" + profile.id.uuidString
            }
        }
    }

    /// Kids can switch between profiles but not add or change them.
    private var isKidsMode: Bool { session.isKids }

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.xl)]

    var body: some View {
        ZStack {
            picker
                .opacity(flying ? 0 : 1)
            flightLayer
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: chosen?.id)
    }

    /// The chosen avatar on its way: from its tile to the middle, then to Home's profile button.
    private var flightLayer: some View {
        GeometryReader { proxy in
            if let chosen, let from = tileFrames[chosen.id] {
                let size: CGFloat = 104
                let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                let target = router.profileButtonFrame
                let landsOnHome = router.selectedTab == .home && target.width > 0
                let position = flying
                    ? (landsOnHome ? CGPoint(x: target.midX, y: target.midY) : middle)
                    : (lifted ? middle : CGPoint(x: from.midX, y: from.midY))
                let scale = flying ? (landsOnHome ? target.width / size : 0.6) : (lifted ? 1.3 : 1)
                ProfileAvatar(profile: chosen, size: size, isSelected: true)
                    .background {
                        Circle()
                            .fill(Theme.accent.opacity(lifted && !flying ? 0.6 : 0))
                            .blur(radius: 30)
                            .scaleEffect(1.5)
                    }
                    .scaleEffect(scale)
                    .position(position)
                    .opacity(flying && !landsOnHome ? 0 : 1)
            }
        }
        .ignoresSafeArea()
        // Positions are in window coordinates (from the left, whatever the language), so the
        // flight is laid out left to right and lands on Home's button in Arabic and English alike.
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
    }

    private var picker: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    VStack(spacing: Theme.Spacing.m) {
                        CinemaBadge()
                        Text(isEditing ? LocalizedStringKey("Edit Profiles") : "Who's Watching?")
                            .font(.display(.largeTitle))
                            .contentTransition(.opacity)
                    }
                    .padding(.top, Theme.Spacing.l)

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
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xxl)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        close()
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

    /// Closes without choosing.
    private func close() {
        withAnimation(.easeOut(duration: 0.3)) {
            router.homeBehindPicker = false
            router.showsProfilePicker = false
        }
    }

    private func profileTile(_ profile: Profile) -> some View {
        let isActive = profile.id == session.activeID
        let isChosen = chosen?.id == profile.id
        let isOther = chosen != nil && !isChosen
        return VStack(spacing: Theme.Spacing.m) {
            ProfileAvatar(profile: profile, size: 104, isSelected: isActive && !isEditing)
                .onWindowFrameChange { tileFrames[profile.id] = $0 }
                .opacity(isChosen ? 0 : 1)
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
            .overlay(alignment: .bottomTrailing) {
                if profile.isKids || (profile.isLocked && Passcode.scope(for: profile.id) != nil) {
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
                .opacity(chosen == nil ? 1 : 0)
        }
        .opacity(isOther ? 0 : 1)
        .scaleEffect(isOther ? 0.85 : 1)
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
        guard chosen == nil else { return }
        let kidsScope = session.activeID.flatMap { Passcode.scope(for: $0) }
        let profileScope = Passcode.scope(for: profile.id)
        if profile.id == session.activeID {
            activate(profile)
        } else if session.isKids && !profile.isKids, let kidsScope {
            // Leaving a kids profile always takes its own passcode, never Face ID.
            auth = .leaveKids(profile, kidsScope)
        } else if profile.isLocked, let profileScope, !LockGate.shared.recentlyUnlocked(profileScope) {
            auth = .open(profile, profileScope)
        } else {
            activate(profile)
        }
    }

    /// Switches profile under the picker, then plays the transition: the others fade away, the
    /// chosen avatar glows in the middle and flies to Home's avatar while Home grows back in.
    private func activate(_ profile: Profile) {
        if profile.id != session.activeID { session.activate(profile) }
        guard !reduceMotion else {
            close()
            return
        }
        router.isProfileFlightActive = true
        chosen = profile
        Task {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                lifted = true
            }
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                flying = true
                router.homeBehindPicker = false
            }
            try? await Task.sleep(for: .milliseconds(430))
            router.isProfileFlightActive = false
            router.showsProfilePicker = false
        }
    }

    private func beginEditing(_ profile: Profile) {
        if profile.isLocked, let scope = Passcode.scope(for: profile.id), !LockGate.shared.recentlyUnlocked(scope) {
            auth = .edit(profile, scope)
        } else {
            editing = .edit(profile)
        }
    }

    @ViewBuilder
    private func authSheet(_ request: ProfileAuth) -> some View {
        switch request {
        case .open(let profile, let scope):
            PasscodeView(mode: .unlock(allowsBiometrics: true), scope: scope, title: "Unlock \(profile.name)", onCancel: { auth = nil }) {
                LockGate.shared.noteUnlocked(scope)
                auth = nil
                activate(profile)
            }
            .interactiveDismissDisabled()
        case .edit(let profile, let scope):
            PasscodeView(mode: .unlock(allowsBiometrics: true), scope: scope, title: "Unlock \(profile.name)", onCancel: { auth = nil }) {
                LockGate.shared.noteUnlocked(scope)
                auth = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    editing = .edit(profile)
                }
            }
            .interactiveDismissDisabled()
        case .leaveKids(let profile, let scope):
            PasscodeView(
                mode: .unlock(allowsBiometrics: false),
                scope: scope,
                title: "Enter Passcode",
                message: "Enter the kids profile's passcode to leave it.",
                onCancel: { auth = nil }
            ) {
                auth = nil
                activate(profile)
            }
            .interactiveDismissDisabled()
        }
    }
}

/// The small Cinema mark and name, at the top of "Who's watching?".
struct CinemaBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(SplashArt.logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
            Text(verbatim: "Cinema")
                .font(.system(.title3, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [Brand.glow, Brand.violet, Brand.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Cinema"))
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
    @State private var symbol = AvatarKind.character(AvatarKind.characters[0]).raw
    @State private var colorHex = AvatarBackground.choices[0]
    /// A picture chosen from the album, cropped, waiting to be saved with the profile.
    @State private var newPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoToCrop: CroppingPhoto?
    @State private var isConfirmingDelete = false
    @State private var isKids = false
    @State private var kidsMaxAge = 7
    @State private var isLocked = false
    @State private var isDefault = false
    /// Set while a new passcode is being created for the lock or the kids profile.
    @State private var pendingPasscode: PendingPasscode?
    /// A new profile's ID, chosen up front so its passcode can be saved before the profile is.
    @State private var draftID = UUID()
    /// Whether this profile has its own passcode yet.
    @State private var hasOwnPasscode = false

    enum PendingPasscode: String, Identifiable {
        case kids, lock, change
        var id: String { rawValue }
    }

    private var profileID: UUID { editedProfile?.id ?? draftID }

    /// Every kids or locked profile has its own passcode, separate from Cinema's.
    private var passcodeScope: PasscodeScope { .profile(profileID) }

    /// At least one grown-up profile must stay, or nobody could leave the kids profiles.
    private var canBeKids: Bool {
        isKids || profiles.contains { !$0.isKids && $0.id != editedProfile?.id }
    }

    private let characterColumns = [GridItem(.adaptive(minimum: 72), spacing: Theme.Spacing.m)]

    struct CroppingPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    /// The picture shown in the preview: a new crop, else the saved one.
    private var previewPhoto: UIImage? {
        guard AvatarKind(symbol) == .photo else { return nil }
        return newPhoto ?? editedProfile.flatMap { AvatarStore.image(for: $0.id) }
    }

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
                        // A large preview of the chosen character or photo.
                        ProfileAvatar(symbol: symbol, colorHex: colorHex, size: 150, photo: previewPhoto)
                            .id(symbol)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .animation(Theme.Motion.spring, value: symbol)
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

                Section {
                    LazyVGrid(columns: characterColumns, spacing: Theme.Spacing.l) {
                        ForEach(AvatarKind.characters, id: \.self) { character in
                            let raw = AvatarKind.character(character).raw
                            Button {
                                withAnimation(Theme.Motion.snappy) { symbol = raw }
                            } label: {
                                ProfileAvatar(symbol: raw, colorHex: colorHex, size: 64, isSelected: raw == symbol)
                                    .scaleEffect(raw == symbol ? 1.06 : 1)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(LocalizedStringKey(character.capitalized)))
                            .accessibilityAddTraits(raw == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)

                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Photo from Album", systemImage: "photo.on.rectangle.angled")
                    }
                } header: {
                    Text("Character")
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
                    if isKids && hasOwnPasscode {
                        Button("Change Kids Passcode") { pendingPasscode = .change }
                    }
                    if isKids {
                        Picker("Age Limit", selection: $kidsMaxAge) {
                            ForEach(Profile.kidsAges, id: \.self) { age in
                                Text(Self.ageTitle(age)).tag(age)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Group {
                        if !canBeKids {
                            Text("Keep at least one grown-up profile so the passcode can be used to leave kids profiles.")
                        } else if isKids {
                            Text("Shows only titles rated for this age on TMDB; titles without a rating are hidden. No Settings or addons. Leaving needs this profile's own passcode.")
                        } else {
                            Text("A kids profile shows only titles suitable for the age you choose.")
                        }
                    }
                    .settingsFooter()
                }

                Section {
                    Toggle("Open Cinema with This Profile", isOn: $isDefault)
                } footer: {
                    Text("Cinema skips “Who's Watching?” and opens straight to this profile. Its passcode, if it has one, is still asked.")
                        .settingsFooter()
                }

                if editedProfile != nil, profiles.count > 1 {
                    Section {
                        Button("Delete Profile", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } footer: {
                        Text("Deleting a profile also deletes its Continue Watching and Library.")
                            .settingsFooter()
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
                    if let editedProfile {
                        Passcode.remove(.profile(editedProfile.id))
                        ProfileStore.delete(editedProfile, in: context)
                    }
                    dismiss()
                }
            }
            .sheet(item: $photoToCrop) { pending in
                CircularCropView(image: pending.image) { cropped in
                    newPhoto = cropped
                    symbol = AvatarKind.photoTag
                    photoToCrop = nil
                } onCancel: {
                    photoToCrop = nil
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photoToCrop = CroppingPhoto(image: CircularCropView.prepared(image))
                    }
                    photoItem = nil
                }
            }
            .sensoryFeedback(.selection, trigger: symbol)
            .sensoryFeedback(.selection, trigger: colorHex)
            .sheet(item: $pendingPasscode) { pending in
                PasscodeView(mode: .create, scope: passcodeScope, title: pending == .kids ? "Kids Profile Passcode" : "Profile Passcode", onCancel: { pendingPasscode = nil }) {
                    pendingPasscode = nil
                    hasOwnPasscode = true
                    withAnimation(Theme.Motion.spring) {
                        switch pending {
                        case .kids:
                            isKids = true
                            giveKidsCharacter()
                        case .lock: isLocked = true
                        case .change: break
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
                isDefault = ProfileSession.shared.defaultID == editedProfile.id
                hasOwnPasscode = Passcode.isSet(.profile(editedProfile.id))
            } else {
                // Suggest a background and character not already taken.
                colorHex = AvatarBackground.choices.first { hex in !profiles.contains { $0.colorHex == hex } } ?? AvatarBackground.choices[0]
                let character = AvatarKind.characters.first { name in !profiles.contains { $0.symbol == AvatarKind.character(name).raw } }
                symbol = AvatarKind.character(character ?? AvatarKind.characters[0]).raw
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if AvatarKind(symbol) == .photo, let newPhoto {
            AvatarStore.save(newPhoto, for: profileID)
        } else if AvatarKind(symbol) != .photo {
            AvatarStore.remove(for: profileID)
        }
        if let editedProfile {
            editedProfile.name = trimmedName
            editedProfile.symbol = symbol
            editedProfile.colorHex = colorHex
            apply(to: editedProfile)
            try? context.save()
            ProfileSession.shared.sync(editedProfile)
        } else if let profile = ProfileStore.add(name: trimmedName, symbol: symbol, colorHex: colorHex, in: context) {
            profile.id = draftID
            apply(to: profile)
            try? context.save()
        }
        if isDefault {
            ProfileSession.shared.defaultID = profileID
        } else if ProfileSession.shared.defaultID == profileID {
            ProfileSession.shared.defaultID = nil
        }
        // A profile that's neither locked nor for kids no longer needs its code.
        if !isKids && !isLocked { Passcode.remove(passcodeScope) }
        dismiss()
    }

    private func apply(to profile: Profile) {
        profile.isKids = isKids
        profile.kidsMaxAge = kidsMaxAge
        profile.isLocked = isLocked && !isKids
    }

    /// A kids profile needs its own passcode; the first time, one is created.
    /// (Locking a grown-up profile is done from its own Settings → Passcode & Face ID.)
    private func setKids(_ on: Bool) {
        if on && !hasOwnPasscode {
            pendingPasscode = .kids
        } else {
            withAnimation(Theme.Motion.spring) { isKids = on }
            if on { giveKidsCharacter() }
        }
    }

    /// A kids profile starts with the robot (unless it's an existing profile with its own picture).
    private func giveKidsCharacter() {
        let kind = AvatarKind(symbol)
        let isOldStyle: Bool = { if case .character = kind { return false } else { return kind != .photo } }()
        if isOldStyle || (editedProfile == nil && kind != .photo) {
            symbol = AvatarKind.character(AvatarKind.kidsCharacter).raw
        }
    }


    static func ageTitle(_ age: Int) -> LocalizedStringKey {
        age == 0 ? "All Ages" : "\(age)+"
    }
}

/// The small avatar button on Home that opens the profile picker.
struct ProfileButton: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]
    @State private var session = ProfileSession.shared

    private var active: Profile? { profiles.first { $0.id == session.activeID } ?? profiles.first }

    var body: some View {
        Button {
            router.presentProfilePicker()
        } label: {
            if let active {
                ProfileAvatar(profile: active, size: 38, isSelected: true)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
            }
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Switch Profile")
        // Where a profile chosen in "Who's watching?" lands; hidden while it flies here.
        .onWindowFrameChange { router.profileButtonFrame = $0 }
        .opacity(router.isProfileFlightActive ? 0 : 1)
    }
}
