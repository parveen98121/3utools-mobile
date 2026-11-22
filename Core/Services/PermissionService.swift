import Foundation
import AVFoundation
import Photos
import CoreLocation
import CoreMotion
import CoreHaptics
import LocalAuthentication

enum PermissionState: Equatable {
    case notDetermined
    case granted
    case limited
    case denied
    case restricted

    var label: String {
        switch self {
        case .notDetermined: return "Not requested yet"
        case .granted: return "Allowed"
        case .limited: return "Limited access"
        case .denied: return "Denied"
        case .restricted: return "Restricted by device settings"
        }
    }

    var isUsable: Bool { self == .granted || self == .limited }
}

/// Reads and requests the four permissions the app uses. Nothing is requested until a feature needs it.
enum PermissionService {
    static func camera() -> PermissionState { map(AVCaptureDevice.authorizationStatus(for: .video)) }
    static func microphone() -> PermissionState { map(AVCaptureDevice.authorizationStatus(for: .audio)) }

    static func photos() -> PermissionState {
        map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    static func location() -> PermissionState {
        map(CLLocationManager().authorizationStatus)
    }

    static func requestCamera() async -> PermissionState {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return camera()
    }

    static func requestMicrophone() async -> PermissionState {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return microphone()
    }

    static func requestPhotos() async -> PermissionState {
        map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func map(_ status: PHAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func map(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

/// Which hardware features iOS reports as present. These are availability flags, not tests.
struct HardwareCapabilities: Equatable {
    var cameraCount: Int
    var hasTorch: Bool
    var biometry: String?
    var hasAccelerometer: Bool
    var hasGyroscope: Bool
    var hasBarometer: Bool
    var hasHaptics: Bool
}

enum HardwareCapabilityService {
    static func read() -> HardwareCapabilities {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )
        let torch = AVCaptureDevice.default(for: .video)?.hasTorch ?? false

        let context = LAContext()
        var error: NSError?
        var biometry: String?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: biometry = "Face ID"
            case .touchID: biometry = "Touch ID"
            default: biometry = nil
            }
        } else {
            // The type is still reported when biometrics exist but are not set up.
            switch context.biometryType {
            case .faceID: biometry = "Face ID (not set up)"
            case .touchID: biometry = "Touch ID (not set up)"
            default: biometry = nil
            }
        }

        let motion = CMMotionManager()
        return HardwareCapabilities(
            cameraCount: discovery.devices.count,
            hasTorch: torch,
            biometry: biometry,
            hasAccelerometer: motion.isAccelerometerAvailable,
            hasGyroscope: motion.isGyroAvailable,
            hasBarometer: CMAltimeter.isRelativeAltitudeAvailable(),
            hasHaptics: CHHapticEngine.capabilitiesForHardware().supportsHaptics
        )
    }
}
