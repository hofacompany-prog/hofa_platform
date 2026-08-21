-- ============================================================================
-- MIGRATION 92 — Báo cáo sự cố giữa tài xế và cửa hàng trong 1 đơn: tài xế báo cáo vấn đề của
-- cửa hàng (làm lâu/không có chỗ để xe/khác) kèm đánh giá khách hàng luôn trong cùng 1 lượt báo
-- cáo; cửa hàng báo cáo vấn đề của tài xế (đến trễ/thái độ/không tới lấy hàng/khác). Admin xem
-- + đánh dấu đã xử lý ở tab Báo cáo (web admin). Đây là kênh NỘI BỘ cho admin theo dõi/xử lý sự
-- cố vận hành — khác hẳn bảng `reviews` (đánh giá công khai khách để lại sau khi giao xong).
-- ============================================================================

CREATE TABLE issue_reports (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id         UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  -- 'driver' = tài xế báo cáo cửa hàng (kèm được customer_rating); 'merchant' = cửa hàng báo
  -- cáo tài xế. Suy ra target (cửa hàng/tài xế) từ chính reporter_type này, không cần cột riêng.
  reporter_type    TEXT NOT NULL CHECK (reporter_type IN ('driver', 'merchant')),
  reporter_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Nhiều vấn đề cùng lúc — mã cố định, nhãn tiếng Việt map ở tầng app (Flutter), không lưu
  -- text tiếng Việt để đổi câu chữ sau này không phải sửa dữ liệu cũ. Tài xế: slow/no_parking/
  -- other. Cửa hàng: late/attitude/no_show/other.
  issue_types      TEXT[] NOT NULL DEFAULT '{}',
  -- Số phút chờ — chỉ có ý nghĩa khi issue_types chứa 'slow' (cửa hàng làm lâu) hoặc 'late'
  -- (tài xế đến trễ).
  wait_minutes     INTEGER CHECK (wait_minutes IS NULL OR wait_minutes > 0),
  -- Ghi chú tự do — bắt buộc nhập ở tầng app khi issue_types chứa 'other'.
  note             TEXT,
  -- Đánh giá khách hàng (1-5 sao) — CHỈ tài xế báo cáo mới có, đi kèm cùng lượt báo cáo cửa
  -- hàng luôn thay vì tách riêng 1 luồng khác, cho tài xế phản hồi nhanh gọn 1 lần/đơn.
  customer_rating  SMALLINT CHECK (customer_rating IS NULL OR customer_rating BETWEEN 1 AND 5),
  status           TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  admin_note       TEXT,
  resolved_by      UUID REFERENCES users(id) ON DELETE SET NULL,
  resolved_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE issue_reports IS
  'Báo cáo sự cố nội bộ giữa tài xế/cửa hàng theo từng đơn — admin xem + đánh dấu xử lý ở tab
   Báo cáo (GET/PATCH /admin/issue-reports). Không hiển thị công khai, khác bảng reviews.';

CREATE INDEX idx_issue_reports_order     ON issue_reports (order_id);
CREATE INDEX idx_issue_reports_status    ON issue_reports (status, created_at DESC);
CREATE INDEX idx_issue_reports_reporter  ON issue_reports (reporter_id);
