-- ============================================================================
-- MIGRATION 88 — Chu kỳ nhắc cài PWA (app Khách) toàn sàn, admin cấu hình bằng SỐ PHÚT. Trước
-- đây khách chưa cài PWA bị CHẶN CỨNG (router redirect sang /install-pwa) trước khi đặt hàng —
-- nay bỏ chặn cứng, thay bằng popup nhắc định kỳ khi khách đang lướt bất kỳ trang nào của app
-- (xem hofa_customer_app CustomerShell), không còn chặn luồng dùng app.
-- ============================================================================

CREATE TABLE pwa_reminder_settings (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  interval_minutes INTEGER NOT NULL DEFAULT 5 CHECK (interval_minutes > 0),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by       UUID REFERENCES users(id) ON DELETE SET NULL
);
COMMENT ON TABLE pwa_reminder_settings IS
  'Chu kỳ (phút) app Khách nhắc lại popup cài PWA cho khách chưa cài — chỉ giữ 1 dòng mới nhất
   theo updated_at đang áp dụng, admin sửa qua GET/PATCH /pwa-reminder-settings.';

INSERT INTO pwa_reminder_settings (interval_minutes) VALUES (5);
