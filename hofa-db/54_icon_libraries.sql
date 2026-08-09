-- Thư viện icon online (qua Iconify — api.iconify.design, gộp sẵn ~200 bộ icon mã nguồn mở
-- trên GitHub thành 1 API tìm kiếm duy nhất) mà admin đã bật để dùng ở màn Icon tabbar. Không
-- có dòng cho 1 prefix nghĩa là thư viện đó đang tắt, không hiện trong ô tìm icon online — chỉ
-- ảnh hưởng tới trải nghiệm tìm kiếm ở admin, không liên quan gì tới icon đã chọn/lưu trước đó
-- (nav_tab_icons chỉ lưu URL ảnh cuối cùng, không phụ thuộc thư viện gốc còn bật hay không).
CREATE TABLE IF NOT EXISTS icon_libraries (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  prefix      TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE icon_libraries IS
  'Thư viện icon Iconify admin đã bật để tìm kiếm ở màn Icon tabbar (tab "Thư viện online") —
   prefix khớp đúng mã thư viện của Iconify (vd "lucide", "tabler", "mdi"), lấy từ
   GET https://api.iconify.design/collections.';
