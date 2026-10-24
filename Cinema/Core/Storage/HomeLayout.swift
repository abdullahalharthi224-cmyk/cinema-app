import Foundation

/// The order of Home's rows and which ones are hidden. Rows are identified by
/// id: built-in rows have fixed ids, addon rows use their catalog's id.
struct HomeLayout: Codable, Equatable, Sendable {
    var order: [String] = []
    var hidden: Set<String> = []

    static let continueWatching = "builtin.continueWatching"
    static let myList = "builtin.myList"
    static let topTen = "builtin.topTen"
    static let platforms = "builtin.platforms"
    static let newEpisodes = "builtin.newEpisodes"
    static let becauseYouWatched = "builtin.becauseYouWatched"
    static let comingSoon = "builtin.comingSoon"
    static let builtIns = [continueWatching, newEpisodes, myList, becauseYouWatched, topTen, platforms, comingSoon]

    /// Every id in display order: the saved order first, then rows that are new
    /// (e.g. from a newly added addon) in their natural order.
    func arranged(_ ids: [String]) -> [String] {
        let available = Set(ids)
        let saved = order.filter { available.contains($0) }
        let known = Set(saved)
        return saved + ids.filter { !known.contains($0) }
    }

    /// The rows to show, in order.
    func visible(_ ids: [String]) -> [String] {
        arranged(ids).filter { !hidden.contains($0) }
    }

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    mutating func setHidden(_ id: String, _ isHidden: Bool) {
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
    }

    /// Moves rows within the arrangement of `ids`, like a list's drag to reorder.
    mutating func move(in ids: [String], fromOffsets source: IndexSet, toOffset destination: Int) {
        var rows = arranged(ids)
        let moving = source.sorted().map { rows[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { rows.remove(at: index) }
        rows.insert(contentsOf: moving, at: min(max(insertion, 0), rows.count))
        // Keep the position of rows that aren't available right now.
        order = rows + order.filter { !rows.contains($0) }
    }
}
