const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['max_distance_meters'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. Fallback 100m nếu chưa từng
 * chạy migration hofa-db/91_buy_on_behalf_pickup_proximity.sql. */
async function currentSettings() {
  const row = await db.queryOne('SELECT * FROM pickup_proximity_settings ORDER BY updated_at DESC LIMIT 1');
  return row || { max_distance_meters: 100 };
}

// Công khai — admin app đọc để hiện Thông số; deliveries.js tự đọc lại trong process server,
// không qua route này.
router.get('/pickup-proximity-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/pickup-proximity-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await db.queryOne('SELECT * FROM pickup_proximity_settings ORDER BY updated_at DESC LIMIT 1');
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('pickup_proximity_settings', existing.id, data)
    : await db.insertRow('pickup_proximity_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
