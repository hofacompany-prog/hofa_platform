-- ============================================================================
-- HOFA — DỮ LIỆU MẪU: Quán Bên Ruộng
-- Chạy SAU khi đã chạy xong 01_schema.sql
--
-- Mục đích: dựng một tình huống thật từ đầu đến cuối để bạn thấy dữ liệu
-- chạy qua những bảng nào — giống hệt cách bạn đang làm thủ công trên Zalo.
--
-- Kịch bản:
--   1 cửa hàng (Quán Bên Ruộng), 1 chi nhánh
--   4 sản phẩm bán lẻ + 1 sản phẩm bán sỉ có 3 bậc giá
--   1 khách hàng, 1 tài xế
--   Đơn A: đơn lẻ giao ngay, đi hết vòng đến "đã giao", thu COD
--   Đơn B: đơn sỉ 200kg rau muống, đặt trước, giao sau 2 ngày
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. NGƯỜI DÙNG
-- ---------------------------------------------------------------------------
INSERT INTO users (id, phone, email, full_name, role, status, phone_verified_at) VALUES
  ('11111111-1111-1111-1111-111111111111', '0901000001', 'hofa@quanbenruong.vn',
   'Hofa',            'merchant_owner', 'active', now()),
  ('22222222-2222-2222-2222-222222222222', '0902000002', NULL,
   'Nguyễn Thị Lan',  'customer',       'active', now()),
  ('33333333-3333-3333-3333-333333333333', '0903000003', NULL,
   'Trần Văn Tân',    'driver',         'active', now()),
  ('44444444-4444-4444-4444-444444444444', '0904000004', NULL,
   'Phạm Hồng Uyên',  'merchant_staff', 'active', now());

-- Địa chỉ của khách
INSERT INTO addresses (id, user_id, label, recipient_name, recipient_phone,
                       line1, ward, district, province, latitude, longitude, note, is_default) VALUES
  ('a0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'Nhà', 'Nguyễn Thị Lan', '0902000002',
   '45 Nguyễn Văn Cừ', 'Phường An Khê', 'Quận Thanh Khê', 'Đà Nẵng',
   16.0678000, 108.1889000, 'Cổng xanh, gọi trước 5 phút', true);

-- ---------------------------------------------------------------------------
-- 2. CỬA HÀNG & CHI NHÁNH
-- ---------------------------------------------------------------------------
INSERT INTO merchants (id, owner_id, name, slug, description, merchant_type, status,
                       phone, commission_rate, min_order_amount, avg_prep_minutes,
                       bank_name, bank_account_no, bank_account_name, standard_certified_at) VALUES
  ('c0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Quán Bên Ruộng', 'quan-ben-ruong',
   'Rau củ sạch từ ruộng, giao trong ngày. Nhận đơn sỉ cho nhà hàng và bếp ăn.',
   'standard', 'active', '0901000001', 12.00, 50000, 20,
   'Vietcombank', '1027368888', 'NGUYEN HOFA', now());

INSERT INTO branches (id, merchant_id, name, phone, line1, ward, district, province,
                      latitude, longitude, is_main, is_open, delivery_radius_km) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
   'Quán Bên Ruộng — Chi nhánh chính', '0901000001',
   '112 Tôn Đức Thắng', 'Phường Hòa Minh', 'Quận Liên Chiểu', 'Đà Nẵng',
   16.0712000, 108.1503000, true, true, 8.00);

-- Giờ mở cửa: 5h30 – 19h00, mở cả tuần (bán rau nên mở sớm)
INSERT INTO branch_hours (branch_id, weekday, open_time, close_time)
SELECT 'b0000000-0000-0000-0000-000000000001', d, '05:30', '19:00'
FROM generate_series(0, 6) AS d;

-- Nhân viên
INSERT INTO merchant_staff (merchant_id, branch_id, user_id, position, permissions) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001',
   '44444444-4444-4444-4444-444444444444', 'Bán hàng',
   '["order.view","order.accept","order.ready","product.edit","inventory.adjust"]'::jsonb);

-- ---------------------------------------------------------------------------
-- 3. DANH MỤC
-- ---------------------------------------------------------------------------
INSERT INTO categories (id, parent_id, name, slug, sort_order) VALUES
  ('d0000000-0000-0000-0000-000000000001', NULL, 'Thực phẩm',  'thuc-pham', 1),
  ('d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   'Rau củ quả', 'rau-cu-qua', 1),
  ('d0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000002',
   'Rau ăn lá',  'rau-an-la',  1),
  ('d0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000002',
   'Củ quả',     'cu-qua',     2);

-- ---------------------------------------------------------------------------
-- 4. SẢN PHẨM BÁN LẺ (mô hình giao ngay)
-- ---------------------------------------------------------------------------
INSERT INTO products (id, merchant_id, name, slug, description, sales_model, status, unit, tags) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
   'Rau muống',   'rau-muong',  'Rau muống hái sáng, cọng non.',       'instant', 'active', 'bó',  ARRAY['rau','sạch','bán chạy']),
  ('e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001',
   'Rau cải xanh','rau-cai-xanh','Cải xanh trồng luống, không thuốc.',  'instant', 'active', 'kg',  ARRAY['rau','sạch']),
  ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001',
   'Cà chua',     'ca-chua',    'Cà chua chín cây.',                    'instant', 'active', 'kg',  ARRAY['củ quả']),
  ('e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000001',
   'Bí đao',      'bi-dao',     'Bí đao già, để được lâu.',             'instant', 'active', 'kg',  ARRAY['củ quả']);

INSERT INTO product_categories (product_id, category_id) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000003'),
  ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003'),
  ('e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000004'),
  ('e0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000004');

-- Biến thể: đây mới là thứ khách bỏ vào giỏ
INSERT INTO product_variants (id, product_id, sku, name, attributes,
                              price, compare_price, cost_price, weight_gram, is_default) VALUES
  -- Rau muống: bán theo bó
  ('f0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001',
   'QBR-RM-BO',  '1 bó (khoảng 300g)', '{"size":"1 bó"}'::jsonb,  8000, 10000,  5000,  300, true),
  ('f0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000001',
   'QBR-RM-3BO', '3 bó',               '{"size":"3 bó"}'::jsonb, 22000, 24000, 15000,  900, false),
  -- Rau cải: bán theo trọng lượng
  ('f0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000002',
   'QBR-RC-500', '500g', '{"size":"500g"}'::jsonb, 12000, NULL,  8000,  500, true),
  ('f0000000-0000-0000-0000-000000000004', 'e0000000-0000-0000-0000-000000000002',
   'QBR-RC-1KG', '1kg',  '{"size":"1kg"}'::jsonb,  22000, 24000, 15000, 1000, false),
  -- Cà chua
  ('f0000000-0000-0000-0000-000000000005', 'e0000000-0000-0000-0000-000000000003',
   'QBR-CC-1KG', '1kg',  '{"size":"1kg"}'::jsonb,  25000, NULL, 18000, 1000, true),
  -- Bí đao
  ('f0000000-0000-0000-0000-000000000006', 'e0000000-0000-0000-0000-000000000004',
   'QBR-BD-1KG', '1kg',  '{"size":"1kg"}'::jsonb,  18000, NULL, 12000, 1000, true);

-- ---------------------------------------------------------------------------
-- 5. SẢN PHẨM BÁN SỈ (mô hình đặt trước) — điểm khác biệt của HOFA
-- ---------------------------------------------------------------------------
INSERT INTO products (id, merchant_id, name, slug, description, sales_model, status, unit, tags) VALUES
  ('e0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000001',
   'Rau muống bán sỉ', 'rau-muong-ban-si',
   'Rau muống số lượng lớn cho nhà hàng, bếp ăn, trường học. Giá giảm theo số lượng.',
   'scheduled', 'active', 'kg', ARRAY['sỉ','rau','nhà hàng']);

INSERT INTO product_categories (product_id, category_id) VALUES
  ('e0000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000003');

INSERT INTO product_variants (id, product_id, sku, name, attributes,
                              price, cost_price, wholesale_price, weight_gram, is_default) VALUES
  ('f0000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000005',
   'QBR-RM-SI', 'Theo kg', '{"unit":"kg"}'::jsonb, 18000, 11000, 15000, 1000, true);

-- Bậc giá sỉ/đặt trước — dựa theo ví dụ trong SDD mục 7.9, minh hoạ thêm 2 giá theo điều
-- kiện số ngày/tuần (unit_price_days) và đạt cả 2 điều kiện (unit_price_both).
INSERT INTO wholesale_tiers (variant_id, min_quantity, max_quantity, unit_price,
                             min_days_per_week, unit_price_days, unit_price_both,
                             requires_deposit, deposit_percent) VALUES
  ('f0000000-0000-0000-0000-000000000007',  50,  99,  15000, 1, 14500, 14000, false,  0),
  ('f0000000-0000-0000-0000-000000000007', 100, 499,  13500, 2, 13000, 12500, false,  0),
  ('f0000000-0000-0000-0000-000000000007', 500, 999,  12000, 3, 11500, 11000, true,  30),
  ('f0000000-0000-0000-0000-000000000007',1000, NULL, 10500, 5, 10000,  9500, true,  50);

-- ---------------------------------------------------------------------------
-- 6. NHẬP KHO — dùng đúng hàm apply_stock_movement, không UPDATE tay
-- ---------------------------------------------------------------------------
SELECT apply_stock_movement(
  'b0000000-0000-0000-0000-000000000001', v.id, 'purchase_in', v.qty,
  'manual', NULL, '11111111-1111-1111-1111-111111111111', 'Nhập hàng sáng 30/07'
)
FROM (VALUES
  ('f0000000-0000-0000-0000-000000000001'::uuid, 120),
  ('f0000000-0000-0000-0000-000000000002'::uuid,  40),
  ('f0000000-0000-0000-0000-000000000003'::uuid,  60),
  ('f0000000-0000-0000-0000-000000000004'::uuid,  35),
  ('f0000000-0000-0000-0000-000000000005'::uuid,  50),
  ('f0000000-0000-0000-0000-000000000006'::uuid,  45),
  ('f0000000-0000-0000-0000-000000000007'::uuid,2000)
) AS v(id, qty);

-- ---------------------------------------------------------------------------
-- 7. TÀI XẾ
-- ---------------------------------------------------------------------------
INSERT INTO drivers (id, user_id, national_id, license_no, license_expiry,
                     vehicle_type, vehicle_plate, vehicle_capacity_kg,
                     status, current_latitude, current_longitude, location_updated_at,
                     wallet_balance, verified_at) VALUES
  ('aa000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
   '048201234567', 'B2-1234567', '2030-05-20',
   'Xe máy có thùng', '43H1-234.56', 80.00,
   'online', 16.0700000, 108.1600000, now(), 0, now());

-- ---------------------------------------------------------------------------
-- 8. VOUCHER
-- ---------------------------------------------------------------------------
INSERT INTO vouchers (id, code, merchant_id, description, discount_type, discount_value,
                      max_discount, min_order_amount, usage_limit, usage_limit_per_user, ends_at) VALUES
  ('ba000000-0000-0000-0000-000000000001', 'RAUSACH10', 'c0000000-0000-0000-0000-000000000001',
   'Giảm 10% cho đơn từ 100k', 'percent', 10, 20000, 100000, 500, 2, now() + interval '30 days');

-- ---------------------------------------------------------------------------
-- 9. ĐƠN A — đơn lẻ giao ngay, chạy hết vòng đời
-- ---------------------------------------------------------------------------
-- Tính tiền: 3 bó rau muống 22.000 + 1kg cà chua 25.000 + 1kg bí đao 18.000
--            = 65.000 tiền hàng; phí giao 15.000; giảm 0 (chưa đạt 100k)
--            => khách trả 80.000; hoa hồng 12% của 65.000 = 7.800
--            => cửa hàng nhận 65.000 - 7.800 = 57.200
INSERT INTO orders (
  id, customer_id, merchant_id, branch_id, sales_model, status,
  ship_recipient_name, ship_recipient_phone, ship_line1, ship_ward, ship_district, ship_province,
  ship_latitude, ship_longitude, ship_note,
  subtotal, delivery_fee, discount_amount, tax_amount, total_amount,
  commission_amount, merchant_payout,
  payment_method, payment_status, customer_note
) VALUES (
  '0a000000-0000-0000-0000-000000000001',
  '22222222-2222-2222-2222-222222222222',
  'c0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000001',
  'instant', 'placed',
  'Nguyễn Thị Lan', '0902000002', '45 Nguyễn Văn Cừ',
  'Phường An Khê', 'Quận Thanh Khê', 'Đà Nẵng',
  16.0678000, 108.1889000, 'Cổng xanh, gọi trước 5 phút',
  65000, 15000, 0, 0, 80000,
  7800, 57200,
  'cod', 'pending', 'Rau non giúp em nhé'
);

INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku, unit,
                         unit_price, quantity, line_total, note) VALUES
  ('0a000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002',
   'Rau muống', '3 bó', 'QBR-RM-3BO', 'bó', 22000, 1, 22000, 'Cọng non'),
  ('0a000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000005',
   'Cà chua',   '1kg',  'QBR-CC-1KG', 'kg',  25000, 1, 25000, NULL),
  ('0a000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000006',
   'Bí đao',    '1kg',  'QBR-BD-1KG', 'kg',  18000, 1, 18000, NULL);

-- Giữ hàng cho đơn (chưa trừ kho, chỉ đánh dấu đã có người mua)
UPDATE inventory SET quantity_reserved = quantity_reserved + 1
WHERE branch_id = 'b0000000-0000-0000-0000-000000000001'
  AND variant_id IN ('f0000000-0000-0000-0000-000000000002',
                     'f0000000-0000-0000-0000-000000000005',
                     'f0000000-0000-0000-0000-000000000006');

-- Cửa hàng xác nhận → chuẩn bị → xong hàng
UPDATE orders SET status = 'confirmed',        confirmed_at = now() WHERE id = '0a000000-0000-0000-0000-000000000001';
UPDATE orders SET status = 'preparing'                              WHERE id = '0a000000-0000-0000-0000-000000000001';
UPDATE orders SET status = 'ready_for_pickup', ready_at    = now()  WHERE id = '0a000000-0000-0000-0000-000000000001';

-- Tạo chuyến giao, gán tài xế
INSERT INTO deliveries (id, order_id, driver_id, status, distance_km, eta_minutes, driver_fee,
                        assigned_at, accepted_at, pickup_otp, delivery_otp) VALUES
  ('da000000-0000-0000-0000-000000000001', '0a000000-0000-0000-0000-000000000001',
   'aa000000-0000-0000-0000-000000000001', 'accepted', 4.20, 18, 12000,
   now(), now(), '4821', '7395');

UPDATE orders SET status = 'assigned' WHERE id = '0a000000-0000-0000-0000-000000000001';

-- Tài xế lấy hàng → trừ kho thật, nhả phần đang giữ
SELECT apply_stock_movement(
  'b0000000-0000-0000-0000-000000000001', v.id, 'sale_out', -1,
  'order', '0a000000-0000-0000-0000-000000000001'::uuid,
  '33333333-3333-3333-3333-333333333333', 'Tài xế lấy hàng'
)
FROM (VALUES
  ('f0000000-0000-0000-0000-000000000002'::uuid),
  ('f0000000-0000-0000-0000-000000000005'::uuid),
  ('f0000000-0000-0000-0000-000000000006'::uuid)
) AS v(id);

UPDATE inventory SET quantity_reserved = quantity_reserved - 1
WHERE branch_id = 'b0000000-0000-0000-0000-000000000001'
  AND variant_id IN ('f0000000-0000-0000-0000-000000000002',
                     'f0000000-0000-0000-0000-000000000005',
                     'f0000000-0000-0000-0000-000000000006');

UPDATE deliveries SET status = 'picked_up', arrived_store_at = now(), picked_up_at = now()
WHERE id = 'da000000-0000-0000-0000-000000000001';
UPDATE orders SET status = 'picked_up', picked_up_at = now()
WHERE id = '0a000000-0000-0000-0000-000000000001';

-- Đang giao → đã giao
UPDATE deliveries SET status = 'delivering' WHERE id = 'da000000-0000-0000-0000-000000000001';
UPDATE orders     SET status = 'delivering' WHERE id = '0a000000-0000-0000-0000-000000000001';

INSERT INTO delivery_tracks (delivery_id, latitude, longitude) VALUES
  ('da000000-0000-0000-0000-000000000001', 16.0712000, 108.1503000),
  ('da000000-0000-0000-0000-000000000001', 16.0705000, 108.1660000),
  ('da000000-0000-0000-0000-000000000001', 16.0690000, 108.1780000),
  ('da000000-0000-0000-0000-000000000001', 16.0678000, 108.1889000);

UPDATE deliveries SET status = 'delivered', delivered_at = now(),
       recipient_name = 'Nguyễn Thị Lan',
       proof_photo_urls = '["https://storage.hofa.vn/proof/da01.jpg"]'::jsonb
WHERE id = 'da000000-0000-0000-0000-000000000001';

UPDATE orders SET status = 'delivered', delivered_at = now()
WHERE id = '0a000000-0000-0000-0000-000000000001';

-- Tài xế thu tiền COD
INSERT INTO payments (order_id, method, status, amount, transaction_code, gateway,
                      collected_by, paid_at, note) VALUES
  ('0a000000-0000-0000-0000-000000000001', 'cod', 'paid', 80000,
   'COD-20260730-0001', 'manual', '33333333-3333-3333-3333-333333333333', now(),
   'Tài xế Tân thu đủ 80.000');

UPDATE orders SET payment_status = 'paid', status = 'completed'
WHERE id = '0a000000-0000-0000-0000-000000000001';

-- Tài xế đang giữ 80.000 tiền khách, được cộng 12.000 phí giao
UPDATE drivers SET wallet_balance = wallet_balance - 80000 + 12000,
                   total_deliveries = total_deliveries + 1
WHERE id = 'aa000000-0000-0000-0000-000000000001';

-- Khách đánh giá
INSERT INTO reviews (order_id, customer_id, target_type, target_id, rating, comment) VALUES
  ('0a000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'merchant', 'c0000000-0000-0000-0000-000000000001', 5, 'Rau tươi, giao nhanh.'),
  ('0a000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'driver',   'aa000000-0000-0000-0000-000000000001', 5, 'Anh tài xế gọi trước, lịch sự.');

-- ---------------------------------------------------------------------------
-- 10. ĐƠN B — đơn sỉ 200kg rau muống, đặt trước, giao sau 2 ngày
-- ---------------------------------------------------------------------------
-- 200kg thuộc bậc 100–499 → 13.500đ/kg = 2.700.000
-- Phí giao xe tải 150.000, không giảm giá
INSERT INTO orders (
  id, customer_id, merchant_id, branch_id, sales_model, status,
  ship_recipient_name, ship_recipient_phone, ship_line1, ship_ward, ship_district, ship_province,
  subtotal, delivery_fee, discount_amount, tax_amount, total_amount,
  commission_amount, merchant_payout,
  payment_method, payment_status, scheduled_for, customer_note
) VALUES (
  '0b000000-0000-0000-0000-000000000001',
  '22222222-2222-2222-2222-222222222222',
  'c0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000001',
  'scheduled', 'confirmed',
  'Bếp ăn Trường THCS Hòa Minh', '0902000002', '88 Nguyễn Lương Bằng',
  'Phường Hòa Minh', 'Quận Liên Chiểu', 'Đà Nẵng',
  2700000, 150000, 0, 0, 2850000,
  324000, 2376000,
  'bank_transfer', 'pending', now() + interval '2 days',
  'Giao trước 6h sáng, vào cổng sau'
);

INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku, unit,
                         unit_price, quantity, line_total, note) VALUES
  ('0b000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000007',
   'Rau muống bán sỉ', 'Theo kg', 'QBR-RM-SI', 'kg', 13500, 200, 2700000,
   'Bậc giá 100-499kg, giao sau 2 ngày');

COMMIT;

-- ============================================================================
-- KIỂM TRA — chạy các câu dưới đây để xem dữ liệu có đúng không
-- ============================================================================

-- A. Tồn kho hiện tại của chi nhánh
SELECT p.name AS san_pham, v.name AS loai, v.sku,
       i.quantity_on_hand AS ton_thuc, i.quantity_reserved AS dang_giu,
       (i.quantity_on_hand - i.quantity_reserved) AS con_ban_duoc,
       to_char(v.price, 'FM999,999,999') || 'đ' AS gia
FROM inventory i
JOIN product_variants v ON v.id = i.variant_id
JOIN products p         ON p.id = v.product_id
WHERE i.branch_id = 'b0000000-0000-0000-0000-000000000001'
ORDER BY p.name, v.name;

-- B. Đơn hàng hôm nay kèm tiền và trạng thái
SELECT o.order_code, u.full_name AS khach, o.status, o.sales_model,
       to_char(o.subtotal,'FM999,999,999')      AS tien_hang,
       to_char(o.delivery_fee,'FM999,999,999')  AS phi_giao,
       to_char(o.total_amount,'FM999,999,999')  AS khach_tra,
       to_char(o.commission_amount,'FM999,999,999') AS hofa_thu,
       to_char(o.merchant_payout,'FM999,999,999')   AS quan_nhan,
       o.payment_method, o.payment_status
FROM orders o JOIN users u ON u.id = o.customer_id
ORDER BY o.created_at;

-- C. Lịch sử trạng thái đơn A — trigger tự ghi, không cần code
SELECT h.created_at::time(0) AS luc,
       COALESCE(h.from_status::text,'(mới tạo)') AS tu,
       h.to_status AS sang, h.note
FROM order_status_history h
JOIN orders o ON o.id = h.order_id
WHERE o.order_code IS NOT NULL
  AND h.order_id = '0a000000-0000-0000-0000-000000000001'
ORDER BY h.created_at, h.id;

-- D. Sổ kho — mọi lần hàng vào/ra đều có vết
SELECT p.name AS san_pham, v.name AS loai, s.move_type, s.quantity,
       s.balance_after AS ton_sau, s.note, s.created_at::time(0) AS luc
FROM stock_movements s
JOIN product_variants v ON v.id = s.variant_id
JOIN products p         ON p.id = v.product_id
ORDER BY s.created_at, s.id;

-- E. Bậc giá sỉ: khách mua 200kg thì tính giá nào
SELECT t.min_quantity AS tu_sl, COALESCE(t.max_quantity::text,'trở lên') AS den_sl,
       to_char(t.unit_price,'FM999,999,999') || 'đ/kg' AS gia,
       t.min_days_per_week AS ngay_toi_thieu_tuan,
       CASE WHEN t.requires_deposit THEN 'cọc ' || t.deposit_percent || '%' ELSE 'không cọc' END AS coc,
       CASE WHEN 200 BETWEEN t.min_quantity AND COALESCE(t.max_quantity, 2147483647)
            THEN '  <-- đơn 200kg dùng bậc này' ELSE '' END AS ghi_chu
FROM wholesale_tiers t
WHERE t.variant_id = 'f0000000-0000-0000-0000-000000000007'
ORDER BY t.min_quantity;

-- F. Đối chiếu tiền cuối ngày: tài xế đang giữ bao nhiêu
SELECT u.full_name AS tai_xe, d.total_deliveries AS so_don,
       to_char(d.wallet_balance,'FM999,999,999') AS so_du_vi,
       CASE WHEN d.wallet_balance < 0
            THEN 'Đang giữ ' || to_char(-d.wallet_balance,'FM999,999,999') || 'đ cần nộp'
            ELSE 'Không nợ' END AS tinh_trang
FROM drivers d JOIN users u ON u.id = d.user_id;

-- G. Điểm đánh giá đã tự cập nhật nhờ trigger
SELECT 'Cửa hàng: ' || name AS doi_tuong, rating_avg AS diem, rating_count AS so_luot
FROM merchants
UNION ALL
SELECT 'Tài xế: ' || u.full_name, d.rating_avg, d.rating_count
FROM drivers d JOIN users u ON u.id = d.user_id;
