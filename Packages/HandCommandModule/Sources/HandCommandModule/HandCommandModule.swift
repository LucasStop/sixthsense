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

    /// Rolling log of the last few processed frames, for the training view
    /// to show what the classifier and router are doing. Most recent first.
    public private(set) var debugLines: [String] = []

    /// Maximum number of debug lines to retain.
    public static let debugLineLimit = 10

    /// The "useful" input range along each normalized axis. Values outside
    /// this range saturate to the screen edge, so the user only needs to
    /// move their hand within a comfortable middle region of the frame.
    public var inputDeadzone: CGFloat = 0.18

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

        latestSnapshot = nil
        latestLeftSnapshot = nil
        latestRightSnapshot = nil
        lastActions = []
        debugLines = []
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

    /// Internal for tests — call with empty readings from a fake pipeline.
    func handleNoHands() {
        latestSnapshot = nil
        latestLeftSnapshot = nil
        latestRightSnapshot = nil
        eventBus.emit(.handTrackingLost)

        // Drive the router with nil/nil so it can release holds gracefully.
        let actions = router.process(left: nil, right: nil)
        dispatch(actions: actions)
    }

    /// Internal for tests — call this directly to bypass the camera and
    /// exercise the full snapshot → router → dispatch pipeline with fake
    /// readings. Tests observe `lastActions`, `debugLines`, and the mock
    /// cursor / keyboard to verify behaviour.
    func handleReadings(_ readings: [HandReading]) {
        // Split readings into known left/right and unknowns.
        var left: HandReading? = nil
        var right: HandReading? = nil
        var unknowns: [HandReading] = []

        for reading in readings {
            switch reading.chirality {
            case .left  where left  == nil: left = reading
            case .right where right == nil: right = reading
            case .unknown: unknowns.append(reading)
            default: break
            }
        }

        // Assign unknowns by the wrist's x-position in the (already mirrored)
        // image: a hand on the right side of the image is the user's right
        // hand. If only one unknown and both slots empty, it defaults to
        // right (cursor). If both slots empty and two unknowns, sort.
        if !unknowns.isEmpty {
            let sorted = unknowns.sorted { a, b in
                let ax = a.snapshot.position(of: .wrist)?.x ?? 0
                let bx = b.snapshot.position(of: .wrist)?.x ?? 0
                return ax > bx  // rightmost first
            }
            for reading in sorted {
                if right == nil {
                    right = reading
                } else if left == nil {
                    left = reading
                }
            }
        }

        latestLeftSnapshot  = left?.snapshot
        latestRightSnapshot = right?.snapshot
        latestSnapshot      = right?.snapshot ?? left?.snapshot

        let actions = router.process(left: left, right: right)
        lastActions = actions
        dispatch(actions: actions)

        recordDebug(left: left, right: right, actions: actions)
    }

    // MARK: - Debug Info

    private func recordDebug(left: HandReading?, right: HandReading?, actions: [HandAction]) {
        let leftDesc  = left.map { "L:\($0.gesture.rawValue)" } ?? "L:—"
        let rightDesc = right.map { "R:\($0.gesture.rawValue)" } ?? "R:—"
        let actionDesc = actions.isEmpty
            ? "—"
            : actions.map { Self.short(describing: $0) }.joined(separator: ",")
        let line = "\(leftDesc)  \(rightDesc)  →  \(actionDesc)"

        // Deduplicate consecutive identical lines so the log doesn't flood.
        if debugLines.first == line { return }
        debugLines.insert(line, at: 0)
        if debugLines.count > Self.debugLineLimit {
            debugLines.removeLast(debugLines.count - Self.debugLineLimit)
        }
    }

    nonisolated static func short(describing action: HandAction) -> String {
        switch action {
        case .moveCursor:        return "move"
        case .click:             return "click"
        case .doubleClick:       return "dblClick"
        case .dragBegin:         return "dragDown"
        case .dragEnd:           return "dragUp"
        case .scroll:            return "scroll"
        case .missionControl:    return "mission"
        case .showDesktop:       return "desktop"
        case .switchSpaceLeft:   return "←space"
        case .switchSpaceRight:  return "space→"
        case .holdCommand:       return "⌘↓"
        case .releaseCommand:    return "⌘↑"
        }
    }

    // MARK: - Action dispatch

    private func dispatch(actions: [HandAction]) {
        guard let screen = NSScreen.main else { return }
        let size = screen.frame.size
        let deadzone = inputDeadzone

        for action in actions {
            switch action {
            case .moveCursor(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, deadzone: deadzone)
                if router.isDragging {
                    // During an active drag, emit a leftMouseDragged event
                    // so apps receive the drag-in-progress notification.
                    // A plain mouseMoved would leave them unaware.
                    cursorController.leftMouseDragged(to: point)
                } else {
                    cursorController.moveTo(point)
                }
            case .click(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, deadzone: deadzone)
                cursorController.leftClick(at: point)
                eventBus.emit(.handGestureDetected(.pinch(phase: .began, position: point)))
            case .dragBegin(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, deadzone: deadzone)
                cursorController.leftMouseDown(at: point)
                eventBus.emit(.handGestureDetected(.grab(phase: .began, position: point)))
            case .dragEnd(let normalized):
                let point = Self.screenPoint(from: normalized, in: size, deadzone: deadzone)
                cursorController.leftMouseUp(at: point)
                eventBus.emit(.handGestureDetected(.grab(phase: .ended, position: point)))

            // Still disabled — keep the gesture set lean. These cases are
            // recognised at the type level but produce no output.
            case .doubleClick, .scroll,
                 .missionControl, .showDesktop,
                 .switchSpaceLeft, .switchSpaceRight,
                 .holdCommand, .releaseCommand:
                break
            }
        }
    }

    /// Convert a normalized Vision point (bottom-left origin) to screen space
    /// using a centered deadzone remap.
    ///
    /// The "useful" region of the camera frame is `[deadzone, 1 - deadzone]`
    /// on each axis; anything outside that saturates at the screen edge. That
    /// way the user can reach every corner of the screen without having to
    /// move their hand all the way to the edge of the camera's view, and
    /// hand jitter near the edges is clamped instead of flickering.
    ///
    /// Vision uses a bottom-left origin; macOS screen coordinates are
    /// top-left, so Y is flipped.
    nonisolated static func screenPoint(from normalized: CGPoint, in size: CGSize, deadzone: CGFloat) -> CGPoint {
        let usableMin = max(0, deadzone)
        let usableMax = min(1, 1 - deadzone)
        let range = max(usableMax - usableMin, 0.01)

        let clampedX = min(max(normalized.x, usableMin), usableMax)
        let clampedY = min(max(normalized.y, usableMin), usableMax)

        let remappedX = (clampedX - usableMin) / range
        let remappedY = (clampedY - usableMin) / range

        let x = remappedX * size.width
        let y = (1 - remappedY) * size.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - Reading Construction

    /// Build a HandReading (chirality + snapshot) from a Vision observation.
    ///
    /// IMPORTANT: we feed Vision a horizontally-mirrored image (`.upMirrored`)
    /// because the front camera produces a mirror-selfie feed that users
    /// expect to see as a mirror. But Vision reports chirality based on the
    /// processed image, not the real-world hand — so in the mirrored feed the
    /// user's real right hand appears on the left and gets labeled `.left`.
    /// We invert the reported chirality here so downstream code talks about
    /// the user's actual right/left hand.
    static func makeReading(from observation: VNHumanHandPoseObservation) -> HandReading {
        let reportedChirality: HandChirality
        if #available(macOS 13.0, *) {
            switch observation.chirality {
            case .left:       reportedChirality = .left
            case .right:      reportedChirality = .right
            case .unknown:    reportedChirality = .unknown
            @unknown default: reportedChirality = .unknown
            }
        } else {
            reportedChirality = .unknown
        }

        // Flip — our input is mirrored, so Vision's left is user's right.
        let userChirality: HandChirality
        switch reportedChirality {
        case .left:    userChirality = .right
        case .right:   userChirality = .left
        case .unknown: userChirality = .unknown
        }

        let snapshot = makeSnapshot(from: observation)
        return HandReading(chirality: userChirality, snapshot: snapshot)
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
