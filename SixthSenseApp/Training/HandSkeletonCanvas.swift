import SwiftUI
import SixthSenseCore

// MARK: - Hand Skeleton Canvas

/// SwiftUI canvas that draws the 21-landmark hand skeleton from a snapshot,
/// showing each joint as a dot and each finger as a connecting line.
///
/// Positions in the snapshot are normalized [0, 1] with origin at bottom-left
/// (Vision's convention). This view converts to top-left pixels to match
/// SwiftUI coordinate space, and mirrors horizontally so left and right match
/// what the user sees in a mirror.
struct HandSkeletonCanvas: View {
    let snapshot: HandLandmarksSnapshot?
    var mirror: Bool = true

    var body: some View {
        Canvas { context, size in
            guard let snapshot else { return }

            // Draw finger chains first (behind dots)
            for chain in HandJoint.fingerChains {
                drawChain(chain, snapshot: snapshot, in: &context, size: size)
            }

            // Draw joints on top
            for joint in HandJoint.allCases {
                guard let landmark = snapshot.landmarks[joint],
                      landmark.isConfident else { continue }
                let pixel = convert(landmark.position, in: size)
                let radius: CGFloat = joint == .wrist ? 6 : 4

                let rect = CGRect(
                    x: pixel.x - radius,
                    y: pixel.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color(for: joint))
                )
            }
        }
    }

    // MARK: - Drawing helpers

    private func drawChain(
        _ chain: [HandJoint],
        snapshot: HandLandmarksSnapshot,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        var started = false
        for joint in chain {
            guard let landmark = snapshot.landmarks[joint],
                  landmark.isConfident else { continue }
            let pixel = convert(landmark.position, in: size)
            if started {
                path.addLine(to: pixel)
            } else {
                path.move(to: pixel)
                started = true
            }
        }
        context.stroke(
            path,
            with: .color(.white.opacity(0.85)),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
    }

    /// Convert normalized Vision coords [0, 1] to SwiftUI pixel space.
    /// Vision uses bottom-left origin; SwiftUI uses top-left.
    private func convert(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        let x = mirror ? (1 - normalized.x) : normalized.x
        let y = 1 - normalized.y  // flip vertically
        return CGPoint(x: x * size.width, y: y * size.height)
    }

    /// Color-code joints by finger for readability.
    private func color(for joint: HandJoint) -> Color {
        switch joint {
        case .wrist:
            return .white
        case .thumbCMC, .thumbMP, .thumbIP, .thumbTip:
            return .orange
        case .indexMCP, .indexPIP, .indexDIP, .indexTip:
            return .yellow
        case .middleMCP, .middlePIP, .middleDIP, .middleTip:
            return .green
        case .ringMCP, .ringPIP, .ringDIP, .ringTip:
            return .cyan
        case .littleMCP, .littlePIP, .littleDIP, .littleTip:
            return .pink
        }
    }
}
