const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['interval_minutes'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM pwa_reminder_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — app khách đọc trực tiếp để biết cách bao nhiêu phút nhắc lại
// popup cài PWA (xem hofa_customer_app CustomerShell), khách chưa đăng nhập vẫn cần đọc được.
router.get('/pwa-reminder-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/pwa-reminder-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('pwa_reminder_settings', existing.id, data)
    : await db.insertRow('pwa_reminder_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
