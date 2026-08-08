const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['bank_name', 'bank_bin', 'account_number', 'account_holder_name', 'min_withdrawal_balance'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM bank_account_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai — app khách cần đọc để tự dựng URL ảnh VietQR ở màn chi tiết đơn (đơn
// bank_transfer), không riêng gì admin.
router.get('/bank-account-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/bank-account-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('bank_account_settings', existing.id, data)
    : await db.insertRow('bank_account_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
