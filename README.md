# SixthSense

> Futuristic macOS control: hand gestures, gaze tracking, iPhone-as-remote, portal displays, cross-reality clipboard, and an interactive notch bar.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

## Modules

| Module | Description | Status |
|--------|-------------|--------|
| **HandCommand** | Control windows with hand gestures via webcam (pinch, swipe, spread) | WIP |
| **GazeShift** | Gaze-aware desktop: windows react to where you look | WIP |
| **AirCursor** | Use your iPhone as a Wii Remote to control the Mac cursor | WIP |
| **PortalView** | Turn any device into a portal to your Mac via QR code + WebRTC | WIP |
| **GhostDrop** | Grab content with a hand gesture, throw it to another device | WIP |
| **NotchBar** | Transform the MacBook notch into an interactive control center | WIP |

## Architecture

Single menu bar app with modular architecture. Each feature is an independent Swift Package that can be enabled/disabled at runtime.

```
SixthSense/
├── Packages/
│   ├── SixthSenseCore/       # Core protocols (ModuleProtocol, EventBus)
│   ├── SharedServices/        # Camera, Network, Overlay, Accessibility, Input
│   ├── HandCommandModule/     # Hand gesture control
���   ├── GazeShiftModule/       # Eye tracking
│   ├── AirCursorModule/       # iPhone gyro cursor
│   ├── PortalViewModule/      # WebRTC display streaming
│   ├── GhostDropModule/       # Cross-device clipboard
│   └── NotchBarModule/        # Notch UI
├── SixthSenseApp/             # Main app shell
└── SixthSenseCompanion/       # iOS companion app
```

## Tech Stack

- **Swift + SwiftUI** (native macOS)
- **Vision Framework** (hand pose + face landmarks)
- **CGEvent** (synthetic input injection)
- **Accessibility API** (window management)
- **Network.framework** (Bonjour device discovery)
- **ScreenCaptureKit** (screen capture)
- **WebRTC** (display streaming)
- **ARKit** (iOS companion AR features)

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+
- Swift 5.9+
- MacBook with camera (for HandCommand and GazeShift)
- iPhone (for AirCursor companion)

## Build

```bash
# Clone
git clone https://github.com/LucasStop/SixthSense.git
cd SixthSense

# Build with SPM
swift build

# Run
swift run SixthSense
```

## Permissions

The app requires the following system permissions:
- **Camera** - Hand gesture and gaze tracking
- **Accessibility** - Window management and cursor control
- **Screen Recording** - Screen capture for PortalView
- **Local Network** - Cross-device communication

## License

MIT License. See [LICENSE](LICENSE) for details.
