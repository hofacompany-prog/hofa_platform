const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['hours_after_delivered'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM chat_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — app khách/tài xế/cửa hàng cần đọc trực tiếp để biết còn
// nhắn tin được không (server vẫn tự kiểm lại lúc POST, đây chỉ để hiện đúng UI).
router.get('/chat-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/chat-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('chat_settings', existing.id, data)
    : await db.insertRow('chat_settings', data);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
