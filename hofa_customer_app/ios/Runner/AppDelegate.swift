import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Gọi thẳng, không phụ thuộc FirebaseMessaging.requestPermission() (push_service.dart) tự
    // trigger — xác nhận qua debug thật (app Cửa hàng): khi quyền Thông báo đã được cấp TỪ
    // TRƯỚC (không phải lần đầu hỏi), firebase_messaging đôi khi không tự gọi lại
    // registerForRemoteNotifications() ở lần mở app sau, khiến app không bao giờ lấy được APNs
    // token (không lỗi, không log gì — chỉ đơn giản không có token) dù quyền vẫn đang bật. Gọi
    // thẳng ở đây luôn an toàn kể cả khi chưa có quyền (không có tác dụng phụ, không tự hiện hộp
    // thoại xin quyền).
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
