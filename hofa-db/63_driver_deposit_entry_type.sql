-- Khôi phục "Nạp tiền" — giờ nạp THẲNG vào ví thu nhập (earning) qua sổ cái, thay vì cột
-- wallet_balance cũ (đã deprecated từ hofa-db/62_driver_wallet_ledger.sql). Cần vì bán kính
-- ký quỹ tối thiểu mới: tài xế phải có earning_balance >= giá trị đơn mới được hệ thống gán đơn
-- (MỌI loại đơn, không riêng COD/mua hộ — xem server/src/dispatch.js
-- findNearestOnlineDriver/offerToSpecificDriver) — tài xế mới (số dư 0) không có cách nào tự
-- nâng số dư ngoài chuyển khoản nạp tiền, nên bắt buộc phải có lại luồng này.
--
-- driver_wallet_deposits (bảng request/duyệt, hofa-db/47_driver_wallet_deposits_withdrawals.sql)
-- giữ nguyên không đổi — chỉ đổi phía server (POST /admin/wallet-deposits/:id/confirm) từ
-- UPDATE drivers.wallet_balance thô sang insert driver_wallet_transactions entry_type='deposit'.

ALTER TABLE driver_wallet_transactions DROP CONSTRAINT driver_wallet_transactions_entry_type_check;
ALTER TABLE driver_wallet_transactions ADD CONSTRAINT driver_wallet_transactions_entry_type_check
  CHECK (entry_type IN (
    'cod_collected', 'cod_settled',
    'earning_released', 'buy_on_behalf_reimbursement',
    'withdrawal', 'withdrawal_rejected', 'admin_adjustment',
    'deposit'
  ));
COMMENT ON COLUMN driver_wallet_transactions.entry_type IS
  'deposit = tài xế tự nạp tiền vào ví thu nhập (chuyển khoản, admin xác nhận qua POST /admin/wallet-deposits/:id/confirm) — dùng để đủ điều kiện ký quỹ tối thiểu (earning_balance >= giá trị đơn) khi nhận đơn mới, đặc biệt với tài xế mới chưa có chuyến nào.';
