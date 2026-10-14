import AnnoFormats
import AnnoRender
import simd

/// Hirsche, die gemächlich über die Insel ziehen und grasen.
@MainActor
final class Herd {
    struct Deer {
        var position: SIMD2<Float>
        var target: SIMD2<Float>
        var heading = SIMD2<Float>(1, 0)
        var idle: Double
    }

    private(set) var deer: [Deer]
    private var rng: SeededRandom
    private let walkable: (Int, Int) -> Bool

    /// Laufgeschwindigkeit in Feldern pro Sekunde.
    static let speed: Float = 0.7
    /// Bildnummern in `TIERE.BSH` (aus `figuren.cod`, Figur `HIRSCH`).
    static let gfx = 304
    static let walkFrames = 8, walkTime = 135
    static let grazeOffset = 112, grazeFrames = 6, grazeTime = 130

    init(positions: [SIMD2<Float>], seed: UInt64, walkable: @escaping (Int, Int) -> Bool) {
        rng = SeededRandom(seed: seed)
        self.walkable = walkable
        deer = positions.map { Deer(position: $0, target: $0, idle: 0) }
        for i in deer.indices { deer[i].idle = Double.random(in: 0...4, using: &rng) }
    }

    func update(dt: Double) {
        for i in deer.indices {
            if deer[i].idle > 0 {
                deer[i].idle -= dt
                if deer[i].idle <= 0 { pickTarget(i) }
                continue
            }
            let delta = deer[i].target - deer[i].position
            let distance = simd_length(delta)
            let step = Self.speed * Float(dt)
            if distance <= step {
                deer[i].position = deer[i].target
                deer[i].idle = Double.random(in: 2...7, using: &rng)
            } else {
                deer[i].heading = delta / distance
                deer[i].position += deer[i].heading * step
            }
        }
    }

    private func pickTarget(_ i: Int) {
        let from = deer[i].position
        for _ in 0..<8 {
            let offset = SIMD2(Float(Int.random(in: -3...3, using: &rng)), Float(Int.random(in: -3...3, using: &rng)))
            let target = from + offset
            let mid = from + offset / 2
            if walkable(Int(target.x.rounded(.down)), Int(target.y.rounded(.down)))
                && walkable(Int(mid.x.rounded(.down)), Int(mid.y.rounded(.down)))
            {
                deer[i].target = target
                return
            }
        }
        deer[i].idle = 2
    }

    func figures(layout: IsometricLayout, library: SpriteLibrary, timeMs: Int) -> [FigureSprite] {
        let zoom = layout.zoom
        return deer.enumerated().compactMap { i, d in
            let direction = screenDirection(of: d.heading, layout: layout)
            let walking = d.idle <= 0
            let local =
                walking
                ? Self.gfx + direction * Self.walkFrames + (timeMs / Self.walkTime + i) % Self.walkFrames
                : Self.gfx + Self.grazeOffset + direction * Self.grazeFrames + (timeMs / Self.grazeTime + i) % Self.grazeFrames
            let index = library.index("TIERE", local)
            guard let size = library.size(of: index) else { return nil }
            return FigureSprite(
                position: d.position, index: index,
                anchor: SIMD2(Float(size.width) / 2, Float(size.height) - Float(zoom.scaled(10))),
                elevation: Float(zoom.scaledElevation(20)))
        }
    }

    /// Felder, auf denen Hirsche laufen dürfen.
    static func isPasture(_ tile: IslandTile?) -> Bool {
        guard let kind = tile?.building.kind else { return false }
        return kind == "BODEN" || kind == "WALD"
    }
}
