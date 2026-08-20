-- ============================================================================
-- MIGRATION 90 — Tách role thành hồ sơ riêng, dùng chung 1 SĐT đăng nhập
--
-- Trước đây public.users.id == auth.users.id (quy ước), users.phone UNIQUE toàn hệ thống,
-- users.role là 1 cột duy nhất bị GHI ĐÈ mỗi lần đăng ký thêm role (vd customer -> driver mất
-- luôn role customer cũ). Từ nay: 1 SĐT (1 auth.users/auth_user_id) có thể có NHIỀU dòng users,
-- mỗi dòng ứng với 1 role riêng biệt, không liên quan tới nhau. Xem server/src/middleware/auth.js
-- (đọc header X-App-Scope để chọn đúng dòng theo role phù hợp app đang gọi).
-- ============================================================================

ALTER TABLE users ADD COLUMN auth_user_id UUID;
UPDATE users SET auth_user_id = id WHERE auth_user_id IS NULL;
ALTER TABLE users ALTER COLUMN auth_user_id SET NOT NULL;

COMMENT ON COLUMN users.auth_user_id IS
  'ID auth.users Supabase (JWT sub) — danh tính đăng nhập THẬT, dùng CHUNG khi 1 SĐT đăng ký
   nhiều role. users.id vẫn là khoá riêng của từng hồ sơ role (1 SĐT có thể có nhiều dòng users,
   mỗi dòng auth_user_id giống nhau nhưng role/id khác nhau).';

-- Gỡ UNIQUE(phone) cũ, thay bằng UNIQUE(phone, role) — 1 SĐT nhiều role, mỗi role 1 SĐT chỉ
-- đăng ký được 1 lần. Tự tra tên constraint thật qua pg_constraint thay vì đoán tên (Postgres
-- tự đặt tên cho UNIQUE khai báo inline, thường là users_phone_key nhưng không chắc chắn 100%).
DO $$
DECLARE
  c_name TEXT;
BEGIN
  SELECT conname INTO c_name
  FROM pg_constraint
  WHERE conrelid = 'users'::regclass
    AND contype = 'u'
    AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'users'::regclass AND attname = 'phone')];
  IF c_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE users DROP CONSTRAINT %I', c_name);
  END IF;
END $$;

ALTER TABLE users ADD CONSTRAINT users_phone_role_unique UNIQUE (phone, role);

CREATE INDEX idx_users_auth_user_id_role ON users (auth_user_id, role) WHERE deleted_at IS NULL;
