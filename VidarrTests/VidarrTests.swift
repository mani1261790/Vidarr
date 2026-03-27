import CoreGraphics
import Testing
import VidarrCore
@testable import Vidarr

struct GestureRecognizerTests {
    private func makeRecognizer() -> GestureRecognizer {
        GestureRecognizer(
            matchScoreThreshold: 0.65,
            minPathLength: 80,
            dominanceRatio: 1.8
        )
    }

    @Test func recognizesLeftStroke() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 320, y: 160),
            CGPoint(x: 220, y: 166),
            CGPoint(x: 80, y: 158)
        ], stepsPerSegment: 30)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "Left", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesDoubleCircleAsOO() {
        let recognizer = makeRecognizer()
        let points = circle(loopCount: 2, center: CGPoint(x: 180, y: 180), radius: 90, segmentsPerLoop: 56)
        let result = recognizer.recognize(points: points)

        #expect(result?.name == "OO", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesUpRightArrow() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 140, y: 40),
            CGPoint(x: 138, y: 220),
            CGPoint(x: 290, y: 220)
        ], stepsPerSegment: 26)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesUpLeftArrow() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 210, y: 40),
            CGPoint(x: 208, y: 220),
            CGPoint(x: 60, y: 218)
        ], stepsPerSegment: 26)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpLeft", "actual result: \(String(describing: result))")
    }

    @Test func recognizesDownLeftForNewTab() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 190, y: 250),
            CGPoint(x: 185, y: 70),
            CGPoint(x: 40, y: 65)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownLeft", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesDownRightStroke() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 125, y: 220),
            CGPoint(x: 125, y: 35),
            CGPoint(x: 220, y: 35)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesDownRightDownRightStroke() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 80, y: 260),
            CGPoint(x: 80, y: 150),
            CGPoint(x: 180, y: 150),
            CGPoint(x: 180, y: 70),
            CGPoint(x: 300, y: 70)
        ], stepsPerSegment: 18)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownRightDownRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func prefersUpRightOverSimpleRightWhenVerticalLeadExists() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 160, y: 60),
            CGPoint(x: 160, y: 240),
            CGPoint(x: 320, y: 235)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpRight", "actual result: \(String(describing: result))")
    }

    @Test func prefersDownLeftOverSimpleLeftWhenVerticalLeadExists() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 220, y: 250),
            CGPoint(x: 214, y: 70),
            CGPoint(x: 70, y: 72)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownLeft", "actual result: \(String(describing: result))")
    }

    @Test func recognizesSingleLoopO() {
        let recognizer = makeRecognizer()
        let points = circle(loopCount: 1, center: CGPoint(x: 190, y: 190), radius: 85, segmentsPerLoop: 54)
        let result = recognizer.recognize(points: points)
        #expect(result?.name == "O", "actual result: \(String(describing: result))")
    }

    @Test func lowConfidenceGestureReturnsNil() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 12, y: 12),
            CGPoint(x: 14, y: 16),
            CGPoint(x: 16, y: 11),
            CGPoint(x: 18, y: 15)
        ], stepsPerSegment: 3)

        let result = recognizer.recognize(points: points)
        #expect(result == nil)
    }

    @Test func disallowedNamesFilterRejectsLShape() {
        let recognizer = makeRecognizer()
        let points = circle(loopCount: 1, center: CGPoint(x: 190, y: 190), radius: 85, segmentsPerLoop: 54)
        let allowedNames: Set<String> = ["Left"]
        let result = recognizer.recognize(points: points, allowedNames: allowedNames)
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
