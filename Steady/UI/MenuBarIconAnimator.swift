import AppKit

// MARK: - Drawing constants

private let kIconWidth: CGFloat = 28
private let kIconHeight: CGFloat = 16
private let kPillWidth: CGFloat = 20
private let kPillHeight: CGFloat = 5.5
private let kGlowCyan = NSColor(red: 0.22, green: 0.80, blue: 0.98, alpha: 1.0)

// MARK: - Icon renderers

/// Passive mode: static outline of the pill dash, no fill.
func makePassiveMenuBarIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: kIconWidth, height: kIconHeight), flipped: false) { _ in
        let pillRect = CGRect(
            x: (kIconWidth - kPillWidth) / 2,
            y: (kIconHeight - kPillHeight) / 2,
            width: kPillWidth,
            height: kPillHeight
        )
        let path = NSBezierPath(roundedRect: pillRect, xRadius: kPillHeight / 2, yRadius: kPillHeight / 2)
        // labelColor adapts to dark / light menu bar appearance
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1.0
        path.stroke()
        return true
    }
    image.isTemplate = false
    return image
}

/// Active mode: filled pill with layered cyan glow.
/// `intensity` ranges 0…1 and modulates glow brightness (used for the pulse cycle).
func makeActiveMenuBarIcon(intensity: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: kIconWidth, height: kIconHeight), flipped: false) { _ in
        let cx = kIconWidth / 2
        let cy = kIconHeight / 2
        let pillRect = CGRect(
            x: cx - kPillWidth / 2,
            y: cy - kPillHeight / 2,
            width: kPillWidth,
            height: kPillHeight
        )
        let radius = kPillHeight / 2

        // Outer glow halos – drawn largest to smallest
        let halos: [(expansion: CGFloat, baseAlpha: CGFloat)] = [
            (6.0, 0.05),
            (4.0, 0.10),
            (2.5, 0.18),
            (1.2, 0.30),
        ]
        // Never drop below ~55 % brightness so the icon is always recognisable
        let t = 0.55 + 0.45 * intensity
        for halo in halos {
            let r = pillRect.insetBy(dx: -halo.expansion, dy: -halo.expansion)
            let p = NSBezierPath(
                roundedRect: r,
                xRadius: radius + halo.expansion,
                yRadius: radius + halo.expansion
            )
            kGlowCyan.withAlphaComponent(halo.baseAlpha * t).setFill()
            p.fill()
        }

        // Core pill fill
        let core = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)
        kGlowCyan.withAlphaComponent(0.75 + 0.25 * intensity).setFill()
        core.fill()

        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Animator

/// Manages the two icon modes and the slow-breathing pulse animation.
@MainActor
final class MenuBarIconAnimator {
    private var pulseTimer: Timer?
    // Timer closures are Sendable but always fire on the main run loop —
    // nonisolated(unsafe) suppresses the Swift 6 actor-isolation warning.
    nonisolated(unsafe) private var phase: CGFloat = 0

    /// Static outline — idle / passive state.
    func showPassive(on button: NSStatusBarButton) {
        stopPulse()
        button.image = makePassiveMenuBarIcon()
    }

    /// Solid filled pill — panel is open / user is engaged.
    func showSolid(on button: NSStatusBarButton) {
        stopPulse()
        button.image = makeActiveMenuBarIcon(intensity: 1.0)
    }

    /// Slow breathing pulse — app wants to engage the user.
    /// Runs at ~20 fps with a ~6-second sine cycle.
    func startPulse(on button: NSStatusBarButton) {
        guard pulseTimer == nil else { return }
        phase = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self, weak button] _ in
            guard let self, let button else { return }
            self.phase += 0.05          // 2π / (20 fps × 0.05) ≈ 6.3 s per cycle
            let intensity = (sin(self.phase) + 1) / 2
            button.image = makeActiveMenuBarIcon(intensity: intensity)
        }
    }

    func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    deinit { pulseTimer?.invalidate() }
}
