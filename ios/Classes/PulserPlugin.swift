import Flutter
import UIKit
import UserNotifications

public class PulserPlugin: NSObject, FlutterPlugin {
    private static var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let ch = FlutterMethodChannel(name: "pulser_sdk/apns",
                                      binaryMessenger: registrar.messenger())
        let instance = PulserPlugin()
        registrar.addMethodCallDelegate(instance, channel: ch)
        // addApplicationDelegate chains safely alongside Firebase swizzling
        registrar.addApplicationDelegate(instance)
        channel = ch
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "register" {
            requestAndRegister()
            result(nil)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - UIApplicationDelegate hooks
    // Flutter's plugin system chains these alongside other delegates (including Firebase),
    // so we never set ourselves as UNUserNotificationCenter.delegate — that would
    // conflict with FirebaseMessaging which owns that role.

    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let env = apnsEnvironment()
        PulserPlugin.channel?.invokeMethod("onToken", arguments: ["token": token, "env": env])
    }

    public func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No-op — SDK degrades gracefully to FCM-only
    }

    // Called by Firebase's UNUserNotificationCenterDelegate when a notification is tapped.
    // Host app should forward this from their delegate, or wire via FirebaseMessaging.
    public func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let notifId = userInfo["notification_id"] as? String {
            PulserPlugin.channel?.invokeMethod("onDelivery", arguments: notifId)
        }
        completionHandler(.newData)
    }

    // MARK: - Private

    private func requestAndRegister() {
        // Do NOT set UNUserNotificationCenter.delegate here — Firebase owns it.
        // Just request permission and register; Firebase's swizzling will forward
        // didRegisterForRemoteNotificationsWithDeviceToken to all registered delegates.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Detects APNs environment from the embedded provisioning profile.
    /// Returns "production" for App Store/TestFlight, "sandbox" for debug/dev builds.
    private func apnsEnvironment() -> String {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let str = String(data: data, encoding: .ascii)
        else {
            // No provisioning profile — likely App Store build, use production
            return "production"
        }
        return str.contains("aps-environment") && str.contains("development") ? "sandbox" : "production"
        #endif
    }
}
