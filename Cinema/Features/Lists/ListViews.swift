import SwiftData
import SwiftUI

/// A list's icon: its symbol on a rounded square in the list's colour.
struct ListIcon: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 44

    var body: some View {
        let color = Color(hex: colorHex) ?? Theme.accent
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .continuous(size * 0.28)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Detail page buttons

/// The title page's one row of labelled actions, under Play: the caller's own tiles
/// (My List, Watched), then Like, Dislike and Lists, then the caller's trailing tile (Download).
struct TitleActionsRow<Leading: View, Trailing: View>: View {
    let route: MetaRoute
    let name: String
    let leading: Leading
    let trailing: Trailing

    @Environment(\.modelContext) private var context
    @Query private var ratings: [TitleRating]
    @Query private var listItems: [UserListItem]
    @State private var showsLists = false

    init(route: MetaRoute, name: String, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.route = route
        self.name = name
        self.leading = leading()
        self.trailing = trailing()
        let metaID = route.id
        _ratings = Query(filter: #Predicate<TitleRating> { $0.metaID == metaID })
        _listItems = Query(filter: #Predicate<UserListItem> { $0.metaID == metaID })
    }

    private var rating: TitleRating? {
        ratings.first { $0.profileID == ProfileSession.shared.activeID && $0.type == route.type }
    }

    private var listCount: Int {
        listItems.filter { $0.profileID == ProfileSession.shared.activeID && $0.type == route.type }.count
    }

    var body: some View {
        let liked = rating?.liked == true
        let disliked = rating?.liked == false
        HStack(spacing: Theme.Spacing.s) {
            leading

            Button {
                withAnimation(Theme.Motion.spring) { RatingStore.rate(route, name: name, liked: true, in: context) }
            } label: {
                ActionTile("Like", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup", isOn: liked)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel(Text(liked ? LocalizedStringKey("Liked") : "Like"))
            .accessibilityAddTraits(liked ? .isSelected : [])

            Button {
                withAnimation(Theme.Motion.spring) { RatingStore.rate(route, name: name, liked: false, in: context) }
            } label: {
                ActionTile("Dislike", systemImage: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", isOn: disliked)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel(Text(disliked ? LocalizedStringKey("Disliked") : "Dislike"))
            .accessibilityAddTraits(disliked ? .isSelected : [])

            Button {
                showsLists = true
            } label: {
                ActionTile("Lists", systemImage: listCount > 0 ? "text.badge.checkmark" : "text.badge.plus", isOn: listCount > 0)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel("Add to List")
            .accessibilityAddTraits(listCount > 0 ? .isSelected : [])

            trailing
        }
        .sensoryFeedback(.selection, trigger: rating?.liked)
        .sheet(isPresented: $showsLists) {
            AddToListSheet(route: route, name: name)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Add to list

/// Puts the title in any of the profile's own lists, and makes new lists.
struct AddToListSheet: View {
    let route: MetaRoute
    let name: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \UserList.sortIndex) private var allLists: [UserList]
    @Query private var items: [UserListItem]
    @State private var showsEditor = false

    init(route: MetaRoute, name: String) {
        self.route = route
        self.name = name
        let metaID = route.id
        _items = Query(filter: #Predicate<UserListItem> { $0.metaID == metaID })
    }

    private var lists: [UserList] { allLists.filter { $0.profileID == ProfileSession.shared.activeID } }

    private func contains(_ list: UserList) -> Bool {
        items.contains { $0.listID == list.id && $0.type == route.type }
    }

    var body: some View {
        NavigationStack {
            List {
                // My List has its own button on the title's page, so only the profile's own lists are here.
                Section {
                    ForEach(lists) { list in
                        row(symbol: list.symbol, colorHex: list.colorHex, title: Text(verbatim: list.name), checked: contains(list)) {
                            UserListStore.toggle(route, name: name, in: list, context: context)
                        }
                    }
                } footer: {
                    Group {
                        if lists.isEmpty {
                            Text("Make your own lists, like “Weekend” or “With the Family”, each with its own icon and colour.")
                        }
                    }
                    .settingsFooter()
                }

                Section {
                    Button {
                        showsEditor = true
                    } label: {
                        Label("New List", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsEditor) {
                ListEditorView(list: nil) { list in
                    UserListStore.toggle(route, name: name, in: list, context: context)
                }
            }
            .sensoryFeedback(.selection, trigger: items.count)
        }
    }

    private func row(symbol: String, colorHex: String, title: Text, checked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Theme.Motion.snappy) { action() }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                ListIcon(symbol: symbol, colorHex: colorHex, size: 34)
                title
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Theme.accent : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}

// MARK: - Editor

/// Names a list and picks its icon and colour; also renames and deletes.
struct ListEditorView: View {
    let list: UserList?
    var onCreate: ((UserList) -> Void)? = nil
    /// When set, the caller deletes the list (after leaving its page).
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var symbol = UserList.symbols[0]
    @State private var colorHex = UserList.colors[0]
    @State private var isConfirmingDelete = false
    @FocusState private var nameFocused: Bool

    private let symbolColumns = [GridItem(.adaptive(minimum: 48), spacing: Theme.Spacing.m)]
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.l) {
                        ListIcon(symbol: symbol, colorHex: colorHex, size: 88)
                            .animation(Theme.Motion.spring, value: symbol)
                            .animation(Theme.Motion.spring, value: colorHex)
                        TextField("List Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .focused($nameFocused)
                            .submitLabel(.done)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.s)
                }
                .listRowBackground(Color.clear)

                Section("Color") {
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(UserList.colors, id: \.self) { hex in
                                Button {
                                    colorHex = hex
                                } label: {
                                    Circle()
                                        .fill((Color(hex: hex) ?? .gray).gradient)
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: hex == colorHex ? 2.5 : 0)
                                                .padding(-4)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: hex))
                            }
                        }
                        .padding(6)
                    }
                    .scrollIndicators(.hidden)
                }

                Section("Icon") {
                    LazyVGrid(columns: symbolColumns, spacing: Theme.Spacing.m) {
                        ForEach(UserList.symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(item == symbol ? Color.white : Color.primary)
                                    .background(
                                        item == symbol ? AnyShapeStyle(Color(hex: colorHex) ?? Theme.accent) : AnyShapeStyle(Theme.surface),
                                        in: .continuous(14)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                if list != nil {
                    Section {
                        Button("Delete List", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .navigationTitle(list == nil ? LocalizedStringKey("New List") : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(list == nil ? LocalizedStringKey("Create") : "Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete this list?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete List", role: .destructive) {
                    if let onDelete {
                        onDelete()
                    } else if let list {
                        UserListStore.delete(list, in: context)
                    }
                    dismiss()
                }
            } message: {
                Text("The titles stay in Cinema; only the list goes.")
            }
            .onAppear {
                if let list {
                    name = list.name
                    symbol = list.symbol
                    colorHex = list.colorHex
                } else {
                    let used = Set(UserListStore.lists(in: context).map(\.colorHex))
                    colorHex = UserList.colors.first { !used.contains($0) } ?? UserList.colors[0]
                    nameFocused = true
                }
            }
        }
    }

    private func save() {
        if let list {
            list.name = trimmedName
            list.symbol = symbol
            list.colorHex = colorHex
            try? context.save()
        } else {
            let created = UserListStore.create(name: trimmedName, symbol: symbol, colorHex: colorHex, in: context)
            onCreate?(created)
        }
        dismiss()
    }
}

// MARK: - Library

/// The Library's row of lists: the profile's own lists, Liked, and a button for a new one.
struct UserListsRow: View {
    let lists: [UserList]
    let counts: [UUID: Int]
    let likedCount: Int

    @State private var showsEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("My Lists")
                .font(.display(.title2))
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.m) {
                    if likedCount > 0 {
                        NavigationLink(value: LibraryRoute.liked) {
                            card(symbol: "hand.thumbsup.fill", colorHex: "#FF5FA2", title: Text("Liked"), count: likedCount)
                        }
                        .buttonStyle(.cardPress)
                    }
                    ForEach(lists) { list in
                        NavigationLink(value: LibraryRoute.list(list.id)) {
                            card(symbol: list.symbol, colorHex: list.colorHex, title: Text(verbatim: list.name), count: counts[list.id] ?? 0)
                        }
                        .buttonStyle(.cardPress)
                    }
                    Button {
                        showsEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(Color.primary.opacity(0.08), in: .continuous(11))
                            Spacer(minLength: 0)
                            Text("New List")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 128, height: 112, alignment: .leading)
                        .padding(Theme.Spacing.m)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                    }
                    .buttonStyle(.cardPress)
                }
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showsEditor) {
            ListEditorView(list: nil)
        }
    }

    private func card(symbol: String, colorHex: String, title: Text, count: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ListIcon(symbol: symbol, colorHex: colorHex, size: 40)
            Spacer(minLength: 0)
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(count) titles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 128, height: 112, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }
}

/// Finds a list by its id for the navigation stack (routes carry ids, not models).
struct UserListLoaderView: View {
    @Query private var lists: [UserList]

    init(id: UUID) {
        _lists = Query(filter: #Predicate<UserList> { $0.id == id })
    }

    var body: some View {
        if let list = lists.first {
            UserListDetailView(list: list)
        } else {
            Color.clear.background(Theme.background.ignoresSafeArea())
        }
    }
}

/// One list's titles in a grid; edit or delete the list from the toolbar.
struct UserListDetailView: View {
    let list: UserList

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [UserListItem]
    @State private var showsEditor = false
    /// Set once the list is being deleted, so the page stops reading it.
    @State private var isGone = false

    init(list: UserList) {
        self.list = list
        let id = list.id
        _items = Query(filter: #Predicate<UserListItem> { $0.listID == id }, sort: \UserListItem.addedAt, order: .reverse)
    }

    var body: some View {
        Group {
            if isGone {
                Color.clear
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label { Text(verbatim: list.name) } icon: { ListIcon(symbol: list.symbol, colorHex: list.colorHex, size: 64) }
                } description: {
                    Text("Open any title and tap Lists to add it here.")
                }
            } else {
                ScrollView {
                    TitleGrid {
                        ForEach(items) { item in
                            NavigationLink(value: item.route) {
                                LibraryCard(
                                    id: item.metaID, name: item.name, poster: item.poster,
                                    caption: Text(item.type == "movie" ? "Movie" : "TV Series")
                                )
                            }
                            .buttonStyle(.cardPress)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation(Theme.Motion.spring) {
                                        context.delete(item)
                                        try? context.save()
                                    }
                                } label: {
                                    Label("Remove from List", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: isGone ? "" : list.name))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsEditor = true
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .accessibilityLabel("Edit List")
            }
        }
        .sheet(isPresented: $showsEditor) {
            ListEditorView(list: list, onDelete: delete)
        }
    }

    /// Leaves the page first, then deletes the list.
    private func delete() {
        isGone = true
        dismiss()
        let list = list
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            UserListStore.delete(list, in: context)
        }
    }
}

/// Everything the profile gave a thumbs up (and, below, a thumbs down).
struct LikedTitlesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TitleRating.date, order: .reverse) private var allRatings: [TitleRating]
    @State private var showsDisliked = false

    private var ratings: [TitleRating] {
        allRatings.filter { $0.profileID == ProfileSession.shared.activeID && $0.liked != showsDisliked }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Picker("Show", selection: $showsDisliked.animation(Theme.Motion.spring)) {
                    Text("Liked").tag(false)
                    Text("Disliked").tag(true)
                }
                .pickerStyle(.segmented)

                if ratings.isEmpty {
                    ContentUnavailableView(
                        showsDisliked ? LocalizedStringKey("Nothing Disliked") : "Nothing Liked Yet",
                        systemImage: showsDisliked ? "hand.thumbsdown" : "hand.thumbsup",
                        description: Text("Use the buttons under Play on any title.")
                    )
                    .padding(.top, 60)
                } else {
                    TitleGrid {
                        ForEach(ratings) { rating in
                            NavigationLink(value: rating.route) {
                                LibraryCard(
                                    id: rating.metaID, name: rating.name, poster: rating.poster,
                                    caption: Text(rating.type == "movie" ? "Movie" : "TV Series")
                                )
                            }
                            .buttonStyle(.cardPress)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation(Theme.Motion.spring) {
                                        context.delete(rating)
                                        try? context.save()
                                    }
                                } label: {
                                    Label("Remove Rating", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Liked")
        .sensoryFeedback(.selection, trigger: showsDisliked)
    }
}

/// An even poster grid sized by the poster-size setting, as in the Library.
struct TitleGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    private var columns: [GridItem] {
        let count = switch HomeCustomization.shared.posterSize {
        case .small: 4
        case .medium: 3
        case .large: 2
        }
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m, alignment: .top), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.l, content: content)
    }
}
