-- ============================================================================
-- RESET — xoá sạch toàn bộ cấu trúc HOFA để dựng lại từ đầu
--
-- CẢNH BÁO: file này XOÁ HẾT dữ liệu trong 26 bảng. Không lấy lại được.
-- Chỉ dùng khi đang học với dữ liệu mẫu. TUYỆT ĐỐI không chạy khi đã có
-- đơn hàng và khách thật.
--
-- Cách dùng:  chạy 00_reset.sql  →  rồi 01_schema.sql  →  rồi 02_seed...sql
--
-- File này chỉ xoá đúng những thứ HOFA tạo ra, không đụng tới các bảng
-- nội bộ của Supabase (auth, storage...).
-- ============================================================================

BEGIN;

-- Bảng: xoá theo thứ tự ngược, CASCADE tự dọn khoá ngoại và view liên quan
DROP TABLE IF EXISTS voucher_redemptions   CASCADE;
DROP TABLE IF EXISTS vouchers              CASCADE;
DROP TABLE IF EXISTS reviews               CASCADE;
DROP TABLE IF EXISTS payments              CASCADE;
DROP TABLE IF EXISTS delivery_tracks       CASCADE;
DROP TABLE IF EXISTS deliveries            CASCADE;
DROP TABLE IF EXISTS order_status_history  CASCADE;
DROP TABLE IF EXISTS order_items           CASCADE;
DROP TABLE IF EXISTS orders                CASCADE;
DROP TABLE IF EXISTS drivers               CASCADE;
DROP TABLE IF EXISTS stock_movements       CASCADE;
DROP TABLE IF EXISTS inventory             CASCADE;
DROP TABLE IF EXISTS wholesale_tiers       CASCADE;
DROP TABLE IF EXISTS product_toppings      CASCADE;
DROP TABLE IF EXISTS product_topping_groups CASCADE;
DROP TABLE IF EXISTS product_variants      CASCADE;
DROP TABLE IF EXISTS product_categories    CASCADE;
DROP TABLE IF EXISTS products              CASCADE;
DROP TABLE IF EXISTS merchant_categories   CASCADE;
DROP TABLE IF EXISTS categories            CASCADE;
DROP TABLE IF EXISTS merchant_staff        CASCADE;
DROP TABLE IF EXISTS branch_hours          CASCADE;
DROP TABLE IF EXISTS branches              CASCADE;
DROP TABLE IF EXISTS merchants             CASCADE;
DROP TABLE IF EXISTS sessions              CASCADE;
DROP TABLE IF EXISTS user_devices          CASCADE;
DROP TABLE IF EXISTS addresses             CASCADE;
DROP TABLE IF EXISTS users                 CASCADE;

-- View
DROP VIEW IF EXISTS inventory_available CASCADE;

-- Hàm
DROP FUNCTION IF EXISTS apply_stock_movement(UUID, UUID, stock_move_type, INTEGER, VARCHAR, UUID, UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS refresh_rating()      CASCADE;
DROP FUNCTION IF EXISTS log_order_status()    CASCADE;
DROP FUNCTION IF EXISTS generate_order_code() CASCADE;
DROP FUNCTION IF EXISTS touch_updated_at()    CASCADE;

-- Sequence
DROP SEQUENCE IF EXISTS order_code_seq CASCADE;

-- Enum — phải xoá SAU khi đã xoá hết bảng dùng chúng
DROP TYPE IF EXISTS review_target    CASCADE;
DROP TYPE IF EXISTS delivery_status  CASCADE;
DROP TYPE IF EXISTS driver_status    CASCADE;
DROP TYPE IF EXISTS payment_status   CASCADE;
DROP TYPE IF EXISTS payment_method   CASCADE;
DROP TYPE IF EXISTS order_status     CASCADE;
DROP TYPE IF EXISTS stock_move_type  CASCADE;
DROP TYPE IF EXISTS product_status   CASCADE;
DROP TYPE IF EXISTS sales_model      CASCADE;
DROP TYPE IF EXISTS merchant_status  CASCADE;
DROP TYPE IF EXISTS merchant_type    CASCADE;
DROP TYPE IF EXISTS user_status      CASCADE;
DROP TYPE IF EXISTS user_role        CASCADE;

COMMIT;

-- Kiểm tra: phải trả về 0 bảng và 0 enum
SELECT
  (SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE') AS con_lai_bang,
  (SELECT COUNT(*) FROM pg_type t
     JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e')              AS con_lai_enum;
