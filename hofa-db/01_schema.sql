-- ============================================================================
-- HOFA PLATFORM — DATABASE SCHEMA (Core / Giai đoạn 1)
-- PostgreSQL 14+  |  Version 1.0  |  2026-07-30
--
-- Phạm vi: các module lõi cần để vận hành thật (SDD mục 7.1 - 7.11)
--   7.1 User      7.2 Merchant   7.3 Product    7.4 Inventory
--   7.5 Order     7.6 Driver     7.7 Payment    7.9 Wholesale
--   7.10 Delivery 7.11 Review
--
-- Chưa làm (giai đoạn sau): Chat (7.12), Notification (7.13),
--   CMS (7.14), Promotion đầy đủ (7.8), Admin config (7.15)
--
-- Quy ước đặt tên: tiếng Anh, snake_case, bảng số nhiều.
--   Mỗi bảng có COMMENT tiếng Việt để người không code vẫn đọc hiểu.
-- Tiền: lưu bằng INTEGER = số VNĐ (không dùng số thập phân cho tiền).
-- Thời gian: TIMESTAMPTZ (có múi giờ), luôn lưu UTC.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";      -- so sánh email không phân biệt hoa thường

-- ============================================================================
-- PHẦN 0: ENUM — các danh sách giá trị cố định
-- ============================================================================

CREATE TYPE user_role AS ENUM (
  'customer',        -- khách hàng
  'merchant_owner',  -- chủ cửa hàng
  'merchant_staff',  -- nhân viên cửa hàng
  'driver',          -- tài xế
  'admin'            -- quản trị viên
);

CREATE TYPE user_status AS ENUM ('pending', 'active', 'suspended', 'banned');

CREATE TYPE merchant_type AS ENUM (
  'standard',   -- HOFA Standard: đạt chuẩn, được ưu tiên hiển thị
  'regular',    -- cửa hàng thường
  'wholesale'   -- cửa hàng bán sỉ
);

CREATE TYPE merchant_status AS ENUM ('draft', 'pending_review', 'active', 'paused', 'rejected', 'closed');

CREATE TYPE sales_model AS ENUM (
  'instant',    -- Mô hình 1: hàng có sẵn, giao ngay
  'scheduled'   -- Mô hình 2: đặt trước / bán sỉ, giao theo lịch
);

CREATE TYPE product_status AS ENUM ('draft', 'active', 'out_of_stock', 'hidden', 'archived');

CREATE TYPE stock_move_type AS ENUM (
  'purchase_in',   -- nhập kho
  'sale_out',      -- xuất kho do bán
  'adjustment',    -- điều chỉnh kiểm kê
  'transfer_in',   -- chuyển kho đến
  'transfer_out',  -- chuyển kho đi
  'return_in',     -- khách trả lại
  'damage_out'     -- hư hỏng, huỷ
);

-- Vòng đời đơn hàng. Thứ tự trong enum = thứ tự thực tế của quy trình.
CREATE TYPE order_status AS ENUM (
  'pending_payment',   -- chờ thanh toán (đơn chuyển khoản trước)
  'placed',            -- khách đã đặt, chờ cửa hàng xác nhận
  'confirmed',         -- cửa hàng đã nhận đơn
  'preparing',         -- đang chuẩn bị hàng
  'ready_for_pickup',  -- hàng xong, chờ tài xế lấy
  'assigned',          -- đã gán tài xế
  'picked_up',         -- tài xế đã lấy hàng
  'delivering',        -- đang trên đường giao
  'delivered',         -- đã giao xong
  'completed',         -- hoàn tất (đã đối chiếu tiền)
  'cancelled',         -- đã huỷ
  'refunded'           -- đã hoàn tiền
);

CREATE TYPE payment_method AS ENUM ('cod', 'bank_transfer', 'qr_code', 'e_wallet', 'credit');
CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'failed', 'refunded', 'partially_refunded');

CREATE TYPE driver_status AS ENUM ('offline', 'online', 'busy', 'on_break');
CREATE TYPE delivery_status AS ENUM ('pending', 'assigned', 'accepted', 'arrived_store', 'picked_up', 'delivering', 'delivered', 'failed', 'returned');

CREATE TYPE review_target AS ENUM ('merchant', 'driver', 'product');

-- ============================================================================
-- PHẦN 1: USER MODULE (SDD 7.1) — Người dùng
-- ============================================================================

CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone           VARCHAR(20)  NOT NULL UNIQUE,   -- ở VN số điện thoại là danh tính chính
  email           CITEXT       UNIQUE,
  password_hash   TEXT,                            -- NULL nếu chỉ đăng nhập bằng OTP
  full_name       VARCHAR(150) NOT NULL,
  avatar_url      TEXT,
  date_of_birth   DATE,
  role            user_role    NOT NULL DEFAULT 'customer',
  status          user_status  NOT NULL DEFAULT 'pending',
  phone_verified_at TIMESTAMPTZ,
  email_verified_at TIMESTAMPTZ,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,                     -- xoá mềm: giữ lại để đối chiếu đơn cũ

  CONSTRAINT users_phone_format CHECK (phone ~ '^[0-9+]{9,20}$')
);
COMMENT ON TABLE  users IS 'Người dùng hệ thống: khách, chủ/nhân viên cửa hàng, tài xế, admin';
COMMENT ON COLUMN users.deleted_at IS 'Xoá mềm. Không xoá thật vì đơn hàng cũ còn trỏ tới người này';

CREATE INDEX idx_users_role_status ON users (role, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_phone       ON users (phone)        WHERE deleted_at IS NULL;

-- Địa chỉ đã lưu của khách hàng
CREATE TABLE addresses (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label         VARCHAR(50),                  -- 'Nhà', 'Công ty', 'Quán'
  recipient_name  VARCHAR(150) NOT NULL,
  recipient_phone VARCHAR(20)  NOT NULL,
  line1         VARCHAR(255) NOT NULL,        -- số nhà, tên đường
  ward          VARCHAR(100),                 -- phường/xã
  district      VARCHAR(100),                 -- quận/huyện
  province      VARCHAR(100) NOT NULL,        -- tỉnh/thành
  postal_code   VARCHAR(20),
  latitude      NUMERIC(10,7),
  longitude     NUMERIC(10,7),
  note          TEXT,                         -- 'cổng xanh, gọi trước 5 phút'
  is_default    BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE addresses IS 'Địa chỉ giao hàng khách đã lưu';

CREATE INDEX idx_addresses_user ON addresses (user_id);
-- Mỗi người chỉ được có đúng 1 địa chỉ mặc định
CREATE UNIQUE INDEX idx_addresses_one_default ON addresses (user_id) WHERE is_default;

-- Thiết bị + phiên đăng nhập (SDD 9.6 Device Binding, 9.7 Session)
CREATE TABLE user_devices (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     VARCHAR(255) NOT NULL,        -- mã máy do app sinh ra
  device_name   VARCHAR(150),                 -- 'iPhone 14 của Hofa'
  platform      VARCHAR(20),                  -- ios | android | web
  push_token    TEXT,                         -- token Firebase để gửi thông báo
  last_active_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);
COMMENT ON TABLE user_devices IS 'Thiết bị đã đăng nhập, dùng để gửi thông báo và chặn đăng nhập lạ';

CREATE TABLE sessions (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id          UUID REFERENCES user_devices(id) ON DELETE SET NULL,
  refresh_token_hash TEXT NOT NULL,           -- KHÔNG bao giờ lưu token gốc
  ip_address         INET,
  user_agent         TEXT,
  expires_at         TIMESTAMPTZ NOT NULL,
  revoked_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE sessions IS 'Phiên đăng nhập. Chỉ lưu bản mã hoá của token, không lưu token thật';

CREATE INDEX idx_sessions_user   ON sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_sessions_expiry ON sessions (expires_at) WHERE revoked_at IS NULL;

-- ============================================================================
-- PHẦN 2: MERCHANT MODULE (SDD 7.2) — Cửa hàng
-- ============================================================================

CREATE TABLE merchants (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id          UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  name              VARCHAR(200) NOT NULL,
  slug              VARCHAR(220) NOT NULL UNIQUE,   -- dùng cho đường dẫn web
  description       TEXT,
  merchant_type     merchant_type   NOT NULL DEFAULT 'regular',
  status            merchant_status NOT NULL DEFAULT 'draft',
  logo_url          TEXT,
  cover_url         TEXT,
  phone             VARCHAR(20),
  email             CITEXT,
  -- Hồ sơ pháp lý
  business_license_no VARCHAR(100),
  tax_code            VARCHAR(50),
  legal_doc_urls      JSONB DEFAULT '[]'::jsonb,
  -- Tài khoản ngân hàng nhận tiền
  bank_name           VARCHAR(150),
  bank_account_no     VARCHAR(50),
  bank_account_name   VARCHAR(200),
  -- Điều kiện kinh doanh
  commission_rate   NUMERIC(5,2) NOT NULL DEFAULT 15.00,  -- % hoa hồng HOFA thu
  min_order_amount  INTEGER NOT NULL DEFAULT 0,           -- VNĐ
  avg_prep_minutes  INTEGER NOT NULL DEFAULT 15,          -- thời gian chuẩn bị trung bình
  -- Điểm chuẩn HOFA Standard (SDD 1.6)
  rating_avg        NUMERIC(3,2) NOT NULL DEFAULT 0,
  rating_count      INTEGER NOT NULL DEFAULT 0,
  cancel_rate       NUMERIC(5,2) NOT NULL DEFAULT 0,      -- % đơn bị huỷ
  standard_certified_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,

  CONSTRAINT merchants_commission_range CHECK (commission_rate >= 0 AND commission_rate <= 100),
  CONSTRAINT merchants_rating_range     CHECK (rating_avg >= 0 AND rating_avg <= 5)
);
COMMENT ON TABLE  merchants IS 'Cửa hàng bán trên HOFA. Một cửa hàng có nhiều chi nhánh';
COMMENT ON COLUMN merchants.commission_rate IS 'Phần trăm hoa hồng HOFA thu trên mỗi đơn';
COMMENT ON COLUMN merchants.standard_certified_at IS 'Thời điểm được cấp nhãn HOFA Standard. NULL = chưa đạt';

CREATE INDEX idx_merchants_status ON merchants (status, merchant_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_merchants_owner  ON merchants (owner_id);

-- Chi nhánh: nơi thật sự có hàng và tài xế đến lấy
CREATE TABLE branches (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name          VARCHAR(200) NOT NULL,
  phone         VARCHAR(20),
  line1         VARCHAR(255) NOT NULL,
  ward          VARCHAR(100),
  district      VARCHAR(100),
  province      VARCHAR(100) NOT NULL,
  latitude      NUMERIC(10,7) NOT NULL,
  longitude     NUMERIC(10,7) NOT NULL,
  is_main       BOOLEAN NOT NULL DEFAULT false,
  is_open       BOOLEAN NOT NULL DEFAULT true,   -- công tắc tạm đóng cửa
  auto_accept_orders BOOLEAN NOT NULL DEFAULT false, -- true = tự xác nhận đơn mới, không cần bấm nhận
  delivery_radius_km NUMERIC(5,2) NOT NULL DEFAULT 5,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);
COMMENT ON TABLE  branches IS 'Chi nhánh cửa hàng — nơi giữ hàng và tài xế tới lấy';
COMMENT ON COLUMN branches.is_open IS 'Công tắc bật/tắt nhanh khi hết hàng hoặc nghỉ đột xuất';
COMMENT ON COLUMN branches.auto_accept_orders IS 'true = hệ thống tự xác nhận đơn mới cho chi nhánh này, không cần nhân viên bấm nhận';

CREATE INDEX idx_branches_merchant ON branches (merchant_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_branches_geo      ON branches (latitude, longitude) WHERE deleted_at IS NULL;

-- Giờ mở cửa theo từng ngày trong tuần
CREATE TABLE branch_hours (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id   UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  weekday     SMALLINT NOT NULL,     -- 0 = Chủ nhật ... 6 = Thứ bảy
  open_time   TIME NOT NULL,
  close_time  TIME NOT NULL,
  CONSTRAINT branch_hours_weekday_range CHECK (weekday BETWEEN 0 AND 6),
  UNIQUE (branch_id, weekday, open_time)
);
COMMENT ON TABLE branch_hours IS 'Giờ mở cửa. weekday: 0=Chủ nhật, 1=Thứ hai ... 6=Thứ bảy';

-- Nhân viên cửa hàng
CREATE TABLE merchant_staff (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  branch_id   UUID REFERENCES branches(id) ON DELETE SET NULL,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  position    VARCHAR(100),                          -- 'thu ngân', 'bếp', 'quản lý'
  permissions JSONB NOT NULL DEFAULT '[]'::jsonb,    -- ['order.accept','product.edit']
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, user_id)
);
COMMENT ON TABLE merchant_staff IS 'Nhân viên được cấp quyền vào app cửa hàng';

-- ============================================================================
-- PHẦN 3: PRODUCT MODULE (SDD 7.3) — Sản phẩm
-- ============================================================================

CREATE TABLE categories (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,
  name        VARCHAR(150) NOT NULL,
  slug        VARCHAR(170) NOT NULL UNIQUE,
  icon_url    TEXT,
  icon_name   VARCHAR(50), -- key trong bộ icon dựng sẵn (vd 'food', 'electronics'), xem IconPickerField ở admin app
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE categories IS 'Danh mục ngành hàng, có thể lồng nhau (Thực phẩm > Rau củ > Rau ăn lá)';

CREATE INDEX idx_categories_parent ON categories (parent_id) WHERE is_active;

-- Danh mục riêng của từng cửa hàng (SDD bổ sung) — mỗi cửa hàng tự đặt tên danh mục hiển
-- thị cho khách (vd "Cà phê máy", "Trà trái cây"), nhưng bên dưới vẫn phải gắn vào ĐÚNG 1
-- danh mục con của hệ thống (categories.parent_id NOT NULL) để admin thống kê/tìm kiếm theo
-- ngành hàng chung. Khách xem trang cửa hàng chỉ thấy danh mục cửa hàng này, không thấy cây
-- danh mục chính/con của hệ thống.
CREATE TABLE merchant_categories (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id UUID NOT NULL REFERENCES merchants(id)  ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE, -- danh mục con hệ thống
  name        VARCHAR(150) NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE merchant_categories IS 'Danh mục riêng của 1 cửa hàng, nằm dưới 1 danh mục con hệ thống — khách chỉ thấy danh mục này khi xem cửa hàng';

CREATE INDEX idx_merchant_categories_merchant ON merchant_categories (merchant_id) WHERE is_active;
CREATE INDEX idx_merchant_categories_category ON merchant_categories (category_id) WHERE is_active;

CREATE TABLE products (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id          UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  merchant_category_id UUID REFERENCES merchant_categories(id) ON DELETE SET NULL,
  name          VARCHAR(255) NOT NULL,
  slug          VARCHAR(280),
  description   TEXT,
  sales_model   sales_model    NOT NULL DEFAULT 'instant',
  status        product_status NOT NULL DEFAULT 'draft',
  brand         VARCHAR(150),
  unit          VARCHAR(30) NOT NULL DEFAULT 'cái',  -- kg, bó, hộp, thùng
  images        JSONB NOT NULL DEFAULT '[]'::jsonb,  -- ["url1","url2"]
  video_url     TEXT,
  tags          TEXT[] DEFAULT '{}',
  is_featured   BOOLEAN NOT NULL DEFAULT false,
  rating_avg    NUMERIC(3,2) NOT NULL DEFAULT 0,
  rating_count  INTEGER NOT NULL DEFAULT 0,
  sold_count    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,

  CONSTRAINT products_rating_range CHECK (rating_avg >= 0 AND rating_avg <= 5)
);
COMMENT ON TABLE  products IS 'Sản phẩm cha. Giá và tồn kho nằm ở bảng product_variants';
COMMENT ON COLUMN products.sales_model IS 'instant = giao ngay; scheduled = đặt trước/bán sỉ';

CREATE INDEX idx_products_merchant ON products (merchant_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_products_search   ON products USING GIN (to_tsvector('simple', name));
CREATE INDEX idx_products_tags     ON products USING GIN (tags);
CREATE INDEX idx_products_merchant_category ON products (merchant_category_id) WHERE deleted_at IS NULL;

-- Một sản phẩm thuộc nhiều danh mục (SDD 7.16)
CREATE TABLE product_categories (
  product_id  UUID NOT NULL REFERENCES products(id)   ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  PRIMARY KEY (product_id, category_id)
);
COMMENT ON TABLE product_categories IS 'Nối sản phẩm với danh mục. Một sản phẩm có thể ở nhiều danh mục';

-- Biến thể: "Rau cải 500g" / "Rau cải 1kg" / "Rau cải 2kg" (ví dụ trong SDD 7.3)
CREATE TABLE product_variants (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id      UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  sku             VARCHAR(100) UNIQUE,
  barcode         VARCHAR(100),
  name            VARCHAR(150) NOT NULL,        -- '500g', 'Size L', 'Đỏ'
  attributes      JSONB NOT NULL DEFAULT '{}'::jsonb, -- {"size":"500g","color":"đỏ"}
  price           INTEGER NOT NULL,             -- giá bán lẻ, VNĐ
  compare_price   INTEGER,                      -- giá gốc để gạch ngang
  cost_price      INTEGER,                      -- giá nhập, để tính lãi
  wholesale_price INTEGER,                      -- giá sỉ cơ bản
  weight_gram     INTEGER,
  is_default      BOOLEAN NOT NULL DEFAULT false,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT variants_price_positive CHECK (price >= 0),
  CONSTRAINT variants_compare_gte    CHECK (compare_price IS NULL OR compare_price >= price)
);
COMMENT ON TABLE  product_variants IS 'Biến thể sản phẩm — đây mới là thứ khách bỏ vào giỏ. Giá nằm ở đây';
COMMENT ON COLUMN product_variants.cost_price IS 'Giá nhập. Có cột này mới tính được lãi thật';

CREATE INDEX idx_variants_product ON product_variants (product_id) WHERE is_active;
CREATE UNIQUE INDEX idx_variants_one_default ON product_variants (product_id) WHERE is_default;

-- ============================================================================
-- PHẦN 4: WHOLESALE MODULE (SDD 7.9) — Bán sỉ, bậc giá theo số lượng
-- ============================================================================

CREATE TABLE wholesale_tiers (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  variant_id      UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  min_quantity    INTEGER NOT NULL,       -- mua từ bao nhiêu
  max_quantity    INTEGER,                -- đến bao nhiêu (NULL = không giới hạn)
  unit_price      INTEGER NOT NULL,       -- giá mỗi đơn vị ở bậc này
  lead_time_days  INTEGER NOT NULL DEFAULT 0,  -- bao nhiêu ngày mới giao được
  requires_deposit BOOLEAN NOT NULL DEFAULT false,
  deposit_percent NUMERIC(5,2) DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT tiers_qty_valid   CHECK (min_quantity > 0 AND (max_quantity IS NULL OR max_quantity >= min_quantity)),
  CONSTRAINT tiers_price_valid CHECK (unit_price >= 0),
  CONSTRAINT tiers_deposit_range CHECK (deposit_percent >= 0 AND deposit_percent <= 100),
  UNIQUE (variant_id, min_quantity)
);
COMMENT ON TABLE wholesale_tiers IS
  'Bậc giá sỉ. Ví dụ SDD: 100kg giao sau 2 ngày, 500kg sau 5 ngày, 1000kg theo lịch hẹn';

CREATE INDEX idx_tiers_variant ON wholesale_tiers (variant_id, min_quantity);

-- Nhóm tuỳ chọn thêm của sản phẩm (topping, size, độ ngọt...) — vd trà sữa: trân châu,
-- thạch, pudding. Mỗi nhóm tự chọn bắt buộc hay không (is_required) và cho chọn nhiều
-- mục hay chỉ 1 (allow_multiple).
CREATE TABLE product_topping_groups (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id     UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name           VARCHAR(150) NOT NULL,
  is_required    BOOLEAN NOT NULL DEFAULT false,
  allow_multiple BOOLEAN NOT NULL DEFAULT false,
  sort_order     INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE product_topping_groups IS 'Nhóm tuỳ chọn thêm của 1 sản phẩm (topping, size, độ ngọt...)';

CREATE INDEX idx_topping_groups_product ON product_topping_groups (product_id);

-- Từng lựa chọn cụ thể trong 1 nhóm topping, có giá cộng thêm riêng (0 = miễn phí)
CREATE TABLE product_toppings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id   UUID NOT NULL REFERENCES product_topping_groups(id) ON DELETE CASCADE,
  name       VARCHAR(150) NOT NULL,
  price      INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT product_toppings_price_nonnegative CHECK (price >= 0)
);
COMMENT ON TABLE product_toppings IS 'Từng lựa chọn cụ thể trong 1 nhóm topping, có giá cộng thêm riêng';

CREATE INDEX idx_toppings_group ON product_toppings (group_id);

-- ============================================================================
-- PHẦN 5: INVENTORY MODULE (SDD 7.4) — Tồn kho
-- ============================================================================

-- Tồn kho theo TỪNG CHI NHÁNH, không phải theo cửa hàng
CREATE TABLE inventory (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id       UUID NOT NULL REFERENCES branches(id)         ON DELETE CASCADE,
  variant_id      UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  quantity_on_hand  INTEGER NOT NULL DEFAULT 0,   -- thực tế đang có
  quantity_reserved INTEGER NOT NULL DEFAULT 0,   -- đang giữ cho đơn chưa giao
  low_stock_threshold INTEGER NOT NULL DEFAULT 5,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT inventory_qty_not_negative CHECK (quantity_on_hand >= 0 AND quantity_reserved >= 0),
  CONSTRAINT inventory_reserved_lte_hand CHECK (quantity_reserved <= quantity_on_hand),
  UNIQUE (branch_id, variant_id)
);
COMMENT ON TABLE  inventory IS 'Tồn kho theo từng chi nhánh';
COMMENT ON COLUMN inventory.quantity_reserved IS 'Hàng đã bị đơn khác giữ. Số bán được = on_hand - reserved';

CREATE INDEX idx_inventory_low_stock ON inventory (branch_id)
  WHERE quantity_on_hand <= low_stock_threshold;

-- Cột ảo: số lượng thật sự còn bán được
--
-- QUAN TRỌNG: security_invoker = on
-- Từ PostgreSQL 15, view mặc định chạy bằng quyền của NGƯỜI TẠO view,
-- nghĩa là nó ĐI XUYÊN QUA Row Level Security của bảng inventory.
-- Nếu không bật cờ này, bất kỳ ai gọi API cũng đọc được toàn bộ tồn kho
-- của mọi cửa hàng, dù bảng inventory đã được khoá RLS.
-- Bật lên = view tuân theo quyền của người đang truy vấn.
CREATE VIEW inventory_available
WITH (security_invoker = on) AS
SELECT i.*, (i.quantity_on_hand - i.quantity_reserved) AS quantity_available
FROM inventory i;
COMMENT ON VIEW inventory_available IS
  'Xem tồn kho kèm số lượng còn bán được. security_invoker=on để không lọt RLS';

-- Mọi thay đổi tồn kho đều ghi lại một dòng ở đây. Không bao giờ sửa, chỉ thêm.
CREATE TABLE stock_movements (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id     UUID NOT NULL REFERENCES branches(id)         ON DELETE RESTRICT,
  variant_id    UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
  move_type     stock_move_type NOT NULL,
  quantity      INTEGER NOT NULL,       -- dương = vào kho, âm = ra kho
  balance_after INTEGER NOT NULL,       -- tồn kho sau khi ghi dòng này
  reference_type VARCHAR(50),           -- 'order' | 'manual' | 'transfer'
  reference_id  UUID,
  unit_cost     INTEGER,
  note          TEXT,
  created_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT stock_qty_not_zero CHECK (quantity <> 0)
);
COMMENT ON TABLE  stock_movements IS
  'Sổ nhật ký kho — chỉ ghi thêm, không sửa không xoá. Đây là bằng chứng khi số liệu lệch';
COMMENT ON COLUMN stock_movements.balance_after IS 'Tồn sau khi ghi. Giúp truy ra chỗ lệch mà không phải tính lại từ đầu';

CREATE INDEX idx_stock_moves_branch_variant ON stock_movements (branch_id, variant_id, created_at DESC);
CREATE INDEX idx_stock_moves_reference      ON stock_movements (reference_type, reference_id);

-- ============================================================================
-- PHẦN 6: DRIVER MODULE (SDD 7.6) — Tài xế
-- ============================================================================

CREATE TABLE drivers (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
  -- Hồ sơ & giấy tờ
  national_id       VARCHAR(20),
  license_no        VARCHAR(50),
  license_expiry    DATE,
  vehicle_type      VARCHAR(50),          -- 'xe máy', 'xe tải 500kg'
  vehicle_plate     VARCHAR(20),
  vehicle_capacity_kg NUMERIC(8,2),
  document_urls     JSONB NOT NULL DEFAULT '[]'::jsonb,
  -- Trạng thái làm việc
  status            driver_status NOT NULL DEFAULT 'offline',
  auto_accept       BOOLEAN NOT NULL DEFAULT false,  -- true = hệ thống tự gán đơn, không cần xác nhận
  current_latitude  NUMERIC(10,7),
  current_longitude NUMERIC(10,7),
  location_updated_at TIMESTAMPTZ,
  -- Ví và thu nhập
  wallet_balance    INTEGER NOT NULL DEFAULT 0,   -- VNĐ, có thể âm khi giữ tiền COD
  total_deliveries  INTEGER NOT NULL DEFAULT 0,
  rating_avg        NUMERIC(3,2) NOT NULL DEFAULT 0,
  rating_count      INTEGER NOT NULL DEFAULT 0,
  verified_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT drivers_rating_range CHECK (rating_avg >= 0 AND rating_avg <= 5)
);
COMMENT ON TABLE  drivers IS 'Hồ sơ tài xế. Thông tin cá nhân dùng chung ở bảng users';
COMMENT ON COLUMN drivers.wallet_balance IS 'Số dư ví. Âm nghĩa là tài xế đang giữ tiền COD chưa nộp';

CREATE INDEX idx_drivers_online ON drivers (status) WHERE status = 'online';
CREATE INDEX idx_drivers_geo    ON drivers (current_latitude, current_longitude) WHERE status IN ('online','busy');

-- ============================================================================
-- PHẦN 7: ORDER MODULE (SDD 7.5) — Đơn hàng. Phần quan trọng nhất.
-- ============================================================================

CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_code        VARCHAR(20) NOT NULL UNIQUE,   -- 'HF26073000001' để đọc qua điện thoại
  customer_id       UUID NOT NULL REFERENCES users(id)      ON DELETE RESTRICT,
  merchant_id       UUID NOT NULL REFERENCES merchants(id)  ON DELETE RESTRICT,
  branch_id         UUID NOT NULL REFERENCES branches(id)   ON DELETE RESTRICT,
  sales_model       sales_model  NOT NULL DEFAULT 'instant',
  status            order_status NOT NULL DEFAULT 'placed',

  -- Bản chụp địa chỉ tại thời điểm đặt. KHÔNG chỉ lưu address_id,
  -- vì khách có thể sửa hoặc xoá địa chỉ sau này.
  ship_recipient_name  VARCHAR(150) NOT NULL,
  ship_recipient_phone VARCHAR(20)  NOT NULL,
  ship_line1        VARCHAR(255) NOT NULL,
  ship_ward         VARCHAR(100),
  ship_district     VARCHAR(100),
  ship_province     VARCHAR(100) NOT NULL,
  ship_latitude     NUMERIC(10,7),
  ship_longitude    NUMERIC(10,7),
  ship_note         TEXT,

  -- Tiền. Mọi con số là VNĐ.
  subtotal          INTEGER NOT NULL DEFAULT 0,   -- tổng tiền hàng
  delivery_fee      INTEGER NOT NULL DEFAULT 0,
  discount_amount   INTEGER NOT NULL DEFAULT 0,
  tax_amount        INTEGER NOT NULL DEFAULT 0,
  total_amount      INTEGER NOT NULL DEFAULT 0,   -- khách phải trả
  commission_amount INTEGER NOT NULL DEFAULT 0,   -- HOFA thu
  merchant_payout   INTEGER NOT NULL DEFAULT 0,   -- cửa hàng nhận
  voucher_code      VARCHAR(50),

  payment_method    payment_method NOT NULL DEFAULT 'cod',
  payment_status    payment_status NOT NULL DEFAULT 'pending',

  -- Thời gian
  scheduled_for     TIMESTAMPTZ,   -- đơn đặt trước: giao lúc nào
  confirmed_at      TIMESTAMPTZ,
  ready_at          TIMESTAMPTZ,
  picked_up_at      TIMESTAMPTZ,
  delivered_at      TIMESTAMPTZ,
  cancelled_at      TIMESTAMPTZ,
  cancel_reason     TEXT,
  cancelled_by      UUID REFERENCES users(id) ON DELETE SET NULL,

  accept_deadline   TIMESTAMPTZ,   -- hạn cửa hàng xác nhận đơn (status='placed'); quá hạn tự huỷ

  customer_note     TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT orders_amounts_not_negative CHECK (
    subtotal >= 0 AND delivery_fee >= 0 AND discount_amount >= 0
    AND tax_amount >= 0 AND total_amount >= 0
  ),
  -- Chốt phép tính tiền ngay trong database. Sai là không ghi được.
  CONSTRAINT orders_total_matches CHECK (
    total_amount = subtotal + delivery_fee + tax_amount - discount_amount
  ),
  CONSTRAINT orders_scheduled_requires_date CHECK (
    sales_model = 'instant' OR scheduled_for IS NOT NULL
  )
);
COMMENT ON TABLE  orders IS 'Đơn hàng. Địa chỉ được chụp lại tại thời điểm đặt, không tham chiếu';
COMMENT ON COLUMN orders.accept_deadline IS 'Hạn cửa hàng xác nhận đơn (áp dụng khi branches.auto_accept_orders = false)';
COMMENT ON CONSTRAINT orders_total_matches ON orders IS
  'Database tự chặn nếu tổng tiền không khớp các thành phần — tránh sai số tiền do lỗi code';

CREATE INDEX idx_orders_customer   ON orders (customer_id, created_at DESC);
CREATE INDEX idx_orders_merchant   ON orders (merchant_id, status, created_at DESC);
CREATE INDEX idx_orders_branch     ON orders (branch_id, status);
CREATE INDEX idx_orders_status     ON orders (status) WHERE status NOT IN ('completed','cancelled','refunded');
CREATE INDEX idx_orders_code       ON orders (order_code);
CREATE INDEX idx_orders_scheduled  ON orders (scheduled_for) WHERE scheduled_for IS NOT NULL;

-- Chi tiết đơn. Giá được CHỤP LẠI, không tham chiếu bảng giá hiện tại.
CREATE TABLE order_items (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  variant_id      UUID REFERENCES product_variants(id) ON DELETE SET NULL,
  -- Bản chụp tên và giá lúc đặt hàng
  product_name    VARCHAR(255) NOT NULL,
  variant_name    VARCHAR(150),
  sku             VARCHAR(100),
  unit            VARCHAR(30),
  unit_price      INTEGER NOT NULL,
  quantity        INTEGER NOT NULL,
  line_total      INTEGER NOT NULL,
  note            TEXT,                 -- 'không lấy đá', 'rau non'
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT items_qty_positive   CHECK (quantity > 0),
  CONSTRAINT items_price_positive CHECK (unit_price >= 0),
  CONSTRAINT items_line_total_matches CHECK (line_total = unit_price * quantity)
);
COMMENT ON TABLE  order_items IS 'Chi tiết đơn. Tên và giá được chụp lại để hoá đơn cũ không đổi khi cửa hàng sửa giá';
COMMENT ON COLUMN order_items.variant_id IS 'Có thể NULL nếu sản phẩm bị xoá sau này. Tên và giá vẫn còn';

CREATE INDEX idx_order_items_order   ON order_items (order_id);
CREATE INDEX idx_order_items_variant ON order_items (variant_id);

-- Topping khách đã chọn cho 1 món trong đơn — bản chụp tên/giá lúc đặt hàng, giống
-- order_items chụp lại tên/giá sản phẩm, để sau này cửa hàng sửa/xoá topping không
-- ảnh hưởng hoá đơn cũ. Giá topping đã được cộng vào order_items.unit_price lúc chốt
-- đơn (xem create_order) — bảng này chỉ để hiển thị lại đã chọn topping gì.
CREATE TABLE order_item_toppings (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_item_id UUID NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  topping_id    UUID REFERENCES product_toppings(id) ON DELETE SET NULL,
  name          VARCHAR(150) NOT NULL,
  price         INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT order_item_toppings_price_nonnegative CHECK (price >= 0)
);
COMMENT ON TABLE order_item_toppings IS 'Topping khách đã chọn cho từng món trong đơn — bản chụp tên/giá lúc đặt hàng';

CREATE INDEX idx_order_item_toppings_item ON order_item_toppings (order_item_id);

-- Nhật ký đổi trạng thái: ai đổi, lúc nào, từ gì sang gì
CREATE TABLE order_status_history (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id      UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  from_status   order_status,
  to_status     order_status NOT NULL,
  changed_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_role    user_role,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE order_status_history IS
  'Lịch sử trạng thái đơn. Khi khách khiếu nại, đây là chỗ tra ai làm gì lúc nào';

CREATE INDEX idx_order_history_order ON order_status_history (order_id, created_at);

-- ============================================================================
-- PHẦN 8: DELIVERY MODULE (SDD 7.10) — Giao hàng
-- ============================================================================

CREATE TABLE deliveries (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id          UUID NOT NULL UNIQUE REFERENCES orders(id)  ON DELETE CASCADE,
  driver_id         UUID REFERENCES drivers(id) ON DELETE SET NULL,
  status            delivery_status NOT NULL DEFAULT 'pending',
  -- Cự ly và thời gian
  distance_km       NUMERIC(8,2),
  eta_minutes       INTEGER,
  driver_fee        INTEGER NOT NULL DEFAULT 0,   -- tài xế được trả bao nhiêu
  -- Mốc thời gian
  assigned_at       TIMESTAMPTZ,
  accept_deadline   TIMESTAMPTZ,   -- tài xế (không auto_accept) phải xác nhận trước mốc này, quá hạn tự gán tài xế khác
  accepted_at       TIMESTAMPTZ,
  arrived_store_at  TIMESTAMPTZ,
  picked_up_at      TIMESTAMPTZ,
  delivered_at      TIMESTAMPTZ,
  -- Bằng chứng giao hàng
  pickup_otp        VARCHAR(10),
  delivery_otp      VARCHAR(10),
  proof_photo_urls  JSONB NOT NULL DEFAULT '[]'::jsonb,
  signature_url     TEXT,
  recipient_name    VARCHAR(150),        -- ai thật sự nhận hàng
  failure_reason    TEXT,
  attempt_count     SMALLINT NOT NULL DEFAULT 0,
  declined_driver_ids UUID[] NOT NULL DEFAULT '{}',  -- tài xế đã từ chối/hết hạn — loại khỏi lần gán tiếp theo
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE  deliveries IS 'Chuyến giao hàng, mỗi đơn một chuyến';
COMMENT ON COLUMN deliveries.delivery_otp IS 'Mã khách đọc cho tài xế để xác nhận đã nhận hàng';
COMMENT ON COLUMN deliveries.accept_deadline IS 'Hạn tài xế xác nhận nhận đơn (chỉ áp dụng khi driver.auto_accept = false)';

CREATE INDEX idx_deliveries_driver ON deliveries (driver_id, status);
CREATE INDEX idx_deliveries_status ON deliveries (status) WHERE status NOT IN ('delivered','failed','returned');

-- Vệt GPS của tài xế trong chuyến, để khách xem trên bản đồ
CREATE TABLE delivery_tracks (
  id            BIGSERIAL PRIMARY KEY,
  delivery_id   UUID NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  latitude      NUMERIC(10,7) NOT NULL,
  longitude     NUMERIC(10,7) NOT NULL,
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE delivery_tracks IS 'Vệt GPS. Bảng này phình rất nhanh — nên dọn dữ liệu cũ định kỳ';

CREATE INDEX idx_tracks_delivery ON delivery_tracks (delivery_id, recorded_at DESC);

-- ============================================================================
-- PHẦN 9: PAYMENT MODULE (SDD 7.7) — Thanh toán
-- ============================================================================

CREATE TABLE payments (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id          UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  method            payment_method NOT NULL,
  status            payment_status NOT NULL DEFAULT 'pending',
  amount            INTEGER NOT NULL,
  currency          CHAR(3) NOT NULL DEFAULT 'VND',
  -- Đối chiếu với cổng thanh toán
  transaction_code  VARCHAR(100) UNIQUE,
  gateway           VARCHAR(50),           -- 'momo','vnpay','zalopay','manual'
  gateway_response  JSONB,
  -- Ai thu tiền (COD thì là tài xế)
  collected_by      UUID REFERENCES users(id) ON DELETE SET NULL,
  paid_at           TIMESTAMPTZ,
  refunded_amount   INTEGER NOT NULL DEFAULT 0,
  refunded_at       TIMESTAMPTZ,
  note              TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT payments_amount_positive CHECK (amount > 0),
  CONSTRAINT payments_refund_lte_amount CHECK (refunded_amount >= 0 AND refunded_amount <= amount)
);
COMMENT ON TABLE  payments IS 'Giao dịch thanh toán. Một đơn có thể nhiều dòng (đặt cọc rồi trả phần còn lại)';
COMMENT ON COLUMN payments.collected_by IS 'Với đơn COD, đây là tài xế đã nhận tiền từ khách';

CREATE INDEX idx_payments_order  ON payments (order_id);
CREATE INDEX idx_payments_status ON payments (status, created_at DESC);

-- ============================================================================
-- PHẦN 10: REVIEW MODULE (SDD 7.11) — Đánh giá
-- ============================================================================

CREATE TABLE reviews (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id      UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  customer_id   UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  target_type   review_target NOT NULL,
  target_id     UUID NOT NULL,          -- id của merchant / driver / product
  rating        SMALLINT NOT NULL,
  comment       TEXT,
  media_urls    JSONB NOT NULL DEFAULT '[]'::jsonb,
  merchant_reply TEXT,
  replied_at    TIMESTAMPTZ,
  is_hidden     BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT reviews_rating_range CHECK (rating BETWEEN 1 AND 5),
  -- Mỗi đơn chỉ đánh giá một lần cho mỗi đối tượng
  UNIQUE (order_id, target_type, target_id)
);
COMMENT ON TABLE reviews IS 'Đánh giá cửa hàng / tài xế / sản phẩm. Bắt buộc gắn với một đơn đã mua';

CREATE INDEX idx_reviews_target ON reviews (target_type, target_id, created_at DESC) WHERE NOT is_hidden;

-- ============================================================================
-- PHẦN 11: VOUCHER (rút gọn từ SDD 7.8) — đủ dùng cho giai đoạn 1
-- ============================================================================

CREATE TABLE vouchers (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code              VARCHAR(50) NOT NULL UNIQUE,
  merchant_id       UUID REFERENCES merchants(id) ON DELETE CASCADE,  -- NULL = toàn sàn
  description       TEXT,
  discount_type     VARCHAR(20) NOT NULL,      -- 'percent' | 'fixed' | 'free_shipping'
  discount_value    INTEGER NOT NULL,
  max_discount      INTEGER,
  min_order_amount  INTEGER NOT NULL DEFAULT 0,
  usage_limit       INTEGER,                   -- NULL = không giới hạn
  usage_limit_per_user INTEGER NOT NULL DEFAULT 1,
  used_count        INTEGER NOT NULL DEFAULT 0,
  starts_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at           TIMESTAMPTZ,
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT vouchers_type_valid CHECK (discount_type IN ('percent','fixed','free_shipping')),
  CONSTRAINT vouchers_period     CHECK (ends_at IS NULL OR ends_at > starts_at)
);
COMMENT ON TABLE vouchers IS 'Mã giảm giá. merchant_id NULL nghĩa là mã của cả sàn HOFA';

CREATE TABLE voucher_redemptions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  voucher_id  UUID NOT NULL REFERENCES vouchers(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  order_id    UUID NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
  discount_amount INTEGER NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (voucher_id, order_id)
);
COMMENT ON TABLE voucher_redemptions IS 'Lượt dùng mã. Dùng để chặn khách dùng quá số lần cho phép';

CREATE INDEX idx_redemptions_user ON voucher_redemptions (voucher_id, user_id);

-- ============================================================================
-- PHẦN 12: TỰ ĐỘNG HOÁ — trigger giữ dữ liệu luôn đúng
-- ============================================================================

-- 1) Tự cập nhật updated_at mỗi lần sửa dòng
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users','addresses','merchants','branches','products','product_variants',
    'inventory','drivers','orders','deliveries','payments'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_touch BEFORE UPDATE ON %1$s
       FOR EACH ROW EXECUTE FUNCTION touch_updated_at()', t);
  END LOOP;
END $$;

-- 2) Sinh mã đơn dạng HF + ngày + số thứ tự: HF26073000001
CREATE SEQUENCE order_code_seq;

CREATE OR REPLACE FUNCTION generate_order_code() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.order_code IS NULL OR NEW.order_code = '' THEN
    NEW.order_code := 'HF'
      || to_char(now(), 'YYMMDD')
      || lpad((nextval('order_code_seq') % 100000)::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_code BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION generate_order_code();

-- 3) Mỗi lần trạng thái đơn đổi, tự ghi một dòng vào lịch sử
CREATE OR REPLACE FUNCTION log_order_status() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO order_status_history (order_id, from_status, to_status, note)
    VALUES (NEW.id, NULL, NEW.status, 'Đơn được tạo');
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO order_status_history (order_id, from_status, to_status)
    VALUES (NEW.id, OLD.status, NEW.status);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_status_log AFTER INSERT OR UPDATE OF status ON orders
FOR EACH ROW EXECUTE FUNCTION log_order_status();

-- 4) Cập nhật lại điểm đánh giá trung bình khi có review mới
CREATE OR REPLACE FUNCTION refresh_rating() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.target_type = 'merchant' THEN
    UPDATE merchants SET
      rating_avg   = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews
                      WHERE target_type='merchant' AND target_id=NEW.target_id AND NOT is_hidden),
      rating_count = (SELECT COUNT(*) FROM reviews
                      WHERE target_type='merchant' AND target_id=NEW.target_id AND NOT is_hidden)
    WHERE id = NEW.target_id;
  ELSIF NEW.target_type = 'driver' THEN
    UPDATE drivers SET
      rating_avg   = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews
                      WHERE target_type='driver' AND target_id=NEW.target_id AND NOT is_hidden),
      rating_count = (SELECT COUNT(*) FROM reviews
                      WHERE target_type='driver' AND target_id=NEW.target_id AND NOT is_hidden)
    WHERE id = NEW.target_id;
  ELSIF NEW.target_type = 'product' THEN
    UPDATE products SET
      rating_avg   = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews
                      WHERE target_type='product' AND target_id=NEW.target_id AND NOT is_hidden),
      rating_count = (SELECT COUNT(*) FROM reviews
                      WHERE target_type='product' AND target_id=NEW.target_id AND NOT is_hidden)
    WHERE id = NEW.target_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reviews_rating AFTER INSERT OR UPDATE ON reviews
FOR EACH ROW EXECUTE FUNCTION refresh_rating();

-- 5) Ghi sổ kho tự động và chặn bán quá tồn
CREATE OR REPLACE FUNCTION apply_stock_movement(
  p_branch_id  UUID,
  p_variant_id UUID,
  p_move_type  stock_move_type,
  p_quantity   INTEGER,
  p_ref_type   VARCHAR DEFAULT NULL,
  p_ref_id     UUID    DEFAULT NULL,
  p_user_id    UUID    DEFAULT NULL,
  p_note       TEXT    DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
  v_new_balance INTEGER;
BEGIN
  INSERT INTO inventory (branch_id, variant_id, quantity_on_hand)
  VALUES (p_branch_id, p_variant_id, 0)
  ON CONFLICT (branch_id, variant_id) DO NOTHING;

  UPDATE inventory
     SET quantity_on_hand = quantity_on_hand + p_quantity
   WHERE branch_id = p_branch_id AND variant_id = p_variant_id
  RETURNING quantity_on_hand INTO v_new_balance;

  INSERT INTO stock_movements (
    branch_id, variant_id, move_type, quantity, balance_after,
    reference_type, reference_id, created_by, note
  ) VALUES (
    p_branch_id, p_variant_id, p_move_type, p_quantity, v_new_balance,
    p_ref_type, p_ref_id, p_user_id, p_note
  );

  RETURN v_new_balance;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION apply_stock_movement IS
  'Cách DUY NHẤT được phép thay đổi tồn kho. Vừa cập nhật tồn vừa ghi sổ trong một lần, không thể lệch';

COMMIT;

-- ============================================================================
-- KẾT THÚC. Tổng: 25 bảng, 13 enum, 1 view, 38 index, 5 hàm, 14 trigger.
-- Bước tiếp theo: chạy 02_seed_quan_ben_ruong.sql để có dữ liệu mẫu.
-- ============================================================================
