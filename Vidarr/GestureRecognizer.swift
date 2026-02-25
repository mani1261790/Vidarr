import CoreGraphics
import Foundation

private struct GestureTemplate {
    let name: String
    let points: [CGPoint]
}

struct GestureResult {
    let name: String
    let score: CGFloat
}

/// 決定論的なテンプレートベース認識。
/// $1 の手順（リサンプル、回転、スケール、平行移動）で正規化し、
/// テンプレートとの距離比較 + 最低限のヒューリスティックで誤爆を抑える。
final class GestureRecognizer {
    private let squareSize: CGFloat = 250
    private let resampleCount: Int = 96

    private let matchScoreThreshold: CGFloat
    private let minPathLength: CGFloat
    private let dominanceRatio: CGFloat
    private let compositePreferenceSlack: CGFloat = 0.12

    private lazy var templates: [GestureTemplate] = {
        Self.rawTemplates().map { template in
            GestureTemplate(name: template.name, points: normalize(template.points))
        }
    }()

    init(matchScoreThreshold: CGFloat = 0.75, minPathLength: CGFloat = 120, dominanceRatio: CGFloat = 2.0) {
        self.matchScoreThreshold = matchScoreThreshold
        self.minPathLength = minPathLength
        self.dominanceRatio = dominanceRatio
    }

    func recognize(points raw: [CGPoint], allowedNames: Set<String>? = nil) -> GestureResult? {
        guard raw.count >= 10 else { return nil }
        guard pathLength(raw) >= minPathLength else { return nil }

        let normalized = normalize(raw)
        let ranked = rankedTemplateMatches(for: normalized)
        guard let passing = bestPassingCandidate(
            from: ranked,
            raw: raw,
            minimumScore: matchScoreThreshold,
            allowedNames: allowedNames
        ) else { return nil }
        return GestureResult(name: passing.name, score: passing.score)
    }

    /// HUD 用。しきい値チェックは行わず現在の最有力候補を返す。
    func bestMatch(points raw: [CGPoint], allowedNames: Set<String>? = nil) -> GestureResult? {
        guard raw.count >= 5 else { return nil }

        let normalized = normalize(raw)
        let ranked = rankedTemplateMatches(for: normalized)

        if let passing = bestPassingCandidate(from: ranked, raw: raw, minimumScore: 0, allowedNames: allowedNames) {
            return GestureResult(name: passing.name, score: passing.score)
        }

        let filteredRanked: [(name: String, score: CGFloat)]
        if let allowedNames {
            filteredRanked = ranked.filter { allowedNames.contains($0.name) }
        } else {
            filteredRanked = ranked
        }

        guard let first = filteredRanked.first else { return nil }
        return GestureResult(name: first.name, score: first.score)
    }

    /// 緩和判定用。距離スコアとヒューリスティックを満たす最上位候補だけ返す。
    func bestPassingMatch(points raw: [CGPoint], minimumScore: CGFloat, allowedNames: Set<String>? = nil) -> GestureResult? {
        guard raw.count >= 5 else { return nil }

        let normalized = normalize(raw)
        let ranked = rankedTemplateMatches(for: normalized)
        guard let passing = bestPassingCandidate(
            from: ranked,
            raw: raw,
            minimumScore: minimumScore,
            allowedNames: allowedNames
        ) else { return nil }
        return GestureResult(name: passing.name, score: passing.score)
    }

    private func rankedTemplateMatches(for normalizedPoints: [CGPoint]) -> [(name: String, score: CGFloat)] {
        var bestDistanceByName: [String: CGFloat] = [:]
        for template in templates {
            let d = pathDistance(normalizedPoints, template.points)
            if let current = bestDistanceByName[template.name] {
                bestDistanceByName[template.name] = min(current, d)
            } else {
                bestDistanceByName[template.name] = d
            }
        }

        let halfDiagonal = 0.5 * sqrt(2) * squareSize
        return bestDistanceByName
            .map { (name: $0.key, score: max(0, min(1, 1 - $0.value / halfDiagonal))) }
            .sorted { $0.score > $1.score }
    }

    private func normalize(_ points: [CGPoint]) -> [CGPoint] {
        var pts = resample(points, n: resampleCount)
        pts = rotateToIndicativeAngle(pts)
        pts = scaleToSquare(pts, size: squareSize)
        pts = translateToOrigin(pts)
        return pts
    }

    private func passesHeuristic(for name: String, raw: [CGPoint]) -> Bool {
        let start = raw.first ?? .zero
        let end = raw.last ?? .zero
        let dx = end.x - start.x
        let dy = end.y - start.y
        let corners = cornerCount(raw)

        switch name {
        case "Left":
            return isSimpleHorizontalStroke(
                raw,
                horizontalDirection: .left,
                dx: dx,
                dy: dy,
                corners: corners
            )

        case "Right":
            return isSimpleHorizontalStroke(
                raw,
                horizontalDirection: .right,
                dx: dx,
                dy: dy,
                corners: corners
            )

        case "L":
            return corners >= 1
                && corners <= 2
                && dx > 0
                && dy < 0
                && abs(dy) > minPathLength * 0.12

        case "LL":
            return corners >= 3
                && pathLength(raw) >= minPathLength * 1.5
                && dx > 0

        case "U":
            return isUShape(raw)

        case "O":
            return isClosedCircular(raw, expectedTurns: 2 * .pi, tolerance: 1.55 * .pi, closeRatioLimit: 0.45)

        case "OO":
            return isClosedCircular(raw, expectedTurns: 4 * .pi, tolerance: 2.35 * .pi, closeRatioLimit: 0.62)
                && pathLength(raw) >= minPathLength * 1.18

        case "UpRight":
            return isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .right)

        case "UpLeft":
            return isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .left)

        case "DownLeft":
            return isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .left)

        case "DownRight":
            return isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .right)

        case "DownRightDownRight":
            return isDoubleDownRight(raw)
                && pathLength(raw) >= minPathLength * 1.45

        case "S":
            return isSLike(raw)

        default:
            return false
        }
    }

    private func bestPassingCandidate(
        from ranked: [(name: String, score: CGFloat)],
        raw: [CGPoint],
        minimumScore: CGFloat,
        allowedNames: Set<String>?
    ) -> (name: String, score: CGFloat)? {
        let passing = ranked.filter { candidate in
            if let allowedNames, !allowedNames.contains(candidate.name) {
                return false
            }
            return candidate.score >= minimumScore && passesHeuristic(for: candidate.name, raw: raw)
        }

        guard let best = passing.first else { return nil }

        if best.name == "Left" || best.name == "Right",
           let composite = passing.first(where: {
               $0.name == "UpRight"
                   || $0.name == "UpLeft"
                   || $0.name == "DownLeft"
                   || $0.name == "DownRight"
                   || $0.name == "DownRightDownRight"
           }),
           composite.score >= best.score - compositePreferenceSlack {
            return composite
        }

        if best.name == "O",
           let doubleCircle = passing.first(where: { $0.name == "OO" }),
           doubleCircle.score >= best.score - 0.14 {
            return doubleCircle
        }

        return best
    }

    private enum HorizontalDirection {
        case left
        case right
    }

    private enum VerticalDirection {
        case up
        case down
    }

    private func isSimpleHorizontalStroke(
        _ raw: [CGPoint],
        horizontalDirection: HorizontalDirection,
        dx: CGFloat,
        dy: CGFloat,
        corners: Int
    ) -> Bool {
        switch horizontalDirection {
        case .left:
            guard dx < 0 else { return false }
        case .right:
            guard dx > 0 else { return false }
        }

        let absDx = abs(dx)
        let absDy = abs(dy)
        guard absDx > max(absDy * 1.6, minPathLength * 0.18) else { return false }
        guard corners <= 1 else { return false }

        let box = boundingBox(raw)
        guard box.width > 0 else { return false }
        guard box.height <= max(box.width * 0.34, 22) else { return false }
        guard totalTurningAngle(raw) <= .pi * 0.66 else { return false }

        switch horizontalDirection {
        case .left:
            guard !isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .left) else { return false }
            guard !isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .left) else { return false }
        case .right:
            guard !isVerticalThenHorizontal(raw, verticalDirection: .up, horizontalDirection: .right) else { return false }
            guard !isVerticalThenHorizontal(raw, verticalDirection: .down, horizontalDirection: .right) else { return false }
        }

        return true
    }

    private func isVerticalThenHorizontal(
        _ raw: [CGPoint],
        verticalDirection: VerticalDirection,
        horizontalDirection: HorizontalDirection
    ) -> Bool {
        guard raw.count >= 8 else { return false }

        let box = boundingBox(raw)
        let minVerticalTravel = max(22, box.height * 0.34)
        let minHorizontalTravel = max(20, box.width * 0.34)

        for ratio in stride(from: 0.34, through: 0.72, by: 0.06) {
            let split = max(2, min(raw.count - 3, Int(CGFloat(raw.count - 1) * CGFloat(ratio))))
            let first = vector(from: raw[0], to: raw[split])
            let second = vector(from: raw[split], to: raw[raw.count - 1])

            guard abs(first.dy) >= minVerticalTravel else { continue }
            guard abs(second.dx) >= minHorizontalTravel else { continue }

            switch verticalDirection {
            case .up:
                guard first.dy > 0, abs(first.dy) > abs(first.dx) * 0.92 else { continue }
            case .down:
                guard first.dy < 0, abs(first.dy) > abs(first.dx) * 0.92 else { continue }
            }

            switch horizontalDirection {
            case .right:
                if second.dx > 0 && abs(second.dx) > abs(second.dy) * 0.7 {
                    return true
                }
            case .left:
                if second.dx < 0 && abs(second.dx) > abs(second.dy) * 0.7 {
                    return true
                }
            }
        }

        return false
    }

    private func isDoubleDownRight(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 12 else { return false }

        let box = boundingBox(raw)
        let minVerticalTravel = max(20, box.height * 0.18)
        let minHorizontalTravel = max(20, box.width * 0.18)

        for r1 in stride(from: 0.14, through: 0.32, by: 0.04) {
            let i1 = max(2, min(raw.count - 5, Int(CGFloat(raw.count - 1) * CGFloat(r1))))
            for r2 in stride(from: 0.34, through: 0.52, by: 0.04) {
                let i2 = max(i1 + 2, min(raw.count - 4, Int(CGFloat(raw.count - 1) * CGFloat(r2))))
                for r3 in stride(from: 0.56, through: 0.78, by: 0.04) {
                    let i3 = max(i2 + 2, min(raw.count - 3, Int(CGFloat(raw.count - 1) * CGFloat(r3))))

                    let v1 = vector(from: raw[0], to: raw[i1])
                    let v2 = vector(from: raw[i1], to: raw[i2])
                    let v3 = vector(from: raw[i2], to: raw[i3])
                    let v4 = vector(from: raw[i3], to: raw[raw.count - 1])

                    guard v1.dy < 0, abs(v1.dy) >= minVerticalTravel, abs(v1.dy) > abs(v1.dx) * 0.78 else { continue }
                    guard v2.dx > 0, abs(v2.dx) >= minHorizontalTravel, abs(v2.dx) > abs(v2.dy) * 0.72 else { continue }
                    guard v3.dy < 0, abs(v3.dy) >= minVerticalTravel, abs(v3.dy) > abs(v3.dx) * 0.78 else { continue }
                    guard v4.dx > 0, abs(v4.dx) >= minHorizontalTravel, abs(v4.dx) > abs(v4.dy) * 0.72 else { continue }

                    return true
                }
            }
        }

        return false
    }

    private func isUShape(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 6 else { return false }

        let ys = raw.map(\.y)
        let xs = raw.map(\.x)

        guard let minY = ys.min(), let maxY = ys.max(), let minX = xs.min(), let maxX = xs.max() else {
            return false
        }

        let height = maxY - minY
        let width = maxX - minX
        guard height > 10, width > 10 else { return false }

        let shouldersY = max(raw.first?.y ?? 0, raw.last?.y ?? 0)
        let floorDistance = shouldersY - minY
        let shoulderGap = abs((raw.first?.y ?? 0) - (raw.last?.y ?? 0))

        return floorDistance > height * 0.45 && shoulderGap < height * 0.35
    }

    private func isClosedCircular(
        _ raw: [CGPoint],
        expectedTurns: CGFloat,
        tolerance: CGFloat,
        closeRatioLimit: CGFloat
    ) -> Bool {
        guard raw.count >= 10 else { return false }

        let totalTurn = totalTurningAngle(raw)
        let turnMatches = abs(totalTurn - expectedTurns) <= tolerance

        let box = boundingBox(raw)
        let diagonal = sqrt(box.width * box.width + box.height * box.height)
        let closeRatio = diagonal > 0 ? distance(raw[0], raw[raw.count - 1]) / diagonal : 1
        let isClosed = closeRatio < closeRatioLimit

        let aspect = box.height > 0 ? box.width / box.height : 999
        let validAspect = aspect > 0.35 && aspect < 2.8

        return turnMatches && isClosed && validAspect
    }

    private func isSLike(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 10 else { return false }

        let box = boundingBox(raw)
        let diagonal = sqrt(box.width * box.width + box.height * box.height)
        if diagonal > 0, distance(raw[0], raw[raw.count - 1]) / diagonal < 0.25 {
            return false
        }

        let strideStep = max(1, raw.count / 16)
        var previousSign: CGFloat = 0
        var signChanges = 0

        var i = strideStep
        while i < raw.count {
            let delta = raw[i].x - raw[i - strideStep].x
            let sign: CGFloat = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
            if sign != 0 {
                if previousSign != 0 && sign != previousSign {
                    signChanges += 1
                }
                previousSign = sign
            }
            i += strideStep
        }

        return signChanges >= 2
    }

    // MARK: - Geometry helpers
    private func resample(_ points: [CGPoint], n: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }

        let interval = pathLength(points) / CGFloat(n - 1)
        guard interval > 0 else { return points }

        var distanceAccumulator: CGFloat = 0
        var newPoints: [CGPoint] = [points[0]]
        var working = points
        var i = 1

        while i < working.count {
            let segmentLength = distance(working[i - 1], working[i])
            if segmentLength == 0 {
                i += 1
                continue
            }

            if distanceAccumulator + segmentLength >= interval {
                let t = (interval - distanceAccumulator) / segmentLength
                let interpolated = CGPoint(
                    x: working[i - 1].x + t * (working[i].x - working[i - 1].x),
                    y: working[i - 1].y + t * (working[i].y - working[i - 1].y)
                )
                newPoints.append(interpolated)
                working.insert(interpolated, at: i)
                distanceAccumulator = 0
                i += 1
            } else {
                distanceAccumulator += segmentLength
                i += 1
            }
        }

        while newPoints.count < n, let last = working.last {
            newPoints.append(last)
        }

        if newPoints.count > n {
            newPoints = Array(newPoints.prefix(n))
        }

        return newPoints
    }

    private func rotateToIndicativeAngle(_ points: [CGPoint]) -> [CGPoint] {
        guard let first = points.first else { return points }
        let c = centroid(points)
        let theta = atan2(first.y - c.y, first.x - c.x)
        return rotate(points, by: -theta, around: c)
    }

    private func rotate(_ points: [CGPoint], by radians: CGFloat, around center: CGPoint) -> [CGPoint] {
        points.map { p in
            let translatedX = p.x - center.x
            let translatedY = p.y - center.y
            let x = translatedX * cos(radians) - translatedY * sin(radians) + center.x
            let y = translatedX * sin(radians) + translatedY * cos(radians) + center.y
            return CGPoint(x: x, y: y)
        }
    }

    private func scaleToSquare(_ points: [CGPoint], size: CGFloat) -> [CGPoint] {
        let box = boundingBox(points)
        let scale = max(box.width, box.height)
        guard scale > 0 else { return points }

        return points.map {
            CGPoint(
                x: ($0.x - box.minX) / scale * size,
                y: ($0.y - box.minY) / scale * size
            )
        }
    }

    private func translateToOrigin(_ points: [CGPoint]) -> [CGPoint] {
        let c = centroid(points)
        return points.map { CGPoint(x: $0.x - c.x, y: $0.y - c.y) }
    }

    private func pathDistance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }

        var total: CGFloat = 0
        for index in 0..<a.count {
            total += distance(a[index], b[index])
        }
        return total / CGFloat(a.count)
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }

        var total: CGFloat = 0
        for i in 1..<points.count {
            total += distance(points[i - 1], points[i])
        }
        return total
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for p in points {
            sumX += p.x
            sumY += p.y
        }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }

    private func vector(from a: CGPoint, to b: CGPoint) -> CGVector {
        CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }

    private func cornerCount(_ points: [CGPoint]) -> Int {
        guard points.count >= 3 else { return 0 }

        let sampled = sampledPoints(points, stride: max(1, points.count / 24))
        guard sampled.count >= 3 else { return 0 }

        var count = 0
        for i in 1..<(sampled.count - 1) {
            let v1 = vector(from: sampled[i - 1], to: sampled[i])
            let v2 = vector(from: sampled[i], to: sampled[i + 1])

            let l1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
            let l2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
            if l1 < 0.1 || l2 < 0.1 { continue }

            let dot = v1.dx * v2.dx + v1.dy * v2.dy
            let normalizedDot = max(-1, min(1, dot / (l1 * l2)))
            let angle = acos(normalizedDot)
            if angle > (.pi / 4) {
                count += 1
            }
        }

        return count
    }

    private func sampledPoints(_ points: [CGPoint], stride: Int) -> [CGPoint] {
        var output: [CGPoint] = []
        var index = 0
        while index < points.count {
            output.append(points[index])
            index += stride
        }
        if let last = points.last, output.last != last {
            output.append(last)
        }
        return output
    }

    private func totalTurningAngle(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }

        var sum: CGFloat = 0
        for i in 2..<points.count {
            let v1 = vector(from: points[i - 2], to: points[i - 1])
            let v2 = vector(from: points[i - 1], to: points[i])
            let a1 = atan2(v1.dy, v1.dx)
            let a2 = atan2(v2.dy, v2.dx)

            var delta = a2 - a1
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            sum += abs(delta)
        }
        return sum
    }

    private func boundingBox(_ points: [CGPoint]) -> (minX: CGFloat, minY: CGFloat, width: CGFloat, height: CGFloat) {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for p in points {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }

        return (minX, minY, maxX - minX, maxY - minY)
    }
}

extension GestureRecognizer {
    private static func rawTemplates() -> [GestureTemplate] {
        func interpolatedLine(from: CGPoint, to: CGPoint, steps: Int = 24) -> [CGPoint] {
            guard steps > 0 else { return [from, to] }
            return (0...steps).map { i in
                let t = CGFloat(i) / CGFloat(steps)
                return CGPoint(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t
                )
            }
        }

        func polyline(_ controlPoints: [CGPoint], stepsPerSegment: Int = 18) -> [CGPoint] {
            guard controlPoints.count >= 2 else { return controlPoints }
            var output: [CGPoint] = []
            for index in 1..<controlPoints.count {
                let segment = interpolatedLine(from: controlPoints[index - 1], to: controlPoints[index], steps: stepsPerSegment)
                if output.isEmpty {
                    output.append(contentsOf: segment)
                } else {
                    output.append(contentsOf: segment.dropFirst())
                }
            }
            return output
        }

        func circle(loopCount: Int, clockwise: Bool, segmentsPerLoop: Int = 64) -> [CGPoint] {
            let center = CGPoint(x: 125, y: 125)
            let radius: CGFloat = 72

            return (0...(segmentsPerLoop * loopCount)).map { i in
                let t = CGFloat(i) / CGFloat(segmentsPerLoop * loopCount)
                let radians = t * 2 * .pi * CGFloat(loopCount) * (clockwise ? -1 : 1)
                return CGPoint(
                    x: center.x + radius * cos(radians),
                    y: center.y + radius * sin(radians)
                )
            }
        }

        let left = interpolatedLine(from: CGPoint(x: 220, y: 120), to: CGPoint(x: 30, y: 120))
        let right = interpolatedLine(from: CGPoint(x: 30, y: 120), to: CGPoint(x: 220, y: 120))

        let lShape = polyline([
            CGPoint(x: 50, y: 210),
            CGPoint(x: 50, y: 50),
            CGPoint(x: 210, y: 50)
        ])

        let llShapeA = polyline([
            CGPoint(x: 35, y: 210),
            CGPoint(x: 35, y: 50),
            CGPoint(x: 105, y: 50),
            CGPoint(x: 105, y: 210),
            CGPoint(x: 105, y: 50),
            CGPoint(x: 220, y: 50)
        ])

        let llShapeB = polyline([
            CGPoint(x: 35, y: 210),
            CGPoint(x: 35, y: 50),
            CGPoint(x: 120, y: 50),
            CGPoint(x: 165, y: 210),
            CGPoint(x: 165, y: 50),
            CGPoint(x: 225, y: 50)
        ])

        let uShape = polyline([
            CGPoint(x: 45, y: 210),
            CGPoint(x: 45, y: 55),
            CGPoint(x: 205, y: 55),
            CGPoint(x: 205, y: 210)
        ])

        let upRight = polyline([
            CGPoint(x: 125, y: 30),
            CGPoint(x: 125, y: 220),
            CGPoint(x: 220, y: 220)
        ])

        let upLeft = polyline([
            CGPoint(x: 125, y: 30),
            CGPoint(x: 125, y: 220),
            CGPoint(x: 30, y: 220)
        ])

        let downLeft = polyline([
            CGPoint(x: 125, y: 220),
            CGPoint(x: 125, y: 35),
            CGPoint(x: 30, y: 35)
        ])

        let downRight = polyline([
            CGPoint(x: 125, y: 220),
            CGPoint(x: 125, y: 35),
            CGPoint(x: 220, y: 35)
        ])

        let downRightDownRight = polyline([
            CGPoint(x: 70, y: 220),
            CGPoint(x: 70, y: 120),
            CGPoint(x: 150, y: 120),
            CGPoint(x: 150, y: 35),
            CGPoint(x: 230, y: 35)
        ])

        let sShapeA = polyline([
            CGPoint(x: 40, y: 210),
            CGPoint(x: 95, y: 230),
            CGPoint(x: 170, y: 190),
            CGPoint(x: 210, y: 145),
            CGPoint(x: 140, y: 115),
            CGPoint(x: 75, y: 85),
            CGPoint(x: 30, y: 35)
        ])

        let sShapeB = polyline([
            CGPoint(x: 210, y: 210),
            CGPoint(x: 150, y: 235),
            CGPoint(x: 90, y: 190),
            CGPoint(x: 45, y: 145),
            CGPoint(x: 110, y: 110),
            CGPoint(x: 165, y: 80),
            CGPoint(x: 210, y: 35)
        ])

        return [
            GestureTemplate(name: "Left", points: left),
            GestureTemplate(name: "Right", points: right),
            GestureTemplate(name: "L", points: lShape),
            GestureTemplate(name: "LL", points: llShapeA),
            GestureTemplate(name: "LL", points: llShapeB),
            GestureTemplate(name: "U", points: uShape),
            GestureTemplate(name: "O", points: circle(loopCount: 1, clockwise: true)),
            GestureTemplate(name: "O", points: circle(loopCount: 1, clockwise: false)),
            GestureTemplate(name: "OO", points: circle(loopCount: 2, clockwise: true)),
            GestureTemplate(name: "OO", points: circle(loopCount: 2, clockwise: false)),
            GestureTemplate(name: "UpRight", points: upRight),
            GestureTemplate(name: "UpLeft", points: upLeft),
            GestureTemplate(name: "DownLeft", points: downLeft),
            GestureTemplate(name: "DownRight", points: downRight),
            GestureTemplate(name: "DownRightDownRight", points: downRightDownRight),
            GestureTemplate(name: "S", points: sShapeA),
            GestureTemplate(name: "S", points: sShapeB)
        ]
    }
}
