import CoreGraphics
import Testing
@testable import Vidarr

struct GestureRecognizerTests {
    private let recognizer = GestureRecognizer(
        matchScoreThreshold: 0.72,
        minPathLength: 80,
        dominanceRatio: 1.8
    )

    @Test func recognizesLeftStroke() {
        let points = polyline([
            CGPoint(x: 320, y: 160),
            CGPoint(x: 220, y: 166),
            CGPoint(x: 80, y: 158)
        ], stepsPerSegment: 30)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "Left", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.72)
    }

    @Test func recognizesDoubleCircleAsOO() {
        let points = circle(loopCount: 2, center: CGPoint(x: 180, y: 180), radius: 90, segmentsPerLoop: 56)
        let result = recognizer.recognize(points: points)

        #expect(result?.name == "OO", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.72)
    }

    @Test func recognizesUpRightArrow() {
        let points = polyline([
            CGPoint(x: 140, y: 40),
            CGPoint(x: 138, y: 220),
            CGPoint(x: 290, y: 220)
        ], stepsPerSegment: 26)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.72)
    }

    @Test func lowConfidenceGestureReturnsNil() {
        let points = polyline([
            CGPoint(x: 12, y: 12),
            CGPoint(x: 14, y: 16),
            CGPoint(x: 16, y: 11),
            CGPoint(x: 18, y: 15)
        ], stepsPerSegment: 3)

        let result = recognizer.recognize(points: points)
        #expect(result == nil)
    }
}

private func polyline(_ controlPoints: [CGPoint], stepsPerSegment: Int) -> [CGPoint] {
    guard controlPoints.count >= 2 else { return controlPoints }

    var output: [CGPoint] = []
    for i in 1..<controlPoints.count {
        let segment = line(from: controlPoints[i - 1], to: controlPoints[i], steps: stepsPerSegment)
        if output.isEmpty {
            output.append(contentsOf: segment)
        } else {
            output.append(contentsOf: segment.dropFirst())
        }
    }
    return output
}

private func line(from: CGPoint, to: CGPoint, steps: Int) -> [CGPoint] {
    guard steps > 0 else { return [from, to] }
    return (0...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps)
        return CGPoint(
            x: from.x + (to.x - from.x) * t,
            y: from.y + (to.y - from.y) * t
        )
    }
}

private func circle(loopCount: Int, center: CGPoint, radius: CGFloat, segmentsPerLoop: Int) -> [CGPoint] {
    let total = segmentsPerLoop * loopCount
    return (0...total).map { i in
        let t = CGFloat(i) / CGFloat(total)
        let radians = t * 2 * .pi * CGFloat(loopCount)
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }
}
