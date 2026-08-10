-- ============================================================================
-- MIGRATION 68 — Hồi tố VAT/TNCN cho đơn tạo TRƯỚC migration 67
-- (hofa-db/67_merchant_net_income_wallet.sql).
--
-- Vấn đề: 67 thêm orders.vat_amount/pit_amount nhưng ALTER TABLE ... ADD COLUMN ... DEFAULT 0
-- backfill mọi đơn CŨ về 0 — nên "Thu nhập" (GET /merchants/:id/finance/summary, đọc thẳng
-- o.vat_amount/o.pit_amount từ sau 67) hết trừ thuế cho các đơn cũ đó (SUM ra 0), trong khi ví
-- (merchant_wallet_transactions) của các đơn đã 'delivered' TRƯỚC 67 vẫn đang giữ đúng số
-- merchant_payout CŨ (chỉ trừ hoa hồng, chưa trừ VAT/TNCN) — 2 lỗi cộng lại làm "Thu nhập"
-- và "Số tiền thu về" lại lệch nhau lần nữa, theo hướng ngược lại.
--
-- Cách sửa — theo yêu cầu người dùng "trừ cả phần chênh VAT+TNCN của đơn đó luôn":
-- 1) Backfill vat_amount/pit_amount/merchant_payout cho MỌI đơn cũ, dùng vat_rate/pit_rate
--    HIỆN TẠI của cửa hàng (không có lịch sử tỷ lệ từng đổi để dùng chính xác hơn — đây là
--    xấp xỉ tốt nhất có thể, đúng như cách "Thu nhập" vẫn tính trước khi có 67).
-- 2) Với đơn NÀO đã có dòng sổ cái entry_type=order_payout rồi (đã giao, đã cộng ví bằng số
--    CŨ) — chèn thêm 1 dòng sổ cái entry_type=tax_correction, amount ÂM đúng bằng phần
--    VAT+TNCN vừa backfill, để số dư ví giảm xuống đúng bằng thu nhập ròng thật. KHÔNG sửa/xoá
--    dòng order_payout cũ (sổ cái không bao giờ mutate) — chỉ ghi thêm dòng điều chỉnh.
--
-- An toàn chạy lại nhiều lần: bước 1 chỉ động tới đơn đang có vat_amount=0 AND pit_amount=0
-- (đơn tạo bằng create_order mới của 67 đã có giá trị khác 0 nên tự động bị bỏ qua); bước 2
-- có NOT EXISTS guard theo order_id, không tạo trùng dòng tax_correction.
--
-- CẢNH BÁO trước khi chạy: bước 2 làm giảm số dư ví thật của cửa hàng. Nếu cửa hàng nào đã rút
-- gần hết số dư (đã bị "phồng" do lỗi cũ) TRƯỚC KHI chạy migration này, số dư có thể xuống ÂM
-- sau khi chạy — kiểm tra bằng query cuối file trước khi cho phép rút tiếp cho các cửa hàng đó.
-- ============================================================================

BEGIN;

-- Mở rộng entry_type cho dòng điều chỉnh hồi tố ở bước 2 bên dưới.
ALTER TABLE merchant_wallet_transactions DROP CONSTRAINT merchant_wallet_transactions_entry_type_check;
ALTER TABLE merchant_wallet_transactions ADD CONSTRAINT merchant_wallet_transactions_entry_type_check
  CHECK (entry_type IN ('order_payout', 'withdrawal', 'withdrawal_rejected', 'admin_adjustment', 'tax_correction'));

-- Bước 1: backfill số liệu trên từng đơn.
UPDATE orders o
   SET vat_amount = ROUND(o.subtotal * m.vat_rate / 100.0),
       pit_amount = ROUND(o.subtotal * m.pit_rate / 100.0),
       merchant_payout = o.subtotal - o.commission_amount
                          - ROUND(o.subtotal * m.vat_rate / 100.0)
                          - ROUND(o.subtotal * m.pit_rate / 100.0)
  FROM merchants m
 WHERE o.merchant_id = m.id
   AND o.vat_amount = 0
   AND o.pit_amount = 0;

-- Bước 2: bù trừ ví cho các đơn đã giao TRƯỚC 67 (đã có order_payout bằng số cũ, chưa trừ thuế).
INSERT INTO merchant_wallet_transactions (merchant_id, entry_type, amount, order_id, note)
SELECT o.merchant_id, 'tax_correction', -(o.vat_amount + o.pit_amount), o.id,
       'Hồi tố khấu trừ VAT/TNCN cho đơn đã cộng ví trước migration 67 (xem hofa-db/68_merchant_tax_backfill.sql)'
  FROM orders o
  JOIN merchant_wallet_transactions t ON t.order_id = o.id AND t.entry_type = 'order_payout'
 WHERE (o.vat_amount + o.pit_amount) > 0
   AND NOT EXISTS (
     SELECT 1 FROM merchant_wallet_transactions tc
      WHERE tc.order_id = o.id AND tc.entry_type = 'tax_correction'
   );

COMMIT;

-- Chạy riêng (SAU khi COMMIT ở trên) để kiểm tra cửa hàng nào bị âm ví sau khi hồi tố —
-- không tự chặn gì, chỉ để biết trước khi cho phép các cửa hàng đó rút tiền tiếp:
--   SELECT merchant_id, balance FROM merchant_wallet_balances WHERE balance < 0;
