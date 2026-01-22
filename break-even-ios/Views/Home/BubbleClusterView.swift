//
//  BubbleClusterView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import QuartzCore

// MARK: - Physics Engine

@Observable
final class BubblePhysicsEngine {
    
    struct Particle {
        var id: String
        var position: CGPoint
        var velocity: CGPoint = .zero
        var radius: CGFloat
        var isDragging: Bool = false
        var dragTarget: CGPoint = .zero
    }
    
    // MARK: - Physics Constants
    
    private let centerPullStrength: CGFloat = 2000.0
    private let collisionStiffness: CGFloat = 364.4
    private let damping: CGFloat = 0.64
    private let velocityThreshold: CGFloat = 0.8
    private let collisionPadding: CGFloat = 19.9
    private let maxDistanceFromCenter: CGFloat = 380.0
    
    // Drag constants
    private let dragSoftLimit: CGFloat = 152.4
    private let dragHardLimit: CGFloat = 241.5
    private let dragFollowSpeed: CGFloat = 0.39
    private let dragResistancePower: CGFloat = 1.2
    
    // Smoothing constants
    private let positionSmoothing: CGFloat = 0.15
    private let velocitySmoothing: CGFloat = 0.30
    
    // MARK: - State
    
    private(set) var particles: [Particle] = []
    private var displayLink: CADisplayLink?
    private var centerPoint: CGPoint = .zero
    private var lastUpdateTime: CFTimeInterval = 0
    private var isSimulating: Bool = false
    private var smoothedPositions: [String: CGPoint] = [:]
    
    // MARK: - Public Interface
    
    func setCenter(_ center: CGPoint) {
        centerPoint = center
    }
    
    func resetParticles(
        from contacts: [(friend: ConvexFriend, amount: Double)],
        in containerSize: CGSize,
        sizeForAmount: (Double) -> CGFloat
    ) {
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        centerPoint = CGPoint(x: centerX, y: centerY)
        
        let sortedContacts = contacts.sorted { $0.amount > $1.amount }
        
        var newParticles: [Particle] = []
        
        // Place first (largest) bubble in center
        if let first = sortedContacts.first {
            let size = sizeForAmount(first.amount)
            newParticles.append(Particle(
                id: first.friend.id,
                position: CGPoint(x: centerX, y: centerY),
                radius: size / 2
            ))
        }
        
        // Place remaining bubbles around
        for (index, contact) in sortedContacts.dropFirst().enumerated() {
            let angle = Double(index) * (2 * .pi / Double(max(sortedContacts.count - 1, 1)))
            let radius = min(containerSize.width, containerSize.height) * 0.3
            
            let x = centerX + cos(angle) * radius
            let y = centerY + sin(angle) * radius
            let size = sizeForAmount(contact.amount)
            
            newParticles.append(Particle(
                id: contact.friend.id,
                position: CGPoint(x: x, y: y),
                radius: size / 2
            ))
        }
        
        particles = newParticles
        
        // Run multiple passes of collision resolution to separate overlapping bubbles
        for _ in 0..<10 {
            resolveOverlaps()
        }
        
        // Initialize smoothed positions to actual positions
        smoothedPositions.removeAll()
        for particle in particles {
            smoothedPositions[particle.id] = particle.position
        }
        
        // Run simulation for settling
        startSimulation()
    }
    
    private func resolveOverlaps() {
        let count = particles.count
        for i in 0..<count {
            for j in (i + 1)..<count {
                let dx = particles[i].position.x - particles[j].position.x
                let dy = particles[i].position.y - particles[j].position.y
                let distance = hypot(dx, dy)
                
                let minDistance = particles[i].radius + particles[j].radius + collisionPadding
                
                guard distance < minDistance && distance > 0.001 else { continue }
                
                let overlap = minDistance - distance
                let pushDirX = dx / distance
                let pushDirY = dy / distance
                
                // Split the separation equally
                particles[i].position.x += pushDirX * overlap * 0.5
                particles[i].position.y += pushDirY * overlap * 0.5
                particles[j].position.x -= pushDirX * overlap * 0.5
                particles[j].position.y -= pushDirY * overlap * 0.5
            }
        }
    }
    
    func position(for id: String) -> CGPoint? {
        // Return smoothed position for rendering
        if let smoothed = smoothedPositions[id] {
            return smoothed
        }
        return particles.first { $0.id == id }?.position
    }
    
    func startDrag(id: String, to position: CGPoint) {
        guard let index = particles.firstIndex(where: { $0.id == id }) else { return }
        
        particles[index].isDragging = true
        particles[index].dragTarget = position
        
        // On first drag frame, initialize smoothed position if needed
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
        
        // Ensure simulation continues for snap-back
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
        let deltaTime = min(CGFloat(currentTime - lastUpdateTime), 0.032) // Cap at ~30fps worth of delta
        lastUpdateTime = currentTime
        
        guard deltaTime > 0 else { return }
        
        physicsStep(deltaTime: deltaTime)
    }
    
    // MARK: - Physics Step
    
    private func physicsStep(deltaTime: CGFloat) {
        let particleCount = particles.count
        guard particleCount > 0 else {
            stopSimulation()
            return
        }
        
        // 1. Handle dragged particles - smooth follow with progressive resistance
        for i in 0..<particleCount {
            guard particles[i].isDragging else { continue }
            
            let target = particles[i].dragTarget
            let dx = target.x - centerPoint.x
            let dy = target.y - centerPoint.y
            let targetDistance = hypot(dx, dy)
            
            // Calculate constrained target with progressive resistance
            var constrainedTarget = target
            
            if targetDistance > dragSoftLimit {
                // Progressive resistance: gets exponentially harder to drag
                let overDistance = targetDistance - dragSoftLimit
                let maxOver = dragHardLimit - dragSoftLimit
                
                // Use smooth curve for resistance (approaches hard limit asymptotically)
                let resistanceFactor = 1.0 - pow(min(overDistance / maxOver, 1.0), dragResistancePower)
                let effectiveDistance = dragSoftLimit + overDistance * resistanceFactor * 0.3
                
                // Clamp to hard limit
                let finalDistance = min(effectiveDistance, dragHardLimit)
                let scale = finalDistance / targetDistance
                
                constrainedTarget = CGPoint(
                    x: centerPoint.x + dx * scale,
                    y: centerPoint.y + dy * scale
                )
            }
            
            // Smooth follow - bubble lags behind finger for weighted feel
            let currentPos = particles[i].position
            particles[i].position = CGPoint(
                x: lerp(currentPos.x, constrainedTarget.x, dragFollowSpeed),
                y: lerp(currentPos.y, constrainedTarget.y, dragFollowSpeed)
            )
        }
        
        // 2. Apply center pull force to non-dragging particles
        for i in 0..<particleCount {
            guard !particles[i].isDragging else { continue }
            
            let direction = CGPoint(
                x: centerPoint.x - particles[i].position.x,
                y: centerPoint.y - particles[i].position.y
            )
            let distance = hypot(direction.x, direction.y)
            
            if distance > 1.0 {
                let normalizedDir = CGPoint(
                    x: direction.x / distance,
                    y: direction.y / distance
                )
                
                // Distance-based multiplier: pull gets stronger further from center
                let distanceMultiplier = 1.0 + pow(distance / 60.0, 1.3)
                let forceMagnitude = centerPullStrength * deltaTime * distanceMultiplier
                
                // Smooth velocity changes
                let newVelX = particles[i].velocity.x + normalizedDir.x * forceMagnitude
                let newVelY = particles[i].velocity.y + normalizedDir.y * forceMagnitude
                particles[i].velocity.x = lerp(particles[i].velocity.x, newVelX, velocitySmoothing)
                particles[i].velocity.y = lerp(particles[i].velocity.y, newVelY, velocitySmoothing)
            }
            
            // Soft boundary with smooth clamping
            if distance > maxDistanceFromCenter {
                let normalizedDir = CGPoint(
                    x: direction.x / distance,
                    y: direction.y / distance
                )
                let targetPos = CGPoint(
                    x: centerPoint.x - normalizedDir.x * maxDistanceFromCenter,
                    y: centerPoint.y - normalizedDir.y * maxDistanceFromCenter
                )
                particles[i].position = CGPoint(
                    x: lerp(particles[i].position.x, targetPos.x, 0.3),
                    y: lerp(particles[i].position.y, targetPos.y, 0.3)
                )
                
                // Dampen outward velocity
                let dotProduct = particles[i].velocity.x * (-normalizedDir.x) + particles[i].velocity.y * (-normalizedDir.y)
                if dotProduct > 0 {
                    particles[i].velocity.x -= (-normalizedDir.x) * dotProduct * 0.5
                    particles[i].velocity.y -= (-normalizedDir.y) * dotProduct * 0.5
                }
            }
        }
        
        // 3. Apply collision forces between all pairs
        for i in 0..<particleCount {
            for j in (i + 1)..<particleCount {
                applyCollision(between: i, and: j, deltaTime: deltaTime)
            }
        }
        
        // 4. Integrate velocity -> position and apply damping
        var allSettled = true
        
        for i in 0..<particleCount {
            guard !particles[i].isDragging else { continue }
            
            // Apply damping
            particles[i].velocity.x *= damping
            particles[i].velocity.y *= damping
            
            // Update position with smoothing
            let newX = particles[i].position.x + particles[i].velocity.x * deltaTime
            let newY = particles[i].position.y + particles[i].velocity.y * deltaTime
            particles[i].position.x = lerp(particles[i].position.x, newX, 0.8)
            particles[i].position.y = lerp(particles[i].position.y, newY, 0.8)
            
            // Check if settled
            let speed = hypot(particles[i].velocity.x, particles[i].velocity.y)
            if speed > velocityThreshold {
                allSettled = false
            }
        }
        
        // 5. Update smoothed positions for rendering
        for particle in particles {
            let current = smoothedPositions[particle.id] ?? particle.position
            smoothedPositions[particle.id] = CGPoint(
                x: lerp(current.x, particle.position.x, positionSmoothing),
                y: lerp(current.y, particle.position.y, positionSmoothing)
            )
        }
        
        // Check if any particle is still dragging
        let anyDragging = particles.contains { $0.isDragging }
        
        // 6. Stop simulation if all settled and none dragging
        if allSettled && !anyDragging {
            // Snap smoothed positions to final positions
            for particle in particles {
                smoothedPositions[particle.id] = particle.position
                particles[particles.firstIndex(where: { $0.id == particle.id })!].velocity = .zero
            }
            stopSimulation()
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
        
        // Smooth position separation to prevent overlap
        let separationStrength: CGFloat = 0.4  // Reduced for smoother movement
        let separationX = pushDirX * overlap * separationStrength
        let separationY = pushDirY * overlap * separationStrength
        
        if particles[i].isDragging {
            // Only move the other particle - smoothly
            particles[j].position.x = lerp(particles[j].position.x, particles[j].position.x - separationX, 0.5)
            particles[j].position.y = lerp(particles[j].position.y, particles[j].position.y - separationY, 0.5)
        } else if particles[j].isDragging {
            // Only move this particle - smoothly
            particles[i].position.x = lerp(particles[i].position.x, particles[i].position.x + separationX, 0.5)
            particles[i].position.y = lerp(particles[i].position.y, particles[i].position.y + separationY, 0.5)
        } else {
            // Both move - split the separation smoothly
            particles[i].position.x = lerp(particles[i].position.x, particles[i].position.x + separationX * 0.5, 0.5)
            particles[i].position.y = lerp(particles[i].position.y, particles[i].position.y + separationY * 0.5, 0.5)
            particles[j].position.x = lerp(particles[j].position.x, particles[j].position.x - separationX * 0.5, 0.5)
            particles[j].position.y = lerp(particles[j].position.y, particles[j].position.y - separationY * 0.5, 0.5)
        }
        
        // Also apply velocity-based push for natural feel
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

// MARK: - Bubble Cluster View

struct BubbleClusterView: View {
    let contacts: [(friend: ConvexFriend, amount: Double)]
    let isOwedToUser: Bool
    let currencyCode: String
    let avatarNamespace: Namespace.ID
    let onPersonTap: (ConvexFriend) -> Void
    
    @State private var engine = BubblePhysicsEngine()
    @State private var containerSize: CGSize = .zero
    
    private let minBubbleSize: CGFloat = 60
    private let maxBubbleSize: CGFloat = 120
    
    private let coordinateSpaceName = "bubbleCluster"
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(contacts, id: \.friend.id) { contact in
                    if let position = engine.position(for: contact.friend.id) {
                        BubbleView(
                            friend: contact.friend,
                            amount: contact.amount,
                            size: bubbleSize(for: contact.amount),
                            isOwedToUser: isOwedToUser,
                            currencyCode: currencyCode,
                            avatarNamespace: avatarNamespace,
                            engine: engine,
                            coordinateSpaceName: coordinateSpaceName,
                            onTap: {
                                onPersonTap(contact.friend)
                            }
                        )
                        .position(position)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: coordinateSpaceName)
            .onAppear {
                containerSize = geometry.size
                initializePhysics()
            }
            .onChange(of: geometry.size) { _, newSize in
                containerSize = newSize
                engine.setCenter(CGPoint(x: newSize.width / 2, y: newSize.height / 2))
                initializePhysics()
            }
            .onChange(of: contacts.map(\.friend.id)) { _, _ in
                initializePhysics()
            }
        }
    }
    
    private func bubbleSize(for amount: Double) -> CGFloat {
        guard !contacts.isEmpty else { return minBubbleSize }
        
        let amounts = contacts.map(\.amount)
        let minAmount = amounts.min() ?? 0
        let maxAmount = amounts.max() ?? 1
        
        if maxAmount == minAmount {
            return (minBubbleSize + maxBubbleSize) / 2
        }
        
        let normalized = (amount - minAmount) / (maxAmount - minAmount)
        return minBubbleSize + (maxBubbleSize - minBubbleSize) * normalized
    }
    
    private func initializePhysics() {
        guard containerSize.width > 0 && containerSize.height > 0 else { return }
        
        engine.resetParticles(
            from: contacts,
            in: containerSize,
            sizeForAmount: bubbleSize(for:)
        )
    }
}

// MARK: - Bubble View

struct BubbleView: View {
    let friend: ConvexFriend
    let amount: Double
    let size: CGFloat
    let isOwedToUser: Bool
    let currencyCode: String
    let avatarNamespace: Namespace.ID
    let engine: BubblePhysicsEngine
    let coordinateSpaceName: String
    let onTap: () -> Void
    
    @State private var isDragging = false
    @State private var hasStartedDrag = false
    
    var body: some View {
        bubbleContent
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .gesture(dragGesture)
            .onTapGesture {
                if !isDragging {
                    onTap()
                }
            }
    }
    
    private var bubbleContent: some View {
        VStack(spacing: -4) {
            // Avatar
            if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initialsView
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .padding(2)
                .glassEffect(.regular.interactive(), in: Circle())
                .matchedTransitionSource(id: friend.id, in: avatarNamespace)
            } else {
                initialsView
                    .matchedTransitionSource(id: friend.id, in: avatarNamespace)
            }
            
            // Amount in user's currency
            Text(amount.asCurrency(code: currencyCode))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isOwedToUser ? Color.accent : Color.appDestructive)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .background(isOwedToUser ? Color.accent.opacity(0.1) : Color.appDestructive.opacity(0.1))
                .clipShape(Capsule())
        }
        .frame(width: size, height: size)
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if !hasStartedDrag {
                    hasStartedDrag = true
                    isDragging = true
                    engine.startDrag(id: friend.id, to: value.location)
                } else {
                    engine.updateDrag(id: friend.id, to: value.location)
                }
            }
            .onEnded { _ in
                isDragging = false
                hasStartedDrag = false
                engine.endDrag(id: friend.id)
            }
    }
    
    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.3, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(isOwedToUser ? Color.accent.opacity(0.6) : Color.appDestructive.opacity(0.6))
            .clipShape(Circle())
    }
}

// MARK: - Bubble Button Style

struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Empty View

struct BubbleClusterEmptyView: View {
    let isOwedToUser: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isOwedToUser ? "checkmark.circle" : "face.smiling")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(isOwedToUser ? "No one owes you" : "You're all caught up!")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(isOwedToUser ? "Start a split to track who owes you" : "No pending payments")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct BubbleClusterPreview: View {
    @Namespace private var namespace
    
    var body: some View {
        BubbleClusterView(
            contacts: [],
            isOwedToUser: true,
            currencyCode: "USD",
            avatarNamespace: namespace,
            onPersonTap: { _ in }
        )
    }
}

#Preview {
    BubbleClusterPreview()
}
