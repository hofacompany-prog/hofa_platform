/// Theo dõi thiết bị hiện tại đã đăng ký thành công (POST /devices) cho ĐÚNG user đang đăng
/// nhập hay chưa — ApiClient chỉ gửi header X-Device-Id sau khi biết chắc dòng user_devices
/// đã tồn tại, để server có thể phát hiện thiết bị bị gỡ (DEVICE_REVOKED) ở request kế tiếp
/// mà không chặn nhầm ngay lúc vừa đăng nhập (trước khi POST /devices đầu tiên chạy xong).
/// Khoá theo cả deviceId lẫn userId — tránh rò từ tài khoản A sang tài khoản B nếu đăng xuất
/// rồi đăng nhập tài khoản khác trên cùng máy/trình duyệt trong cùng 1 phiên chạy app.
class DeviceSession {
  DeviceSession._();

  static String? _deviceId;
  static String? _userId;

  static void markRegistered(String deviceId, String userId) {
    _deviceId = deviceId;
    _userId = userId;
  }

  static void clear() {
    _deviceId = null;
    _userId = null;
  }

  static String? headerFor(String? currentUserId) {
    if (currentUserId == null || _userId != currentUserId) return null;
    return _deviceId;
  }
}
