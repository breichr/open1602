/// Waren, die für das Bauen gebraucht werden (die übrigen kommen mit der Wirtschaft in M5).
public enum Ware: String, Sendable, CaseIterable {
    case wood = "HOLZ"
    case tools = "WERKZEUG"
    case bricks = "ZIEGEL"
    case food = "NAHRUNG"
    case cannons = "KANONEN"
}

/// Lagerbestand (Schiffsladung oder Kontor).
public struct Stock: Sendable, Equatable {
    public private(set) var amounts: [Ware: Int] = [:]

    public init(_ amounts: [Ware: Int] = [:]) { self.amounts = amounts }

    public subscript(ware: Ware) -> Int {
        get { amounts[ware] ?? 0 }
        set { amounts[ware] = max(newValue, 0) }
    }

    public mutating func add(_ other: Stock) {
        for (ware, amount) in other.amounts { self[ware] += amount }
    }
}
