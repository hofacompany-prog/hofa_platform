const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = [
  'is_active', 'base_fee', 'base_distance_km', 'per_km_fee',
  'free_ship_threshold', 'max_fee', 'round_to',
];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM shipping_fee_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — app khách cần đọc để ước tính phí ship khi tính tổng đơn.
router.get('/shipping-fee-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/shipping-fee-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('shipping_fee_settings', existing.id, data)
    : await db.insertRow('shipping_fee_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
