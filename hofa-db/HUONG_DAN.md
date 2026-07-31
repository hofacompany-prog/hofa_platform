# Database HOFA — Hướng dẫn cho người không biết code

Ngày 30/07/2026 · Dựa trên SDD mục 7 · PostgreSQL

---

## Phần 1 — Ba khái niệm cần hiểu trước

Chỉ ba cái này thôi, hiểu rồi là đọc được toàn bộ phần còn lại.

**Bảng (table)** giống một sheet trong Excel. Bảng `products` là sheet danh sách sản phẩm, mỗi dòng một sản phẩm.

**Khoá ngoại (foreign key)** là cách nối hai bảng. Trong bảng `orders` có cột `customer_id` chứa mã của khách. Nhờ vậy máy biết đơn này của ai mà không phải chép lại tên, số điện thoại, địa chỉ vào từng đơn. Giống như bạn ghi "đơn của khách số 12" rồi tra sổ khách hàng ở trang 12.

**Ràng buộc (constraint)** là luật bạn cài sẵn để dữ liệu sai *không thể* ghi vào. Ví dụ đã cài: tổng tiền phải bằng tiền hàng + phí giao + thuế − giảm giá. Nếu app viết sai phép tính, database sẽ từ chối thay vì lặng lẽ lưu con số lệch. Cái này quan trọng hơn bạn tưởng — tiền lệch mà không ai biết là vấn đề đắt nhất của mọi hệ thống bán hàng.

---

## Phần 2 — Tại sao t chọn PostgreSQL + Supabase

SDD của bạn đã ghi PostgreSQL, và đó là lựa chọn đúng. T dựng theo đúng vậy.

Nhưng PostgreSQL trần thì bạn phải tự dựng server, tự lo sao lưu, tự viết API — không làm được nếu không biết code. Nên t khuyên dùng **Supabase**: đó là PostgreSQL thật, có sẵn:

- Bảng hiển thị như Excel, bạn bấm sửa trực tiếp được
- Tự sinh API — app gọi dữ liệu được ngay, không cần viết backend
- Có sẵn hệ thống đăng nhập, lưu ảnh
- Miễn phí ở mức nhỏ; khoảng 25 USD/tháng khi lớn hơn
- Nếu sau này muốn chuyển đi, mang nguyên database đi được vì nó là Postgres chuẩn

Không bị khoá chân vào ai. Đây là điểm t quan tâm nhất khi chọn giúp bạn.

---

## Phần 3 — Chạy thử trong 10 phút

**Bước 1.** Vào `supabase.com`, đăng ký, bấm **New project**. Chọn region gần nhất (Singapore). Đặt mật khẩu database và **lưu lại chỗ nào an toàn** — mất là phải tạo lại project.

**Bước 2.** Trong project, mở **SQL Editor** ở cột bên trái, bấm **New query**.

**Bước 3.** Mở file `01_schema.sql`, copy toàn bộ, dán vào, bấm **Run**. Thấy "Success" là xong — 25 bảng đã được tạo.

**Bước 4.** Làm lại với `02_seed_quan_ben_ruong.sql`. File này nhồi dữ liệu mẫu của Quán Bên Ruộng và chạy trọn hai đơn hàng. Cuối file có 7 câu truy vấn kiểm tra, kết quả hiện ngay bên dưới.

**Bước 5.** Mở **Table Editor** để xem các bảng như Excel. Bấm vào `orders` — bạn sẽ thấy hai đơn với đủ tiền, trạng thái, giờ giấc.

Nếu bước nào báo lỗi đỏ, copy nguyên dòng lỗi đưa t, t sửa.

---

## Phần 4 — 25 bảng, giải thích bằng tiếng người

### Nhóm người dùng

| Bảng | Giữ cái gì | Ví dụ ở quán bạn |
|---|---|---|
| `users` | Mọi người dùng: khách, chủ quán, nhân viên, tài xế, admin | Bạn, chị Uyên bán hàng, anh Tân shipper, khách Lan |
| `addresses` | Địa chỉ khách đã lưu | "Nhà — 45 Nguyễn Văn Cừ, cổng xanh, gọi trước 5 phút" |
| `user_devices` | Điện thoại đã đăng nhập | Để gửi thông báo đơn mới, và phát hiện đăng nhập lạ |
| `sessions` | Phiên đăng nhập | Cho phép "đăng xuất khỏi mọi thiết bị" khi mất máy |

Một người **một dòng duy nhất** trong `users`, dù họ vừa là khách vừa là tài xế. Tránh được cảnh cùng một số điện thoại nằm ở ba nơi với ba cái tên viết khác nhau.

### Nhóm cửa hàng

| Bảng | Giữ cái gì |
|---|---|
| `merchants` | Cửa hàng: tên, giấy phép, tài khoản ngân hàng, % hoa hồng, điểm sao |
| `branches` | Chi nhánh: địa chỉ, toạ độ GPS, bán kính giao, công tắc đóng/mở |
| `branch_hours` | Giờ mở cửa từng ngày trong tuần |
| `merchant_staff` | Nhân viên và quyền của họ |

Tại sao tách `merchants` và `branches`? Vì **hàng và tài xế thuộc chi nhánh, không thuộc cửa hàng**. Hôm nay bạn một chi nhánh, mai mở chi nhánh Hòa Khánh thì chỉ thêm một dòng — không phải đập lại hệ thống.

Cột `is_open` ở `branches` là công tắc bạn sẽ dùng mỗi ngày: hết rau thì tắt, khỏi nhận thêm đơn rồi phải gọi xin lỗi khách.

### Nhóm sản phẩm

| Bảng | Giữ cái gì |
|---|---|
| `categories` | Danh mục lồng nhau: Thực phẩm › Rau củ quả › Rau ăn lá |
| `products` | Sản phẩm cha: tên, mô tả, ảnh, bán lẻ hay bán sỉ |
| `product_variants` | **Biến thể — giá nằm ở đây** |
| `product_categories` | Nối sản phẩm với nhiều danh mục |
| `wholesale_tiers` | Bậc giá sỉ theo số lượng |

Chỗ này dễ nhầm nhất, nên nói rõ: **giá không nằm ở `products`, mà ở `product_variants`.**

"Rau muống" là một `product`. Nhưng bạn bán "1 bó 8.000đ" và "3 bó 22.000đ" — đó là hai `product_variants`. Khách bỏ vào giỏ là bỏ biến thể, không phải sản phẩm. Đúng ví dụ trong SDD của bạn: rau cải → 500g / 1kg / 2kg.

T cũng thêm cột `cost_price` (giá nhập). SDD không có, nhưng thiếu nó thì bạn không bao giờ biết lãi thật bao nhiêu — chỉ biết doanh thu.

`wholesale_tiers` là phần khác biệt của HOFA. Ví dụ đã nhồi sẵn:

| Mua từ | Giá | Giao sau | Cọc |
|---|---|---|---|
| 50 kg | 15.000đ/kg | 1 ngày | không |
| 100 kg | 13.500đ/kg | 2 ngày | không |
| 500 kg | 12.000đ/kg | 5 ngày | 30% |
| 1.000 kg | 10.500đ/kg | 7 ngày | 50% |

### Nhóm tồn kho

| Bảng | Giữ cái gì |
|---|---|
| `inventory` | Số lượng còn, theo từng chi nhánh |
| `stock_movements` | Sổ nhật ký: mọi lần hàng vào/ra |

`inventory` có hai con số quan trọng: `quantity_on_hand` (thực tế đang có) và `quantity_reserved` (đã bị đơn khác giữ). **Số bán được = on_hand − reserved.**

Không có `reserved` thì hai khách cùng đặt bó rau cuối cùng, cả hai đều thành công, rồi bạn phải gọi xin lỗi một người. Có nó thì người thứ hai thấy "hết hàng" ngay.

`stock_movements` chỉ được **ghi thêm, không sửa không xoá**. Cuối tháng kiểm kê thấy lệch 3kg, bạn mở sổ này ra truy được lệch ở đâu, ai nhập, lúc nào. Không có nó thì chỉ biết là lệch.

### Nhóm đơn hàng — quan trọng nhất

| Bảng | Giữ cái gì |
|---|---|
| `orders` | Đơn: khách, cửa hàng, địa chỉ, tiền, trạng thái, thời gian |
| `order_items` | Từng món trong đơn |
| `order_status_history` | Ai đổi trạng thái, lúc nào, từ gì sang gì |

Hai quyết định t muốn bạn hiểu rõ, vì nó ngược với trực giác:

**1. Địa chỉ được chép vào đơn, không phải trỏ tới bảng địa chỉ.**
Đơn hàng có `ship_line1`, `ship_ward`, `ship_district`... thay vì chỉ một `address_id`. Nghe như dư thừa. Nhưng nếu chỉ trỏ, khách sửa địa chỉ tháng sau thì **đơn cũ đổi địa chỉ theo** — hoá đơn và lịch sử giao hàng sai hết. Đơn hàng là chứng từ, phải đóng băng.

**2. Tên và giá món cũng được chép vào `order_items`.**
Cùng lý do. Bạn tăng giá rau muống lên 10.000đ thì đơn tuần trước vẫn phải là 8.000đ.

`order_status_history` được ghi **tự động** bằng trigger — bạn không phải làm gì. Khi khách khiếu nại "đặt 2 tiếng chưa thấy", mở bảng này ra là biết đơn nằm ở bước nào, bao lâu, ai xử lý.

Trạng thái đơn đi theo 12 bước: `placed` → `confirmed` → `preparing` → `ready_for_pickup` → `assigned` → `picked_up` → `delivering` → `delivered` → `completed`, cộng `pending_payment`, `cancelled`, `refunded`.

### Nhóm giao hàng, tài xế, tiền

| Bảng | Giữ cái gì |
|---|---|
| `drivers` | Hồ sơ tài xế, xe, giấy phép, vị trí, ví |
| `deliveries` | Chuyến giao: cự ly, ETA, OTP, ảnh giao hàng |
| `delivery_tracks` | Vệt GPS để khách xem trên bản đồ |
| `payments` | Giao dịch: COD, chuyển khoản, QR, hoàn tiền |
| `reviews` | Đánh giá cửa hàng / tài xế / sản phẩm |
| `vouchers`, `voucher_redemptions` | Mã giảm giá và lượt dùng |

`drivers.wallet_balance` giải quyết đúng cái nhóm "CHECK TIỀN" bạn đang làm tay: khi tài xế thu 80.000đ tiền COD, ví bị **trừ** 80.000 và **cộng** 12.000 phí giao. Số dư âm 68.000 nghĩa là anh ấy đang giữ 68.000 của bạn chưa nộp. Cuối ngày mở bảng này ra là biết ai nợ bao nhiêu, không phải đọc lại chat.

`deliveries.delivery_otp` là mã khách đọc cho tài xế. Có nó thì không còn tranh chấp "tôi chưa nhận hàng".

---

## Phần 5 — Bốn thứ tự động, bạn không phải làm gì

1. **Mã đơn** tự sinh dạng `HF26073000001` — đọc qua điện thoại được, không phải đọc chuỗi UUID dài 36 ký tự.
2. **Lịch sử trạng thái** tự ghi mỗi lần đơn đổi bước.
3. **Điểm sao** của quán, tài xế, sản phẩm tự tính lại khi có đánh giá mới.
4. **`updated_at`** tự cập nhật, biết dòng nào vừa bị sửa.

Và một hàm bạn nên biết tên: `apply_stock_movement`. Đây là **cách duy nhất được phép thay đổi tồn kho**. Nó vừa cập nhật số tồn vừa ghi sổ trong một lần, nên hai con số không bao giờ lệch nhau. Ai làm app cho bạn sau này, bắt họ dùng hàm này, đừng cho `UPDATE inventory` trực tiếp.

---

## Phần 6 — T đã kiểm những gì, và chưa kiểm được gì

Nói rõ để bạn biết mức độ tin cậy.

**Đã kiểm:**

- Cú pháp SQL: chạy qua bộ phân tích chính thức của PostgreSQL (libpg_query). 131 câu lệnh trong schema, 49 trong seed, không lỗi.
- Toàn bộ khoá ngoại đều trỏ tới bảng có thật, và bảng được tham chiếu luôn khai báo trước.
- 13 enum dùng trong file đều đã được định nghĩa.
- 38 index đều trên bảng có thật.
- Số học dữ liệu mẫu: tổng tiền hai đơn khớp công thức, tổng dòng chi tiết khớp tiền hàng, hoa hồng + tiền quán nhận = tiền hàng, đơn đặt trước có ngày giao.

**Chưa kiểm được:** t không dựng được PostgreSQL trong môi trường này (không có quyền cài), nên chưa *thực thi* file trên server thật. Cú pháp đúng và cấu trúc đúng, nhưng vẫn có thể vướng ở lúc chạy — ví dụ tên extension khác trên Supabase.

Nên bước 3–4 ở Phần 3 chính là lần chạy thật đầu tiên. Có lỗi đỏ, copy đưa t.

---

## Phần 7 — Chưa có gì, và t nghĩ nên làm gì tiếp

**Chưa làm** (SDD có, giai đoạn sau mới cần):
`chat` (7.12) — Zalo đang làm tốt hơn · `notifications` (7.13) · `cms` banner (7.14) · khuyến mãi đầy đủ như flash sale, điểm thưởng (7.8) · bảng cấu hình hệ thống (7.15) · `audit_logs` (9.15) · phân quyền chi tiết (9.9).

Thiếu chúng vẫn bán hàng được. Thêm sau không phải đập lại cấu trúc.

**Việc nên làm ngay khi dựng xong trên Supabase — không được bỏ:**

Bật **Row Level Security**. Mặc định Supabase mở API cho mọi bảng, nghĩa là ai biết đường dẫn cũng đọc được toàn bộ số điện thoại khách và doanh thu của bạn. Chưa bật RLS thì **đừng đưa dữ liệu khách thật vào**. Cứ chạy dữ liệu mẫu để học trước.

Đây là việc tiếp theo t làm cùng bạn nếu bạn muốn.

**Sau đó:** một màn hình đơn giản để bạn và chị Uyên bấm thử — xem đơn mới, bấm nhận đơn, gán tài xế. Có cái bấm được thì bạn mới biết thiết kế này có khớp với cách quán chạy thật hay không. Database đẹp mà không khớp việc thật thì cũng phải sửa.

---

## Phụ lục — Sơ đồ quan hệ

```
users ──┬── addresses
        ├── user_devices ── sessions
        ├── merchants ──┬── branches ──┬── branch_hours
        │               │              ├── merchant_staff
        │               │              └── inventory ── stock_movements
        │               ├── products ──┬── product_categories ── categories
        │               │              └── product_variants ── wholesale_tiers
        │               └── vouchers ── voucher_redemptions
        ├── drivers
        └── orders ──┬── order_items
                     ├── order_status_history
                     ├── deliveries ── delivery_tracks
                     ├── payments
                     └── reviews
```

Đọc sơ đồ: dấu `──` nghĩa là "một cái bên trái có nhiều cái bên phải". Một `users` có nhiều `addresses`. Một `orders` có nhiều `order_items`.
