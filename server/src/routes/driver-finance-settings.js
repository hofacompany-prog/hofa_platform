const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['driver_fee_commission_rate', 'vat_rate', 'pit_rate', 'cod_debt_limit', 'buy_on_behalf_fee_share_rate'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM driver_finance_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — store/driver app không cần đọc trực tiếp (server tự áp
// dụng trong RPC), nhưng admin app cần trước khi đăng nhập xong provider mới chạy được, giữ
// công khai cho nhất quán với các file *-settings.js khác.
router.get('/driver-finance-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/driver-finance-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('driver_finance_settings', existing.id, data)
    : await db.insertRow('driver_finance_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
