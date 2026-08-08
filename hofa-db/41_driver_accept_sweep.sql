-- Thanh trượt "Nhận đơn" của tài xế (driver app) — cấu hình RIÊNG với auto_accept_settings
-- (cửa hàng), admin sửa qua GET/PATCH /driver-accept-settings. Chỉ giữ 1 dòng đang áp dụng
-- (dòng mới nhất theo updated_at), cùng kiểu với auto_accept_settings/shipping_fee_settings.
--
-- Tài xế BẬT "Tự động nhận đơn" (drivers.auto_accept): màn nhận đơn vẫn hiện (khác hành vi cũ
-- là bỏ qua thẳng), thanh màu xanh chạy auto_accept_sweep_seconds giây rồi tự NHẬN đơn.
-- Tài xế TẮT: thanh màu cam chạy manual_accept_sweep_seconds giây, hết giờ mà chưa trượt thì tự
-- chuyển đơn cho tài xế gần nhất tiếp theo (dùng lại dispatch.reassignAfterDecline có sẵn).
--
-- Khác cơ chế "Tự động nhận đơn" bên cửa hàng (đã bỏ hẳn quét server, chuyển thuần phía client):
-- driver app GIỮ server làm nguồn xác thực chính (deliveries.accept_deadline + sweepExpiredOffers
-- quét mỗi 10s, xem server/src/dispatch.js) vì tài xế di chuyển ngoài đường, mạng không ổn định
-- bằng cửa hàng ngồi 1 chỗ — client chỉ thêm thanh màu để hiển thị trực quan + tự gọi API sớm
-- hơn khi hết giờ (không cần đợi vòng quét).
CREATE TABLE IF NOT EXISTS driver_accept_settings (
  id                            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auto_accept_sweep_seconds     INTEGER NOT NULL DEFAULT 8,
  manual_accept_sweep_seconds   INTEGER NOT NULL DEFAULT 25,
  updated_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by                    UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE driver_accept_settings IS
  'Cấu hình toàn sàn cho thanh trượt "Nhận đơn" của tài xế (driver app) — chỉ giữ 1 dòng, admin sửa qua GET/PATCH /driver-accept-settings, riêng biệt với auto_accept_settings (cửa hàng).';
COMMENT ON COLUMN driver_accept_settings.auto_accept_sweep_seconds IS
  'Số giây thanh màu chạy ở màn nhận đơn khi tài xế BẬT "Tự động nhận đơn" — hết giờ mà chưa trượt thì hệ thống tự nhận đơn hộ.';
COMMENT ON COLUMN driver_accept_settings.manual_accept_sweep_seconds IS
  'Số giây thanh màu chạy ở màn nhận đơn khi tài xế TẮT "Tự động nhận đơn" — hết giờ mà chưa trượt thì đơn tự chuyển cho tài xế gần nhất tiếp theo.';

INSERT INTO driver_accept_settings (auto_accept_sweep_seconds, manual_accept_sweep_seconds)
SELECT 8, 25 WHERE NOT EXISTS (SELECT 1 FROM driver_accept_settings);
