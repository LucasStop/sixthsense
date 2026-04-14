import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices
@preconcurrency import Vision
import Combine
import CoreMedia
import SixthSenseCore
import SharedServices

// MARK: - HandCommand Module

/// Tracks both of the user's hands via the webcam and translates gestures into
/// real desktop actions:
///
///   • Right hand: cursor movement, click/double-click, drag, scroll.
///   • Left  hand: Mission Control, Show Desktop, switch Space, hold Command.
///
/// The pure classification and action routing lives in `HandGestureClassifier`
/// and `HandActionRouter` (both in SixthSenseCore), so the Vision/CGEvent
/// glue here stays thin.
@MainActor
@Observable
public final class HandCommandModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "hand-command",
        name: "HandCommand",
        tagline: "Minority Report Desktop",
        systemImage: "hand.raised",
        category: .input
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .camera,
                reason: "O rastreamento de mãos requer a câmera frontal"
            ),
            PermissionRequirement(
                type: .accessibility,
                reason: "Necessário para controle do cursor e gerenciamento de janelas"
            ),
        ]
    }

    // MARK: - Settings

    /// Sensitivity multiplier for cursor movement (0.1 ... 3.0).
    public var sensitivity: Double = 1.0

    // MARK: - Live Snapshots

    /// Snapshot of whichever hand was seen most recently (kept for backward
    /// compatibility — training views can read either side).
    public private(set) var latestSnapshot: HandLandmarksSnapshot?

    /// The last right-hand reading (cursor hand).
    public private(set) var latestRightSnapshot: HandLandmarksSnapshot?

    /// The last left-hand reading (modifier hand).
    public private(set) var latestLeftSnapshot: HandLandmarksSnapshot?

    /// Live actions emitted on the most recent frame — useful for the
    /// training window to show what just happened.
    public private(set) var lastActions: [HandAction] = []

    // MARK: - Dependencies

    private let cameraManager: any CameraPipeline
    private let overlayManager: any OverlayPresenter
    private let accessibilityService: any WindowAccessibility
    private let cursorController: any MouseController
    private let keyboardInput: any KeyboardInput
    private let eventBus: EventBus

    private let handPoseQueue = DispatchQueue(label: "com.sixthsense.handcommand.vision", qos: .userInteractive)
    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    /// Pure state machine that converts raw readings into actions.
    private var router = HandActionRouter()

    // MARK: - Init

    /// - Parameters:
    ///   - cursorController: must also conform to KeyboardInput for left-hand
    ///     shortcuts. The real CursorController does; tests can pass separate
    ///     mocks via the overload below.
    public init(
        cameraManager: any CameraPipeline,
        overlayManager: any OverlayPresenter,
        accessibilityService: any WindowAccessibility,
        cursorController: any MouseController,
        eventBus: EventBus
    ) {
        // The concrete CursorController conforms to both protocols, so we try
        // to reuse it as the keyboard backend. Tests can use the overload
        // below to inject a separate mock keyboard.
        self.cameraManager = cameraManager
        self.overlayManager = overlayManager
        self.accessibilityService = accessibilityService
        self.cursorController = cursorController
        self.keyboardInput = (cursorController as? KeyboardInput) ?? NoopKeyboardInput()
        self.eventBus = eventBus

        handPoseRequest.maximumHandCount = 2
    }

    /// Test-friendly overload that accepts a dedicated keyboard controller.
    public init(
        cameraManager: any CameraPipeline,
        overlayManager: any OverlayPresenter,
        accessibilityService: any WindowAccessibility,
        cursorController: any MouseController,
        keyboardInput: any KeyboardInput,
        eventBus: EventBus
    ) {
        self.cameraManager = cameraManager
        self.overlayManager = overlayManager
        self.accessibilityService = accessibilityService
        self.cursorController = cursorController
        self.keyboardInput = keyboardInput
        self.eventBus = eventBus

        handPoseRequest.maximumHandCount = 2
    }

    // MARK: - Lifecycle

    public func start() async throws {
        state = .starting

        cameraManager.subscribe(id: Self.descriptor.id) { [weak self] sampleBuffer in
            Task { @MainActor in self?.processCameraFrame(sampleBuffer) }
        }

        state = .running
    }

    public func stop() async {
        state = .stopping
        cameraManager.unsubscribe(id: Self.descriptor.id)
        overlayManager.removeOverlay(id: Self.descriptor.id)

        // Release any modifiers that might have been left held.
        if router.isCommandHeld {
            keyboardInput.releaseKey(keyCode: CGKeyCode(0x37), modifiers: [])
        }

        latestSnapshot = nil
        latestLeftSnapshot = nil
        latestRightSnapshot = nil
        lastActions = []
        router = HandActionRouter()

        state = .disabled
    }

    // MARK: - Vision Processing

    private func processCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored, options: [:])

        handPoseQueue.async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([self.handPoseRequest])
                let observations = self.handPoseRequest.results ?? []
                if observations.isEmpty {
                    Task { @MainActor in self.handleNoHands() }
                    return
                }

                // Build one reading per observation on the Vision queue.
                let readings = observations.map { Self.makeReading(from: $0) }
                Task { @MainActor in self.handleReadings(readings) }
            } catch {
                // Vision request failed; silently skip this frame.
            }
        }
    }

    private func handleNoHands() {
        latestSnapshot = nil
        latestLeftSnapshot = nil
        latestRightSnapshot = nil
        eventBus.emit(.handTrackingLost)

        // Drive the router with nil/nil so it can release holds gracefully.
        let actions = router.process(left: nil, right: nil)
        dispatch(actions: actions)
    }

    private func handleReadings(_ readings: [HandReading]) {
        // Pick the first reading per chirality.
        var left: HandReading? = nil
        var right: HandReading? = nil
        for reading in readings {
            switch reading.chirality {
            case .left  where left  == nil: left = reading
            case .right where right == nil: right = reading
            case .unknown:
                // Assume unknown is the right hand (cursor hand) so basic
                // single-handed use still works on Macs that don't report
                // chirality reliably.
                if right == nil { right = reading }
            default: break
            }
        }

        latestLeftSnapshot  = left?.snapshot
        latestRightSnapshot = right?.snapshot
        latestSnapshot      = right?.snapshot ?? left?.snapshot

        let actions = router.process(left: left, right: right)
        lastActions = actions
        dispatch(actions: actions)
    }

    // MARK: - Action dispatch

    private func dispatch(actions: [HandAction]) {
        guard let screen = NSScreen.main else { return }
        let size = screen.frame.size

        for action in actions {
            switch action {
            case .moveCursor(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, sensitivity: sensitivity)
                cursorController.moveTo(point)
            case .click(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, sensitivity: sensitivity)
                cursorController.leftClick(at: point)
                eventBus.emit(.handGestureDetected(.pinch(phase: .began, position: point)))
            case .doubleClick(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, sensitivity: sensitivity)
                cursorController.leftClick(at: point)
                cursorController.leftClick(at: point)
            case .dragBegin(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, sensitivity: sensitivity)
                cursorController.leftMouseDown(at: point)
            case .dragEnd(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, sensitivity: sensitivity)
                cursorController.leftMouseUp(at: point)
            case .scroll(let deltaY):
                cursorController.scroll(deltaY: deltaY, deltaX: 0)
            case .missionControl:
                // Control + Up Arrow
                keyboardInput.pressKey(keyCode: CGKeyCode(0x7E), modifiers: .maskControl)
            case .showDesktop:
                // F11 toggles show desktop
                keyboardInput.pressKey(keyCode: CGKeyCode(0x67), modifiers: [])
            case .switchSpaceLeft:
                // Control + Left Arrow
                keyboardInput.pressKey(keyCode: CGKeyCode(0x7B), modifiers: .maskControl)
            case .switchSpaceRight:
                // Control + Right Arrow
                keyboardInput.pressKey(keyCode: CGKeyCode(0x7C), modifiers: .maskControl)
            case .holdCommand:
                // 0x37 is Command key
                keyboardInput.holdKey(keyCode: CGKeyCode(0x37), modifiers: [])
            case .releaseCommand:
                keyboardInput.releaseKey(keyCode: CGKeyCode(0x37), modifiers: [])
            }
        }
    }

    /// Convert a normalized Vision point (bottom-left origin) to screen space.
    nonisolated static func screenPoint(from normalized: CGPoint, in size: CGSize, sensitivity: Double) -> CGPoint {
        let x = normalized.x * size.width * sensitivity
        let y = (1 - normalized.y) * size.height * sensitivity
        return CGPoint(x: x, y: y)
    }

    // MARK: - Reading Construction

    /// Build a HandReading (chirality + snapshot) from a Vision observation.
    static func makeReading(from observation: VNHumanHandPoseObservation) -> HandReading {
        let chirality: HandChirality
        if #available(macOS 13.0, *) {
            switch observation.chirality {
            case .left:  chirality = .left
            case .right: chirality = .right
            case .unknown: chirality = .unknown
            @unknown default: chirality = .unknown
            }
        } else {
            chirality = .unknown
        }

        let snapshot = makeSnapshot(from: observation)
        return HandReading(chirality: chirality, snapshot: snapshot)
    }

    /// Map a Vision observation to the neutral HandLandmarksSnapshot type.
    static func makeSnapshot(from observation: VNHumanHandPoseObservation) -> HandLandmarksSnapshot {
        var landmarks: [HandJoint: HandLandmark] = [:]

        for (jointName, coreJoint) in Self.jointMapping {
            guard let point = try? observation.recognizedPoint(jointName) else { continue }
            let landmark = HandLandmark(
                joint: coreJoint,
                position: point.location,
                confidence: point.confidence
            )
            landmarks[coreJoint] = landmark
        }

        let pending = HandLandmarksSnapshot(landmarks: landmarks, gesture: .none)
        let classified = HandGestureClassifier.classify(pending)
        return HandLandmarksSnapshot(
            landmarks: landmarks,
            gesture: classified,
            timestamp: pending.timestamp
        )
    }

    /// Explicit mapping from Vision's joint names to our Core HandJoint enum.
    private static let jointMapping: [(VNHumanHandPoseObservation.JointName, HandJoint)] = [
        (.wrist,       .wrist),
        (.thumbCMC,    .thumbCMC),
        (.thumbMP,     .thumbMP),
        (.thumbIP,     .thumbIP),
        (.thumbTip,    .thumbTip),
        (.indexMCP,    .indexMCP),
        (.indexPIP,    .indexPIP),
        (.indexDIP,    .indexDIP),
        (.indexTip,    .indexTip),
        (.middleMCP,   .middleMCP),
        (.middlePIP,   .middlePIP),
        (.middleDIP,   .middleDIP),
        (.middleTip,   .middleTip),
        (.ringMCP,     .ringMCP),
        (.ringPIP,     .ringPIP),
        (.ringDIP,     .ringDIP),
        (.ringTip,     .ringTip),
        (.littleMCP,   .littleMCP),
        (.littlePIP,   .littlePIP),
        (.littleDIP,   .littleDIP),
        (.littleTip,   .littleTip),
    ]

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("Rastreamento de Mãos") {
                HStack {
                    Text("Sensibilidade")
                    Slider(value: Binding(get: { self.sensitivity },
                                          set: { self.sensitivity = $0 }),
                           in: 0.1...3.0, step: 0.1)
                    Text(String(format: "%.1fx", sensitivity))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                Text("Ajuste o quanto o movimento da mão se traduz em movimento do cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Noop Keyboard

/// Fallback used when the injected cursorController doesn't also conform to
/// KeyboardInput. All calls are no-ops, so the left-hand shortcuts become
/// silent but nothing crashes. Tests should pass an explicit mock instead.
private struct NoopKeyboardInput: KeyboardInput {
    func pressKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {}
    func holdKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {}
    func releaseKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {}
}
