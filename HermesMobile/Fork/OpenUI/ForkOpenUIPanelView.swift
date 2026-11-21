import Charts
import SwiftUI

struct ForkOpenUIPanelView: View {
    let panel: OpenUIPanel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: panel.title).font(AppFont.subheadline(weight: .semibold))
            content
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .stat(_, let value, let detail): stat(value, detail)
        case .bars(_, let unit, let bars): barChart(unit, bars)
        case .series(let kind, _, let unit, let categories, let series):
            ForkOpenUISeriesChart(kind: kind, unit: unit, categories: categories, series: series).frame(height: 200)
        case .table(_, let columns, let rows): table(columns, rows)
        case .treemap(_, let sizeLabel, let colorLabel, let rows):
            ForkOpenUITreemap(rows: rows).frame(height: 220).accessibilityLabel(Text(verbatim: "\(sizeLabel), \(colorLabel)"))
        case .heatmap(_, let unit, let rows, let columns, let counts): heatmap(unit, rows, columns, counts)
        case .unsupported: EmptyView()
        }
    }

    private func stat(_ value: OpenUICell, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: Self.format(value)).font(AppFont.title(weight: .semibold)).monospacedDigit()
            if let detail { Text(verbatim: detail).font(AppFont.footnote()).foregroundStyle(.appSecondary) }
        }
    }

    private func barChart(_ unit: String, _ bars: [(label: String, value: Double)]) -> some View {
        let axis = unit.isEmpty ? "Value" : unit
        return Chart(bars.indices, id: \.self) { index in
            BarMark(x: .value(axis, bars[index].value), y: .value("Label", bars[index].label))
                .foregroundStyle(Color.accentColor)
        }
        .frame(height: CGFloat(max(bars.count, 2)) * 28)
    }

    private func table(_ columns: [String], _ rows: [[OpenUICell]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(columns.indices, id: \.self) { index in
                        Text(verbatim: columns[index]).font(AppFont.caption(weight: .semibold)).foregroundStyle(.appSecondary)
                    }
                }
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row].indices, id: \.self) { column in
                            Text(verbatim: Self.format(rows[row][column])).font(AppFont.footnote()).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func heatmap(_ unit: String, _ rows: [String], _ columns: [String], _ counts: [[Double]]) -> some View {
        let legend = unit.isEmpty ? "Count" : unit
        let cells = rows.indices.flatMap { row in columns.indices.map { (row: row, column: $0) } }
        return Chart(cells.indices, id: \.self) { index in
            let cell = cells[index]
            RectangleMark(x: .value("Column", columns[cell.column]), y: .value("Row", rows[cell.row]))
                .foregroundStyle(by: .value(legend, counts[cell.row][cell.column]))
        }
        .chartForegroundStyleScale(range: Gradient(colors: [Color(.appFillTertiary), Color.accentColor]))
        .frame(height: CGFloat(max(rows.count, 2)) * 26 + 30)
    }

    static func format(_ cell: OpenUICell) -> String {
        switch cell {
        case .text(let text): text
        case .number(let number): number.formatted(.number.precision(.fractionLength(0...2)))
        }
    }
}

private struct ForkOpenUISeriesChart: View {
    let kind: OpenUISeriesKind
    let unit: String
    let categories: [String]
    let series: [OpenUISeries]

    var body: some View {
        Chart(points, id: \.self) { point in
            mark(point)
        }
        .chartLegend(series.count > 1 ? .visible : .hidden)
    }

    private var points: [ForkOpenUIPoint] {
        series.indices.flatMap { row in categories.indices.map { ForkOpenUIPoint(series: row, category: $0) } }
    }

    @ChartContentBuilder
    private func mark(_ point: ForkOpenUIPoint) -> some ChartContent {
        let name = series[point.series].name
        let x = PlottableValue.value("Category", categories[point.category])
        let y = PlottableValue.value(unit.isEmpty ? "Value" : unit, series[point.series].values[point.category])
        switch kind {
        case .line:
            LineMark(x: x, y: y).foregroundStyle(by: .value("Series", name)).symbol(by: .value("Series", name))
        case .stackedArea:
            AreaMark(x: x, y: y, stacking: .standard).foregroundStyle(by: .value("Series", name))
        case .stackedBar:
            BarMark(x: x, y: y, stacking: .standard).foregroundStyle(by: .value("Series", name))
        }
    }
}

private struct ForkOpenUIPoint: Hashable {
    let series: Int
    let category: Int
}

private struct ForkOpenUITreemap: View {
    let rows: [OpenUITreemapRow]

    var body: some View {
        GeometryReader { proxy in
            let tiles = OpenUITreemapLayout.tiles(rows, in: OpenUIRect(x: 0, y: 0, width: proxy.size.width, height: proxy.size.height))
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25 + 0.65 * tile.colorLevel))
                        .overlay(alignment: .topLeading) {
                            if tile.rect.width > 56, tile.rect.height > 22 {
                                Text(verbatim: tile.row.path.split(separator: "/").last.map(String.init) ?? tile.row.path)
                                    .font(AppFont.caption2())
                                    .lineLimit(1)
                                    .padding(4)
                            }
                        }
                        .overlay(Rectangle().strokeBorder(Color(.appSurface), lineWidth: 1))
                        .frame(width: max(tile.rect.width, 0), height: max(tile.rect.height, 0))
                        .offset(x: tile.rect.x, y: tile.rect.y)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "\(tile.row.path): \(tile.row.size.formatted())"))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
