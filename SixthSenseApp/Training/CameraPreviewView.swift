import SwiftUI
import AVFoundation
import AppKit

// MARK: - Camera Preview

/// NSViewRepresentable that attaches an AVCaptureVideoPreviewLayer to the
/// shared camera session from CameraManager. The session is already running
/// when this view appears (because HandCommand must be active to produce
/// snapshots); we just mirror its output.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.wantsLayer = true
        view.attach(session: session)
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.attach(session: session)
    }
}

// MARK: - Hosting NSView

/// Container view that keeps the preview layer sized to its bounds as the
/// window resizes. Also mirrors horizontally so the preview matches a mirror,
/// which is what the user sees in Photo Booth / FaceTime.
final class PreviewContainerView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override var isFlipped: Bool { true }

    func attach(session: AVCaptureSession?) {
        if let previewLayer, previewLayer.session === session {
            return
        }

        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        guard let session else {
            needsDisplay = true
            return
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds

        // Mirror horizontally
        var transform = CATransform3DIdentity
        transform = CATransform3DScale(transform, -1, 1, 1)
        layer.transform = transform

        self.layer?.addSublayer(layer)
        previewLayer = layer
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
