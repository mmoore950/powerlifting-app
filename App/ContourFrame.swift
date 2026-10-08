import Foundation
import Vision
import CoreGraphics
import LiftingCore

struct ContourLandmark {
    let x: Double, y: Double, area: Double, aspect: Double
}
struct ContourFrame {
    let candidates: [BarCandidate]
    let landmarks: [ContourLandmark]
    private struct Shape {
        let bounds: CGRect
        let circularity: Double
        let radius: Double
        let aspect: Double
    }
    static func extract(_ image: CGImage, cancellation: VisionCancellation) throws -> ContourFrame {
        let request = VNDetectContoursRequest()
        request.maximumImageDimension = 512
        request.contrastAdjustment = 1
        request.detectsDarkOnLight = true
        cancellation.begin(request)
        defer { cancellation.end(request) }
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        guard let result = request.results?.first else { return ContourFrame(candidates: [], landmarks: []) }
        var queue = Array(result.topLevelContours.prefix(128)), contours: [VNContour] = []
        while !queue.isEmpty, contours.count < 256 {
            let item = queue.removeFirst(); contours.append(item)
            queue.append(contentsOf: item.childContours.prefix(16))
        }
        let width = Double(image.width), height = Double(image.height)
        var candidates: [BarCandidate] = [], landmarks: [ContourLandmark] = []
        for contour in contours {
            guard let shape = measure(contour, width: width, height: height) else { continue }
            let bounds = shape.bounds
            if shape.circularity >= 0.65, shape.aspect >= 0.4,
               shape.radius >= min(width,height)*0.035, shape.radius <= min(width,height)*0.35 {
                let hub = contour.childContours.prefix(16).compactMap { child -> Shape? in
                    guard let nested = measure(child,width:width,height:height), nested.circularity >= 0.55,
                          (0.04...0.35).contains(nested.radius / shape.radius),
                          hypot(Double(nested.bounds.midX-bounds.midX),Double(nested.bounds.midY-bounds.midY)) <= shape.radius*0.18 else { return nil }
                    return nested
                }.max { $0.circularity < $1.circularity }
                if let hub, let color = meanColor(image, bounds: bounds),
                   let point = try? VideoPoint(visionX: Double(hub.bounds.midX)/width, visionY: Double(hub.bounds.midY)/height),
                   let candidate = try? BarCandidate(center: point, radius: shape.radius/max(width,height), aspect: shape.aspect,
                       hubRatio: hub.radius/shape.radius, shapeScore: min(1,shape.circularity), color: color) {
                    if !candidates.contains(where: { hypot($0.center.x-point.x,$0.center.y-point.y) < 0.008 }) {
                        candidates.append(candidate)
                    }
                }
            }
            let area = Double(bounds.width*bounds.height)/(width*height)
            if area >= 0.001, area <= 0.08, landmarks.count < 80 {
                let x = Double(bounds.midX)/width, y = 1-Double(bounds.midY)/height
                if !landmarks.contains(where: { hypot($0.x-x,$0.y-y) < 0.015 }) {
                    landmarks.append(ContourLandmark(x:x,y:y,area:area,aspect:shape.aspect))
                }
            }
        }
        // Candidate regions cannot vote for background/camera motion.
        landmarks.removeAll { landmark in candidates.contains { candidate in
            hypot((landmark.x-candidate.center.x)*width,(landmark.y-candidate.center.y)*height) < candidate.radius*max(width,height)*1.5
        } }
        return ContourFrame(candidates:Array(candidates.sorted { $0.radius > $1.radius }.prefix(64)),landmarks:landmarks)
    }
    private static func measure(_ contour: VNContour, width: Double, height: Double) -> Shape? {
        let raw = contour.normalizedPoints
        guard raw.count >= 12 else { return nil }
        let strideSize = max(1,Int(ceil(Double(raw.count)/512)))
        let points = stride(from:0,to:raw.count,by:strideSize).map { (x:Double(raw[$0].x)*width,y:Double(raw[$0].y)*height) }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!,minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
        guard maxX>minX,maxY>minY else { return nil }
        var area=0.0,perimeter=0.0
        for index in points.indices {
            let a=points[index],b=points[(index+1)%points.count]
            area += a.x*b.y-b.x*a.y;perimeter += hypot(a.x-b.x,a.y-b.y)
        }
        guard perimeter>0 else { return nil }
        return Shape(bounds:CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY),
            circularity:min(1,4 * .pi * abs(area/2)/(perimeter*perimeter)), radius:max(maxX-minX,maxY-minY)/2,
            aspect:min(maxX-minX,maxY-minY)/max(maxX-minX,maxY-minY))
    }
    private static func meanColor(_ image: CGImage, bounds: CGRect) -> [Double]? {
        let cropRect=CGRect(x:bounds.minX,y:CGFloat(image.height)-bounds.maxY,width:bounds.width,height:bounds.height)
        guard let crop=image.cropping(to:cropRect) else { return nil }
        var bytes=[UInt8](repeating:0,count:4)
        let made=bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .high;context.draw(crop,in:CGRect(x:0,y:0,width:1,height:1));return true
        }
        return made ? bytes.prefix(3).map { Double($0)/255 } : nil
    }
    static func sceneShift(previous: [ContourLandmark], current: [ContourLandmark]) -> BarSceneShift? {
        var shifts:[(x:Double,y:Double,landmark:ContourLandmark)]=[],used=Set<Int>()
        for old in previous {
            let match=current.enumerated().filter { !used.contains($0.offset) && abs($0.element.aspect-old.aspect)<0.15 &&
                (0.75...1.33).contains($0.element.area/old.area) && hypot($0.element.x-old.x,$0.element.y-old.y)<0.05 }
                .min { hypot($0.element.x-old.x,$0.element.y-old.y)<hypot($1.element.x-old.x,$1.element.y-old.y) }
            if let match { used.insert(match.offset);shifts.append((match.element.x-old.x,match.element.y-old.y,old)) }
        }
        guard shifts.count>=8 else { return nil }
        func median(_ values:[Double])->Double { let sorted=values.sorted();return sorted[sorted.count/2] }
        let dx=median(shifts.map(\.x)),dy=median(shifts.map(\.y))
        let coherent=shifts.filter { hypot($0.x-dx,$0.y-dy)<0.006 }
        guard coherent.count>=8,Double(coherent.count)/Double(shifts.count)>=0.8,
              (coherent.map { $0.landmark.x }.max()! - coherent.map { $0.landmark.x }.min()!)>0.2,
              (coherent.map { $0.landmark.y }.max()! - coherent.map { $0.landmark.y }.min()!)>0.2 else { return nil }
        return try? BarSceneShift(x:dx,y:dy)
    }
}
