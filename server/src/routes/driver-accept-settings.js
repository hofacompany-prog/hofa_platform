const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['auto_accept_sweep_seconds', 'manual_accept_sweep_seconds', 'offer_reminder_interval_seconds'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM driver_accept_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai — admin app đọc để hiện Thông số; driver app KHÔNG cần gọi trực tiếp vì
// dispatch.offerToNearestDriver đã tính sẵn accept_deadline theo đúng giá trị này rồi.
router.get('/driver-accept-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/driver-accept-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('driver_accept_settings', existing.id, data)
    : await db.insertRow('driver_accept_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
