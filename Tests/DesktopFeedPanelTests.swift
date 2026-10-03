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

    func testPanelOpensAtDefaultWidthWhenNothingIsStored() {
        XCTAssertEqual(DesktopPanelPlacement.defaultWidth, 300)
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 0), 300)
        XCTAssertEqual(DesktopPanelPlacement.frame(in: CGRect(x: 0, y: 0, width: 1440, height: 860), edge: "right", width: 0).width, 300)
    }

    func testPanelWidthClampsToDraggableRange() {
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 100), 240)
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 360), 360)
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 900), 480)
    }

    func testDraggingTheInnerEdgeGrowsThePanelAwayFromTheDockedEdge() {
        // Right-docked: the draggable edge is on the left, so pulling left grows it.
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 300, draggingBy: -60, edge: "right"), 360)
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 300, draggingBy: 60, edge: "right"), 240)
        // Left-docked: the draggable edge is on the right, so the sign flips.
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 300, draggingBy: 60, edge: "left"), 360)
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 300, draggingBy: -60, edge: "left"), 240)
        // Dragging past the limits parks at the limit instead of running away.
        XCTAssertEqual(DesktopPanelPlacement.width(fromStoredWidth: 300, draggingBy: -1000, edge: "right"), 480)
    }

    func testResizingKeepsTheDockedEdgeAnchored() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1440, height: 860)

        let rightDocked = DesktopPanelPlacement.frame(in: visibleFrame, edge: "right", width: 420)
        XCTAssertEqual(rightDocked.maxX, visibleFrame.maxX)
        XCTAssertEqual(rightDocked.width, 420)

        let leftDocked = DesktopPanelPlacement.frame(in: visibleFrame, edge: "left", width: 420)
        XCTAssertEqual(leftDocked.minX, visibleFrame.minX)
        XCTAssertEqual(leftDocked.width, 420)
    }
}