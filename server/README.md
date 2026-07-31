# API HOFA — Node.js/Express, chạy trên Render

Ngày 30/07/2026. Đây là bản thay thế cho `gas/` (Google Apps Script) — cùng logic nghiệp vụ,
cùng 8 hàm RPC trong `../04_api_functions.sql`, nhưng chạy như 1 server Node.js thật.

So với bản GAS, bản này:
- Có route chuẩn REST (`GET /products`, `POST /orders`...) thay vì 1 endpoint + `action` string.
- Trả đúng HTTP status code (200/401/403/404...) thay vì luôn luôn 200.
- Đọc token qua header `Authorization: Bearer <token>` thật, không cần nhét vào query/body.
- Kết nối thẳng Postgres qua `pg` (không qua PostgREST), gọi RPC bằng SQL trực tiếp.

---

## Phần 1 — Triển khai lên Render (10 phút)

**Bước 1.** Nếu chưa, chạy `01_schema.sql` rồi `04_api_functions.sql` trong Supabase SQL Editor.

**Bước 2.** Đẩy thư mục này (`server/`) lên 1 GitHub repo (Render deploy từ git).

**Bước 3.** Vào [render.com](https://render.com) > **New > Blueprint**, chọn repo vừa đẩy.
Render tự đọc `render.yaml` và đề nghị tạo 1 Web Service tên `hofa-api`. Bấm **Apply**.

Không dùng Blueprint? Tạo thủ công: **New > Web Service**, trỏ vào repo, điền:
- Root Directory: `server`
- Build Command: `npm install`
- Start Command: `npm start`

**Bước 4.** Vào tab **Environment** của service, thêm 3 biến:

| Biến | Lấy ở đâu |
|---|---|
| `DATABASE_URL` | Supabase > Project Settings > Database > Connection string > mục **Session pooler** (cổng 5432). Nhớ thay `[YOUR-PASSWORD]` bằng mật khẩu database thật. |
| `SUPABASE_URL` | Supabase > Project Settings > General > Project ID → ghép thành `https://<project-id>.supabase.co`. Không phải bí mật, chỉ là địa chỉ project (dùng để lấy khoá công khai xác minh JWT). |
| `PAYMENT_WEBHOOK_SECRET` | Tự đặt 1 chuỗi dài ngẫu nhiên (vd: mở terminal gõ `openssl rand -hex 32`) |

**Vì sao dùng "Session pooler" chứ không phải kết nối trực tiếp cổng 5432 gốc?**
Render (và hầu hết PaaS) không cấp IPv6 tĩnh, mà Supabase yêu cầu IPv6 cho kết nối
trực tiếp ở nhiều region. Pooler (Supavisor) hỗ trợ IPv4, ổn định hơn khi deploy ngoài
mạng nội bộ Supabase.

**Bước 5.** Bấm **Deploy**. Xem tab **Logs**, thấy dòng `HOFA API đang chạy ở cổng ...`
là thành công. Test nhanh:

```bash
curl https://<ten-service>.onrender.com/health
```

Phải trả về `{"ok":true,"data":{"status":"up"}}`.

**Chạy thử ở máy mình trước khi deploy (khuyến khích):**
```bash
cd server
cp .env.example .env   # rồi điền 3 biến ở trên vào .env
npm install
npm run dev
```

---

## Phần 2 — Cách gọi API

Mọi request kèm token thật qua header chuẩn:

```
GET /products?merchant_id=xxx
Authorization: Bearer eyJhbGciOi...
```

```
POST /orders
Authorization: Bearer eyJhbGciOi...
Content-Type: application/json

{
  "merchant_id": "...",
  "branch_id": "...",
  "items": [{"variant_id": "...", "quantity": 2, "note": "rau non"}],
  "ship_recipient_name": "Nguyễn Văn A",
  "ship_recipient_phone": "0901234567",
  "ship_line1": "45 Nguyễn Văn Cừ",
  "ship_province": "Đà Nẵng",
  "payment_method": "cod"
}
```

Phản hồi luôn dạng:
```json
{ "ok": true, "data": { ... } }
{ "ok": false, "error": { "code": "FORBIDDEN", "message": "..." } }
```
Nay HTTP status code đã phản ánh đúng lỗi (401/403/404/409/500...), nhưng vẫn nên đọc
field `ok` cho chắc — một số lỗi nghiệp vụ (vd: hết tồn kho) trả 400 kèm message rõ ràng.

**id trong `public.users` phải trùng với id của Supabase Auth** — giống hệt yêu cầu ở bản
GAS. Sau khi client đăng nhập/đăng ký lần đầu qua Supabase Auth, gọi ngay `POST /me/sync`
với access token vừa nhận, để tạo dòng hồ sơ tương ứng.

---

## Phần 3 — Danh sách route theo module

| Module | Route | Ai gọi được | Ghi chú |
|---|---|---|---|
| **Auth/User** | `GET /me` | đã đăng nhập | |
| | `POST /me/sync` | đã đăng nhập | gọi ngay sau lần đăng nhập đầu tiên |
| | `PATCH /me` | đã đăng nhập | |
| | `GET/PATCH /admin/users...` | admin | |
| | `GET/POST/PATCH/DELETE /addresses` | chủ địa chỉ | |
| | `GET/POST /devices` | đã đăng nhập | |
| **Merchant** | `GET /merchants`, `GET /merchants/:id` | công khai | |
| | `POST/PATCH /merchants...` | chủ/nhân viên/admin | |
| | `POST /merchants/:id/submit-for-review` | chủ/nhân viên | |
| | `POST /merchants/:id/review` | admin | duyệt/từ chối |
| | `PATCH /merchants/:id/pause` | chủ/nhân viên | |
| | `GET/POST/PATCH /merchants/:id/branches`, `/branches/:id` | công khai (get); chủ/nhân viên/admin (còn lại) | |
| | `PATCH /branches/:id/toggle-open` | chủ/nhân viên/admin | công tắc nhanh |
| | `GET/PUT /branches/:id/hours` | công khai (get); chủ/nhân viên (put) | |
| | `GET/POST/DELETE /merchants/:id/staff` | chủ/nhân viên/admin | |
| **Product** | `GET/POST/PATCH /categories` | công khai (get); admin (còn lại) | |
| | `GET /products`, `GET /products/:id` | công khai | chủ/nhân viên/admin thấy thêm trạng thái không active |
| | `POST/PATCH/DELETE /products/:id` | chủ/nhân viên/admin | delete = xoá mềm |
| | `PUT /products/:id/categories` | chủ/nhân viên/admin | |
| | `GET/POST /products/:id/variants`, `PATCH/DELETE /variants/:id` | công khai (get); chủ/nhân viên/admin (còn lại) | |
| **Wholesale** | `GET/POST /variants/:id/wholesale-tiers`, `PATCH/DELETE /wholesale-tiers/:id` | công khai (get); chủ/nhân viên/admin (còn lại) | |
| **Inventory** | `GET /branches/:id/inventory`, `/inventory/low-stock` | chủ/nhân viên/admin | |
| | `POST /inventory/adjust` | chủ/nhân viên/admin | gọi RPC apply_stock_movement |
| | `GET /branches/:id/stock-movements` | chủ/nhân viên/admin | |
| **Order** | `POST /orders` | khách | gọi RPC create_order |
| | `GET /orders/:id`, `/orders/:id/history` | khách/chủ quán/tài xế liên quan/admin | |
| | `GET /orders/mine` | khách | |
| | `GET /merchants/:id/orders` | chủ/nhân viên/admin | |
| | `PATCH /orders/:id/status` | tuỳ trạng thái đích | gọi RPC update_order_status |
| **Driver** | `GET/PATCH /drivers/me...` | tài xế | |
| | `POST /drivers/register` | đã đăng nhập | |
| | `GET /drivers/available` | chủ/nhân viên/admin | |
| | `GET/POST /admin/drivers...` | admin | |
| **Delivery** | `GET /orders/:id/delivery` | như quyền xem đơn | |
| | `GET /deliveries/mine` | tài xế | |
| | `POST /orders/:id/assign-driver` | chủ/nhân viên/admin | gọi RPC assign_driver |
| | `PATCH /deliveries/:id/status` | tài xế phụ trách | gọi RPC update_delivery_status, cần OTP |
| | `POST/GET /deliveries/:id/tracks` | tài xế (post); quyền xem đơn (get) | |
| **Payment** | `GET /orders/:id/payments` | như quyền xem đơn | |
| | `POST /payments` | tài xế phụ trách (COD)/chủ/nhân viên/admin | gọi RPC record_payment |
| | `POST /payments/:id/refund` | chủ/nhân viên/admin | gọi RPC refund_payment |
| | `POST /payments/webhook` | cổng thanh toán (webhook_secret) | **thay xác minh thật trước khi dùng** |
| **Review** | `GET /reviews` | công khai | |
| | `POST /reviews` | khách có đơn đã giao | |
| | `PATCH /reviews/:id/reply`, `/hidden` | chủ/nhân viên (merchant)/admin | |
| **Voucher** | `GET /vouchers` | công khai | |
| | `POST/PATCH /vouchers...` | chủ/nhân viên (mã riêng)/admin (mã toàn sàn) | |
| | `POST /vouchers/validate` | khách | không trừ lượt |

---

## Phần 4 — Việc KHÔNG được bỏ qua

- **Bật Row Level Security** trên Supabase trước khi đưa dữ liệu khách thật vào (server
  dùng kết nối trực tiếp với quyền đầy đủ, tương đương service_role — RLS vẫn nên bật
  để chặn rò rỉ nếu sau này có ai lỡ dùng chuỗi kết nối này ở nơi khác).
- **Không commit `.env`** — đã có trong `.gitignore`, nhưng double-check trước khi push.
- **`POST /payments/webhook` mới là khung sườn** — phải thay bằng xác minh chữ ký thật của
  MoMo/VNPay/ZaloPay trước khi nhận tiền thật.
- Trên gói Render **Free**, service tự "ngủ" sau 15 phút không có request và mất khoảng
  30-50 giây để "thức dậy" ở lần gọi tiếp theo — bình thường khi test, nhưng cân nhắc gói
  trả phí (hoặc dịch vụ ping định kỳ) nếu cần phản hồi tức thời cho người dùng thật.
- Test thử toàn luồng: `POST /me/sync` → tạo cửa hàng → thêm sản phẩm → `POST /orders` →
  xác nhận → gán tài xế → lấy hàng (OTP) → giao hàng (OTP) → đánh giá.
- **Về xác minh JWT**: Supabase đang dần chuyển các project sang hệ thống "JWT Signing Keys"
  (ký bất đối xứng, vd ES256) thay cho secret HS256 dùng chung kiểu cũ. Server này verify
  bằng JWKS (khoá công khai, tự tải qua `SUPABASE_URL`) nên tương thích với cả 2 kiểu —
  không cần biết project của bạn đang ở kiểu nào.

---

## Phần 5 — Ghi chú

Bản Google Apps Script (thư mục `gas/`) đã được gỡ bỏ khỏi repo — dự án giờ chỉ dùng
lớp API Node.js/Express này. Vẫn dùng chung `01_schema.sql` và `04_api_functions.sql`
với database, chỉ đổi lớp API.
