const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['phone'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM admin_contact_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai — app khách cần đọc để hiện nút "Liên hệ hỗ trợ" ở màn chi tiết cửa hàng mua hộ,
// không bắt buộc đăng nhập (khách xem trang chủ/chi tiết cửa hàng không cần tài khoản).
router.get('/admin-contact-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/admin-contact-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('admin_contact_settings', existing.id, data)
    : await db.insertRow('admin_contact_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
