const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['min_order_amount', 'registration_otp_enabled'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM otp_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — app cửa hàng/tài xế/khách cần đọc trực tiếp để biết có bắt
// buộc nhập OTP cho đơn hiện tại hay không (server vẫn tự kiểm lại trong update_delivery_status,
// đây chỉ để hiện đúng UI), admin cần trước khi đăng nhập xong provider mới chạy được.
router.get('/otp-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/otp-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('otp_settings', existing.id, data)
    : await db.insertRow('otp_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
