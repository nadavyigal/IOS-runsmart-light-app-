import XCTest
@testable import IOS_RunSmart_app

final class FlexWeekAnalyticsTests: XCTestCase {

    // MARK: - Adjustment History

    override func setUp() {
        super.setUp()
        FlexWeekAdjustmentHistory.clear()
    }

    func testRecordAndRetrieveWithinWindow() {
        let record = FlexWeekRecord(reason: "tired", confirmedAt: Date(), changesCount: 2)
        FlexWeekAdjustmentHistory.record(record)
        let history = FlexWeekAdjustmentHistory.historyWithin(7 * 24 * 3600)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.reason, "tired")
        XCTAssertEqual(history.first?.changesCount, 2)
    }

    func testRecordOutsideWindowNotReturned() {
        let oldDate = Date().addingTimeInterval(-(8 * 24 * 3600))
        let record = FlexWeekRecord(reason: "sick", confirmedAt: oldDate, changesCount: 3)
        FlexWeekAdjustmentHistory.record(record)
        let history = FlexWeekAdjustmentHistory.historyWithin(7 * 24 * 3600)
        XCTAssertEqual(history.count, 0)
    }

    func testHistoryCappedAtTenRecords() {
        for i in 0..<12 {
            FlexWeekAdjustmentHistory.record(
                FlexWeekRecord(reason: "tired", confirmedAt: Date(), changesCount: i)
            )
        }
        XCTAssertEqual(FlexWeekAdjustmentHistory.all().count, 10)
    }

    func testClearRemovesAllRecords() {
        FlexWeekAdjustmentHistory.record(
            FlexWeekRecord(reason: "tired", confirmedAt: Date(), changesCount: 1)
        )
        FlexWeekAdjustmentHistory.clear()
        XCTAssertEqual(FlexWeekAdjustmentHistory.all().count, 0)
    }

    func testMixedWindowBoundary() {
        let recent = Date().addingTimeInterval(-3600)
        let old = Date().addingTimeInterval(-(8 * 24 * 3600))
        FlexWeekAdjustmentHistory.record(FlexWeekRecord(reason: "traveling", confirmedAt: recent, changesCount: 1))
        FlexWeekAdjustmentHistory.record(FlexWeekRecord(reason: "sick", confirmedAt: old, changesCount: 2))
        let history = FlexWeekAdjustmentHistory.historyWithin(7 * 24 * 3600)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.reason, "traveling")
    }

    // MARK: - Analytics rawValue correctness

    func testFlexWeekCancelStepRawValues() {
        XCTAssertEqual(FlexWeekCancelStep.picker.rawValue, "picker")
        XCTAssertEqual(FlexWeekCancelStep.loading.rawValue, "loading")
        XCTAssertEqual(FlexWeekCancelStep.diff.rawValue, "diff")
    }

    func testFlexWeekInterventionActionRawValues() {
        XCTAssertEqual(FlexWeekInterventionAction.talkToCoach.rawValue, "talk_to_coach")
        XCTAssertEqual(FlexWeekInterventionAction.continueToPicker.rawValue, "continue_to_picker")
    }
}
