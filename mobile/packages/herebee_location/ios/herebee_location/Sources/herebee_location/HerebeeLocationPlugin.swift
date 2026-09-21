import CoreLocation
import Flutter
import UIKit

/// Location for HereBee on iOS.
///
/// Uses CoreLocation directly: no third-party SDK, and the plugin never touches
/// the network. It hands raw fixes to Dart, which encrypts them, so no
/// coordinate exists in native code in a form it could transmit.
///
/// Background behaviour, and its honest limits:
///  - With `UIBackgroundModes: location` plus `allowsBackgroundLocationUpdates`,
///    updates continue while the app is backgrounded and the screen is locked.
///    iOS shows the blue indicator throughout, which is correct: someone IS
///    seeing this device's position.
///  - Only When-In-Use authorisation is requested. Always would let iOS relaunch
///    the app after termination, but it is far more than an ephemeral, link-
///    scoped sharing session needs, and the sharper prompt would be dishonest.
///  - Consequence: if the user swipes the app away, sharing ends and iOS will
///    not relaunch it. That matches the Android behaviour here and is the
///    behaviour people expect from swiping an app away.
public class HerebeeLocationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
                                    CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var sink: FlutterEventSink?
    private var pendingPermission: FlutterResult?
    private var sharing = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = HerebeeLocationPlugin()
        let methods = FlutterMethodChannel(name: "app.herebee/location",
                                           binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        let events = FlutterEventChannel(name: "app.herebee/location/updates",
                                         binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Without this, iOS pauses updates when it decides the device has been
        // stationary "long enough" — and never resumes them on its own, which
        // looks exactly like the app breaking.
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    // MARK: - Stream

    public func onListen(withArguments _: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        sink = eventSink
        return nil
    }

    public func onCancel(withArguments _: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    // MARK: - Methods

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermission":
            result(permissionState())
        case "requestPermission":
            requestPermission(result: result)
        case "start":
            start(call: call, result: result)
        case "stop":
            stop()
            result(nil)
        case "isSharing":
            result(sharing)
        case "isBatteryOptimized":
            // Android-only concept; iOS has no equivalent user-facing setting.
            result(false)
        case "openBatterySettings", "openAppSettings":
            openAppSettings()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func permissionState() -> String {
        guard CLLocationManager.locationServicesEnabled() else { return "servicesDisabled" }
        switch manager.authorizationStatus {
        case .notDetermined:
            return "notDetermined"
        case .restricted, .denied:
            return "deniedForever"
        case .authorizedWhenInUse, .authorizedAlways:
            // iOS 14+ lets the user grant reduced accuracy; the map stays usable
            // but visibly vague, so the app says so rather than pretending.
            return manager.accuracyAuthorization == .fullAccuracy ? "whileInUse" : "coarseOnly"
        @unknown default:
            return "denied"
        }
    }

    private func requestPermission(result: @escaping FlutterResult) {
        let state = permissionState()
        guard state == "notDetermined" else {
            result(state)
            return
        }
        guard pendingPermission == nil else {
            result(FlutterError(code: "pending",
                                message: "a permission request is already in flight",
                                details: nil))
            return
        }
        pendingPermission = result
        manager.requestWhenInUseAuthorization()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let pending = pendingPermission else {
            // Authorisation revoked mid-session: stop rather than go quiet.
            if sharing, manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                stop()
                sink?(["event": "stopped", "reason": "permissionLost"])
            }
            return
        }
        pendingPermission = nil
        pending(permissionState())
    }

    private func start(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let state = permissionState()
        guard state == "whileInUse" || state == "coarseOnly" else {
            result(FlutterError(code: state == "servicesDisabled" ? "servicesDisabled" : "permission",
                                message: "location permission not granted",
                                details: nil))
            return
        }

        let args = call.arguments as? [String: Any]
        manager.distanceFilter = (args?["distanceFilter"] as? NSNumber)?.doubleValue ?? 3

        // Requires UIBackgroundModes: location in Info.plist. Setting it without
        // that entry throws, so failing loudly here is better than a share that
        // silently dies the moment the screen locks.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        sharing = true
        result(nil)
    }

    private func stop() {
        guard sharing else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        sharing = false
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    // MARK: - Delegate

    public func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let sink else { return }
        // Negative values mean "unavailable" in CoreLocation. Passing them
        // through as numbers would make a standing peer look like it is heading
        // due north at zero metres of accuracy.
        sink([
            "event": "fix",
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "acc": location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            "hdg": location.course >= 0 ? location.course : nil,
            "spd": location.speed >= 0 ? location.speed : nil,
            "at": Int(location.timestamp.timeIntervalSince1970 * 1000),
        ])
    }

    public func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        // A transient failure (no fix yet indoors) is normal and must not end the
        // session; only a hard denial does.
        guard let clError = error as? CLError, clError.code == .denied else { return }
        stop()
        sink?(["event": "stopped", "reason": "permissionLost"])
    }
}
