# hofa_customer_app

App Khách hàng HOFA — Android, iOS & Web (PWA, `hofa.com.vn`). Đặt hàng, đặt trước/giá sỉ,
theo dõi đơn theo thời gian thực, nhận push khi đơn đổi trạng thái.

## Chạy thử

```bash
cd hofa_customer_app
cp env.example.json env.json   # điền SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL thật
flutter pub get
flutter run                              # máy ảo/điện thoại Android hoặc iOS đã kết nối
flutter run -d chrome --dart-define-from-file=env.json   # bản web (PWA)
```

Bản web deploy qua `./build_web.sh` (build + ghi version vào `web/app-version.json`) rồi
`wrangler deploy` lên Cloudflare Workers — xem chi tiết ở `CLAUDE.md` gốc repo.

Không cấu hình Firebase (bước dưới) app native vẫn chạy và dùng được bình thường — chỉ riêng
push notification sẽ không hoạt động.

## Thiết lập Firebase (bắt buộc để có push notification trên Android/iOS)

Web đã dùng sẵn project Firebase `hofa-production` (xem `web/firebase-messaging-sw.js`) —
Android/iOS thêm app vào **cùng project này**, không tạo project mới, để dùng chung 1 nguồn push.

1. Vào [Firebase Console](https://console.firebase.google.com) → project `hofa-production`.
2. **Thêm app Android**: package name `com.hofa.hofa_customer` (khớp `applicationId` trong
   `android/app/build.gradle.kts`) → tải file `google-services.json` → bỏ vào
   `android/app/google-services.json`.
3. **Thêm app iOS**: Bundle ID `com.hofa.hofaCustomer` (khớp `PRODUCT_BUNDLE_IDENTIFIER` trong
   `ios/Runner.xcodeproj`) → tải file `GoogleService-Info.plist` → mở `ios/Runner.xcworkspace`
   bằng Xcode, kéo file vào thư mục `Runner` (tick "Copy items if needed").
4. **iOS cần thêm APNs key** (nếu chưa có chung cho các app khác): Apple Developer →
   Certificates, Identifiers & Profiles → Keys → tạo 1 APNs key → upload vào Firebase Console
   (Project settings → Cloud Messaging → Apple app configuration).
5. Build lại app sau khi có 2 file cấu hình trên — `build.gradle.kts` chỉ áp dụng Google
   Services plugin khi thấy `google-services.json`, nên trước đó build vẫn chạy bình thường.

`google-services.json`, `GoogleService-Info.plist` đã có trong `.gitignore` — không commit lên
git vì gắn với project Firebase thật.

## Đưa lên Google Play / App Store

### Android — đã có sẵn keystore ký release

Keystore ký bản release đã tạo sẵn tại `android/app/upload-keystore.jks`, mật khẩu lưu ở
`android/key.properties` (2 file này **không** commit vào git, xem `android/.gitignore`).

**QUAN TRỌNG — sao lưu ngay**: mất `upload-keystore.jks` hoặc mật khẩu trong `key.properties`
thì **không bao giờ cập nhật được app đã lên Play Store nữa** (Google bắt buộc mọi bản cập nhật
phải ký cùng 1 khoá với bản đầu tiên) — copy 2 file này ra nơi lưu trữ an toàn NGOÀI máy này
(trình quản lý mật khẩu, ổ cứng ngoài mã hoá...) trước khi làm gì khác.

```bash
flutter build appbundle   # ra file .aab để nộp Play Console (khuyến nghị)
```

### iOS — cần mở Xcode 1 lần để gán Team

```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```
Trong Xcode: chọn target `Runner` → tab "Signing & Capabilities" → đăng nhập Apple ID → chọn
đúng Team (cần Apple Developer Program, $99/năm) → Xcode tự tạo Provisioning Profile. Build:

```bash
flutter build ipa
```

### Nội dung cần chuẩn bị trước khi nộp

- Icon 1024×1024 không nền trong suốt — đã sinh sẵn từ `assets/icon/icon.png` (chạy lại
  `dart run flutter_launcher_icons` nếu đổi ảnh gốc, cấu hình ở `pubspec.yaml`).
- Screenshot đúng kích cỡ store yêu cầu, mô tả app, **chính sách bảo mật** (bắt buộc — app có
  xin quyền vị trí/thông báo).
- Trả lời bảng câu hỏi Data Safety (Google Play) / App Privacy (App Store) về dữ liệu thu thập
  (vị trí giao hàng, số điện thoại, thông báo đẩy).
