import AVFoundation
import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase
    FirebaseApp.configure()
    
    // Set FCM delegate
    Messaging.messaging().delegate = self

    // Set notification delegate
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)

    // Request notification permissions
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        print("✅ Notification permission granted: \(granted)")
        if let error = error {
          print("❌ Notification permission error: \(error.localizedDescription)")
        }
      }
    }

    // Register for remote notifications
    application.registerForRemoteNotifications()

    // Developer Mode MethodChannel
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "developer_mode",
                                         binaryMessenger: controller.binaryMessenger)

      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "isDeveloperMode" {
          #if targetEnvironment(simulator)
            result(true)
          #else
            let devMode = UserDefaults.standard.bool(forKey: "com.apple.DeveloperModeStatus")
            result(devMode)
          #endif
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // Image clipboard MethodChannel
      let clipboardChannel = FlutterMethodChannel(name: "image_clipboard",
                                                  binaryMessenger: controller.binaryMessenger)

      clipboardChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "hasImage" {
          result(UIPasteboard.general.hasImages)
          return
        }
        if call.method == "readImage" {
          guard let image = UIPasteboard.general.image,
                let data = image.pngData() else {
            result(nil)
            return
          }
          result(["bytes": FlutterStandardTypedData(bytes: data), "extension": "png"])
          return
        }
        guard call.method == "copyImage" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let typed = args["bytes"] as? FlutterStandardTypedData,
              !typed.data.isEmpty else {
          result(FlutterError(code: "NO_DATA",
                              message: "No image bytes were supplied",
                              details: nil))
          return
        }
        guard let image = UIImage(data: typed.data) else {
          result(FlutterError(code: "COPY_FAILED",
                              message: "Could not decode the image",
                              details: nil))
          return
        }
        UIPasteboard.general.image = image
        result(true)
      }
    }

    // awesome_notifications grabs the notification centre delegate for itself
    // on UIApplication.didFinishLaunchingNotification — that is, after this
    // method returns — and answers every notification it did not create with
    // [.alert, .badge, .sound]. Taking the delegate back on the next run loop
    // turn puts the presentation choice (see willPresent below) back in this
    // file; whatever held it is kept in `delegateBehind` and still gets every
    // callback this class does not answer itself.
    DispatchQueue.main.async { [weak self] in
      self?.reclaimNotificationCenterDelegate()
    }

    // A plugin can claim the delegate again later, so the claim is re-checked
    // on every foregrounding rather than only at launch.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reclaimNotificationCenterDelegate()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The delegate that was in place before this class took it back, so its
  /// notifications and action taps keep being handled.
  private weak var delegateBehind: UNUserNotificationCenterDelegate?

  private func reclaimNotificationCenterDelegate() {
    guard #available(iOS 10.0, *) else { return }
    let center = UNUserNotificationCenter.current()
    guard !(center.delegate === self) else { return }
    delegateBehind = center.delegate
    center.delegate = self
  }

  
  // CRITICAL: Register APNS token with Firebase
  override func application(_ application: UIApplication, 
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("📱 Device registered for remote notifications")
    
    // Set APNs token for Firebase
    Messaging.messaging().apnsToken = deviceToken
    
    // Print token for debugging
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("📱 APNs Device Token: \(token)")
    
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
  
  // Handle registration failure
  override func application(_ application: UIApplication, 
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
  }
  
  // Handle remote notifications in background
  override func application(_ application: UIApplication, 
                            didReceiveRemoteNotification userInfo: [AnyHashable : Any], 
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📬 Received remote notification: \(userInfo)")
    completionHandler(.newData)
  }
  
  // Show notification when app is in foreground
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    print("🔔 Will present notification: \(userInfo)")

    // Anything this app did not receive from FCM belongs to whichever plugin
    // built it — hand it back untouched.
    if userInfo["gcm.message_id"] == nil,
       let behind = delegateBehind,
       behind.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
      behind.userNotificationCenter?(center,
                                     willPresent: notification,
                                     withCompletionHandler: completionHandler)
      return
    }

    var options: UNNotificationPresentationOptions
    if #available(iOS 14.0, *) {
      options = [.banner, .badge]
    } else {
      options = [.alert, .badge]
    }

    // The tone that ships with the app cannot be named on the APNs payload from
    // here, so the banner is presented without a sound and the tone is played
    // alongside it. Playing it here rather than from Dart keeps it on the one
    // callback that is certain to run for this notification.
    if isChatNotification(userInfo) && usesAppChatTone() {
      playChatTone()
    } else {
      options.insert(.sound)
    }

    completionHandler(options)
  }

  /// Held for as long as it plays — an AVAudioPlayer stops the moment it is
  /// released.
  private var chatTonePlayer: AVAudioPlayer?

  /// Plays `assets/sounds/messageReceiveNotification.mp3` out of the Flutter
  /// asset bundle.
  private func playChatTone() {
    let assetKey = FlutterDartProject.lookupKey(forAsset: "assets/sounds/messageReceiveNotification.mp3")
    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
      print("❌ Chat tone missing from the bundle: \(assetKey)")
      return
    }

    do {
      // .ambient keeps the tone in a notification's lane: it mixes with
      // whatever is already playing instead of interrupting it, and it follows
      // the ring/silent switch the way any notification sound does.
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)

      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      chatTonePlayer = player
      player.prepareToPlay()
      player.play()
      print("🎵 Chat tone playing")
    } catch {
      print("❌ Chat tone failed: \(error.localizedDescription)")
    }
  }

  /// Whether the user picked the app's own chat tone over the phone default.
  ///
  /// Written from Dart through SharedPreferences, which stores into
  /// `UserDefaults` under a `flutter.` prefix. Absent means the app tone,
  /// matching `ChatNotificationSoundStore.fallback`.
  private func usesAppChatTone() -> Bool {
    return UserDefaults.standard.string(forKey: "flutter.chatNotificationSound") != "phoneDefault"
  }

  /// Guest booking (35) and transport (10) pushes are not chat, so they keep
  /// the system sound whatever the chat tone is set to.
  private func isChatNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
    guard let msgType = userInfo["msg_type"] else { return true }
    let value = String(describing: msgType)
    return value != "35" && value != "10"
  }

  // Handle notification tap
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("👆 User tapped notification: \(userInfo)")

    // The plugin behind this delegate used to receive taps directly, and its
    // action bookkeeping still expects them — it calls the completion handler.
    if let behind = delegateBehind,
       behind.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
      behind.userNotificationCenter?(center,
                                     didReceive: response,
                                     withCompletionHandler: completionHandler)
      return
    }

    completionHandler()
  }
}

// CRITICAL: FCM Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔥 Firebase FCM Token: \(fcmToken ?? "nil")")
    
    // Send token to your server if needed
    if let token = fcmToken {
      // Post notification to Flutter side
      NotificationCenter.default.post(
        name: Notification.Name("FCMToken"),
        object: nil,
        userInfo: ["token": token]
      )
    }
  }
}