// Moods — the school's shared behaviour. Now and then the koi gather and circle
// together, or settle down and rest; and sometimes two koi chase each other.

import SpriteKit

final class KoiMoods {
    private enum Mood { case roam, gather, rest }

    private var mood = Mood.roam
    private var moodLeft = CGFloat.random(in: 30...60)
    private var centre = CGPoint.zero
    private var centreHeading = CGFloat.random(in: 0..<(2 * .pi))
    private var orbit: CGFloat = 0
    private var calm: CGFloat = 1   // eased speed multiplier (rest slows everyone down)

    private var chaseLeft: CGFloat = 0
    private var nextChase = CGFloat.random(in: 15...40)
    private weak var chaser: Koi?
    private weak var leader: Koi?

    func update(dt: CGFloat, koi: [Koi], bounds: CGRect, unit u: CGFloat, moods: Bool, chase: Bool) {
        updateMood(dt: dt, koi: koi, bounds: bounds, unit: u, on: moods)
        updateChase(dt: dt, koi: koi, on: chase)
    }

    // MARK: Moods

    private func updateMood(dt: CGFloat, koi: [Koi], bounds: CGRect, unit u: CGFloat, on: Bool) {
        if !on, mood != .roam { begin(.roam, koi: koi, bounds: bounds) }
        moodLeft -= dt
        if on, moodLeft <= 0 {
            // Roaming most of the time, with a gathering or a rest in between.
            begin(mood == .roam ? (Bool.random() ? .gather : .rest) : .roam, koi: koi, bounds: bounds)
        }

        let targetCalm: CGFloat = mood == .rest ? 0.4 : 1
        calm += (targetCalm - calm) * min(1, dt * 0.4)

        switch mood {
        case .gather:
            // The gathering point wanders slowly; koi hold places on a turning ring around it.
            centreHeading += sin(orbit * 0.7) * 0.2 * dt
            centre.x += cos(centreHeading) * 18 * u * dt
            centre.y += sin(centreHeading) * 18 * u * dt
            let area = bounds.insetBy(dx: bounds.width * 0.25, dy: bounds.height * 0.25)
            if !area.contains(centre) {
                centreHeading = atan2(bounds.midY - centre.y, bounds.midX - centre.x)
            }
            orbit += dt * 0.35
            let radius = (70 + 22 * CGFloat(koi.count)) * u
            for (k, fish) in koi.enumerated() {
                let a = orbit + CGFloat(k) / CGFloat(max(1, koi.count)) * 2 * .pi
                fish.goal = CGPoint(x: centre.x + cos(a) * radius, y: centre.y + sin(a) * radius * 0.7)
                fish.goalWeight = 1.1
                fish.speedScale = calm
                fish.wanderScale = 0.4
            }
        case .roam, .rest:
            for fish in koi {
                fish.goal = nil
                fish.speedScale = calm
                fish.wanderScale = mood == .rest ? 0.35 : 1
            }
        }
    }

    private func begin(_ m: Mood, koi: [Koi], bounds: CGRect) {
        mood = m
        switch m {
        case .roam: moodLeft = .random(in: 40...80)
        case .gather:
            moodLeft = .random(in: 20...35)
            // Start where the school already is, so nobody crosses the whole screen.
            let n = CGFloat(max(1, koi.count))
            centre = CGPoint(x: koi.map(\.head.x).reduce(0, +) / n, y: koi.map(\.head.y).reduce(0, +) / n)
            let area = bounds.insetBy(dx: bounds.width * 0.25, dy: bounds.height * 0.25)
            centre = CGPoint(x: min(max(centre.x, area.minX), area.maxX), y: min(max(centre.y, area.minY), area.maxY))
        case .rest: moodLeft = .random(in: 20...35)
        }
    }

    // MARK: Chasing

    private func updateChase(dt: CGFloat, koi: [Koi], on: Bool) {
        if chaseLeft > 0 {
            chaseLeft -= dt
            if chaseLeft <= 0 || !on || chaser == nil || leader == nil { endChase() }
            return
        }
        guard on, koi.count >= 2, mood != .rest else { return }
        nextChase -= dt
        guard nextChase <= 0 else { return }
        nextChase = .random(in: 25...60)
        // A pair that's reasonably close, and not busy with food.
        let free = koi.filter { !$0.isBusy }
        var best: (Koi, Koi)?
        var bestDist = CGFloat.infinity
        for a in free {
            for b in free where a !== b {
                let d = hypot(a.head.x - b.head.x, a.head.y - b.head.y)
                if d < bestDist { bestDist = d; best = (a, b) }
            }
        }
        guard let (a, b) = best else { return }
        chaser = a
        leader = b
        a.chasing = b
        b.fleeing = true
        chaseLeft = .random(in: 4...7)
    }

    private func endChase() {
        chaser?.chasing = nil
        leader?.fleeing = false
        chaser = nil
        leader = nil
        chaseLeft = 0
    }
}
