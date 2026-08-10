-- Tên nhóm biến thể (VD: "Trọng lượng", "Kích cỡ", "Loại") — nhãn hiển thị phía trên danh
-- sách biến thể của 1 sản phẩm, KHÔNG phải đơn vị đo (products.unit vẫn giữ nguyên nghĩa
-- "kg/bó/hộp" dùng để hiển thị sau giá bán ở app khách, xem product_detail_screen.dart) —
-- tách riêng 2 khái niệm vì unit đã có ý nghĩa cố định ở nhiều nơi (order_items.unit,
-- create_order snapshot), không thể tái dùng cho mục đích khác.
ALTER TABLE products ADD COLUMN variant_group_name VARCHAR(50);
COMMENT ON COLUMN products.variant_group_name IS 'Tên nhóm biến thể hiển thị phía trên danh sách biến thể (VD: Trọng lượng, Kích cỡ) — không bắt buộc';
