const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['ttl_hours'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at, cùng kiểu shipping_fee_settings. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM notification_settings ORDER BY updated_at DESC LIMIT 1');
}

// Khác shipping-fee-settings/order-settings (public, app khách cần đọc) — cái này chỉ web
// admin dùng để tự dọn hộp thư, không app nào khác cần biết nên chặn admin luôn ở cả GET.
router.get('/notification-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/notification-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('notification_settings', existing.id, data)
    : await db.insertRow('notification_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
