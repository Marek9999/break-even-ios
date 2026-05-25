//
//  BuoyancyPhysicsEngine.swift
//  PayUp
//
//  Physics engine for floating bubbles that rise from below, collide,
//  and settle against a top "ceiling". Modeled on BubblePhysicsEngine
//  but uses constant upward buoyancy + axis-aligned walls instead of
//  radial center pull.
//

import SwiftUI
import QuartzCore

@Observable
final class BuoyancyPhysicsEngine {

    /// Visual shape of a bubble. Physics always uses the spec's `radius` for
    /// collisions/walls, so a rounded-rect bubble is treated identically to a
    /// circular one (its `radius` is the circumscribed radius).
    enum BubbleShape {
        case circle
        /// Continuous rounded rectangle of the given side length. Corner radius
        /// defaults to a generous "squircle" curvature.
        case roundedRect(side: CGFloat, cornerRadius: CGFloat)
    }

    struct BubbleSpec: Identifiable {
        let id: String
        let radius: CGFloat
        let color: Color
        var shape: BubbleShape = .circle
        /// Optional emoji rendered inside the bubble. When set, replaces the
        /// solid color fill; a softly blurred copy is layered behind the crisp
        /// emoji to add depth.
        var emoji: String? = nil
        /// Optional asset image rendered inside the bubble. When set, it takes
        /// precedence over `emoji` and fills the bubble's visual shape.
        var imageName: String? = nil
        /// Optional rest target as a fraction of container height (0 = top,
        /// 1 = bottom). When set, the particle is pulled toward this Y with
        /// a spring force instead of receiving upward buoyancy, so it locks
        /// in at that vertical position instead of rising to the ceiling.
        var relativeTargetY: CGFloat? = nil
        /// Optional rest target as a fraction of container width (0 = left,
        /// 1 = right). When set, the particle is pulled horizontally toward
        /// this X via a spring force.
        var relativeTargetX: CGFloat? = nil
    }

    struct Particle {
        var id: String
        var position: CGPoint
        var velocity: CGPoint = .zero
        var radius: CGFloat
        var isDragging: Bool = false
        var dragTarget: CGPoint = .zero
        /// Multiplier applied to the engine's global buoyancy. Use < 1 to make a
        /// particle float slowly upward instead of cruising at full speed.
        var buoyancyMultiplier: CGFloat = 1.0
        /// Optional per-particle damping that overrides the engine default. Lower values
        /// (further below 1) shed velocity faster, useful for "shoot fast then settle" feel.
        var dampingOverride: CGFloat? = nil
        /// Optional absolute target Y. When non-nil, buoyancy is replaced with a
        /// spring force pulling the particle to this Y so it locks in mid-screen
        /// instead of floating to the top.
        var targetY: CGFloat? = nil
        /// Optional absolute target X for horizontal spring locking.
        var targetX: CGFloat? = nil
    }

    // MARK: - Physics Constants

    private let buoyancy: CGFloat = -2400.0         // upward acceleration (negative y is up in screen space)
    private let horizontalDamping: CGFloat = 1.4    // damps lateral drift
    private let collisionStiffness: CGFloat = 364.4
    private let damping: CGFloat = 0.97             // less drag so they coast upward longer
    private let velocityThreshold: CGFloat = 1.2
    private let collisionPadding: CGFloat = 6.0
    private let wallRestitution: CGFloat = 0.12     // soft thunk against ceiling/walls

    // Drag constants (copied from BubblePhysicsEngine)
    private let dragFollowSpeed: CGFloat = 0.39

    // Smoothing
    private let positionSmoothing: CGFloat = 0.3
    private let velocitySmoothing: CGFloat = 0.30

    // MARK: - State

    private(set) var particles: [Particle] = []
    private var displayLink: CADisplayLink?
    private var containerSize: CGSize = .zero
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var lastUpdateTime: CFTimeInterval = 0
    private var isSimulating: Bool = false
    private var smoothedPositions: [String: CGPoint] = [:]

    // MARK: - Public Interface

    /// Adds a single bubble shot from below the container. Use this for
    /// the staggered onboarding cannon effect (one bubble per haptic).
    func shootSingle(
        spec: BubbleSpec,
        in containerSize: CGSize,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        verticalVelocityRange: ClosedRange<CGFloat> = -1400 ... -1000,
        horizontalVelocityRange: ClosedRange<CGFloat> = -90 ... 90,
        buoyancyMultiplier: CGFloat = 1.0,
        dampingOverride: CGFloat? = nil,
        targetY: CGFloat? = nil,
        targetX: CGFloat? = nil
    ) {
        self.containerSize = containerSize
        self.topInset = topInset
        self.bottomInset = bottomInset

        let r = spec.radius
        let safeWidth = max(containerSize.width, 1)
        // If a horizontal target is supplied, launch from that column and
        // skip the random lateral velocity so the particle rises straight up.
        let x = targetX.map { min(max($0, r), safeWidth - r) }
            ?? CGFloat.random(in: r...max(safeWidth - r, r))
        let y = containerSize.height + r
        let initialVy = CGFloat.random(in: verticalVelocityRange)
        let initialVx = targetX == nil ? CGFloat.random(in: horizontalVelocityRange) : 0

        let particle = Particle(
            id: spec.id,
            position: CGPoint(x: x, y: y),
            velocity: CGPoint(x: initialVx, y: initialVy),
            radius: r,
            buoyancyMultiplier: buoyancyMultiplier,
            dampingOverride: dampingOverride,
            targetY: targetY,
            targetX: targetX
        )

        if let index = particles.firstIndex(where: { $0.id == spec.id }) {
            particles[index] = particle
        } else {
            particles.append(particle)
        }
        smoothedPositions[spec.id] = particle.position

        startSimulation()
    }

    func updateContainer(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        self.containerSize = size
        self.topInset = topInset
        self.bottomInset = bottomInset
    }

    func position(for id: String) -> CGPoint? {
        if let smoothed = smoothedPositions[id] {
            return smoothed
        }
        return particles.first { $0.id == id }?.position
    }

    // MARK: - Drag

    func startDrag(id: String, to position: CGPoint) {
        guard let index = particles.firstIndex(where: { $0.id == id }) else { return }
        particles[index].isDragging = true
        particles[index].dragTarget = position
        if smoothedPositions[id] == nil {
            smoothedPositions[id] = particles[index].position
        }
        startSimulation()
    }

    func updateDrag(id: String, to position: CGPoint) {
        guard let index = particles.firstIndex(where: { $0.id == id }),
              particles[index].isDragging else { return }
        particles[index].dragTarget = position
    }

    func endDrag(id: String) {
        guard let index = particles.firstIndex(where: { $0.id == id }) else { return }
        particles[index].isDragging = false
        particles[index].velocity = .zero
        startSimulation()
    }

    // MARK: - Simulation Control

    private func startSimulation() {
        guard !isSimulating else { return }
        isSimulating = true
        lastUpdateTime = CACurrentMediaTime()

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopSimulation() {
        displayLink?.invalidate()
        displayLink = nil
        isSimulating = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let currentTime = link.timestamp
        let deltaTime = min(CGFloat(currentTime - lastUpdateTime), 0.032)
        lastUpdateTime = currentTime

        guard deltaTime > 0 else { return }
        physicsStep(deltaTime: deltaTime)
    }

    // MARK: - Physics Step

    private func physicsStep(deltaTime: CGFloat) {
        let count = particles.count
        guard count > 0 else {
            stopSimulation()
            return
        }

        // 1. Dragged particles smoothly follow finger.
        for i in 0..<count where particles[i].isDragging {
            let target = particles[i].dragTarget
            let current = particles[i].position
            particles[i].position = CGPoint(
                x: lerp(current.x, target.x, dragFollowSpeed),
                y: lerp(current.y, target.y, dragFollowSpeed)
            )
        }

        // 2. Apply buoyancy (or spring-to-target) + horizontal damping
        //    to non-dragged particles.
        // Spring constants for particles with a `targetY`.
        let targetSpring: CGFloat = 60.0     // pull strength toward target Y
        let targetDamping: CGFloat = 6.0     // velocity damping along Y near target

        for i in 0..<count where !particles[i].isDragging {
            if let targetY = particles[i].targetY {
                let dy = targetY - particles[i].position.y
                let accel = targetSpring * dy - targetDamping * particles[i].velocity.y
                let newVy = particles[i].velocity.y + accel * deltaTime
                particles[i].velocity.y = lerp(particles[i].velocity.y, newVy, velocitySmoothing)
            } else {
                let particleBuoyancy = buoyancy * particles[i].buoyancyMultiplier
                let newVy = particles[i].velocity.y + particleBuoyancy * deltaTime
                particles[i].velocity.y = lerp(particles[i].velocity.y, newVy, velocitySmoothing)
            }
            if let targetX = particles[i].targetX {
                let dx = targetX - particles[i].position.x
                let accelX = targetSpring * dx - targetDamping * particles[i].velocity.x
                let newVx = particles[i].velocity.x + accelX * deltaTime
                particles[i].velocity.x = lerp(particles[i].velocity.x, newVx, velocitySmoothing)
            } else {
                particles[i].velocity.x *= max(0, 1 - horizontalDamping * deltaTime)
            }
        }

        // 3. Pairwise collisions.
        for i in 0..<count {
            for j in (i + 1)..<count {
                applyCollision(between: i, and: j, deltaTime: deltaTime)
            }
        }

        // 4. Integrate + damping + walls.
        var allSettled = true

        for i in 0..<count where !particles[i].isDragging {
            let effectiveDamping = particles[i].dampingOverride ?? damping
            particles[i].velocity.x *= effectiveDamping
            particles[i].velocity.y *= effectiveDamping

            particles[i].position.x += particles[i].velocity.x * deltaTime
            particles[i].position.y += particles[i].velocity.y * deltaTime

            clampToWalls(index: i)

            let speed = hypot(particles[i].velocity.x, particles[i].velocity.y)
            if speed > velocityThreshold {
                allSettled = false
            }
        }

        // 5. Smooth positions for rendering.
        for particle in particles {
            let current = smoothedPositions[particle.id] ?? particle.position
            smoothedPositions[particle.id] = CGPoint(
                x: lerp(current.x, particle.position.x, positionSmoothing),
                y: lerp(current.y, particle.position.y, positionSmoothing)
            )
        }

        let anyDragging = particles.contains { $0.isDragging }
        let anyOffscreen = particles.contains { $0.position.y > containerSize.height + $0.radius * 2 }

        if allSettled && !anyDragging && !anyOffscreen {
            for idx in particles.indices {
                particles[idx].velocity = .zero
                smoothedPositions[particles[idx].id] = particles[idx].position
            }
            stopSimulation()
        }
    }

    private func clampToWalls(index i: Int) {
        let r = particles[i].radius

        // Top ceiling
        let topLimit = topInset + r
        if particles[i].position.y < topLimit {
            particles[i].position.y = topLimit
            if particles[i].velocity.y < 0 {
                particles[i].velocity.y = -particles[i].velocity.y * wallRestitution
            }
        }

        // Left wall
        if particles[i].position.x < r {
            particles[i].position.x = r
            if particles[i].velocity.x < 0 {
                particles[i].velocity.x = -particles[i].velocity.x * wallRestitution
            }
        }

        // Right wall
        let rightLimit = containerSize.width - r
        if particles[i].position.x > rightLimit {
            particles[i].position.x = rightLimit
            if particles[i].velocity.x > 0 {
                particles[i].velocity.x = -particles[i].velocity.x * wallRestitution
            }
        }

        // Soft bottom guard so dragged-down bubbles can't escape forever.
        let bottomLimit = containerSize.height - bottomInset + r * 4
        if particles[i].position.y > bottomLimit {
            particles[i].position.y = bottomLimit
        }
    }

    private func applyCollision(between i: Int, and j: Int, deltaTime: CGFloat) {
        let dx = particles[i].position.x - particles[j].position.x
        let dy = particles[i].position.y - particles[j].position.y
        let distance = hypot(dx, dy)

        let minDistance = particles[i].radius + particles[j].radius + collisionPadding

        guard distance < minDistance && distance > 0.001 else { return }

        let overlap = minDistance - distance
        let pushDirX = dx / distance
        let pushDirY = dy / distance

        let separationStrength: CGFloat = 0.5
        let separationX = pushDirX * overlap * separationStrength
        let separationY = pushDirY * overlap * separationStrength

        if particles[i].isDragging {
            particles[j].position.x -= separationX
            particles[j].position.y -= separationY
        } else if particles[j].isDragging {
            particles[i].position.x += separationX
            particles[i].position.y += separationY
        } else {
            particles[i].position.x += separationX * 0.5
            particles[i].position.y += separationY * 0.5
            particles[j].position.x -= separationX * 0.5
            particles[j].position.y -= separationY * 0.5
        }

        let pushStrength = min(overlap * collisionStiffness * deltaTime, 30.0)

        if particles[i].isDragging {
            particles[j].velocity.x -= pushDirX * pushStrength
            particles[j].velocity.y -= pushDirY * pushStrength
        } else if particles[j].isDragging {
            particles[i].velocity.x += pushDirX * pushStrength
            particles[i].velocity.y += pushDirY * pushStrength
        } else {
            particles[i].velocity.x += pushDirX * pushStrength * 0.5
            particles[i].velocity.y += pushDirY * pushStrength * 0.5
            particles[j].velocity.x -= pushDirX * pushStrength * 0.5
            particles[j].velocity.y -= pushDirY * pushStrength * 0.5
        }
    }

    // MARK: - Helpers

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }

    deinit {
        stopSimulation()
    }
}
