import Foundation
@preconcurrency import Vision
import SixthSenseCore

// MARK: - Enrolled Face Print

/// One capture from the guided enrollment flow: a Vision feature print
/// bundled with the head pose that produced it. Recognition uses the
/// pose to pick only the closest stored prints to compare against, so
/// an intruder has to match the user at the CURRENT angle instead of
/// just at any one of the nine enrollment angles.
public struct EnrolledFacePrint: Sendable {
    public let print: VNFeaturePrintObservation
    public let pose: FaceAngle

    public init(print: VNFeaturePrintObservation, pose: FaceAngle) {
        self.print = print
        self.pose = pose
    }
}

// MARK: - Enrollment Payload (persisted on disk)

/// Everything we save to disk for a completed enrollment: the feature
/// prints, their per-capture pose tags, and the calibration numbers
/// derived from the pairwise distances across the enrollment set.
///
/// The prints themselves are Foundation objects and travel through
/// `NSKeyedArchiver`; poses and calibration are plain values encoded
/// as JSON. We glue them together with a single enrollment-version
/// byte so the loader can cleanly reject old formats.
private struct EnrollmentPayload: Codable {
    let version: Int
    let poses: [FaceAnglePayload]
    let calibration: FaceRecognitionCalibration
    let printsArchive: Data

    struct FaceAnglePayload: Codable {
        let yaw: Double
        let pitch: Double

        init(_ angle: FaceAngle) {
            self.yaw = angle.yaw
            self.pitch = angle.pitch
        }

        var angle: FaceAngle { FaceAngle(yaw: yaw, pitch: pitch) }
    }
}

// MARK: - Face Embedding Store

/// Persists the user's enrolled face as a bundle of pose-tagged feature
/// prints plus the per-user recognition calibration. Also persists the
/// selected `FaceLockMode` in UserDefaults.
public final class FaceEmbeddingStore: @unchecked Sendable {

    // MARK: - UserDefaults keys

    private enum DefaultsKey {
        static let lockMode = "com.lucasstop.sixthsense.faceLock.mode"
        static let enrolledAt = "com.lucasstop.sixthsense.faceLock.enrolledAt"
    }

    /// Bump whenever the on-disk format changes. Older payloads are
    /// treated as missing enrollment and the user is asked to re-enroll.
    private static let currentFormatVersion = 2

    private let defaults: UserDefaults
    private let fileManager: FileManager

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    // MARK: - Lock mode

    public var lockMode: FaceLockMode {
        get {
            guard let raw = defaults.string(forKey: DefaultsKey.lockMode),
                  let mode = FaceLockMode(rawValue: raw) else {
                return .disabled
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: DefaultsKey.lockMode)
        }
    }

    public var enrolledAt: Date? {
        defaults.object(forKey: DefaultsKey.enrolledAt) as? Date
    }

    // MARK: - Enrollment file

    /// ~/Library/Application Support/SixthSense/face.bin
    public var enrollmentFileURL: URL? {
        guard let baseDir = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let appDir = baseDir.appendingPathComponent("SixthSense", isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir.appendingPathComponent("face.bin")
    }

    public var hasEnrolledFace: Bool {
        guard let url = enrollmentFileURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Save / Load

    /// Save a complete enrollment (pose-tagged prints + calibration).
    /// Overwrites any previous enrollment.
    public func save(
        prints: [EnrolledFacePrint],
        calibration: FaceRecognitionCalibration
    ) throws {
        guard let url = enrollmentFileURL else {
            throw FaceEmbeddingStoreError.unavailableDirectory
        }

        let visionPrints = prints.map(\.print)
        let printsArchive = try NSKeyedArchiver.archivedData(
            withRootObject: visionPrints,
            requiringSecureCoding: true
        )

        let payload = EnrollmentPayload(
            version: Self.currentFormatVersion,
            poses: prints.map { EnrollmentPayload.FaceAnglePayload($0.pose) },
            calibration: calibration,
            printsArchive: printsArchive
        )

        let encoded = try JSONEncoder().encode(payload)
        try encoded.write(to: url, options: [.atomic])
        defaults.set(Date(), forKey: DefaultsKey.enrolledAt)
    }

    /// Load previously enrolled pose-tagged prints. Returns `nil` if no
    /// enrollment exists or the file is in an older / corrupt format.
    public func load() -> (prints: [EnrolledFacePrint], calibration: FaceRecognitionCalibration)? {
        guard let url = enrollmentFileURL,
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        guard let payload = try? JSONDecoder().decode(EnrollmentPayload.self, from: data),
              payload.version == Self.currentFormatVersion else {
            return nil
        }

        guard let visionPrints = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
            ofClass: VNFeaturePrintObservation.self,
            from: payload.printsArchive
        ), visionPrints.count == payload.poses.count else {
            return nil
        }

        let prints = zip(visionPrints, payload.poses).map { print, posePayload in
            EnrolledFacePrint(print: print, pose: posePayload.angle)
        }
        return (prints, payload.calibration)
    }

    /// Removes the enrollment file and clears the lock mode back to disabled.
    public func clearEnrollment() {
        if let url = enrollmentFileURL, fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        defaults.removeObject(forKey: DefaultsKey.enrolledAt)
        defaults.set(FaceLockMode.disabled.rawValue, forKey: DefaultsKey.lockMode)
    }
}

public enum FaceEmbeddingStoreError: Error {
    case unavailableDirectory
}
