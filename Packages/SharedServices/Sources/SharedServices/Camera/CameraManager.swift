import AVFoundation
import SixthSenseCore

// MARK: - Camera Manager

/// Manages a single shared AVCaptureSession and distributes frames to multiple subscribers.
/// HandCommand uses this pipeline; additional modules can subscribe as extra frame consumers.
@MainActor
@Observable
public final class CameraManager {
    public private(set) var isRunning = false
    public private(set) var error: Error?

    private var session: AVCaptureSession?
    private let distributor = CameraFrameDistributor()
    private var subscriberCount = 0

    /// Exposes the underlying AVCaptureSession for read-only consumers like
    /// the training preview window, which needs to wire an
    /// AVCaptureVideoPreviewLayer to the shared session. Returns nil when no
    /// subscribers are active (session is not running).
    public var avSession: AVCaptureSession? {
        session
    }

    public init() {}

    /// Subscribe to camera frames. The camera starts automatically when the first subscriber registers.
    /// - Parameters:
    ///   - id: Unique identifier for this subscriber (e.g., module id)
    ///   - handler: Callback receiving each camera frame
    public func subscribe(id: String, handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        distributor.addSubscriber(id: id, handler: handler)
        subscriberCount += 1
        if subscriberCount == 1 {
            startSession()
        }
    }

    /// Unsubscribe from camera frames. The camera stops when the last subscriber unregisters.
    public func unsubscribe(id: String) {
        distributor.removeSubscriber(id: id)
        subscriberCount = max(0, subscriberCount - 1)
        if subscriberCount == 0 {
            stopSession()
        }
    }

    // MARK: - Private

    private func startSession() {
        guard session == nil else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            self.error = CameraError.deviceNotAvailable
            return
        }

        guard session.canAddInput(input) else {
            self.error = CameraError.cannotAddInput
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(distributor, queue: distributor.processingQueue)

        guard session.canAddOutput(output) else {
            self.error = CameraError.cannotAddOutput
            return
        }
        session.addOutput(output)

        self.session = session

        Task.detached { [session] in
            session.startRunning()
        }

        isRunning = true
        error = nil
    }

    private func stopSession() {
        guard let session else { return }
        Task.detached { [session] in
            session.stopRunning()
        }
        self.session = nil
        isRunning = false
    }
}

// MARK: - Camera Errors

public enum CameraError: LocalizedError {
    case deviceNotAvailable
    case cannotAddInput
    case cannotAddOutput
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .deviceNotAvailable: return "Dispositivo de câmera não disponível"
        case .cannotAddInput: return "Não foi possível adicionar entrada de câmera à sessão"
        case .cannotAddOutput: return "Não foi possível adicionar saída de vídeo à sessão"
        case .permissionDenied: return "Permissão de câmera negada"
        }
    }
}
