const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pagination, requireAuth } = require('../utils');

/** Hộp thư thông báo trong app — 1 dòng/user cho mỗi push đã gửi (xem push.js
 * saveNotifications), độc lập với việc push có thật sự tới máy hay không. */

router.get('/notifications', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const { limit, offset } = pagination(req.query);
  const rows = await db.query(
    'SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3',
    [req.ctx.userId, limit, offset]
  );
  res.json({ ok: true, data: rows });
}));

router.get('/notifications/unread-count', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const row = await db.queryOne(
    'SELECT COUNT(*) AS count FROM notifications WHERE user_id = $1 AND read_at IS NULL',
    [req.ctx.userId]
  );
  res.json({ ok: true, data: { count: Number(row.count) } });
}));

router.patch('/notifications/:id/read', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const existing = await db.queryOne('SELECT id FROM notifications WHERE id = $1 AND user_id = $2', [req.params.id, req.ctx.userId]);
  if (!existing) throw new ApiError('NOT_FOUND', 'Không tìm thấy thông báo', 404);
  const updated = await db.updateById('notifications', req.params.id, { read_at: new Date().toISOString() });
  res.json({ ok: true, data: updated });
}));

router.post('/notifications/read-all', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  await db.query(
    'UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL',
    [req.ctx.userId]
  );
  res.json({ ok: true, data: { marked: true } });
}));

module.exports = router;
