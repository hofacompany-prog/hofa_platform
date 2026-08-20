const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pagination, requireProfile } = require('../utils');

/** Hộp thư thông báo trong app — 1 dòng/user cho mỗi push đã gửi (xem push.js
 * saveNotifications), độc lập với việc push có thật sự tới máy hay không. */

router.get('/notifications', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const { limit, offset } = pagination(req.query);
  const params = [req.ctx.userId];
  let categoryClause = '';
  if (req.query.category) {
    params.push(req.query.category);
    categoryClause = ` AND category = $${params.length}`;
  }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM notifications WHERE user_id = $1${categoryClause} ORDER BY created_at DESC, id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows, hasMore: rows.length === limit });
}));

router.get('/notifications/unread-count', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const params = [req.ctx.userId];
  let categoryClause = '';
  if (req.query.category) {
    params.push(req.query.category);
    categoryClause = ' AND category = $2';
  }
  const row = await db.queryOne(
    `SELECT COUNT(*) AS count FROM notifications WHERE user_id = $1 AND read_at IS NULL${categoryClause}`,
    params
  );
  res.json({ ok: true, data: { count: Number(row.count) } });
}));

router.patch('/notifications/:id/read', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const existing = await db.queryOne('SELECT id FROM notifications WHERE id = $1 AND user_id = $2', [req.params.id, req.ctx.userId]);
  if (!existing) throw new ApiError('NOT_FOUND', 'Không tìm thấy thông báo', 404);
  const updated = await db.updateById('notifications', req.params.id, { read_at: new Date().toISOString() });
  res.json({ ok: true, data: updated });
}));

router.post('/notifications/read-all', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  await db.query(
    'UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL',
    [req.ctx.userId]
  );
  res.json({ ok: true, data: { marked: true } });
}));

module.exports = router;
