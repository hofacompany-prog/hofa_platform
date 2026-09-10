const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['enabled'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at, xem
 * hofa-db/110_wholesale_preorder_toggle.sql. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM wholesale_preorder_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — app Khách gọi ngay lúc mở app, kể cả chưa đăng nhập, để
// biết có ẩn "Đặt trước/Bán sỉ" hay không, giữ nguyên convention các file *-settings.js khác.
router.get('/wholesale-preorder-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/wholesale-preorder-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('wholesale_preorder_settings', existing.id, data)
    : await db.insertRow('wholesale_preorder_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
