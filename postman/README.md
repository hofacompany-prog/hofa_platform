# Test API + Database bằng Postman

File `hofa-platform.postman_collection.json` chứa sẵn 11 request theo đúng thứ tự, giả lập
1 luồng thật: tạo tài khoản → tạo cửa hàng → thêm sản phẩm → nhập kho → đặt đơn → xác nhận đơn.
Mỗi request tự lưu lại token/id cần cho request sau — bạn chỉ cần bấm **Send** lần lượt từ trên
xuống, không phải tự copy-paste gì cả.

---

## Bước 1 — Cài Postman (nếu chưa có)

Tải ở [postman.com/downloads](https://www.postman.com/downloads/), cài như app bình thường.
Không bắt buộc phải đăng ký tài khoản Postman để dùng tính năng này.

## Bước 2 — Import file test

Mở Postman → **File > Import** (hoặc kéo thả file) → chọn file
`hofa-platform.postman_collection.json` trong thư mục này.

## Bước 3 — Điền 3 giá trị bí mật

Bấm vào tên collection **"HOFA Platform — Test API + Database"** ở cột bên trái → tab
**Variables**. Điền cột **CURRENT VALUE** cho 3 dòng sau (lấy ở Supabase > Project Settings > API):

| Biến | Lấy ở đâu |
|---|---|
| `supabase_url` | Project URL, dạng `https://xxxxx.supabase.co` |
| `supabase_anon_key` | mục **anon / public** key |
| `supabase_service_key` | mục **service_role** key — **giữ kín, không chia sẻ file này cho ai sau khi điền** |

Các biến còn lại (`api_base_url`, `test_email`...) đã điền sẵn, không cần đổi. Bấm **Save**.

## Bước 4 — Chạy lần lượt

Mở từng request theo thứ tự **0.1 → 0.2 → 1.1 → 1.2 → ... → 1.11**, bấm nút xanh **Send**,
xem tab **Test Results** bên dưới — mỗi request phải hiện dấu tích xanh (pass). Nếu có dấu ✗
đỏ, đọc dòng chữ lỗi, đó thường là chỉ dẫn khá rõ (thiếu tồn kho, sai quyền, thiếu tham số...).

**Mẹo nhanh hơn:** click phải vào tên collection > **Run collection** > bấm **Run HOFA Platform**
— Postman tự chạy hết 11 request theo thứ tự chỉ trong vài giây, hiện luôn bảng tổng kết pass/fail.

## Ý nghĩa từng request

| # | Request | Kiểm tra gì |
|---|---|---|
| 0.1 | Tạo user test | Tạo tài khoản đăng nhập test qua Supabase Admin API (auto-confirm, khỏi cần xác thực email) |
| 0.2 | Đăng nhập lấy access_token | Xác nhận Supabase Auth hoạt động, lấy JWT để gọi các bước sau |
| 1.1 | Đồng bộ hồ sơ | API tạo được dòng `users` với đúng `id` = id của Supabase Auth |
| 1.2 | Xem hồ sơ | JWT xác thực đúng, tra được role |
| 1.3 | Tạo cửa hàng | Ghi được vào bảng `merchants`, tự nâng role lên `merchant_owner` |
| 1.4 | Tạo chi nhánh | Ghi được vào `branches`, đúng quyền chủ cửa hàng |
| 1.5 | Tạo sản phẩm | Ghi được vào `products` |
| 1.6 | Tạo biến thể + giá | Ghi được vào `product_variants` |
| 1.7 | Nhập kho | Gọi đúng hàm RPC `apply_stock_movement`, tồn kho lên đúng 100 |
| 1.8 | Đặt đơn hàng | Gọi đúng hàm RPC `create_order` — chốt giá từ DB (không tin giá client), giữ tồn kho, tính đúng tổng tiền |
| 1.9 | Xem đơn hàng | Đơn + món hàng khớp dữ liệu vừa tạo |
| 1.10 | Xác nhận đơn | Gọi đúng hàm RPC `update_order_status`, đúng state machine |
| 1.11 | Xem lịch sử trạng thái | Trigger tự ghi `order_status_history` hoạt động đúng |

Nếu cả 11 request đều xanh — nghĩa là toàn bộ chuỗi API ↔ RPC ↔ Database đã thông suốt,
có thể yên tâm bắt đầu làm UI app rồi.

## Chạy lại nhiều lần

Chạy lại từ đầu vẫn được — bước 0.1 sẽ báo lỗi "đã tồn tại" (bình thường, cứ bỏ qua), bước 1.3
tự sinh `slug` khác nhau mỗi lần (nhờ `{{$timestamp}}`) nên không bị trùng.

## Lưu ý bảo mật

File JSON này sau khi bạn điền `supabase_service_key` vào sẽ chứa 1 khoá rất mạnh (bỏ qua
được mọi lớp bảo vệ dữ liệu). **Không commit file đã điền key vào git, không gửi cho ai.**
Nếu lỡ làm lộ, vào Supabase > Project Settings > API > bấm **Reset** để đổi key mới ngay.
