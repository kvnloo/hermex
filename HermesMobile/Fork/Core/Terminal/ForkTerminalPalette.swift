import Foundation

enum ForkTerminalPalette {
    private static let basic: [(Int, Int, Int)] = [
        (0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16), (36, 114, 200), (188, 63, 188), (17, 168, 205), (229, 229, 229),
        (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67), (59, 142, 234), (214, 112, 214), (41, 184, 219), (255, 255, 255),
    ]

    static func rgb(_ index: Int) -> (red: Int, green: Int, blue: Int) {
        let index = min(max(index, 0), 255)
        if index < 16 { return basic[index] }
        if index >= 232 {
            let level = 8 + (index - 232) * 10
            return (level, level, level)
        }
        let cube = index - 16
        func step(_ value: Int) -> Int { value == 0 ? 0 : 55 + value * 40 }
        return (step(cube / 36), step((cube / 6) % 6), step(cube % 6))
    }
}
