const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireRole, pagination } = require('../utils');
const push = require('../push');

/** Số thiết bị đang có push_token — hiện cho admin xem trước khi bấm gửi, để biết ước
 * chừng sẽ chạm tới bao nhiêu người. Có ?user_ids=a,b,c thì chỉ đếm trong nhóm đó (dùng
 * khi admin đã chọn khách hàng cụ thể), không thì đếm toàn bộ khách hàng. */
router.get('/admin/notifications/audience', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const userIds = req.query.user_ids
    ? String(req.query.user_ids).split(',').map((s) => s.trim()).filter(Boolean)
    : null;

  const row = userIds && userIds.length
    ? await db.queryOne(
        'SELECT COUNT(DISTINCT push_token) AS count FROM user_devices WHERE user_id = ANY($1::uuid[]) AND push_token IS NOT NULL',
        [userIds]
      )
    : await db.queryOne(`
        SELECT COUNT(DISTINCT d.push_token) AS count
          FROM user_devices d
          JOIN users u ON u.id = d.user_id
         WHERE u.role = 'customer' AND u.deleted_at IS NULL AND d.push_token IS NOT NULL
      `);
  res.json({ ok: true, data: { count: Number(row.count) } });
}));

router.get('/admin/notifications', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const rows = await db.query(`
    SELECT n.*, u.full_name AS created_by_name,
           (SELECT array_agg(ru.full_name ORDER BY ru.full_name)
              FROM admin_notification_recipients r
              JOIN users ru ON ru.id = r.user_id
             WHERE r.notification_id = n.id) AS recipient_names
      FROM admin_notifications n
      LEFT JOIN users u ON u.id = n.created_by
     ORDER BY n.created_at DESC
     LIMIT $1 OFFSET $2
  `, [limit, offset]);
  res.json({ ok: true, data: rows });
}));

router.post('/admin/notifications', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['title', 'body']);
  const title = String(req.body.title).trim();
  const body = String(req.body.body).trim();
  if (!title || title.length > 150) {
    throw new ApiError('BAD_REQUEST', 'Tiêu đề không được để trống và tối đa 150 ký tự', 400);
  }
  if (!body || body.length > 500) {
    throw new ApiError('BAD_REQUEST', 'Nội dung không được để trống và tối đa 500 ký tự', 400);
  }
  const userIds = Array.isArray(req.body.user_ids) ? req.body.user_ids.filter(Boolean) : [];
  const isSpecific = userIds.length > 0;

  const { sent, total } = isSpecific
    ? await push.sendToUserIds(userIds, { title, body })
    : await push.sendBroadcastToCustomers({ title, body });

  const saved = await db.insertRow('admin_notifications', {
    title,
    body,
    target: isSpecific ? 'specific_users' : 'all_customers',
    sent_count: sent,
    total_count: total,
    created_by: req.ctx.userId
  });

  if (isSpecific) {
    await db.insertRows('admin_notification_recipients', userIds.map((userId) => ({
      notification_id: saved.id,
      user_id: userId
    })));
  }

  res.status(201).json({ ok: true, data: saved });
}));

module.exports = router;
