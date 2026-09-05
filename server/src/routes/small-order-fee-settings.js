const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['is_active', 'threshold_amount', 'fee_amount'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at, xem
 * hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM small_order_fee_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — admin app cần đọc trước khi đăng nhập xong provider mới
// chạy được, giữ công khai cho nhất quán với các file *-settings.js khác.
router.get('/small-order-fee-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/small-order-fee-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('small_order_fee_settings', existing.id, data)
    : await db.insertRow('small_order_fee_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
