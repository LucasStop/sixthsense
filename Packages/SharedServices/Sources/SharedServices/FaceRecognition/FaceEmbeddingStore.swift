import Foundation
@preconcurrency import Vision
import SixthSenseCore

// MARK: - Face Embedding Store

/// Persists the user's enrolled face as a set of `VNFeaturePrintObservation`
/// blobs in Application Support. Also persists the selected `FaceLockMode`
/// in UserDefaults.
///
/// We store multiple embeddings (one per captured frame) rather than a
/// single averaged one — comparison is done against all of them and the
/// smallest distance wins. This gives better robustness to small pose
/// variations without any averaging heuristics.
public final class FaceEmbeddingStore: @unchecked Sendable {

    // MARK: - UserDefaults keys

    private enum DefaultsKey {
        static let lockMode = "com.lucasstop.sixthsense.faceLock.mode"
        static let enrolledAt = "com.lucasstop.sixthsense.faceLock.enrolledAt"
    }

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

    /// Saves an array of feature prints as the enrolled face. Overwrites
    /// any previous enrollment.
    public func save(embeddings: [VNFeaturePrintObservation]) throws {
        guard let url = enrollmentFileURL else {
            throw FaceEmbeddingStoreError.unavailableDirectory
        }
        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: embeddings,
            requiringSecureCoding: true
        )
        try archived.write(to: url, options: [.atomic])
        defaults.set(Date(), forKey: DefaultsKey.enrolledAt)
    }

    /// Loads previously enrolled feature prints, or `nil` if none exists.
    public func loadEmbeddings() -> [VNFeaturePrintObservation]? {
        guard let url = enrollmentFileURL,
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let unarchived = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
            ofClass: VNFeaturePrintObservation.self,
            from: data
        ) else {
            return nil
        }
        return unarchived
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
