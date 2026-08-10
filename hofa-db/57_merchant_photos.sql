-- Thư viện ảnh cửa hàng (không phải logo/ảnh bìa/giấy tờ pháp lý — đã có logo_url/cover_url/
-- legal_doc_urls riêng) — ảnh chụp không gian/sản phẩm thật của cửa hàng, chủ cửa hàng tự
-- thêm lúc đăng ký hoặc sửa thông tin, khách/admin xem được ở màn "chi tiết cửa hàng".
ALTER TABLE merchants ADD COLUMN photo_urls JSONB NOT NULL DEFAULT '[]'::jsonb;
COMMENT ON COLUMN merchants.photo_urls IS 'Ảnh cửa hàng (không phải logo/bìa/giấy tờ) — hiện cạnh logo ở màn chi tiết cửa hàng';
