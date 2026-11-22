struct LiveLaneRouter: Equatable, Sendable {
    struct Turn: Equatable, Sendable {
        let lane: Int
        fileprivate let serial: Int
    }

    static let root = 0
    static let capacity = 5
    private(set) var lanes = [root]
    private(set) var selected = root
    private(set) var pending: Turn?
    private var nextLane = 1
    private var nextTurn = 0

    var canAttach: Bool { pending == nil && lanes.count < Self.capacity }

    mutating func attach() -> Int? {
        guard canAttach else { return nil }
        let lane = nextLane
        nextLane += 1
        lanes.append(lane)
        selected = lane
        return lane
    }

    mutating func select(_ lane: Int) -> Bool {
        guard pending == nil, lane != selected, lanes.contains(lane) else { return false }
        selected = lane
        return true
    }

    mutating func detachSelected() -> Int? {
        guard pending == nil, selected != Self.root else { return nil }
        let lane = selected
        lanes.removeAll { $0 == lane }
        selected = Self.root
        return lane
    }

    mutating func beginTurn() -> Turn? {
        guard pending == nil else { return nil }
        nextTurn += 1
        let turn = Turn(lane: selected, serial: nextTurn)
        pending = turn
        return turn
    }

    mutating func finish(_ turn: Turn) -> Bool {
        guard pending == turn else { return false }
        pending = nil
        return true
    }
}
