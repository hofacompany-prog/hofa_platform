-- ============================================================================
-- MIGRATION 80 — 2 tính năng sắp xếp độc lập:
--
-- 1) Cửa hàng tự sắp xếp thứ tự sản phẩm hiển thị cho khách ở màn chi tiết cửa hàng (khác
--    is_featured đã có — đó là "nổi bật", không liên quan thứ tự). Chỉ áp dụng khi xem đúng
--    1 cửa hàng (GET /products?merchant_id=...) — duyệt nhiều cửa hàng cùng lúc (tìm kiếm/danh
--    mục) vẫn giữ nguyên thứ tự created_at DESC như cũ, sort_order riêng từng cửa hàng không
--    có ý nghĩa khi trộn lẫn.
--
-- 2) Admin chọn + sắp xếp danh sách cửa hàng "nổi bật" hiện ở trang chủ app Khách (thay vì mọi
--    cửa hàng active đều tự động hiện, sắp theo đánh giá như trước) — cửa hàng KHÔNG được chọn
--    vẫn tồn tại bình thường, khách vẫn tìm/vào được qua ô tìm kiếm (GET /merchants?q=...),
--    chỉ không xuất hiện ở danh sách duyệt mặc định của trang chủ.
-- ============================================================================

ALTER TABLE products ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN products.sort_order IS
  'Thứ tự hiển thị sản phẩm cho khách ở màn chi tiết cửa hàng (số nhỏ lên trước) — cửa hàng tự sắp xếp, chỉ áp dụng khi xem 1 cửa hàng cụ thể. Khác products.is_featured (đánh dấu "nổi bật", không phải thứ tự).';

ALTER TABLE merchants ADD COLUMN featured_home BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE merchants ADD COLUMN featured_home_sort_order INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN merchants.featured_home IS
  'true = admin chọn hiện cửa hàng này ở danh sách duyệt mặc định của trang chủ app Khách. false vẫn là cửa hàng bình thường — khách tìm/vào được qua tìm kiếm, chỉ không nằm trong danh sách trang chủ.';
COMMENT ON COLUMN merchants.featured_home_sort_order IS
  'Thứ tự hiển thị trong danh sách trang chủ (số nhỏ lên trước) — chỉ có ý nghĩa khi featured_home = true, admin sắp xếp ở màn riêng trong admin app.';
