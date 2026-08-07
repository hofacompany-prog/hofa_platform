# HOFA Platform

Nền tảng giao hàng/thương mại kết nối khách hàng — cửa hàng (merchant) — tài xế, gồm 3 phần
trong monorepo này:

| Thư mục | Vai trò | Trạng thái |
|---|---|---|
| `server/` | API Node.js/Express, deploy trên Render, nối thẳng Postgres (Supabase) qua `pg` | Đã có nhiều route |
| `hofa-db/` | Schema Postgres + seed + RPC functions cho Supabase | Đã có |
| `hofa_admin_app/` | **Web admin (admin.hofa.com.vn)** — Flutter build cho web | 🎯 **Đang ưu tiên build** |
| `hofa_store_app/` | App cho chủ cửa hàng, Flutter | Sau |
| `postman/` | Postman collection test luồng API thật (không phải test tự động) | Tham khảo |

**Ưu tiên hiện tại: hoàn thiện `hofa_admin_app` thành một website admin đầy đủ, gọi API/DB thật
cho mọi màn hình (không dùng dữ liệu giả), tối giản – hiện đại – chuyên nghiệp.**

---

## Design system — hofa_admin_app

- **Màu chủ đạo**: xanh lá `#85C100` (primary — hành động chính, trạng thái tích cực/active) và
  cam `#FB8519` (accent — cảnh báo nhẹ, số liệu cần chú ý, trạng thái "đang chờ/đang chạy").
  Dùng `ColorScheme.fromSeed` hoặc khai báo `ColorScheme` thủ công từ 2 màu này thay vì
  `colorSchemeSeed: Colors.indigo` hiện tại ở [main.dart](hofa_admin_app/lib/main.dart).
- **Phong cách**: tối giản, phẳng (elevation 0, đã dùng ở [dashboard_screen.dart](hofa_admin_app/lib/screens/dashboard/dashboard_screen.dart) và
  [stat_card.dart](hofa_admin_app/lib/widgets/stat_card.dart)), nhiều khoảng trắng, phân cấp bằng typography
  chứ không phải viền/đổ bóng, bo góc vừa phải (8–12px), icon outline khi chưa chọn / filled khi chọn
  (pattern đã có ở [admin_shell.dart](hofa_admin_app/lib/screens/dashboard/admin_shell.dart)).
- Chưa có ảnh tham chiếu cụ thể trong phiên làm việc này — các nguyên tắc trên là mặc định hợp lý.
  Nếu người dùng cung cấp ảnh sau, ưu tiên đọc kỹ ảnh và điều chỉnh layout/spacing/component theo
  đúng ảnh, giữ nguyên 2 màu thương hiệu.
- Giao diện, nhãn, thông báo lỗi: **tiếng Việt** (đúng convention hiện có trong toàn bộ codebase).

## Kiến trúc hofa_admin_app (Flutter, build web)

- **State/DI**: `flutter_riverpod`. Provider gọi thẳng Repository, không có state management thừa.
- **Routing**: `go_router`, 1 `ShellRoute` bọc `AdminShell` (NavigationRail bên trái) — xem
  [router.dart](hofa_admin_app/lib/router.dart). Redirect logic kiểm tra Supabase session +
  `profile.role == 'admin'`, tự đăng xuất và đá về `/login` nếu không phải admin.
- **Auth**: đăng nhập qua `supabase_flutter` (Supabase Auth), **không** dùng Supabase cho data —
  mọi dữ liệu nghiệp vụ gọi qua `ApiClient` tới `server/` bằng access_token của session hiện tại
  (header `Authorization: Bearer <token>`).
- **Gọi API**: 1 `ApiClient` dùng chung ([api_client.dart](hofa_admin_app/lib/core/api_client.dart)) +
  1 `Repository` gom API theo domain (vd [admin_repository.dart](hofa_admin_app/lib/repositories/admin_repository.dart)).
  Khi thêm màn hình mới, thêm method vào repository tương ứng, đừng gọi `ApiClient` trực tiếp từ UI.
- **Model**: mỗi entity có `fromJson` riêng trong `lib/models/`.
- **Format**: tiền luôn format bằng `formatVnd` (số nguyên VNĐ, không có số lẻ) và ngày giờ bằng
  `formatDateTime` trong [format.dart](hofa_admin_app/lib/core/format.dart) — không tự ý dùng
  `NumberFormat`/`DateFormat` khác.
- **Cấu trúc thư mục**: `core/` (hạ tầng: api client, env, format) · `models/` · `providers/` ·
  `repositories/` · `screens/<domain>/` · `widgets/` (component dùng chung). Theo đúng cấu trúc này
  khi thêm màn hình mới.

### Chạy & build

```bash
cd hofa_admin_app
cp env.example.json env.json   # điền SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL thật
flutter run -d chrome --dart-define-from-file=env.json
./build_web.sh   # build + ghi version (git commit hash) vào web/app-version.json, xem PWA update-check bên dưới
```

`env.json` chứa anon key (public) và URL — không phải secret tuyệt mật, nhưng vẫn không nên
commit; hiện chưa có dòng riêng trong `.gitignore` cho `env.json`, cân nhắc thêm nếu sắp commit
thư mục `hofa_admin_app/`.

- **PWA update-check**: cả 4 app (admin/customer/driver/store) đều có `PwaVersionService`
  ([pwa_version_service.dart](hofa_admin_app/lib/core/pwa_version_service.dart)) — lúc mở web,
  so `Env.appVersion` (đóng cứng lúc build) với `web/app-version.json` (đọc runtime, fetch bỏ
  cache). Khớp thì bỏ qua; lệch thì báo "Đã có phiên bản mới" với nút "Cập nhật ngay" duy nhất,
  bấm vào sẽ xoá Cache Storage rồi reload (giữ nguyên session Supabase/token FCM vì 2 thứ đó
  không nằm trong Cache Storage). Version luôn lấy từ git commit hash qua `./build_web.sh` của
  từng app — **luôn build bằng script này khi deploy web, không gọi `flutter build web` trực
  tiếp**, nếu không `app-version.json` sẽ không khớp bản vừa build.

## Backend (server/)

- Express thuần, không ORM — SQL trực tiếp qua `pg` trong [db.js](server/src/db.js).
- **Auth**: JWT của Supabase verify bằng JWKS (khoá công khai, ES256) trong
  [middleware/auth.js](server/src/middleware/auth.js) — không cần secret dùng chung. Middleware
  luôn parse token nếu có (không bắt buộc login ở tầng global); từng route tự gọi
  `requireAuth`/`requireRole(ctx, roles)` từ [utils.js](server/src/utils.js) khi cần chặn quyền.
- **Response envelope** cố định: `{ ok: true, data }` hoặc `{ ok: false, error: { code, message } }`
  (xem [errors.js](server/src/errors.js), [index.js](server/src/index.js)). Giữ đúng format này cho
  mọi route mới để `ApiClient._handle()` phía Flutter parse được.
- **Route theo domain** trong `src/routes/*.js`: admin, users, merchants, products, inventory,
  wholesale, orders, drivers, deliveries, payments, reviews, vouchers.
- Route admin-only (`requireRole(ctx, ['admin'])`) đã có: `GET /admin/stats`, `GET /admin/users`,
  `PATCH /admin/users/:id/role|status`, `GET /admin/orders`, `GET /admin/drivers`,
  `POST /admin/drivers/:id/verify`. Nhiều route "chung" khác (vd `/merchants`, `/orders/:id/status`,
  `/categories`) cũng nới quyền thêm cho role admin ngay trong route đó — kiểm tra route trước khi
  giả định phải thêm endpoint `/admin/...` mới.
- Chạy dev: `cd server && npm install && npm run dev` (cần `.env` copy từ `.env.example`: `DATABASE_URL`,
  `SUPABASE_URL`, `PAYMENT_WEBHOOK_SECRET`).

## Database (hofa-db/)

- Postgres (Supabase). Bảng tiếng Anh số nhiều, `snake_case`, mỗi bảng có `COMMENT` tiếng Việt.
- **Tiền = INTEGER (VNĐ)**, không dùng số thập phân. **Thời gian = TIMESTAMPTZ**, luôn lưu UTC.
- Xoá mềm bằng `deleted_at` ở các bảng có dữ liệu liên quan lâu dài (users, merchants...).
- Domain chính: `users` (role: customer/merchant_owner/merchant_staff/driver/admin) · `merchants` ·
  `branches` · `products`/`variants` · `orders` (12 trạng thái, xem enum `order_status` trong
  [01_schema.sql](hofa-db/01_schema.sql)) · `deliveries` · `payments` · `reviews` · `vouchers`.
- Đổi schema thì sửa file `.sql` tương ứng, không sửa trực tiếp trên Supabase dashboard rồi quên
  đồng bộ lại file.

## Nguyên tắc chung khi code trong repo này

- Comment/docstring giải thích **lý do** (why), không giải thích **cái gì** — style hiện có trong
  toàn bộ codebase, giữ nguyên.
- Không mock dữ liệu ở tầng UI cho các màn hình "thật" — luôn gọi qua Repository → ApiClient → API →
  Postgres. Nếu API chưa có endpoint cần thiết, thêm route mới ở `server/src/routes/` theo đúng
  convention envelope + `requireRole`, đừng giả lập ở phía Flutter.
- Trước khi thêm bảng/cột mới, kiểm tra `hofa-db/01_schema.sql` và `04_api_functions.sql` xem đã có
  chưa — schema đã khá đầy đủ cho giai đoạn 1 (xem mục enum ở đầu file).
- `postman/hofa-platform.postman_collection.json` là nguồn tham khảo nhanh để hiểu 1 luồng nghiệp vụ
  thật (tạo tài khoản → cửa hàng → sản phẩm → nhập kho → đặt đơn → xác nhận), hữu ích khi cần biết
  thứ tự gọi API đúng cho 1 tính năng mới.
