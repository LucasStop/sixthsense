import SixthSenseCore

// MARK: - Shared Service Container

/// Simple dependency container constructed once at app launch and injected
/// into the HandCommand module. Not a DI framework — just a plain class
/// holding all shared services.
@MainActor
public final class SharedServiceContainer {
    public let camera: CameraManager
    public let overlay: OverlayWindowManager
    public let accessibility: AccessibilityService
    public let input: CursorController
    public let permissions: PermissionsManager
    public let eventBus: EventBus
    public let settings: ModuleSettingsStore
    public let faceRecognition: FaceRecognitionManager

    public init() {
        self.eventBus = EventBus()
        self.permissions = PermissionsManager()
        let camera = CameraManager()
        self.camera = camera
        self.overlay = OverlayWindowManager()
        self.accessibility = AccessibilityService()
        self.input = CursorController()
        self.settings = ModuleSettingsStore()
        self.faceRecognition = FaceRecognitionManager(cameraManager: camera)
    }
}
