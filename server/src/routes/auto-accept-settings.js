const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = [
  'confirm_sweep_seconds', 'manual_confirm_sweep_seconds',
  'prep_tier_items', 'prep_tier_value_vnd',
  'prep_default_base_minutes', 'prep_default_increment_minutes', 'prep_default_max_minutes',
  'prep_ceiling_base_minutes', 'prep_ceiling_increment_minutes', 'prep_ceiling_max_minutes'
];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM auto_accept_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai — store app cần đọc để tính trần thời gian chuẩn bị + hiện đếm ngược ở màn nhận đơn.
router.get('/auto-accept-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/auto-accept-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('auto_accept_settings', existing.id, data)
    : await db.insertRow('auto_accept_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
