import Foundation

/// Sampling requests are only requests. Accepted observations use the decoder's actual PTS.
public struct VideoSampleClock: Sendable {
    public let start: Double
    public let end: Double
    public let requestCount: Int
    private var last: Double?
    private var accepted = 0
    public init(start: Double, end: Double) throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end <= 1_800, end-start <= 30 else {
            throw VideoTraceError.invalidRange
        }
        self.start=start; self.end=end; requestCount=min(450,Int(ceil((end-start)*15))+1)
    }
    public func requestedSeconds(index: Int) throws -> Double {
        guard (0..<requestCount).contains(index) else { throw VideoTraceError.invalidRange }
        return min(end,start+Double(index)/15)
    }
    public mutating func accept(value: Int64, timescale: Int32, epoch: Int64) throws -> Double? {
        guard timescale>0, epoch==0 else { throw VideoTraceError.invalidSample }
        let seconds=Double(value)/Double(timescale)
        guard seconds.isFinite else { throw VideoTraceError.invalidSample }
        guard seconds>=start,seconds<=end,last.map({seconds>$0}) ?? true else { return nil }
        guard accepted<450 else { throw VideoTraceError.invalidRange }
        last=seconds;accepted+=1;return seconds
    }
}
