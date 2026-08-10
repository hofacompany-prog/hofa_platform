const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['default_radius_km'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM delivery_radius_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — store app cần đọc để so với bán kính riêng của chi nhánh
// lúc thêm/sửa chi nhánh (gợi ý, không bắt buộc theo).
router.get('/delivery-radius-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/delivery-radius-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('delivery_radius_settings', existing.id, data)
    : await db.insertRow('delivery_radius_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
