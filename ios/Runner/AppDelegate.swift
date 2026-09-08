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
  
  // Handle remote notifications, foreground and background alike
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📬 Received remote notification: \(userInfo)")

    // `FirebaseAppDelegateProxyEnabled` is false in Info.plist, so nothing
    // swizzles this callback: handing the payload up to super is the only
    // thing that puts it in front of firebase_messaging, and so the only
    // thing that raises it on `FirebaseMessaging.onMessage` in Dart.
    //
    // A silent push — a reaction or an edit, sent as `content-available`
    // with no alert — arrives here and nowhere else, because willPresent
    // below only runs for a notification that has something to show.
    // Answering the completion handler here instead of forwarding it
    // swallowed those updates, which is why a reaction never reached an open
    // chat on iOS while Android, whose service hands every data message
    // straight to Dart, was fine.
    let once = OneShotFetchCompletion(completionHandler)
    super.application(application, didReceiveRemoteNotification: userInfo) { result in
      once.call(result)
    }
    // Nothing downstream is obliged to answer, and iOS punishes a background
    // handler that is left hanging.
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      once.call(.noData)
    }
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

    // A push that carries an alert never reaches
    // application:didReceiveRemoteNotification:fetchCompletionHandler: while
    // the app is in the foreground, so this callback is the only place
    // firebase_messaging can hear about one — and taking the notification
    // centre delegate above cut it out of the chain that used to deliver it.
    // Handing the notification up to super puts it back, which is what raises
    // the message on `FirebaseMessaging.onMessage` and so what makes the open
    // chat and the chat list refresh. Its presentation choice is swallowed:
    // the options below are this app's to make, not the plugin's.
    super.userNotificationCenter(center,
                                 willPresent: notification,
                                 withCompletionHandler: { _ in })

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

    // Same story as willPresent: a tap is how `onMessageOpenedApp` is raised,
    // and firebase_messaging only learns of one through the delegate chain
    // this class stepped in front of. Its completion handler is swallowed —
    // the one below is answered once, by whoever this tap is really for.
    if userInfo["gcm.message_id"] != nil {
      super.userNotificationCenter(center,
                                   didReceive: response,
                                   withCompletionHandler: {})
    }

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

/// Runs a `fetchCompletionHandler` at most once, whichever of the plugin chain
/// and the timeout beside it gets there first: calling one twice is a crash,
/// and never calling it costs the app its background time.
private final class OneShotFetchCompletion {
  private let lock = NSLock()
  private var handler: ((UIBackgroundFetchResult) -> Void)?

  init(_ handler: @escaping (UIBackgroundFetchResult) -> Void) {
    self.handler = handler
  }

  func call(_ result: UIBackgroundFetchResult) {
    lock.lock()
    let pending = handler
    handler = nil
    lock.unlock()
    pending?(result)
  }
}
