import XCTest
@testable import LiftingCore

final class VideoSampleClockTests: XCTestCase {
    func testActualVFRPTSIsKeptAndDuplicateBackstepOutOfRangeIsSkipped() throws {
        var clock=try VideoSampleClock(start:0,end:0.2)
        XCTAssertEqual(try clock.accept(value:0,timescale:600,epoch:0),0)
        XCTAssertEqual(try clock.accept(value:40,timescale:600,epoch:0),1.0/15)
        XCTAssertNil(try clock.accept(value:80,timescale:1200,epoch:0))
        XCTAssertEqual(try clock.accept(value:91,timescale:1000,epoch:0),0.091)
        XCTAssertNil(try clock.accept(value:90,timescale:1000,epoch:0))
        XCTAssertNil(try clock.accept(value:300,timescale:1000,epoch:0))
        XCTAssertEqual(try clock.accept(value:200,timescale:1000,epoch:0),0.2)
        XCTAssertNotEqual(try clock.requestedSeconds(index:2),0.091)
    }
    func testInvalidEpochScaleAndResourceBoundsReject() throws {
        XCTAssertThrowsError(try VideoSampleClock(start:0,end:31))
        var clock=try VideoSampleClock(start:0,end:30)
        XCTAssertEqual(clock.requestCount,450)
        XCTAssertThrowsError(try clock.accept(value:0,timescale:0,epoch:0))
        XCTAssertThrowsError(try clock.accept(value:0,timescale:600,epoch:1))
        XCTAssertThrowsError(try clock.requestedSeconds(index:450))
        for frame in 0..<450 { XCTAssertNotNil(try clock.accept(value:Int64(frame),timescale:20,epoch:0)) }
        XCTAssertThrowsError(try clock.accept(value:450,timescale:20,epoch:0))
    }
}
