import Foundation

struct OpenUIRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var area: Double { width * height }
}

struct OpenUITreemapTile: Equatable, Sendable {
    let row: OpenUITreemapRow
    let rect: OpenUIRect
    let colorLevel: Double
}

enum OpenUITreemapLayout {
    static func tiles(_ rows: [OpenUITreemapRow], in bounds: OpenUIRect) -> [OpenUITreemapTile] {
        let positive = rows.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = positive.reduce(0) { $0 + $1.size }
        guard total > 0, bounds.area > 0 else { return [] }
        let colors = positive.map(\.color)
        let low = colors.min() ?? 0, high = colors.max() ?? 0
        func level(_ value: Double) -> Double { high > low ? (value - low) / (high - low) : 0.5 }
        let scale = bounds.area / total
        var tiles: [OpenUITreemapTile] = []
        var remaining = bounds
        var pending = positive[...]
        while !pending.isEmpty {
            let side = min(remaining.width, remaining.height)
            var strip: [OpenUITreemapRow] = []
            var bestWorst = Double.infinity
            while let next = pending.first {
                let candidate = strip + [next]
                let worst = worstRatio(candidate.map { $0.size * scale }, side: side)
                if !strip.isEmpty && worst > bestWorst { break }
                strip = candidate
                bestWorst = worst
                pending = pending.dropFirst()
            }
            let stripArea = strip.reduce(0) { $0 + $1.size * scale }
            let horizontal = remaining.width >= remaining.height
            let thickness = side > 0 ? stripArea / side : 0
            var offset = 0.0
            for row in strip {
                let length = thickness > 0 ? row.size * scale / thickness : 0
                let rect = horizontal
                    ? OpenUIRect(x: remaining.x, y: remaining.y + offset, width: thickness, height: length)
                    : OpenUIRect(x: remaining.x + offset, y: remaining.y, width: length, height: thickness)
                tiles.append(OpenUITreemapTile(row: row, rect: rect, colorLevel: level(row.color)))
                offset += length
            }
            remaining = horizontal
                ? OpenUIRect(x: remaining.x + thickness, y: remaining.y, width: max(remaining.width - thickness, 0), height: remaining.height)
                : OpenUIRect(x: remaining.x, y: remaining.y + thickness, width: remaining.width, height: max(remaining.height - thickness, 0))
        }
        return tiles
    }

    private static func worstRatio(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0, let largest = areas.max(), let smallest = areas.min(), smallest > 0 else { return .infinity }
        let squared = side * side
        return max(squared * largest / (sum * sum), (sum * sum) / (squared * smallest))
    }
}
