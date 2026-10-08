import XCTest
@testable import LiftingCore

final class BarCandidateTrackerTests: XCTestCase {
    private func candidate(_ x: Double, radius: Double = 0.08, color: [Double] = [0.2,0.2,0.2]) throws -> BarCandidate {
        try BarCandidate(center: VideoPoint(x:x,y:0.5),radius:radius,aspect:0.9,hubRatio:0.15,shapeScore:0.9,color:color)
    }
    private func initialized() throws -> (BarCandidateTracker, BarDecision) {
        var machine=BarCandidateTracker()
        var result=try machine.process(seconds:0,candidates:[candidate(0.3)],scene:BarSceneShift(x:0,y:0))
        for frame in 1...5 {
            result=try machine.process(seconds:Double(frame)/10,candidates:[candidate(0.3+Double(frame)*0.005)],scene:BarSceneShift(x:0,y:0))
        }
        XCTAssertEqual(result.kind,.automatic);XCTAssertNotNil(result.point)
        return (machine,result)
    }
    func testStaticCirclesAndCameraOnlyMotionNeverInitialize() throws {
        var staticMachine=BarCandidateTracker(),cameraMachine=BarCandidateTracker()
        for frame in 0...15 {
            let time=Double(frame)/10
            XCTAssertNil(try staticMachine.process(seconds:time,candidates:[candidate(0.3)],scene:BarSceneShift(x:0,y:0)).point)
            XCTAssertNil(try cameraMachine.process(seconds:time,candidates:[candidate(0.3+Double(frame)*0.002)],scene:BarSceneShift(x:0.002,y:0)).point)
        }
    }
    func testCompetingMovingTargetsAbstainInsteadOfSelectingNearSide() throws {
        var machine=BarCandidateTracker()
        for frame in 0...8 {
            let dx=Double(frame)*0.005
            let result=try machine.process(seconds:Double(frame)/10,
                candidates:[candidate(0.2+dx),candidate(0.6+dx,radius:0.075)],scene:BarSceneShift(x:0,y:0))
            XCTAssertNil(result.point)
        }
    }
    func testLossRequiresThreeUniqueAppearanceMatchesAndKeepsIdentity() throws {
        var (machine,initial)=try initialized()
        let lost=try machine.process(seconds:0.6,candidates:[],scene:BarSceneShift(x:0,y:0))
        XCTAssertEqual(lost.kind,.lost);XCTAssertNil(lost.point)
        XCTAssertNil(try machine.process(seconds:0.7,candidates:[candidate(0.335)],scene:BarSceneShift(x:0,y:0)).point)
        XCTAssertNil(try machine.process(seconds:0.8,candidates:[candidate(0.34)],scene:BarSceneShift(x:0,y:0)).point)
        let recovered=try machine.process(seconds:0.9,candidates:[candidate(0.345)],scene:BarSceneShift(x:0,y:0))
        XCTAssertEqual(recovered.targetID,initial.targetID);XCTAssertEqual(recovered.kind,.tracked)
    }
    func testAmbiguousOrWrongAppearanceCannotReacquireAndCameraFailureResets() throws {
        var (machine,_)=try initialized()
        XCTAssertNil(try machine.process(seconds:0.6,candidates:[candidate(0.328),candidate(0.332)],scene:BarSceneShift(x:0,y:0)).point)
        XCTAssertNil(try machine.process(seconds:0.7,candidates:[candidate(0.335,color:[0.9,0.1,0.1])],scene:BarSceneShift(x:0,y:0)).point)
        XCTAssertNil(try machine.process(seconds:0.8,candidates:[candidate(0.34)],scene:nil).point)
        XCTAssertNil(try machine.process(seconds:0.9,candidates:[candidate(0.345)],scene:BarSceneShift(x:0,y:0)).point)
        XCTAssertThrowsError(try machine.process(seconds:0.9,candidates:[],scene:BarSceneShift(x:0,y:0)))
    }
    func testTraceBreaksWhenCandidateIdentityChanges() throws {
        let point=try VideoPoint(x:0.5,y:0.5)
        let trace=try VideoTrace(start:0,end:1,samples:[
            VideoTraceSample(seconds:0.1,point:point,confidence:0.9,kind:.automatic,targetID:"one"),
            VideoTraceSample(seconds:0.2,point:point,confidence:0.9,kind:.automatic,targetID:"two")])
        XCTAssertEqual(trace.segments(through:1).map(\.count),[1,1])
    }
    func testCameraShiftDuringLossAccumulatesWithoutDrawingAndExpiredIdentityIsDiscarded() throws {
        var (machine,initial)=try initialized()
        XCTAssertNil(try machine.process(seconds:0.6,candidates:[],scene:BarSceneShift(x:0.01,y:0)).point)
        XCTAssertNil(try machine.process(seconds:0.7,candidates:[candidate(0.355)],scene:BarSceneShift(x:0.01,y:0)).point)
        XCTAssertNil(try machine.process(seconds:0.8,candidates:[candidate(0.37)],scene:BarSceneShift(x:0.01,y:0)).point)
        let recovered=try machine.process(seconds:0.9,candidates:[candidate(0.385)],scene:BarSceneShift(x:0.01,y:0))
        XCTAssertEqual(recovered.targetID,initial.targetID)
        for frame in 10...17 {
            XCTAssertNil(try machine.process(seconds:Double(frame)/10,candidates:[],scene:BarSceneShift(x:0,y:0)).point)
        }
        let restarted=try machine.process(seconds:1.8,candidates:[candidate(0.4)],scene:BarSceneShift(x:0,y:0))
        XCTAssertNil(restarted.point);XCTAssertNil(restarted.targetID)
    }
    func testInvalidEvidenceAndUnorderedFramesReject() throws {
        XCTAssertThrowsError(try BarCandidate(center:VideoPoint(x:0.5,y:0.5),radius:0.1,aspect:1,hubRatio:0.15,shapeScore:.nan,color:[0,0,0]))
        XCTAssertThrowsError(try BarSceneShift(x:0.04,y:0))
        var machine=BarCandidateTracker()
        _=try machine.process(seconds:1,candidates:[],scene:nil)
        XCTAssertThrowsError(try machine.process(seconds:0.9,candidates:[],scene:nil))
    }
}
