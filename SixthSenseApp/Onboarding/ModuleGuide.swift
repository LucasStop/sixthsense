import Foundation

// MARK: - Module Guide Data

/// Contains all tutorial/training data for each SixthSense module.
struct ModuleGuide: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tagline: String
    let overview: String
    let requirements: [GuideRequirement]
    let steps: [GuideStep]
    let gestures: [GestureInfo]
    let tips: [String]
}

struct GuideRequirement: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let description: String
}

struct GuideStep: Identifiable {
    let id: Int
    let title: String
    let description: String
    let icon: String
}

struct GestureInfo: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let action: String
    let howTo: String
}

// MARK: - All Guides

extension ModuleGuide {

    static let allGuides: [ModuleGuide] = [
        handCommand,
        gazeShift,
        airCursor,
        portalView,
        ghostDrop,
        notchBar
    ]

    // MARK: - HandCommand

    static let handCommand = ModuleGuide(
        id: "hand-command",
        name: "HandCommand",
        icon: "hand.raised",
        tagline: "Minority Report Desktop",
        overview: "Control your Mac windows using hand gestures captured by your webcam. Move, resize, and manage windows just by moving your hands in front of the camera.",
        requirements: [
            GuideRequirement(icon: "camera", name: "Camera", description: "Built-in or external webcam"),
            GuideRequirement(icon: "accessibility", name: "Accessibility", description: "Required to move and resize windows"),
            GuideRequirement(icon: "light.max", name: "Good Lighting", description: "Well-lit room for accurate hand detection"),
        ],
        steps: [
            GuideStep(id: 1, title: "Grant Permissions", description: "Enable Camera and Accessibility in System Settings > Privacy & Security.", icon: "lock.open"),
            GuideStep(id: 2, title: "Position Yourself", description: "Sit about 50-80cm from the webcam. Make sure your hands are visible in the camera frame.", icon: "person.and.background.dotted"),
            GuideStep(id: 3, title: "Enable the Module", description: "Toggle HandCommand ON in the menu bar. A hand skeleton overlay will appear on screen.", icon: "power"),
            GuideStep(id: 4, title: "Try Basic Gestures", description: "Start with pointing (index finger up) to move the cursor. Then try pinching to grab a window.", icon: "hand.point.up.left"),
            GuideStep(id: 5, title: "Practice Window Control", description: "Pinch to grab, move your hand to reposition, spread fingers to resize. Open your hand to release.", icon: "macwindow.on.rectangle"),
        ],
        gestures: [
            GestureInfo(name: "Point", icon: "hand.point.up", action: "Move Cursor", howTo: "Extend your index finger. The cursor follows your fingertip position."),
            GestureInfo(name: "Pinch", icon: "hand.pinch", action: "Grab Window", howTo: "Touch your thumb and index finger together over a window to grab it."),
            GestureInfo(name: "Move", icon: "hand.draw", action: "Drag Window", howTo: "While pinching, move your hand to drag the grabbed window."),
            GestureInfo(name: "Spread", icon: "hand.raised.fingers.spread", action: "Resize Window", howTo: "With a grabbed window, spread all fingers apart to make it larger."),
            GestureInfo(name: "Fist", icon: "hand.raised.slash", action: "Release", howTo: "Close your hand into a fist to release the window."),
            GestureInfo(name: "Swipe", icon: "hand.wave", action: "Switch Space", howTo: "Swipe your open hand left or right quickly to switch desktop spaces."),
        ],
        tips: [
            "Keep your hand between 30-60cm from the camera for best tracking",
            "Avoid wearing gloves or having objects in your hands",
            "A plain background behind your hands improves accuracy",
            "Start with slow, deliberate gestures until you get comfortable",
            "Adjust sensitivity in Settings if gestures feel too fast or slow",
        ]
    )

    // MARK: - GazeShift

    static let gazeShift = ModuleGuide(
        id: "gaze-shift",
        name: "GazeShift",
        icon: "eye",
        tagline: "Gaze-Aware Desktop",
        overview: "Your Mac knows where you're looking. Windows you gaze at get focused and brightened, while others dim. A subtle HUD follows your gaze point.",
        requirements: [
            GuideRequirement(icon: "camera", name: "Camera", description: "Built-in webcam (FaceTime camera works best)"),
            GuideRequirement(icon: "accessibility", name: "Accessibility", description: "Required to focus and manage windows"),
            GuideRequirement(icon: "light.max", name: "Consistent Lighting", description: "Even lighting on your face, avoid backlighting"),
        ],
        steps: [
            GuideStep(id: 1, title: "Grant Permissions", description: "Enable Camera and Accessibility in System Settings.", icon: "lock.open"),
            GuideStep(id: 2, title: "Position Yourself", description: "Sit directly facing the webcam, about 50-70cm away. Keep your head relatively still.", icon: "person.crop.circle"),
            GuideStep(id: 3, title: "Enable GazeShift", description: "Toggle GazeShift ON. A calibration screen will appear.", icon: "power"),
            GuideStep(id: 4, title: "Calibrate", description: "Look at each dot that appears on screen for 2 seconds. This maps your eye positions to screen coordinates. 5 points minimum.", icon: "scope"),
            GuideStep(id: 5, title: "Start Using", description: "Look at different windows. After a brief dwell time (~500ms), the window you're looking at will focus and others will dim.", icon: "eye.trianglebadge.exclamationmark"),
        ],
        gestures: [
            GestureInfo(name: "Gaze at Window", icon: "eye", action: "Focus Window", howTo: "Look at a window for about half a second. It will come to the front and brighten."),
            GestureInfo(name: "Look Away", icon: "eye.slash", action: "Dim Window", howTo: "When you look away from a window, it gradually dims to indicate it's not in focus."),
            GestureInfo(name: "Gaze HUD", icon: "circle.dotted", action: "Visual Feedback", howTo: "A subtle circle follows your estimated gaze point on screen."),
        ],
        tips: [
            "Recalibrate if you change your sitting position significantly",
            "Works best with the built-in MacBook camera (closest to screen)",
            "Gaze detection works by screen region, not pixel-precise — it detects which area you're looking at",
            "Avoid strong light sources behind you (backlighting confuses face detection)",
            "Adjust the dim intensity in Settings to your preference",
        ]
    )

    // MARK: - AirCursor

    static let airCursor = ModuleGuide(
        id: "air-cursor",
        name: "AirCursor",
        icon: "iphone.radiowaves.left.and.right",
        tagline: "Telekinesis KVM",
        overview: "Turn your iPhone into a Wii Remote! Point your phone at the Mac and the cursor follows. Tilt to click, twist to scroll. Like magic.",
        requirements: [
            GuideRequirement(icon: "iphone", name: "iPhone", description: "iPhone with the SixthSense Companion app installed"),
            GuideRequirement(icon: "wifi", name: "Same Network", description: "Both devices on the same Wi-Fi network"),
            GuideRequirement(icon: "network", name: "Local Network", description: "Allow local network access when prompted"),
        ],
        steps: [
            GuideStep(id: 1, title: "Install Companion App", description: "Install the SixthSense Companion app on your iPhone (build from the SixthSenseCompanion folder in Xcode).", icon: "arrow.down.app"),
            GuideStep(id: 2, title: "Same Wi-Fi", description: "Make sure your Mac and iPhone are connected to the same Wi-Fi network.", icon: "wifi"),
            GuideStep(id: 3, title: "Enable AirCursor", description: "Toggle AirCursor ON on your Mac. It will start advertising via Bonjour.", icon: "power"),
            GuideStep(id: 4, title: "Connect from iPhone", description: "Open the Companion app > AirCursor tab. Your Mac should appear in the list. Tap to connect.", icon: "link"),
            GuideStep(id: 5, title: "Calibrate", description: "Hold your iPhone pointing at the center of your Mac screen. Press 'Calibrate' in the companion app.", icon: "scope"),
            GuideStep(id: 6, title: "Start Controlling", description: "Point your phone to move the cursor. Tilt forward to click, twist to scroll!", icon: "hand.point.right"),
        ],
        gestures: [
            GestureInfo(name: "Point", icon: "iphone.gen3", action: "Move Cursor", howTo: "Point your iPhone at the screen. Cursor moves where you point (pitch = vertical, yaw = horizontal)."),
            GestureInfo(name: "Tilt Down", icon: "iphone.gen3.radiowaves.left.and.right.circle", action: "Left Click", howTo: "Quickly tilt the phone forward (toward the screen) to perform a left click."),
            GestureInfo(name: "Twist", icon: "arrow.triangle.2.circlepath", action: "Right Click", howTo: "Twist your wrist clockwise quickly to trigger a right click."),
            GestureInfo(name: "Tilt & Hold", icon: "arrow.up.and.down", action: "Scroll", howTo: "Tilt the phone gently up or down and hold to scroll continuously."),
        ],
        tips: [
            "Hold the phone comfortably — you don't need to point precisely",
            "Adjust gyro sensitivity in Settings if the cursor moves too fast/slow",
            "The connection uses UDP for minimal latency (~5ms)",
            "If the cursor drifts, re-calibrate by pointing at screen center",
            "Works great for presentations — control your Mac from across the room!",
        ]
    )

    // MARK: - PortalView

    static let portalView = ModuleGuide(
        id: "portal-view",
        name: "PortalView",
        icon: "rectangle.on.rectangle",
        tagline: "Portal Display",
        overview: "Turn ANY device with a browser into an extra display for your Mac. Scan a QR code and your phone, tablet, or another computer becomes a wireless monitor. With AR mode, the Mac window floats in physical space!",
        requirements: [
            GuideRequirement(icon: "rectangle.badge.checkmark", name: "Screen Recording", description: "Required to capture screen content"),
            GuideRequirement(icon: "wifi", name: "Same Network", description: "All devices on the same local network"),
            GuideRequirement(icon: "qrcode", name: "Camera on Device", description: "Receiving device needs a camera to scan QR code"),
        ],
        steps: [
            GuideStep(id: 1, title: "Grant Screen Recording", description: "Enable Screen Recording permission in System Settings > Privacy & Security.", icon: "lock.open"),
            GuideStep(id: 2, title: "Enable PortalView", description: "Toggle PortalView ON. A virtual display will be created and a QR code will appear.", icon: "power"),
            GuideStep(id: 3, title: "Scan QR Code", description: "On any other device, scan the QR code with the camera. It opens a browser page showing your Mac's virtual display.", icon: "qrcode.viewfinder"),
            GuideStep(id: 4, title: "Drag Windows", description: "Drag any window to the virtual display (it appears in Display settings as an extra monitor).", icon: "macwindow.badge.plus"),
            GuideStep(id: 5, title: "AR Mode (iPhone)", description: "Using the Companion app, the virtual display appears as a floating panel in AR, anchored to a surface.", icon: "arkit"),
        ],
        gestures: [
            GestureInfo(name: "Drag to Portal", icon: "arrow.right.square", action: "Send Window", howTo: "Drag any window to the virtual display area (shown in Displays settings)."),
            GestureInfo(name: "QR Scan", icon: "qrcode.viewfinder", action: "Connect Device", howTo: "Scan the QR code on any device to start receiving the display stream."),
        ],
        tips: [
            "5GHz Wi-Fi gives the best streaming quality with lowest latency",
            "You can connect multiple devices simultaneously",
            "The virtual display resolution is configurable in Settings",
            "AR mode on iPhone requires a flat surface for the anchor point",
            "Great for extending your workspace to an iPad or old tablet!",
        ]
    )

    // MARK: - GhostDrop

    static let ghostDrop = ModuleGuide(
        id: "ghost-drop",
        name: "GhostDrop",
        icon: "hand.draw",
        tagline: "Cross-Reality Clipboard",
        overview: "Grab content from your Mac screen with a hand gesture and throw it to your phone! Text, images, and files fly between devices with a throwing motion. It's like having telekinetic copy-paste.",
        requirements: [
            GuideRequirement(icon: "camera", name: "Camera", description: "Webcam for hand gesture detection"),
            GuideRequirement(icon: "wifi", name: "Same Network", description: "Both devices on the same Wi-Fi"),
            GuideRequirement(icon: "iphone", name: "Companion App", description: "SixthSense Companion on the receiving device"),
        ],
        steps: [
            GuideStep(id: 1, title: "Enable GhostDrop", description: "Toggle GhostDrop ON. If HandCommand is also active, it shares the same hand tracking.", icon: "power"),
            GuideStep(id: 2, title: "Connect Device", description: "Open Companion app > GhostDrop tab. Your Mac should appear. Tap to connect.", icon: "link"),
            GuideStep(id: 3, title: "Copy Content", description: "Copy any text, image, or file to your Mac clipboard (Cmd+C as usual).", icon: "doc.on.clipboard"),
            GuideStep(id: 4, title: "Grab Gesture", description: "Make a grab gesture (close all fingers into a fist) in front of the camera. You'll see a visual confirmation.", icon: "hand.raised.slash"),
            GuideStep(id: 5, title: "Throw!", description: "Make a quick throwing motion toward your phone. The content flies to the connected device!", icon: "paperplane"),
            GuideStep(id: 6, title: "Receive on Phone", description: "The content appears in the Companion app and is copied to your phone's clipboard.", icon: "checkmark.circle"),
        ],
        gestures: [
            GestureInfo(name: "Grab", icon: "hand.raised.slash", action: "Capture Clipboard", howTo: "Close all fingers into a fist. This captures whatever is on your Mac clipboard."),
            GestureInfo(name: "Throw", icon: "paperplane", action: "Send to Device", howTo: "After grabbing, flick your hand quickly in any direction to send the content."),
            GestureInfo(name: "Catch", icon: "hand.raised", action: "Receive Content", howTo: "Open your hand (palm facing camera) when content is incoming from another device."),
        ],
        tips: [
            "Works best when HandCommand is also active (shares the hand tracking pipeline)",
            "You can throw to any connected device — the throw direction picks the target",
            "Text, images, and small files are supported",
            "The throw animation shows the content flying off screen",
            "If you have multiple devices connected, throw left or right to choose which one",
        ]
    )

    // MARK: - NotchBar

    static let notchBar = ModuleGuide(
        id: "notch-bar",
        name: "NotchBar",
        icon: "menubar.rectangle",
        tagline: "Notch Alive",
        overview: "Transform the MacBook notch from dead space into an interactive control center. See now-playing music with a visualizer, quick notifications, and shortcut actions — all living inside the notch.",
        requirements: [
            GuideRequirement(icon: "laptopcomputer", name: "MacBook with Notch", description: "MacBook Pro 14\"/16\" (2021+) or MacBook Air M2+. Falls back to top-center bar on other Macs."),
            GuideRequirement(icon: "mic", name: "Microphone (Optional)", description: "For audio visualization in the notch"),
        ],
        steps: [
            GuideStep(id: 1, title: "Enable NotchBar", description: "Toggle NotchBar ON. The notch area will transform into an interactive bar.", icon: "power"),
            GuideStep(id: 2, title: "Hover to Expand", description: "Move your cursor to the notch area. It expands to show more controls and information.", icon: "arrow.up.left.and.arrow.down.right"),
            GuideStep(id: 3, title: "Now Playing", description: "When music is playing, the notch shows the song title and a waveform visualizer.", icon: "music.note"),
            GuideStep(id: 4, title: "Notifications", description: "New notifications slide down from the notch briefly before disappearing.", icon: "bell"),
            GuideStep(id: 5, title: "Customize", description: "In Settings, choose what appears in the notch: music, notifications, quick actions, or system status.", icon: "slider.horizontal.3"),
        ],
        gestures: [
            GestureInfo(name: "Hover", icon: "cursorarrow.motionlines", action: "Expand Notch", howTo: "Move your cursor to the notch area to reveal the expanded control center."),
            GestureInfo(name: "Click", icon: "cursorarrow.click", action: "Quick Actions", howTo: "Click on items in the expanded notch to trigger actions."),
            GestureInfo(name: "Move Away", icon: "cursorarrow", action: "Collapse", howTo: "Move your cursor away and the notch bar collapses back to minimal view."),
        ],
        tips: [
            "On Macs without a notch, NotchBar creates a floating bar at the top center",
            "The music visualizer reacts to whatever audio is currently playing",
            "You can disable auto-hide in Settings to keep the notch bar always visible",
            "NotchBar works alongside all other modules — it won't conflict",
            "Grant Microphone permission for the audio visualizer feature",
        ]
    )
}
