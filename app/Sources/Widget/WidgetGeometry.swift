import Foundation

struct WidgetGeometry {
    var width: Double
    var height: Double
    var left: Double
    var top: Double
    var locked: Bool
    var fillsLeftSide = false
    var reservedBottom: Double = 0

    static func fullHeightFrame(in area: CGRect, width: CGFloat) -> CGRect {
        let margin: CGFloat = 10
        let width = min(max(width, 300), area.width - 2 * margin)
        return CGRect(x: area.minX + margin, y: area.minY + margin,
                      width: width, height: area.height - 2 * margin)
    }

    static func availableFrame(in area: CGRect, width: CGFloat, widgets: [CGRect]?, reservedBottom: CGFloat = 0) -> CGRect? {
        guard widgets != nil || reservedBottom > 0 else { return nil }
        var column = fullHeightFrame(in: area, width: width)
        let reserve = min(max(reservedBottom.isFinite ? reservedBottom : 0, 0), column.height)
        column.origin.y += reserve
        column.size.height -= reserve
        let gap: CGFloat = 16
        let obstacles = (widgets ?? []).filter { $0.intersects(column) }.sorted { $0.maxY > $1.maxY }
        var ceiling = column.maxY
        for obstacle in obstacles {
            let floor = max(column.minY, obstacle.maxY + gap)
            if ceiling - floor >= 320 {
                return CGRect(x: column.minX, y: floor, width: column.width, height: ceiling - floor)
            }
            ceiling = min(ceiling, obstacle.minY - gap)
        }
        guard ceiling - column.minY >= 320 else { return nil }
        return CGRect(x: column.minX, y: column.minY, width: column.width, height: ceiling - column.minY)
    }

    static func fittedFrame(_ value: WidgetGeometry, in area: CGRect, minimum: NSSize, maximum: NSSize) -> CGRect {
        func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
            min(max(value.isFinite ? value : lower, lower), upper)
        }
        let width = clamp(value.width, min(minimum.width, area.width), min(maximum.width, area.width))
        let height = clamp(value.height, min(minimum.height, area.height), min(maximum.height, area.height))
        let left = clamp(value.left, 0, area.width - width)
        let top = clamp(value.top, 0, area.height - height)
        return CGRect(x: area.minX + left, y: area.maxY - top - height, width: width, height: height)
    }
}
