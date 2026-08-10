const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireRole, requirePermission } = require('../utils');
const push = require('../push');

// ---- Cửa hàng: số dư + rút tiền ----

/** Số dư khả dụng để rút (SUM toàn bộ merchant_wallet_transactions, không giới hạn khoảng thời
 * gian — khác GET /merchants/:id/finance/summary chỉ tính theo period). */
router.get('/merchants/:merchantId/wallet/balance', asyncHandler(async (req, res) => {
  await requirePermission(req.ctx, req.params.merchantId, 'finance.view');
  const row = await db.queryOne(
    'SELECT balance FROM merchant_wallet_balances WHERE merchant_id = $1',
    [req.params.merchantId]
  );
  res.json({ ok: true, data: { balance: row?.balance ?? 0 } });
}));

/** Yêu cầu rút tiền — trừ NGAY (atomic, xem RPC request_merchant_withdrawal:
 * hofa-db/65_merchant_wallet_withdrawals.sql). Bắt buộc đã có thông tin ngân hàng vì admin cần
 * đó để chuyển khoản trả cửa hàng — không có QR như bên tài xế (merchants chưa thu thập mã BIN
 * ngân hàng), admin tự chuyển khoản tay bằng thông tin hiện ra ở tab duyệt. */
router.post('/merchants/:merchantId/wallet/withdrawals', asyncHandler(async (req, res) => {
  await requirePermission(req.ctx, req.params.merchantId, 'finance.view');
  requireFields(req.body, ['amount']);
  const amount = Number(req.body.amount);
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new ApiError('BAD_REQUEST', 'Số tiền rút không hợp lệ', 400);
  }
  const merchant = await db.queryOne(
    'SELECT bank_name, bank_account_no, bank_account_name FROM merchants WHERE id = $1',
    [req.params.merchantId]
  );
  if (!merchant?.bank_name || !merchant?.bank_account_no || !merchant?.bank_account_name) {
    throw new ApiError('BANK_INFO_REQUIRED', 'Cần cập nhật thông tin ngân hàng (Sửa hồ sơ cửa hàng) trước khi rút tiền', 400);
  }
  const created = await db.callRpc('request_merchant_withdrawal', {
    p_merchant_id: req.params.merchantId,
    p_amount: amount
  });
  res.status(201).json({ ok: true, data: created });
}));

// ---- Admin: tổng quan + rút tiền + điều chỉnh tay ----

/** Danh sách cửa hàng kèm số dư ví — route admin-only RIÊNG, không đụng GET /merchants (route
 * đó công khai cho app khách duyệt cửa hàng, không được lộ số dư tài chính). */
router.get('/admin/merchant-wallets', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const rows = await db.query(
    `SELECT m.id, m.name, COALESCE(w.balance, 0) AS balance
       FROM merchants m
       LEFT JOIN merchant_wallet_balances w ON w.merchant_id = m.id
      WHERE m.deleted_at IS NULL
      ORDER BY m.name ASC LIMIT $1 OFFSET $2`,
    [limit, offset]
  );
  res.json({ ok: true, data: rows });
}));

router.get('/admin/merchant-wallets/summary', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await db.queryOne(
    `SELECT
       COALESCE((SELECT SUM(balance) FROM merchant_wallet_balances), 0) AS total_balance,
       COALESCE((SELECT SUM(amount) FROM merchant_wallet_withdrawals WHERE status = 'pending'), 0) AS pending_withdrawals`
  );
  res.json({ ok: true, data: row });
}));

router.get('/admin/merchant-wallet-withdrawals', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`w.status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT w.*, m.name AS merchant_name, m.bank_name, m.bank_bin, m.bank_account_no, m.bank_account_name
       FROM merchant_wallet_withdrawals w
       JOIN merchants m ON m.id = w.merchant_id
      ${where}
      ORDER BY w.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** Admin xác nhận ĐÃ chuyển khoản trả cửa hàng — tiền đã bị trừ khỏi ví từ lúc cửa hàng tạo yêu
 * cầu, nên ở đây chỉ đánh dấu xong, không đụng sổ cái nữa. */
router.post('/admin/merchant-wallet-withdrawals/:id/confirm', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const withdrawal = await db.queryOne(`SELECT * FROM merchant_wallet_withdrawals WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!withdrawal) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu rút tiền đang chờ', 404);

  const updated = await db.updateById('merchant_wallet_withdrawals', req.params.id, {
    status: 'confirmed',
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  push.notifyMerchantWallet(withdrawal.merchant_id, 'withdrawal_confirmed', withdrawal.amount).catch(() => {});
  res.json({ ok: true, data: updated });
}));

/** Từ chối yêu cầu rút — hoàn lại đúng số tiền đã trừ tạm lúc tạo yêu cầu, bằng 1 dòng sổ cái
 * entry_type=withdrawal_rejected (không UPDATE trực tiếp). */
router.post('/admin/merchant-wallet-withdrawals/:id/reject', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const withdrawal = await db.queryOne(`SELECT * FROM merchant_wallet_withdrawals WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!withdrawal) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu rút tiền đang chờ', 404);

  const updated = await db.updateById('merchant_wallet_withdrawals', req.params.id, {
    status: 'rejected',
    reject_reason: req.body.reason || null,
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  await db.insertRow('merchant_wallet_transactions', {
    merchant_id: withdrawal.merchant_id,
    entry_type: 'withdrawal_rejected',
    amount: withdrawal.amount,
    withdrawal_id: withdrawal.id,
    created_by: req.ctx.userId
  });
  push.notifyMerchantWallet(withdrawal.merchant_id, 'withdrawal_rejected', withdrawal.amount, req.body.reason).catch(() => {});
  res.json({ ok: true, data: updated });
}));

/** Điều chỉnh tay ví cửa hàng — luôn qua 1 dòng sổ cái kèm lý do bắt buộc (không bao giờ sửa số
 * dư trực tiếp), xem CHECK merchant_wallet_tx_adjustment_needs_note. */
router.post('/admin/merchants/:id/wallet-adjustment', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['amount', 'reason']);
  const amount = Number(req.body.amount);
  if (!Number.isInteger(amount) || amount === 0) {
    throw new ApiError('BAD_REQUEST', 'Số tiền điều chỉnh không hợp lệ', 400);
  }
  const merchant = await db.findById('merchants', req.params.id);
  if (!merchant) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);

  const created = await db.insertRow('merchant_wallet_transactions', {
    merchant_id: merchant.id,
    entry_type: 'admin_adjustment',
    amount,
    note: req.body.reason,
    created_by: req.ctx.userId
  });
  push.notifyMerchantWallet(merchant.id, 'admin_adjustment', amount, req.body.reason).catch(() => {});
  res.status(201).json({ ok: true, data: created });
}));

module.exports = router;
