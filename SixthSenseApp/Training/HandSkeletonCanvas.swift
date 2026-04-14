import SwiftUI
import SixthSenseCore

// MARK: - Hand Skeleton Canvas

/// SwiftUI canvas that draws the 21-landmark hand skeleton from a snapshot,
/// showing each joint as a dot and each finger as a connecting line.
///
/// Vision landmarks come from an image the module already fed through with
/// `orientation: .upMirrored` — so the coordinates are already in the
/// mirrored camera space. The CameraPreviewView also shows the camera feed
/// mirrored, so we draw the skeleton **without** any additional horizontal
/// flip: `normalized.x = 0.8` (user's real right hand) lands at the right
/// side of the canvas, matching the camera feed.
struct HandSkeletonCanvas: View {
    let snapshot: HandLandmarksSnapshot?

    /// Tint applied to the skeleton lines and non-wrist dots. Individual
    /// finger color-coding is preserved underneath.
    var tint: Color = .white

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
                let radius: CGFloat = joint == .wrist ? 7 : 4

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
            with: .color(tint.opacity(0.9)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    /// Convert normalized Vision coords [0, 1] to SwiftUI pixel space.
    /// Vision (with `.upMirrored`) hands us coordinates already matching
    /// the mirrored camera feed, so we only flip Y (Vision origin is
    /// bottom-left, SwiftUI is top-left).
    private func convert(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
    }

    /// Color-code joints by finger for readability. Wrist uses the tint so
    /// two overlaid skeletons (left + right) can be visually distinguished.
    private func color(for joint: HandJoint) -> Color {
        switch joint {
        case .wrist:
            return tint
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
