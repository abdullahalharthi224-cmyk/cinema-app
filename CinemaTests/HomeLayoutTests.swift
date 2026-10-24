import XCTest
@testable import Cinema

final class HomeLayoutTests: XCTestCase {
    func testNewRowsFollowTheSavedOrder() {
        let layout = HomeLayout(order: ["c", "a", "gone"])
        XCTAssertEqual(layout.arranged(["a", "b", "c", "d"]), ["c", "a", "b", "d"])
    }

    func testHiddenRowsAreLeftOut() {
        var layout = HomeLayout()
        layout.setHidden("b", true)
        XCTAssertEqual(layout.visible(["a", "b", "c"]), ["a", "c"])
        layout.setHidden("b", false)
        XCTAssertEqual(layout.visible(["a", "b", "c"]), ["a", "b", "c"])
    }

    func testMoveLikeAList() {
        var layout = HomeLayout()
        let ids = ["a", "b", "c", "d"]
        // Drag "a" below "c".
        layout.move(in: ids, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(layout.arranged(ids), ["b", "c", "a", "d"])
        // Drag "d" to the top.
        layout.move(in: ids, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(layout.arranged(ids), ["d", "b", "c", "a"])
    }

    func testRoundTripsThroughJSON() throws {
        var layout = HomeLayout(order: ["x", "y"])
        layout.setHidden("y", true)
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded, layout)
    }
}
