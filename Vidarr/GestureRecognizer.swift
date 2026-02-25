import Foundation
import CoreGraphics

struct GestureTemplate {
    let name: String
    let points: [CGPoint]
}

struct GestureResult {
    let name: String
    let score: CGFloat // 0..1, 1 is best
}

/// 決定論的な $1 Unistroke Recognizer 実装（回転不変性を無効化し、方向を尊重）。
final class GestureRecognizer {
    // MARK: - Config (公開しやすいようにイニシャライザ引数)
    private let squareSize: CGFloat = 250
    private let resampleCount: Int = 64
    private let matchScoreThreshold: CGFloat
    private let minPathLength: CGFloat
    private let dominanceRatio: CGFloat

    // 回転は行わず、方向（Left/Right, Up/Down）をそのまま評価
    private let rotationInvariant: Bool = false

    private lazy var templates: [GestureTemplate] = Self.canonicalTemplates()

    init(matchScoreThreshold: CGFloat = 0.75, minPathLength: CGFloat = 120, dominanceRatio: CGFloat = 2.0) {
        self.matchScoreThreshold = matchScoreThreshold
        self.minPathLength = minPathLength
        self.dominanceRatio = dominanceRatio
    }

    // MARK: - Public API
    func recognize(points raw: [CGPoint]) -> GestureResult? {
        guard raw.count >= 10 else { return nil }
        guard pathLength(raw) >= minPathLength else { return nil }

        let pts = normalize(raw)
        let best = bestTemplateMatch(for: pts)
        guard let bestName = best.name else { return nil }
        let score = best.score

        // 補助ヒューリスティクス：O/OO の信頼性を高める
        if bestName == "O" || bestName == "OO" {
            let turns = totalTurningAngle(points: pts)
            let startEnd = distance(pts.first!, pts.last!)
            let closeEnough = startEnd < (squareSize * 0.25)
            let expectedTurns: CGFloat = bestName == "O" ? (2 * .pi) : (4 * .pi)
            let within = abs(turns - expectedTurns) < (.pi * 0.75) // 許容誤差
            let longEnough = pathLength(raw) >= minPathLength * 1.2
            if !(closeEnough && within && longEnough) { return nil }
        }

        // UpRight / UpLeft は最初のセグメントが優勢に上向きであること
        if bestName == "UpRight" || bestName == "UpLeft" {
            guard isDominantlyUpward(raw) else { return nil }
        }

        return score >= matchScoreThreshold ? GestureResult(name: bestName, score: score) : nil
    }

    /// HUD 用：しきい値に関係なく現在の最良一致を返す
    func bestMatch(points raw: [CGPoint]) -> GestureResult? {
        guard raw.count >= 5 else { return nil }
        let pts = normalize(raw)
        let best = bestTemplateMatch(for: pts)
        if let name = best.name { return GestureResult(name: name, score: max(0, min(1, best.score))) }
        return nil
    }

    // MARK: - Matching core
    private func bestTemplateMatch(for pts: [CGPoint]) -> (name: String?, score: CGFloat) {
        var bestName: String? = nil
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for tpl in templates {
            let d = pathDistance(pts, tpl.points)
            if d < bestDistance { bestDistance = d; bestName = tpl.name }
        }
        let halfDiag = 0.5 * sqrt(2) * squareSize
        let score = 1 - (bestDistance / halfDiag)
        return (bestName, max(0, min(1, score)))
    }

    // MARK: - $1 steps (rotation 無効)
    private func normalize(_ raw: [CGPoint]) -> [CGPoint] {
        var pts = resample(raw, n: resampleCount)
        if rotationInvariant {
            let c = centroid(pts)
            let theta = atan2(pts[0].y - c.y, pts[0].x - c.x)
            pts = rotate(pts, by: -theta)
        }
        pts = scaleToSquare(pts, size: squareSize)
        pts = translateToOrigin(pts)
        return pts
    }

    private func resample(_ points: [CGPoint], n: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let I = pathLength(points) / CGFloat(n - 1)
        var D: CGFloat = 0
        var newPts: [CGPoint] = [points.first!]
        var pts = points
        var i = 1
        while i < pts.count {
            let d = distance(pts[i - 1], pts[i])
            if (D + d) >= I {
                let t = (I - D) / d
                let nx = pts[i - 1].x + t * (pts[i].x - pts[i - 1].x)
                let ny = pts[i - 1].y + t * (pts[i].y - pts[i - 1].y)
                let q = CGPoint(x: nx, y: ny)
                newPts.append(q)
                pts.insert(q, at: i)
                D = 0
            } else {
                D += d
                i += 1
            }
        }
        if newPts.count == n - 1 { newPts.append(pts.last!) }
        return newPts
    }

    private func rotate(_ pts: [CGPoint], by radians: CGFloat) -> [CGPoint] {
        let c = centroid(pts)
        return pts.map { p in
            let qx = (p.x - c.x) * cos(radians) - (p.y - c.y) * sin(radians) + c.x
            let qy = (p.x - c.x) * sin(radians) + (p.y - c.y) * cos(radians) + c.y
            return CGPoint(x: qx, y: qy)
        }
    }

    private func scaleToSquare(_ pts: [CGPoint], size: CGFloat) -> [CGPoint] {
        let (minX, minY, maxX, maxY) = boundingBox(pts)
        let w = maxX - minX
        let h = maxY - minY
        let scale = max(w, h)
        guard scale > 0 else { return pts }
        return pts.map { CGPoint(x: ($0.x - minX) / scale * size, y: ($0.y - minY) / scale * size) }
    }

    private func translateToOrigin(_ pts: [CGPoint]) -> [CGPoint] {
        let c = centroid(pts)
        return pts.map { CGPoint(x: $0.x - c.x, y: $0.y - c.y) }
    }

    private func pathDistance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        precondition(a.count == b.count)
        var d: CGFloat = 0
        for i in 0..<a.count { d += distance(a[i], b[i]) }
        return d / CGFloat(a.count)
    }

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        var x: CGFloat = 0, y: CGFloat = 0
        for p in pts { x += p.x; y += p.y }
        return CGPoint(x: x / CGFloat(pts.count), y: y / CGFloat(pts.count))
    }

    private func boundingBox(_ pts: [CGPoint]) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return (minX, minY, maxX, maxY)
    }

    private func pathLength(_ pts: [CGPoint]) -> CGFloat {
        var d: CGFloat = 0
        for i in 1..<pts.count { d += distance(pts[i - 1], pts[i]) }
        return d
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    // 総回転角（絶対値）
    private func totalTurningAngle(points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var angleSum: CGFloat = 0
        for i in 2..<points.count {
            let v1 = CGVector(dx: points[i - 1].x - points[i - 2].x, dy: points[i - 1].y - points[i - 2].y)
            let v2 = CGVector(dx: points[i].x - points[i - 1].x, dy: points[i].y - points[i - 1].y)
            let a1 = atan2(v1.dy, v1.dx)
            let a2 = atan2(v2.dy, v2.dx)
            var da = a2 - a1
            // wrap to [-pi, pi]
            while da > .pi { da -= 2 * .pi }
            while da < -.pi { da += 2 * .pi }
            angleSum += abs(da)
        }
        return angleSum
    }

    // 最初の区間が優勢に上方向かどうか
    private func isDominantlyUpward(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 5 else { return false }
        let endIndex = max(2, raw.count / 5)
        let dx = raw[endIndex].x - raw[0].x
        let dy = raw[endIndex].y - raw[0].y
        return dy > 0 && abs(dy) > abs(dx) * dominanceRatio
    }
}

// MARK: - Canonical Templates
extension GestureRecognizer {
    static func canonicalTemplates() -> [GestureTemplate] {
        // 直線補助
        func line(from: CGPoint, to: CGPoint, steps: Int = 32) -> [CGPoint] {
            (0...steps).map { i in
                let t = CGFloat(i) / CGFloat(steps)
                return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            }
        }
        func poly(_ pts: [CGPoint]) -> [CGPoint] { pts }

        // Left/Right: 水平線
        let left = line(from: CGPoint(x: 200, y: 125), to: CGPoint(x: 50, y: 125))
        let right = line(from: CGPoint(x: 50, y: 125), to: CGPoint(x: 200, y: 125))

        // L: 縦下→横右（およびその逆順）
        let L_vert_then_horiz = poly(line(from: CGPoint(x: 60, y: 200), to: CGPoint(x: 60, y: 60)) + line(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 200, y: 60)))
        let L_horiz_then_vert = poly(line(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 200, y: 60)) + line(from: CGPoint(x: 60, y: 200), to: CGPoint(x: 60, y: 60)))

        // U: 上左→下→右→上（鏡像も許可）
        let U_right = poly(line(from: CGPoint(x: 60, y: 200), to: CGPoint(x: 60, y: 60)) + line(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 200, y: 60)) + line(from: CGPoint(x: 200, y: 60), to: CGPoint(x: 200, y: 200)))
        let U_left  = poly(line(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 200, y: 60)) + line(from: CGPoint(x: 200, y: 60), to: CGPoint(x: 60, y: 60)) + line(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 60, y: 200)))

        // UpRight / UpLeft
        let upRight = poly(line(from: CGPoint(x: 125, y: 50), to: CGPoint(x: 125, y: 200)) + line(from: CGPoint(x: 125, y: 200), to: CGPoint(x: 220, y: 200)))
        let upLeft  = poly(line(from: CGPoint(x: 125, y: 50), to: CGPoint(x: 125, y: 200)) + line(from: CGPoint(x: 125, y: 200), to: CGPoint(x: 30, y: 200)))

        // Circle O / Double O（OO は 2 周連続）
        func circle(center: CGPoint, radius: CGFloat, segments: Int = 64) -> [CGPoint] {
            (0...segments).map { i in
                let t = CGFloat(i) / CGFloat(segments) * 2 * .pi
                return CGPoint(x: center.x + radius * cos(t), y: center.y + radius * sin(t))
            }
        }
        let O = circle(center: CGPoint(x: 125, y: 125), radius: 70)
        let OO = O + O

        // S カーブ（近似）
        let Sshape: [CGPoint] = [
            CGPoint(x: 40, y: 190), CGPoint(x: 80, y: 210), CGPoint(x: 120, y: 190), CGPoint(x: 160, y: 170), CGPoint(x: 200, y: 190),
            CGPoint(x: 160, y: 110), CGPoint(x: 120, y: 130), CGPoint(x: 80, y: 110), CGPoint(x: 40, y: 90)
        ]

        return [
            GestureTemplate(name: "Left", points: left),
            GestureTemplate(name: "Right", points: right),
            GestureTemplate(name: "L", points: L_vert_then_horiz),
            GestureTemplate(name: "L", points: L_horiz_then_vert),
            GestureTemplate(name: "U", points: U_right),
            GestureTemplate(name: "U", points: U_left),
            GestureTemplate(name: "UpRight", points: upRight),
            GestureTemplate(name: "UpLeft", points: upLeft),
            GestureTemplate(name: "O", points: O),
            GestureTemplate(name: "OO", points: OO),
            GestureTemplate(name: "S", points: Sshape)
        ]
    }
}
