# HOFA — Tài liệu luồng nghiệp vụ (Flow)

> Tài liệu này mô tả toàn bộ các luồng nghiệp vụ đang tồn tại trong codebase HOFA tại thời điểm
> viết (dựa trên khảo sát trực tiếp mã nguồn `server/`, `hofa-db/`, `hofa_admin_app/`,
> `hofa_store_app/`, `hofa_driver_app/`, `hofa_customer_app/`). Mỗi luồng được viết theo các bước
> tuần tự, kèm endpoint API, bảng/cột DB liên quan, vai trò tham gia, và các trường hợp đặc biệt
> (kể cả các khoảng trống/nợ kỹ thuật phát hiện được trong lúc khảo sát — được đánh dấu ⚠️).
>
> Quy ước chung áp dụng cho mọi luồng bên dưới:
> - Response envelope API luôn là `{ ok: true, data }` hoặc `{ ok: false, error: { code, message } }`.
> - Tiền tệ luôn là `INTEGER` (VNĐ, không thập phân). Thời gian luôn là `TIMESTAMPTZ` lưu UTC.
> - `requireAuth`/`requireRole`/`requireMerchantAccess`/`requireOrderAccess` là các hàm kiểm tra
>   quyền dùng chung, định nghĩa tại `server/src/utils.js`.

---

## Mục lục

1. [Xác thực, Phân quyền & Thiết bị/Push](#1-xác-thực-phân-quyền--thiết-bịpush)
2. [Tạo & Quản lý Cửa hàng (Merchant)](#2-tạo--quản-lý-cửa-hàng-merchant)
3. [Danh mục — Sản phẩm — Kho hàng — Bán sỉ](#3-danh-mục--sản-phẩm--kho-hàng--bán-sỉ)
4. [Vòng đời Đơn hàng (Order)](#4-vòng-đời-đơn-hàng-order)
5. [Giao hàng / Tài xế & Thanh toán](#5-giao-hàng--tài-xế--thanh-toán)
6. [Đánh giá — Voucher — Quản trị hệ thống](#6-đánh-giá--voucher--quản-trị-hệ-thống)
7. [Tổng hợp các khoảng trống & rủi ro kỹ thuật](#7-tổng-hợp-các-khoảng-trống--rủi-ro-kỹ-thuật)

---

## 1. Xác thực, Phân quyền & Thiết bị/Push

### 1.0. Kiến trúc tổng quan

- **Nhà cung cấp xác thực:** Supabase Auth. Cả 4 app Flutter dùng `supabase_flutter` gọi thẳng
  Supabase Auth (không qua backend HOFA) để đăng ký/đăng nhập/đăng xuất/refresh token.
- **Backend chỉ làm 2 việc:**
  1. Verify JWT Supabase qua JWKS (`server/src/middleware/auth.js`, khoá công khai ES256, không
     cần secret dùng chung).
  2. Đồng bộ/khởi tạo hồ sơ nghiệp vụ trong `public.users` (`POST /me/sync`).
- **Ràng buộc thiết kế:** `public.users.id` PHẢI trùng `auth.users.id` (`claims.sub` trong JWT).

#### ⚠️ Không có OTP SMS thật

HOFA đăng ký/đăng nhập bằng **số điện thoại**, nhưng Supabase Auth chỉ hỗ trợ sẵn email/password.
Giải pháp tạm: `phoneToAuthEmail(phone)` quy đổi SĐT → `<digits>@hofa.local` (email nội bộ, không
có thật), và OTP là **mã cố định `123123`** chỉ so sánh phía client — không có SMS nào được gửi,
không có xác minh server-side. Cột `users.phone_verified_at` tồn tại trong schema nhưng **không
bao giờ được set** ở bất kỳ đâu trong code (tương tự `email_verified_at`, `last_login_at`).

### 1.1. Schema liên quan

| Bảng | Cột chính | Ghi chú |
|---|---|---|
| `users` | `id, phone UNIQUE, email CITEXT UNIQUE, role, status, phone_verified_at, email_verified_at, deleted_at` | `role`: `customer\|merchant_owner\|merchant_staff\|driver\|admin`. `status`: `pending\|active\|suspended\|banned`. |
| `user_devices` | `user_id, device_id, platform, push_token`, UNIQUE `(user_id, device_id)` | Lưu push token FCM theo từng thiết bị. |
| `sessions` | `refresh_token_hash, ip_address, expires_at, revoked_at` | ⚠️ **Schema chết** — không có code nào ghi/đọc bảng này; quản lý phiên thực tế do Supabase SDK tự lo. |
| `merchant_staff.permissions` | `JSONB` | ⚠️ Lưu nhưng **không được đọc/kiểm tra** ở đâu trong `server/src` — mọi staff có quyền như nhau. |

### 1.2. Middleware xác thực (`attachContext`, `server/src/middleware/auth.js`)

Áp dụng cho **mọi** request (middleware global):
1. Không có header `Authorization` → `req.ctx = { authenticated: false, ... }`, không chặn — để
   từng route tự quyết có bắt buộc login hay không.
2. Có token → verify chữ ký qua JWKS Supabase. Sai/hết hạn → `401 UNAUTHORIZED`.
3. Verify OK → `SELECT * FROM users WHERE id = claims.sub`. Có thể `null` nếu user đã đăng nhập
   Supabase nhưng chưa từng gọi `/me/sync`.
4. `req.ctx = { authenticated: true, userId, claims, profile, role: profile?.role ?? null }`.

⚠️ **Không kiểm tra `profile.deleted_at`/`profile.status` ở middleware này** — xem mục 7.

### 1.3. Hàm phân quyền (`server/src/utils.js`)

| Hàm | Logic |
|---|---|
| `requireAuth(ctx)` | Chỉ kiểm `ctx.authenticated`. Không kiểm `ctx.profile` tồn tại. |
| `requireRole(ctx, roles)` | `requireAuth` + `roles.includes(ctx.role)`. `role=null` (chưa sync) → luôn `403`. |
| `requireOwnRow(table, id, userId, ownerField)` | Dùng cho tài nguyên sở hữu cá nhân (địa chỉ...). |
| `requireMerchantAccess(ctx, merchantId)` | `admin` luôn qua; `merchant_owner` qua nếu là chủ; `merchant_staff` qua nếu có dòng `merchant_staff` khớp. |
| `requireOrderAccess(ctx, orderId)` | admin / customer (chủ đơn) / merchant (qua `requireMerchantAccess`) / driver (đơn được gán). |

### 1.4. Endpoint `users.js`

| Method & Path | Vai trò | Mô tả |
|---|---|---|
| `GET /me` | `requireAuth` | Trả hồ sơ hiện tại; `404 PROFILE_NOT_FOUND` nếu chưa sync. |
| `POST /me/sync` | `requireAuth` | **Endpoint quan trọng nhất luồng đăng ký** — xem 1.5. |
| `PATCH /me` | `requireAuth` | Sửa `full_name, email, avatar_url, date_of_birth`. |
| `GET/PATCH /admin/users...` | `admin` | Xem/sửa hồ sơ, đổi `role`, đổi `status`, xoá mềm (`deleted_at` + `status='banned'`). |
| `GET/POST/PATCH/DELETE /addresses` | `requireAuth` + `requireOwnRow` | Địa chỉ giao hàng cá nhân. |
| `GET/POST /devices` | `requireAuth` | Đăng ký push token — xem 1.6. |

### 1.5. `POST /me/sync` — chi tiết

1. `requireFields(['full_name', 'phone'])`.
2. `existing = findById('users', ctx.userId)`.
3. **Đã tồn tại** → chỉ patch `full_name, email, avatar_url, date_of_birth` (idempotent, an toàn
   gọi lại nhiều lần — các app đều tận dụng điều này).
4. **Chưa tồn tại** → `INSERT` với `id = ctx.userId`, **`role` luôn là `customer`**, **`status`
   luôn là `active` ngay lập tức** (không có bước "chờ duyệt" cho user thường).

⚠️ **Race condition:** gọi `/me/sync` đồng thời 2 lần → cả 2 đọc `existing=null` → cả 2 `INSERT` →
lần 2 vi phạm unique PK/`phone` → `409 DUPLICATE`, không có xử lý "trả lại row đã có" tự động.

### 1.6. Đăng ký thiết bị / Push (`POST /devices`)

Upsert theo `(user_id, device_id)`:
- Đã tồn tại `(user_id, device_id)` → `UPDATE push_token/device_name/platform/last_active_at`.
- Chưa có → `INSERT` mới.

⚠️ **`device_id` không unique riêng, chỉ unique theo cặp `(user_id, device_id)`** — nếu tài khoản
A đăng xuất trên 1 máy (không xoá token phía server, không API nào làm việc này) rồi tài khoản B
đăng nhập trên cùng máy đó, **cả A và B đều còn dòng `user_devices` riêng cho cùng thiết bị vật
lý** → cả 2 đều có thể tiếp tục nhận push. Không có API xoá token khi đăng xuất ở cả 4 app.

Luồng nhận push tự động: `PushService.init()` lắng nghe `FirebaseMessaging.onTokenRefresh` **và**
`Supabase auth.onAuthStateChange` — mỗi lần đăng nhập/đăng xuất/refresh, app tự gọi lại
`POST /devices`.

### 1.7. Luồng theo từng app

| Khía cạnh | Customer | Store | Driver | Admin |
|---|---|---|---|---|
| Đăng nhập | SĐT (quy đổi email nội bộ) + mật khẩu | như customer | như customer | **Email thật + mật khẩu** |
| OTP | Giả lập `123123` | Giả lập `123123` | Giả lập `123123` | Không có |
| Đăng ký trong app | Có | Có | Có | **Không** — tài khoản tạo sẵn ngoài luồng (Supabase Dashboard / admin khác đổi role) |
| Bước hoàn tất hồ sơ bắt buộc | `/complete-profile` (dự phòng) | `/onboarding` (tạo merchant + branch) | `/register-driver` (hồ sơ giấy tờ) | Không có |
| Nâng role tự động | Không | `customer → merchant_owner` khi tạo cửa hàng | `customer → driver` khi đăng ký hồ sơ | Không (phải sẵn là `admin`) |
| Kiểm tra role sau login | Không | Không kiểm role cụ thể, chỉ cần có `merchant` | Không kiểm role cụ thể, chỉ cần có `driver` | **Bắt buộc `role==='admin'`, tự `signOut()` nếu sai (2 lớp: login screen + router redirect)** |
| Push notification | Có (`order_updates`) | Có (`order_offers`, auto-navigate khi app đang mở) | Có (`delivery_offers`, auto-navigate) | Không (web-only, không FCM) |

**Redirect logic customer** (`hofa_customer_app/lib/router.dart`):
```
session == null   → /login
profile == null   → /complete-profile
đã có profile mà đang ở /login hay /complete-profile → /
```

**Redirect logic store** (`hofa_store_app/lib/router.dart`):
```
session == null                        → /login
profile == null                        → /onboarding
profile có nhưng myMerchant()==null    → /onboarding
đang ở /onboarding mà đã có merchant   → /products
```
`myMerchant()` gọi `GET /merchants/mine`, **chỉ lọc `owner_id = ctx.userId`** — xem ⚠️ ở mục 7 về
`merchant_staff` bị kẹt vô hạn ở `/onboarding`.

**Redirect logic driver** (`hofa_driver_app/lib/router.dart`):
```
session == null                       → /login
profile == null hoặc driver == null   → /register-driver
đang ở /register-driver mà đã có driver → /
```
`GET /drivers/me` yêu cầu `requireRole(['driver'])` → trả `403` (không phải `404`) nếu role còn là
`customer`; lỗi này bị nuốt trong `catch(_){}` ở router, có thể khiến redirect không chạy đúng ở
lần đầu tiên trước khi role được nâng cấp.

**Redirect logic admin** (`hofa_admin_app/lib/router.dart`) — **kiểm tra 2 lớp**:
```
session == null                     → /login
có session nhưng role != 'admin'    → tự signOut() + về /login
đang ở /login mà đã pass hết check  → về /
```
Kiểm tra role admin xảy ra CẢ ở `admin_login_screen.dart` (ngay sau `signInWithPassword`) LẪN ở
`router.redirect` (phòng khi session cũ còn hiệu lực từ trước hoặc user vào thẳng URL).

### 1.8. Nâng cấp role tự động (3 điểm, cùng 1 pattern)

Tất cả đều dùng `UPDATE users SET role=X WHERE id=$1 AND role='customer'` — **chỉ nâng từ
`customer`**, không ghi đè role khác (vd đã là `driver` thì không tự thành `merchant_owner` qua
luồng tạo cửa hàng được, phải admin đổi tay):

1. `customer → merchant_owner` khi `POST /merchants` (tạo cửa hàng lần đầu).
2. `customer → merchant_staff` khi được owner thêm qua `POST /merchants/:id/staff`.
3. `customer → driver` khi `POST /drivers/register`.

---

## 2. Tạo & Quản lý Cửa hàng (Merchant)

### 2.0. Enum & bảng liên quan

**`merchant_status`**: `draft → pending_review → active ⇄ paused`, và `active`/`pending_review` →
`rejected` hoặc `closed`.

| Bảng | Cột chính |
|---|---|
| `merchants` | `owner_id, name, slug UNIQUE, merchant_type, status(default draft), business_license_no, tax_code, legal_doc_urls, bank_*, commission_rate(default 15%), min_order_amount, avg_prep_minutes, rating_avg, cancel_rate, standard_certified_at, deleted_at` |
| `branches` | `merchant_id (CASCADE), address/toạ độ, is_main, is_open, auto_accept_orders, delivery_radius_km` |
| `branch_hours` | `branch_id, weekday(0=CN), open_time`, UNIQUE `(branch_id, weekday, open_time)` |
| `merchant_staff` | `merchant_id, branch_id?, user_id, position, permissions`, UNIQUE `(merchant_id, user_id)` — 1 user có thể là staff của nhiều merchant |

### 2.1. Chủ cửa hàng tạo cửa hàng mới (hofa_store_app)

1. **Đăng nhập/đồng bộ hồ sơ** → nếu chưa có merchant, router đẩy vào `/onboarding`
   (`CreateStoreScreen`).
2. Bấm "Tạo cửa hàng" → gọi `POST /me/sync` trước (an toàn, idempotent).
3. **Nhập 1 form duy nhất**: thông tin chủ (họ tên), cửa hàng (tên, SĐT, ảnh **bắt buộc**), chi
   nhánh chính (tên, địa chỉ, tỉnh/thành, lat/lng). Slug tự sinh client-side:
   `slugify(tên) + '-' + timestamp%100000` (không gọi API kiểm tra trùng).
4. `POST /merchants` (`server/src/routes/merchants.js:73-91`):
   - `ownerId = ctx.userId` (owner tự làm chủ, trừ khi admin gửi kèm `owner_phone` để tạo hộ).
   - Server **ép `status='draft'`** — client không set được.
   - `INSERT merchants`, rồi `UPDATE users SET role='merchant_owner' WHERE role='customer'`.
5. `POST /merchants/:id/branches` tạo chi nhánh chính (`is_main:true`).
6. `ref.invalidate(myMerchantProvider)` → router redirect vào `/products` (dashboard đầy đủ).

#### ⚠️ Không có bước "nộp duyệt" tự động

Route `POST /merchants/:id/submit-for-review` (`draft/rejected → pending_review`) **tồn tại ở
server nhưng không được gọi ở bất kỳ đâu trong `hofa_store_app`**. Router chỉ kiểm tra "có
merchant hay chưa" (không kiểm `status`) → chủ cửa hàng vào thẳng dashboard đầy đủ chức năng dù
merchant vẫn `draft`. Merchant chỉ chuyển trạng thái khi **admin chủ động** duyệt/đổi trạng thái
(admin có thể duyệt thẳng từ `draft`, không bắt buộc phải qua `pending_review` trước).

### 2.2. Sửa hồ sơ cửa hàng (`StoreProfileEditScreen`)

`PATCH /merchants/:id` (`requireMerchantAccess`) — sửa mô tả, liên hệ, pháp lý, ngân hàng. Dùng
chung field-whitelist (`MERCHANT_FIELDS`) cho cả owner lẫn admin.

⚠️ **`commission_rate` nằm trong `MERCHANT_FIELDS`** — về mặt API, owner có thể tự đổi % hoa hồng
của chính mình (UI store app không có field này nhưng server không chặn riêng theo role).

⚠️ **Merchant `rejected` không có cách "nộp lại" qua UI** — owner sửa được thông tin bất cứ lúc
nào (kể cả khi `rejected`), nhưng không có nút nào gọi `submit-for-review`; phải chờ admin bấm
"Duyệt" hoặc "Đổi trạng thái" thủ công.

### 2.3. Quản lý chi nhánh (`BranchSettingsScreen`)

- Bật/tắt "mở cửa" → `PATCH /branches/:id/toggle-open`.
- Bật/tắt "Tự động nhận đơn" (`auto_accept_orders`) → `PATCH /branches/:id`.
- Sửa địa chỉ/bán kính giao hàng → `PATCH /branches/:id`.
- Đặt giờ mở cửa → `PUT /branches/:id/hours` (xoá hết + insert lại toàn bộ mảng).

⚠️ **Không có nút "Thêm chi nhánh mới"** ở bất kỳ UI nào (store app lẫn admin app) sau khi merchant
đã tồn tại — dù API `POST /merchants/:id/branches` hỗ trợ đầy đủ multi-branch không giới hạn. Thực
tế mỗi merchant hiện chỉ có đúng 1 chi nhánh trong suốt vòng đời.

### 2.4. Quản lý nhân viên cửa hàng (`merchant_staff`)

API đầy đủ: `GET/POST/DELETE /merchants/:merchantId/staff`. `requireMerchantAccess` cho phép cả
owner lẫn staff hiện có tự thêm/xoá staff khác.

⚠️⚠️ **Không có UI nào cho tính năng này ở cả `hofa_store_app` lẫn `hofa_admin_app`** — không có
màn "mời nhân viên". Hệ quả nghiêm trọng hơn: vì `GET /merchants/mine` chỉ lọc `owner_id`, **user
có role `merchant_staff` hiện không đăng nhập dùng được `hofa_store_app`** — bị đẩy vào
`/onboarding` (màn tạo cửa hàng) lặp vô hạn.

### 2.5. Luồng Admin

| Hành động | Endpoint | Ghi chú |
|---|---|---|
| Xem danh sách (mọi trạng thái) | `GET /merchants?q=` | Role admin → server bỏ filter `status='active'`. |
| Duyệt / Từ chối | `POST /merchants/:id/review` | `approve:true` → `status='active'` (+ tuỳ chọn cấp nhãn "HOFA Standard"); `approve:false` → `status='rejected'`. **Không kiểm tra status hiện tại** — duyệt được từ bất kỳ trạng thái nào. |
| Đổi trạng thái tuỳ ý | `PATCH /merchants/:id/status` | Set thẳng, không kiểm tra transition hợp lệ — cách duy nhất đưa merchant ra khỏi `rejected`/`closed`. |
| Tạo merchant hộ (owner có sẵn) | `POST /merchants` kèm `owner_phone` | Tìm user theo `phone`; nếu không thấy → `404`. Tài khoản chủ phải đã tồn tại từ trước. |
| Xem chi tiết | `GET /merchants/:id` | Ẩn field nhạy cảm (`bank_*`, `tax_code`, `legal_doc_urls`) nếu người gọi không phải admin/owner. |
| Xoá (mềm) | `DELETE /merchants/:id` | `deleted_at=now()` + `status='closed'`. |

### 2.6. Bảng tổng hợp theo vai trò

| Bước | Vai trò | Endpoint | Ảnh hưởng |
|---|---|---|---|
| Tạo cửa hàng | owner/admin | `POST /merchants` | `status=draft`; nâng role owner |
| Tạo chi nhánh chính | owner/admin | `POST /merchants/:id/branches` | `branches` |
| Sửa hồ sơ | owner/admin | `PATCH /merchants/:id` | không đổi status |
| Nộp duyệt | ⚠️ không có UI | `POST /merchants/:id/submit-for-review` | `status→pending_review` |
| Duyệt/Từ chối | admin | `POST /merchants/:id/review` | `status→active/rejected` |
| Đổi trạng thái tuỳ ý | admin | `PATCH /merchants/:id/status` | `status→bất kỳ` |
| Tạm dừng/mở lại | owner/admin | `PATCH /merchants/:id/pause` | `status⇄paused` |
| Xoá | admin | `DELETE /merchants/:id` | xoá mềm |
| Thêm/xoá nhân viên | ⚠️ chỉ qua API | `POST/DELETE .../staff` | `merchant_staff` |

### 2.7. Trường hợp đặc biệt

- **Một owner có nhiều merchant**: DB không cấm; nhưng `MerchantRepository.myMerchant()` phía
  store app chỉ lấy `list.first` (merchant mới nhất) — merchant cũ hơn của cùng owner **không thể
  truy cập qua `hofa_store_app`** (không có màn chọn cửa hàng).
- **Field nhạy cảm** chỉ trả cho admin/owner, không lộ cho khách hàng.
- **Phân quyền field cập nhật chưa tách bạch** — owner và admin dùng chung 1 whitelist field.

---

## 3. Danh mục — Sản phẩm — Kho hàng — Bán sỉ

### 3.0. Bảng liên quan

| Bảng | Cột chính |
|---|---|
| `categories` | `parent_id (self-ref, SET NULL), name, slug UNIQUE, icon_url, icon_name, sort_order, is_active` |
| `products` | `merchant_id (CASCADE), name, slug, sales_model(instant\|scheduled), status(draft\|active\|out_of_stock\|hidden\|archived), images[], is_featured, deleted_at` |
| `product_categories` | `(product_id, category_id)` — N-N, cả 2 `ON DELETE CASCADE` |
| `product_variants` | `product_id, sku UNIQUE, price, compare_price, wholesale_price, is_default, is_active` — UNIQUE INDEX đảm bảo chỉ 1 `is_default=true`/sản phẩm |
| `wholesale_tiers` | `variant_id (CASCADE), min_quantity, max_quantity, unit_price, requires_deposit, deposit_percent` |
| `inventory` | `(branch_id, variant_id) UNIQUE, quantity_on_hand, quantity_reserved, low_stock_threshold(default 5)` — CHECK `reserved <= on_hand` |
| `stock_movements` | append-only, `move_type ∈ {purchase_in,sale_out,adjustment,transfer_in,transfer_out,return_in,damage_out}` |

Hàm DB quan trọng: `apply_stock_movement()` (cách duy nhất đổi `quantity_on_hand`),
`reserve_inventory()`/`release_inventory()` (giữ/nhả `quantity_reserved`).

### 3.1. Admin — Quản lý danh mục (2 cấp)

1. `GET /categories` — trả toàn bộ danh mục `is_active` (không phân trang, không lọc `parent_id`
   theo request thực tế đang dùng); client tự dựng cây gốc/con.
2. **Tạo**: dialog chọn tên + cha (chỉ liệt kê danh mục gốc, giới hạn 2 cấp **ở UI**) +
   `IconPickerField` (chọn từ ~2146 Material Icons, không upload ảnh). `POST /categories`
   (`requireRole admin`), slug tự sinh + hậu tố timestamp.
3. **Sửa**: chỉ tên + icon. `PATCH /categories/:id`.
4. **Xoá**: `DELETE /categories/:id` (admin) — nhờ FK:
   - Danh mục con của nó → tự động thành danh mục gốc (`parent_id SET NULL`).
   - Sản phẩm gắn danh mục đó → chỉ mất tag (`product_categories` CASCADE), sản phẩm không đổi.

⚠️ Giới hạn 2 cấp chỉ là quy ước UI — DB cho phép self-reference vô hạn cấp; danh mục
`is_active=false` không có cách nào xem lại/bật lại (API không có tham số hiện "đã ẩn").

### 3.2. Cửa hàng — Tạo/sửa sản phẩm & biến thể

1. **Tạo mới** (`ProductFormScreen`): tên, mô tả, ảnh (**bắt buộc**, chỉ 1 ảnh dù DB hỗ trợ mảng),
   đơn vị, hình thức bán (`instant`/`scheduled`) + khối "Giá bán" (giá, giá gốc, giá nhập, giá sỉ
   nếu `scheduled`, tồn kho ban đầu).
2. `POST /products` — kèm mảng `variants: [{name: đơn vị, price, ..., is_default:true}]` (biến thể
   đầu tiên luôn mặc định).
3. Nếu có tồn kho ban đầu → gọi thêm `POST /inventory/adjust` (`move_type:'purchase_in'`); lỗi ở
   bước này bị nuốt, không chặn tạo sản phẩm.
4. **Sửa** (bước 2): form chính chỉ sửa tên/mô tả/đơn vị/trạng thái; giá nằm trong từng biến thể.
   - Thêm biến thể mới → `POST /products/:id/variants`. **Không kiểm tra unique `is_default` ở
     API** — dựa hẳn vào UNIQUE INDEX ở DB.
   - Sửa biến thể → `PATCH /variants/:id`; đổi tồn kho qua `inventory/adjust` (`move_type:
     'adjustment'`).
   - Xoá biến thể → `DELETE /variants/:id` = xoá **mềm** (`is_active=false`).

⚠️ Xoá đúng biến thể `is_default=true` → sản phẩm không còn biến thể mặc định active; không tự
gán lại — phía customer app fallback về `variants.first`.

⚠️ **`PUT /products/:id/categories` (gán danh mục cho sản phẩm) không có UI nào gọi** ở
`hofa_store_app` — sản phẩm mới tạo mặc định **không gắn danh mục nào**, sẽ không xuất hiện khi
khách duyệt theo danh mục (dù vẫn tìm được qua ô search).

### 3.3. Kho hàng (Inventory)

- Xem tồn kho theo chi nhánh: `GET /branches/:branchId/inventory` (view `inventory_available` =
  `on_hand - reserved`).
- Điều chỉnh thủ công: `POST /inventory/adjust` — loại `purchase_in/adjustment/damage_out/
  return_in` (UI); **`sale_out` bị chặn cứng gọi tay** ("chỉ được ghi tự động khi giao hàng").
- **Trừ kho thật** chỉ xảy ra khi tài xế xác nhận `picked_up` (RPC `update_delivery_status` gọi
  `release_inventory` rồi `apply_stock_movement('sale_out')`) — lúc đặt hàng chỉ **giữ chỗ**
  (`reserve_inventory`, tăng `quantity_reserved`), chưa trừ `on_hand`.
- Đặt hàng mà không đủ `quantity_available` → RPC raise exception, đơn **không tạo được** — đây là
  điểm chặn "hết hàng" thực sự duy nhất trong hệ thống (ở tầng tạo đơn, không phải tầng hiển thị).

### 3.4. Bán sỉ (Wholesale tiers)

API đầy đủ (`GET/POST/PATCH/DELETE .../wholesale-tiers`, quyền qua chuỗi
`tier→variant→product→merchant`).

⚠️⚠️ **Không có UI nào (kể cả `hofa_store_app`) để tạo/sửa/xoá bậc giá sỉ** — chỉ có thể tạo qua
gọi thẳng API. Customer app chỉ **đọc** (`GET`) và hiển thị bậc giá theo số lượng đang chọn; nếu
không khớp bậc nào → fallback về `variant.price` (giá lẻ). Field `requires_deposit`/
`deposit_percent` có trong DB/model nhưng **không hiển thị ở UI khách hàng**.

### 3.5. Khách hàng — Duyệt danh mục 2 cấp → sản phẩm nổi bật → sản phẩm

1. **Trang chủ**: lưới 2 hàng × 4 cột (7 danh mục gốc + 1 ô "Xem tất cả"), kích thước ô cố định
   tuyệt đối (không phình to trên web).
2. Bấm 1 danh mục gốc → `CategoryDetailScreen`: hiện "Danh mục con" (nếu có) + "Sản phẩm nổi bật"
   (`GET /products?category_id=X&is_featured=true&limit=10`).
   - ⚠️ Filter theo `category_id` **khớp chính xác**, không tự gộp sản phẩm của danh mục con — sản
     phẩm phải được gán trực tiếp `category_id` = danh mục gốc mới hiện ở đây.
3. Bấm 1 danh mục con → `CategoryProductsScreen` (danh sách sản phẩm đầy đủ, không phân trang, tối
   đa ~50 sản phẩm/lần tải).
4. **Tìm kiếm** (trang chủ): 2 tầng — gợi ý nhỏ (debounce 350ms, `limit:6`, gọi thẳng repository
   không qua provider cache) và tìm kiếm đầy đủ (Enter/bấm gợi ý → `productSearchProvider`).
   Server dùng `name ILIKE '%q%'` (⚠️ không tận dụng GIN full-text index đã tạo sẵn trong schema).

⚠️ Sản phẩm hết hàng thật (`quantity_available=0`) nhưng `status` vẫn `active` (chủ shop không tự
đổi) → **vẫn hiển thị & thêm được vào giỏ bình thường**, chỉ bị chặn lúc tạo đơn.

### 3.6. Chi tiết sản phẩm & thêm vào giỏ

- Tự chọn `defaultVariant`; nếu có bậc giá sỉ (`scheduled`) → tính giá theo số lượng.
- **Không kiểm tra tồn kho ở bước thêm vào giỏ** — điểm chặn duy nhất vẫn là lúc tạo đơn.
- Giỏ hàng chỉ chứa 1 merchant + 1 branch tại một thời điểm; thêm sản phẩm merchant khác sẽ hỏi
  xác nhận xoá giỏ hiện tại.

---

## 4. Vòng đời Đơn hàng (Order)

### 4.1. Enum `order_status` (12 trạng thái, thứ tự = quy trình thực tế)

```
pending_payment → placed → confirmed → preparing → ready_for_pickup → assigned
→ picked_up → delivering → delivered → completed
cancelled, refunded (2 trạng thái "cụt")
```

### 4.2. State machine (nguồn sự thật: RPC `update_order_status`, `hofa-db/04_api_functions.sql`)

```
pending_payment  → placed | cancelled
placed           → confirmed | cancelled
confirmed        → preparing | cancelled
preparing        → ready_for_pickup | cancelled
ready_for_pickup → assigned | cancelled
assigned         → picked_up | cancelled
picked_up        → delivering                    (không huỷ được nữa)
delivering       → delivered | cancelled          (giao thất bại)
delivered        → completed | refunded
completed        → refunded
```
Vi phạm → `RAISE EXCEPTION` trừ khi `p_force=true` (chỉ admin, `orders.js`:
`p_force: ctx.role === 'admin'`).

### 4.3. Phân quyền chuyển trạng thái (`ORDER_STATUS_ROLES`, `orders.js`)

```js
{
  confirmed:        ['merchant_owner', 'merchant_staff', 'admin'],
  preparing:        ['merchant_owner', 'merchant_staff', 'admin'],
  ready_for_pickup: ['merchant_owner', 'merchant_staff', 'admin'],
  cancelled:        ['customer', 'merchant_owner', 'merchant_staff', 'admin'],
  completed:        ['admin'],
  refunded:         ['admin'],
}
```
`cancelled` do `customer`: bắt buộc `order.customer_id === ctx.userId`. `admin` luôn được phép
(bỏ qua bảng, gọi RPC với `p_force=true`).

Các trạng thái **không** nằm trong bảng trên (`pending_payment, placed, assigned, picked_up,
delivering, delivered`) không đi qua `PATCH /orders/:id/status` bởi role thường — do hệ thống/RPC
khác tự đặt (xem 4.5).

### 4.4. Endpoint chính

| Method + Path | Vai trò | Mô tả |
|---|---|---|
| `POST /orders` | customer | Tạo đơn — RPC `create_order` |
| `GET /orders/mine` | customer | Đơn của tôi |
| `GET /admin/orders` | admin | Toàn bộ đơn mọi cửa hàng |
| `GET /merchants/:id/orders` | merchant/admin | Đơn của 1 cửa hàng |
| `GET /orders/:id`, `/history` | `requireOrderAccess` | Chi tiết + lịch sử trạng thái |
| `PATCH /orders/:id/status` | theo `ORDER_STATUS_ROLES` | Đổi trạng thái |
| `POST /orders/:id/assign-driver`, `/find-driver` | merchant/admin | Gán/tìm tài xế thủ công |
| `PATCH /deliveries/:id/status` | driver | `accepted→...→delivered` |

### 4.5. Luồng "happy path" đầy đủ

1. **Giỏ hàng** — local (`SharedPreferences`), 1 merchant/branch tại 1 thời điểm.
2. **Checkout** — chọn địa chỉ, áp voucher, chọn `payment_method` (`cod`/`bank_transfer`), bấm đặt
   hàng → `POST /orders`.
3. **RPC `create_order`**: chốt giá thật từ `product_variants` (không tin giá client), `reserve_
   inventory` giữ chỗ tồn kho, áp voucher nếu có, `INSERT orders` (`status='placed'` nếu `cod`,
   ngược lại `'pending_payment'`), `INSERT order_items`. Trigger tự ghi `order_status_history`.
4. **[COD]** `orderOffer.offerOrderToMerchant()`:
   - `branch.auto_accept_orders=true` → tự `confirmed` ngay.
   - Ngược lại → `accept_deadline = now()+120s`, push cửa hàng, mở `OrderOfferScreen` (đếm ngược).
   **[Chuyển khoản]** `pending_payment` → thanh toán qua `POST /payments`/webhook → RPC `record_
   payment` đủ tiền → tự chuyển `placed` → tiếp tục luồng offer merchant.
5. **Cửa hàng xác nhận** → `PATCH .../status {confirmed}` (chặn nếu quá `accept_deadline`, tự huỷ
   + `409 OFFER_EXPIRED`).
6. **Chuẩn bị** → `{preparing}` → **Sẵn sàng giao** → `{ready_for_pickup}` (ghi `ready_at`, tự
   trigger `dispatch.offerToNearestDriver()`).
7. **Gán tài xế tự động** (chi tiết đầy đủ ở mục 5) → `assigned`.
8. **Tài xế xác nhận & lấy hàng**: `accepted → arrived_store` (chỉ đổi `deliveries.status`, KHÔNG
   đổi `orders.status`) → `picked_up` (OTP đúng, trừ tồn kho thật, đồng bộ `orders.status`) →
   `delivering` → `delivered` (OTP đúng, cộng ví tài xế nếu COD).
9. **Hoàn tất** — chỉ **admin** chuyển `delivered → completed` (thao tác thủ công trong admin app,
   dùng để đánh dấu đã đối soát tiền).

### 4.6. Luồng ngoại lệ

| Tình huống | Ai | Cách xử lý |
|---|---|---|
| Khách huỷ trước khi tài xế lấy hàng | customer (đơn của mình) | `{cancelled}` khi `status ∈ {pending_payment,placed,confirmed,preparing,ready_for_pickup,assigned}`; tự `release_inventory`, trả tài xế (nếu có) về `online` |
| Cửa hàng từ chối đơn mới | merchant | `{cancelled}` trong cửa sổ 120s hoặc sau đó (`placed/confirmed/preparing`) |
| Cửa hàng không xác nhận kịp (auto-cancel) | hệ thống | `accept_deadline` quá hạn → tự `cancelled`, note "Tự huỷ do cửa hàng không xác nhận kịp thời" — 3 lớp bảo vệ: client tự gọi khi hết đếm ngược, server lazy-check khi confirm trễ, cron quét mỗi 10s |
| Tài xế từ chối/hết hạn nhận đơn | hệ thống | **Không huỷ đơn** — chỉ đổi tài xế (xem mục 5); `orders.status` đứng yên |
| Giao hàng thất bại | driver | `{failed}` (bảng `deliveries`, KHÔNG đổi `orders.status`) — phải huỷ thủ công hoặc gán lại tài xế |
| Hết hàng giữa chừng | — | Không có luồng riêng; chặn chính là `reserve_inventory` lúc tạo đơn; nếu lệch kiểm kê thực tế → huỷ đơn thủ công |
| Hoàn tiền | admin | `{refunded}` từ `delivered`/`completed`; **tách biệt** với `POST /payments/:id/refund` (đổi tiền thật) — admin phải tự làm cả 2 |
| Gỡ đơn kẹt | admin | "Chuyển trạng thái thủ công" — dropdown chọn bất kỳ trong 12 trạng thái, `p_force=true`, bỏ qua state machine |

⚠️ Nếu order có nhiều dòng `payments` (đặt cọc + trả sau), `refund_payment` set
`orders.payment_status` dựa theo trạng thái của **riêng dòng payment vừa hoàn**, không tổng hợp
toàn bộ — có thể sai lệch nếu hoàn 1 phần.

---

## 5. Giao hàng / Tài xế & Thanh toán

### 5.0. Enum & bảng

- `driver_status`: `offline|online|busy|on_break`. `delivery_status`: `pending|assigned|accepted|
  arrived_store|picked_up|delivering|delivered|failed|returned`.
- `drivers`: `status, auto_accept, current_latitude/longitude, wallet_balance(có thể ÂM khi đang
  giữ COD chưa nộp), verified_at(NULL=chưa duyệt)`.
- `deliveries` (1 order = 1 delivery, `order_id UNIQUE`): `driver_id, status, pickup_otp,
  delivery_otp, accept_deadline, declined_driver_ids[]` (then chốt cơ chế loại trừ khi reassign).

### 5.1. Đăng ký hồ sơ tài xế

1. Đăng nhập → chưa có `drivers` record → `/register-driver`.
2. Nhập CCCD, GPLX, loại xe, biển số, ảnh giấy tờ → `POST /drivers/register`.
3. Chặn đăng ký trùng (`409 CONFLICT`). `INSERT drivers` (`verified_at=NULL`), nâng
   `role→driver`.
4. Admin duyệt: `DriversScreen` → `POST /admin/drivers/:id/verify` → `verified_at=now()`.

⚠️ **UI nói "phải duyệt mới bật được online" nhưng server không enforce** — `PATCH /drivers/me/
status` (bật online) không kiểm tra `verified_at`. Tài xế chưa duyệt vẫn bật online & nhận đơn
được trên thực tế.

### 5.2. Bật online / nhận đơn tự động hay thủ công

- `PATCH /drivers/me/status` — đổi `offline/online/busy/on_break`; bật online bắt buộc xin quyền
  vị trí, gửi ngay 1 lần toạ độ.
- `PATCH /drivers/me/auto-accept` — bật/tắt `auto_accept`.
- UI chặn tắt online khi `status='busy'` (đang có đơn).

### 5.3. Gán tài xế — TỰ ĐỘNG

**Trigger**: `order.status → ready_for_pickup` → `dispatch.offerToNearestDriver(orderId)`
(fire-and-forget):
1. Tìm tài xế `status='online'` gần branch nhất (Haversine), loại trừ `excludeDriverIds`.
2. Không còn ai → dừng (chờ merchant bấm "Tìm tài xế" thủ công).
3. Tính `distanceKm`, `driverFee = 12,000 + 4,000/km`, `etaMinutes`.
4. RPC `assign_driver`: `INSERT/UPDATE deliveries` (`status='assigned'`, sinh OTP),
   `drivers.status='busy'`. Chỉ đổi `orders.status→'assigned'` ở **lần gán đầu tiên**.
5. Rẽ nhánh theo `driver.auto_accept`:
   - `true` → tự `update_delivery_status('accepted')` ngay, không cần xác nhận.
   - `false` → `accept_deadline = now()+25s`, push `delivery_offer`, mở `OfferScreen` (đếm ngược).

Gán thủ công: `POST /orders/:id/assign-driver` (chọn 1 driver cụ thể) hoặc `/find-driver` (tìm lại
tự động khi không có ai nhận).

### 5.4. Cơ chế TIMEOUT & tự động chuyển tài xế khác (3 lớp)

| Lớp | Cơ chế |
|---|---|
| 1 — App tài xế | `OfferScreen` đếm ngược 25s; hết giờ → **chủ động gọi `POST /deliveries/:id/decline`** ngay lập tức (không chờ server) |
| 2 — Server lazy-check | Nếu tài xế bấm "Nhận đơn" SAU khi `accept_deadline` đã qua → server phát hiện ngay tại request, gọi `reassignAfterDecline`, trả `409 OFFER_EXPIRED` |
| 3 — Cron quét nền | `setInterval` mỗi **10 giây** trong `index.js` gọi `dispatch.sweepExpiredOffers()`: quét `deliveries WHERE status='assigned' AND accept_deadline < now()` → `reassignAfterDecline` cho từng cái |

**`reassignAfterDecline(deliveryId)`** (dùng chung cho decline chủ động / trễ hạn / cron):
1. Trả tài xế cũ `busy → online`.
2. Thêm tài xế cũ vào `declined_driver_ids`.
3. Reset delivery: `driver_id=NULL, status='pending', accept_deadline=NULL`.
4. Gọi lại `offerToNearestDriver(excludeDriverIds: declined)` — tìm tài xế gần nhất **kế tiếp**,
   loại trừ toàn bộ tài xế đã từng bị gán/từ chối/hết hạn cho đơn này → lặp lại chu trình (đếm
   ngược 25s mới hoặc auto-accept).
5. Không còn ai → delivery "kẹt" ở `pending`/`driver_id=NULL`, chờ merchant "Tìm tài xế" thủ công.
   ⚠️ Không có polling nền tự phát hiện khi có tài xế MỚI online cho các đơn đang kẹt.

Hằng số: `ACCEPT_WINDOW_SECONDS = 25s` (dispatch.js). Cơ chế song song bên merchant xác nhận đơn
dùng cùng pattern nhưng khung **120 giây** và kết quả cuối là **huỷ đơn** (không "chuyển cửa hàng
khác" vì đơn thuộc về 1 merchant cố định) — xem mục 4.6.

### 5.5. Tài xế thực hiện chuyến giao

`assigned → accepted → arrived_store → picked_up → delivering → delivered` (hoặc `failed`), qua
`PATCH /deliveries/:id/status`:

| Trạng thái | Ràng buộc & hiệu ứng |
|---|---|
| `accepted` | Xoá `accept_deadline` |
| `arrived_store` | — |
| `picked_up` | **Bắt buộc đúng `pickup_otp`**; trừ tồn kho thật (`release_inventory` → `apply_stock_movement('sale_out')`); đồng bộ `orders.status` (force) |
| `delivering` | Đồng bộ `orders.status` |
| `delivered` | **Bắt buộc đúng `delivery_otp`**; `drivers.status='online'`, `total_deliveries+=1`; nếu COD: `wallet_balance += total_amount - driver_fee` |
| `failed` | Lưu `failure_reason`, `attempt_count+=1`, trả tài xế `online`; KHÔNG tự re-dispatch |

Mỗi lần đổi trạng thái → push khách qua `notifyCustomerOrderStatus()`.

### 5.6. Thu nhập tài xế

`GET /drivers/me/earnings` — `wallet_balance, total_deliveries, rating`, danh sách chuyến gần đây.
⚠️ **Không có API rút tiền/yêu cầu thanh toán ví** — quản lý nộp/rút có vẻ là quy trình ngoài hệ
thống (thủ công).

### 5.7. Thanh toán (Payment)

**Enum**: `payment_method`: `cod|bank_transfer|qr_code|e_wallet|credit` (UI checkout chỉ hỗ trợ
`cod`/`bank_transfer`, 3 phương thức còn lại chưa có UI). `payment_status`:
`pending|paid|failed|refunded|partially_refunded`.

**`POST /payments`** (ghi nhận thanh toán) — phân quyền:
- `driver`: chỉ COD **và** chính là tài xế phụ trách đơn đó (xác nhận đã thu tiền mặt).
- `merchant_owner/staff/admin`: cho chuyển khoản/QR/ghi tay.

RPC `record_payment`: `INSERT payments`, tính tổng đã trả, `UPDATE orders.payment_status`; nếu đủ
tiền và đơn đang `pending_payment` → tự chuyển `placed`.

⚠️ Không có idempotency key ngoài `transaction_code UNIQUE` (optional) — gọi API 2 lần có thể ghi
trùng payment nếu không gửi `transaction_code`.

**`POST /payments/:id/refund`** — admin hoặc merchant (đúng đơn); chặn hoàn vượt số đã thu.

**`POST /payments/webhook`** — không JWT, xác thực bằng so khớp `webhook_secret` với biến môi
trường `PAYMENT_WEBHOOK_SECRET`.

⚠️⚠️ **Cảnh báo được ghi rõ trong code**: đây "chỉ là khung sườn" — chưa verify chữ ký số thực của
MoMo/VNPay/ZaloPay, hiện chỉ so 1 secret dùng chung. **Không dùng thật cho tới khi thay bằng đúng
thuật toán ký số của từng cổng.**

**Doanh thu admin dashboard** (`GET /admin/stats`): tính từ `SUM(orders.total_amount/
commission_amount) WHERE status IN ('delivered','completed')` — **không phải tổng hợp từ bảng
`payments`** — có thể lệch nếu đơn COD được đánh dấu `delivered` nhưng tài xế chưa ghi nhận
`POST /payments` xác nhận đã thu.

---

## 6. Đánh giá — Voucher — Quản trị hệ thống

### 6.1. Đánh giá (Review)

**Bảng `reviews`**: `order_id (bắt buộc, FK orders CASCADE), customer_id, target_type(merchant|
driver|product), target_id, rating(1-5, CHECK), comment, media_urls, merchant_reply, replied_at,
is_hidden`. **`UNIQUE (order_id, target_type, target_id)`** — chặn đánh giá trùng ở tầng DB.
Trigger `refresh_rating` (chạy cả khi `INSERT` lẫn `UPDATE`) tự tính lại `rating_avg`/
`rating_count` trên `merchants`/`drivers`/`products` tương ứng, chỉ tính dòng `NOT is_hidden`.

| Method & Path | Vai trò | Mô tả |
|---|---|---|
| `GET /reviews?target_type&target_id` | Public | Luôn lọc `NOT is_hidden` |
| `POST /reviews` | `requireAuth` | Tạo đánh giá — xem quy trình bên dưới |
| `PATCH /reviews/:id/reply` | merchant (đúng target) hoặc admin | Trả lời đánh giá |
| `PATCH /reviews/:id/hidden` | admin (mọi loại) / merchant (chỉ loại `merchant` của mình) | Ẩn/hiện |

**`POST /reviews` — thứ tự kiểm tra**: `requireAuth` → bắt buộc `order_id, target_type, target_id,
rating` → tìm `order` (404 nếu không có) → `order.customer_id !== ctx.userId` → `403` (chặn đánh
giá hộ) → `!['delivered','completed'].includes(order.status)` → `400` ("Chỉ đánh giá được sau khi
đơn đã giao") → `rating` ngoài 1-5 → `400` → `INSERT`; vi phạm `UNIQUE` → `409 DUPLICATE`.

**Luồng khách hàng** (`hofa_customer_app`): `Order.canReview` = `['delivered','completed']`
quyết định hiện nút "Đánh giá cửa hàng" trên `OrderDetailScreen` → dialog chọn sao (1-5) + nhận
xét → `POST /reviews` với `targetType:'merchant'`.

⚠️ **Nút "Đánh giá" không tự ẩn sau khi đã gửi** — client không kiểm tra đã review chưa (không gọi
lại `GET /reviews` để lọc theo chính mình), chỉ phụ thuộc `status` đơn. Bấm gửi lần 2 → `409` hiện
thông báo lỗi thô, không thân thiện.

⚠️ **Chỉ có luồng đánh giá cửa hàng (`target_type='merchant'`) hoạt động trên app** — dù schema/API
hỗ trợ đầy đủ cả 3 loại (`merchant|driver|product`), không tìm thấy nơi nào trong
`hofa_customer_app` gửi review cho `product`/`driver`. Sản phẩm chỉ **hiển thị** review có sẵn
(đọc `GET /reviews?target_type=product`), không có nút viết đánh giá sản phẩm.

⚠️ **`hofa_store_app` không có màn hình trả lời đánh giá** — endpoint `PATCH /reviews/:id/reply`
tồn tại nhưng chưa có UI phía cửa hàng.

### 6.2. Mã giảm giá (Voucher)

**Bảng `vouchers`**: `code UNIQUE, merchant_id (NULL = mã toàn sàn), discount_type(percent|fixed|
free_shipping), discount_value, max_discount, min_order_amount, usage_limit(NULL=vô hạn),
usage_limit_per_user(default 1), used_count, starts_at/ends_at, is_active`. Bảng
`voucher_redemptions`: `(voucher_id, user_id, order_id, discount_amount)`, UNIQUE
`(voucher_id, order_id)`. `orders.voucher_code` chỉ lưu **code** (không FK), `orders.
discount_amount` khớp constraint `orders_total_matches`.

**Ai tạo/sửa voucher?** (`server/src/routes/vouchers.js`)
- Có `merchant_id` trong body → `requireMerchantAccess` — owner/staff của đúng cửa hàng, hoặc
  admin.
- Không có `merchant_id` (mã toàn sàn) → **chỉ `admin`**.
- Quyền sửa/tắt voucher đã tồn tại luôn đọc `voucher.merchant_id` từ DB (không phải từ body) —
  merchant không thể "chiếm" voucher toàn sàn.

⚠️⚠️ **Không có UI nào (store app lẫn admin app) để tạo/sửa/tắt voucher** — chỉ gọi được qua API
trực tiếp. Đây là gap giống hệt bậc giá sỉ (mục 3.4).

**`POST /vouchers/validate`** (dùng khi khách nhập mã ở checkout — **không trừ lượt dùng**, chỉ mô
phỏng để hiển thị số tiền giảm dự kiến). Luôn trả `200`, app phải tự đọc field `valid`:
`code` không tồn tại/`is_active=false` → `valid:false` → sai cửa hàng (`merchant_id` khác) →
chưa/hết hạn (`starts_at`/`ends_at`) → chưa đạt `min_order_amount` → hết lượt toàn hệ thống
(`used_count >= usage_limit`) → hết lượt cá nhân (đếm `voucher_redemptions` theo `user_id`).

⚠️ **`free_shipping` bị tính sai ở bước validate** — route chỉ có nhánh `percent`/`fixed`, không có
`free_shipping` → `estimated_discount` trả về `0` (gây hiểu lầm cho khách), trong khi RPC lúc đặt
hàng thật tính đúng bằng `delivery_fee`.

**Áp dụng thật sự khi đặt hàng** — toàn bộ nằm trong RPC `create_order` (không phải Node), **khoá
dòng voucher `FOR UPDATE`** để chống race condition khi nhiều đơn cùng lúc dùng 1 mã gần hết lượt:
kiểm tra lại toàn bộ điều kiện (hạn, đơn tối thiểu, lượt dùng chung/riêng) → tính `discount` (có
trần `max_discount` cho `percent`; `free_shipping` = đúng `delivery_fee`) → `LEAST(discount,
subtotal + delivery_fee)` (chặn đơn âm tiền) → `used_count += 1` → `INSERT voucher_redemptions` —
tất cả trong 1 transaction, rollback toàn bộ nếu lỗi.

⚠️ **Race giữa validate và đặt hàng**: `validate` không khoá dữ liệu (chỉ ước lượng) — khách có thể
thấy mã hợp lệ lúc kiểm tra nhưng đặt hàng thất bại nếu người khác vừa dùng hết lượt trong lúc đó.

⚠️ Checkout customer app chỉ gửi `voucher_code` khi tạo đơn **nếu đã bấm "Kiểm tra" và hợp lệ**
(`_voucherDiscount > 0`) — gõ mã mà quên bấm kiểm tra thì mã bị bỏ qua hoàn toàn, không cảnh báo.

### 6.3. Quản trị hệ thống (Admin)

> Lưu ý vị trí code: `GET /admin/stats` nằm ở `server/src/routes/admin.js`; toàn bộ CRUD user
> (`GET/PATCH/DELETE /admin/users*`) nằm ở `server/src/routes/users.js` — cùng base URL, khác file.

**`GET /admin/stats`** — 5 truy vấn song song (`Promise.all`): `users` (tổng/customer/merchant/
driver/blocked), `merchants` (tổng/active/pending_review/paused), `orders` (tổng/hôm nay/đang
chạy/huỷ), `revenue` (**chỉ tính đơn `delivered`/`completed`**), `recentOrders` (8 đơn mới nhất).

**Quản lý user** (`server/src/routes/users.js:59-124`):

| Method & Path | Mô tả |
|---|---|
| `GET /admin/users` | Lọc `role`/`status`, loại `password_hash` khỏi response |
| `GET /admin/users/:id` | Kèm `addresses` |
| `PATCH /admin/users/:id` | Chỉ `full_name, email, phone, avatar_url, date_of_birth` — không đổi role/status |
| `PATCH /admin/users/:id/status` | Đổi `status` bất kỳ giá trị enum |
| `PATCH /admin/users/:id/role` | Đổi `role` bất kỳ giá trị enum |
| `DELETE /admin/users/:id` | Xoá mềm: `deleted_at=now()` **và** `status='banned'` cùng lúc |

⚠️⚠️ **Không có bảo vệ nào chống admin tự khoá/tự hạ quyền chính mình** — không route nào so sánh
`req.params.id` với `ctx.userId`, và UI (`UsersScreen`/`UserDetailScreen`) cũng không disable nút
khi đang xem chính mình. Hệ quả nghiêm trọng nhất: admin tự đổi `role` khỏi `'admin'` → **request
kế tiếp bị `403` ở mọi API admin, kể cả API để tự khôi phục** — phải sửa trực tiếp DB.

⚠️ **"Mở khoá" trong UI luôn set `status='active'`** bất kể trạng thái khoá trước đó là `suspended`
hay `banned` — không phân biệt 2 mức độ.

⚠️ Không whitelist giá trị `status`/`role` ở tầng Node cho 2 route trên — dựa hoàn toàn vào enum
Postgres để chặn giá trị rác (giá trị sai → lỗi DB được map thành `400 BAD_INPUT`).

**`AdminLoginScreen` & `router.dart`** — kiểm tra role admin **2 lớp độc lập**: (1) ngay sau
`signInWithPassword`, tự `signOut()` nếu `profile.role != 'admin'`; (2) trong `router.redirect`,
chạy lại kiểm tra này ở **mỗi lần điều hướng** (không chỉ lúc login) — phòng trường hợp role bị hạ
giữa phiên làm việc. Lỗi mạng tạm thời khi gọi `/me` **không** đá người dùng ra (tránh logout oan).

⚠️ Giới hạn của lớp UI: nếu admin đứng yên trên 1 trang (không điều hướng) và bị đổi role ngay lúc
đó, UI không tự động đá ra ngay lập tức — nhưng mọi API call tiếp theo vẫn bị chặn `403` (bảo vệ
thật sự nằm ở backend, `requireRole` đọc `role` mới từ DB mỗi request).

---

## 7. Tổng hợp các khoảng trống & rủi ro kỹ thuật

Danh sách toàn bộ ⚠️ phát hiện được trong lúc khảo sát, gom lại để dễ tra cứu khi lên kế hoạch xử lý:

### Auth / Phân quyền
1. OTP không có thật — mã cố định `123123`, không xác minh quyền sở hữu SĐT.
2. `users.status` (`banned/suspended`) và `deleted_at` **không được kiểm tra ở tầng API** — user
   bị khoá vẫn dùng được mọi endpoint nếu JWT Supabase còn hạn.
3. Đăng xuất không xoá `user_devices`/vô hiệu push token — thiết bị dùng chung có thể nhận push
   cho tài khoản cũ đã đăng xuất.
4. `sessions` table và `merchant_staff.permissions` là schema chết — không có code đọc/ghi.
5. `merchant_staff` không đăng nhập dùng được `hofa_store_app` (kẹt vô hạn ở `/onboarding`) vì
   `GET /merchants/mine` chỉ lọc `owner_id`.
6. `hofa_driver_app` router có thể bỏ qua redirect nếu `GET /drivers/me` trả `403` (lỗi bị nuốt).

### Merchant
7. Không có bước "nộp duyệt" tự động — merchant `draft` vào thẳng dashboard đầy đủ chức năng.
8. Merchant `rejected` không có cách tự "nộp lại" qua UI, phải chờ admin.
9. Không có UI "Thêm chi nhánh mới" — multi-branch chỉ tồn tại ở tầng API/DB.
10. Không có UI mời/quản lý nhân viên cửa hàng ở cả store app và admin app.
11. Owner có nhiều merchant — chỉ truy cập được merchant mới nhất qua `hofa_store_app`.
12. `commission_rate` có thể bị chính owner tự sửa qua API (dù UI ẩn field).

### Catalog / Kho / Bán sỉ
13. Giới hạn 2 cấp danh mục chỉ là quy ước UI, DB cho phép vô hạn cấp.
14. Danh mục `is_active=false` không có cách xem lại/bật lại.
15. Không có UI gán danh mục cho sản phẩm ở store app (`PUT /products/:id/categories` mồ côi).
16. Không có UI tạo/sửa/xoá bậc giá sỉ (`wholesale_tiers`) ở bất kỳ app nào.
17. Trường đặt cọc bán sỉ (`requires_deposit`/`deposit_percent`) không hiển thị cho khách.
18. Không kiểm tra tồn kho ở bước thêm-vào-giỏ — chỉ chặn lúc tạo đơn.
19. Tìm kiếm sản phẩm dùng `ILIKE`, không tận dụng GIN full-text index đã tạo sẵn.
20. `GET /products/:id` không kiểm tra quyền sở hữu — ai cũng xem được chi tiết nếu biết ID, kể cả
    sản phẩm `draft`/`hidden`.

### Order / Delivery / Payment
21. `refund_payment` khi order có nhiều dòng payment có thể set `orders.payment_status` sai lệch.
22. Giao hàng thất bại (`deliveries.status='failed'`) không tự động re-dispatch — cần can thiệp
    thủ công.
23. Không có polling nền tự tìm tài xế mới cho các đơn "kẹt" (không ai nhận) — cần merchant bấm
    "Tìm tài xế" thủ công.
24. Không có API rút tiền ví tài xế — quy trình ngoài hệ thống.
25. Webhook thanh toán (`POST /payments/webhook`) **chưa verify chữ ký số thật** của
    MoMo/VNPay/ZaloPay — chỉ so 1 secret dùng chung, không an toàn để dùng thật.
26. Doanh thu admin dashboard tính từ `orders`, không đối chiếu với `payments` — có thể lệch với
    COD chưa được xác nhận đã thu.

### Review / Voucher / Admin
27. Nút "Đánh giá cửa hàng" không tự ẩn sau khi đã gửi — có thể bấm gửi trùng, nhận lỗi `409` thô.
28. Chỉ luồng đánh giá **cửa hàng** hoạt động end-to-end trên app — đánh giá sản phẩm/tài xế và
    trả lời đánh giá (phía merchant) chưa có UI dù backend/DB đã sẵn sàng.
29. Không có UI tạo/sửa/tắt voucher ở cả store app và admin app — chỉ gọi được qua API trực tiếp.
30. Bước "Kiểm tra mã" (`/vouchers/validate`) không khoá dữ liệu — có thể báo hợp lệ nhưng đặt
    hàng thất bại ngay sau đó nếu mã vừa hết lượt (race condition, RPC `create_order` là nguồn sự
    thật cuối cùng, có khoá `FOR UPDATE`).
31. `free_shipping` bị tính sai (hiển thị giảm 0đ) ở bước validate, dù áp đúng lúc đặt hàng thật.
32. Gõ mã voucher mà quên bấm "Kiểm tra" → mã bị bỏ qua hoàn toàn khi đặt hàng, không cảnh báo.
33. **Không có bảo vệ chống admin tự khoá/tự hạ quyền chính mình** — tự đổi `role` khỏi `admin` sẽ
    tự loại mình khỏi mọi trang quản trị ngay từ request kế tiếp, phải sửa trực tiếp DB để khôi
    phục. Cả server lẫn UI admin app đều không có kiểm tra này.
34. "Mở khoá" tài khoản trong UI luôn set thẳng `active`, không phân biệt mức độ khoá trước đó
    (`suspended` vs `banned`).

---

## Ghi chú phương pháp

Tài liệu này được tổng hợp từ 6 lượt khảo sát đọc-mã-nguồn độc lập (auth/role/device, merchant
onboarding, catalog/inventory/wholesale, vòng đời đơn hàng, giao hàng-tài xế/thanh toán,
đánh giá-voucher/quản trị), đối chiếu chéo `hofa-db/`, `server/src/`, và cả 4 app Flutter. Các mục
đánh dấu ⚠️ là khoảng trống/nợ kỹ thuật phát hiện qua đọc trực tiếp code (không phải suy đoán) —
nên được rà soát lại trước khi dùng tài liệu này để lên kế hoạch phát triển hoặc audit bảo mật.
