import Foundation
import XCTest
@testable import Precis

final class DesktopFeedPanelTests: XCTestCase {
    func testDefaultSelectionIncludesAllAvailableFeeds() {
        let firstFeedID = UUID()
        let secondFeedID = UUID()
        let availableFeedIDs: Set<UUID> = [firstFeedID, secondFeedID]

        XCTAssertEqual(DesktopPanelFeedSelection.selectedFeedIDs(from: "*", availableFeedIDs: availableFeedIDs), availableFeedIDs)
        XCTAssertTrue(DesktopPanelFeedSelection.selectedFeedIDs(from: "none", availableFeedIDs: availableFeedIDs).isEmpty)
    }

    func testExplicitSelectionIgnoresDeletedFeeds() {
        let selectedFeedID = UUID()
        let removedFeedID = UUID()
        let storedValue = "\(selectedFeedID.uuidString),\(removedFeedID.uuidString)"

        XCTAssertEqual(
            DesktopPanelFeedSelection.selectedFeedIDs(
                from: storedValue,
                availableFeedIDs: [selectedFeedID]
            ),
            [selectedFeedID]
        )
    }

    func testSourceSelectionEncodingUsesStableTokens() {
        let firstFeedID = UUID()
        let secondFeedID = UUID()
        let availableFeedIDs: Set<UUID> = [firstFeedID, secondFeedID]

        XCTAssertEqual(DesktopPanelFeedSelection.storedValue(for: availableFeedIDs, availableFeedIDs: availableFeedIDs), "*")
        XCTAssertEqual(DesktopPanelFeedSelection.storedValue(for: [], availableFeedIDs: availableFeedIDs), "none")
    }

    func testPanelPlacementUsesChosenEdgeAndVisibleFrame() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1440, height: 860)

        XCTAssertEqual(DesktopPanelPlacement.frame(in: visibleFrame, edge: "left", width: 320), CGRect(x: 20, y: 40, width: 320, height: 860))
        XCTAssertEqual(DesktopPanelPlacement.frame(in: visibleFrame, edge: "right", width: 320), CGRect(x: 1140, y: 40, width: 320, height: 860))
    }
}