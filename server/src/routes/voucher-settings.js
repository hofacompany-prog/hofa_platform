const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['max_vouchers_per_order'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM voucher_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — app khách cần đọc để biết chọn/nhập tối đa mấy mã.
router.get('/voucher-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/voucher-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('voucher_settings', existing.id, data)
    : await db.insertRow('voucher_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
