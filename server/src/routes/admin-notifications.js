const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireRole, pagination } = require('../utils');
const push = require('../push');

/** role thật trong bảng users ứng với từng "nhóm" admin chọn ở màn Thông báo — cửa hàng
 * gồm cả chủ lẫn nhân viên vì cả 2 đều dùng app cửa hàng. */
const AUDIENCE_ROLES = {
  customer: ['customer'],
  driver: ['driver'],
  merchant: ['merchant_owner', 'merchant_staff']
};

function parseCsv(value) {
  return value ? String(value).split(',').map((s) => s.trim()).filter(Boolean) : [];
}

/** Số thiết bị đang có push_token cho 1 nhóm — hiện cho admin xem trước khi bấm gửi.
 * ?merchant_ids=... (nhóm cửa hàng, cụ thể) hoặc ?user_ids=... (khách hàng/tài xế, cụ thể)
 * — không truyền thì đếm toàn bộ nhóm audience_type. */
router.get('/admin/notifications/audience', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const audienceType = req.query.audience_type || 'customer';
  if (!AUDIENCE_ROLES[audienceType]) {
    throw new ApiError('BAD_REQUEST', 'audience_type không hợp lệ', 400);
  }

  let userIds = null;
  if (audienceType === 'merchant' && req.query.merchant_ids) {
    userIds = await push.resolveMerchantUserIds(parseCsv(req.query.merchant_ids));
  } else if (req.query.user_ids) {
    userIds = parseCsv(req.query.user_ids);
  }

  const row = userIds
    ? await db.queryOne(
        'SELECT COUNT(DISTINCT push_token) AS count FROM user_devices WHERE user_id = ANY($1::uuid[]) AND push_token IS NOT NULL',
        [userIds]
      )
    : await db.queryOne(
        `SELECT COUNT(DISTINCT d.push_token) AS count
           FROM user_devices d
           JOIN users u ON u.id = d.user_id
          WHERE u.role::text = ANY($1::text[]) AND u.deleted_at IS NULL AND d.push_token IS NOT NULL`,
        [AUDIENCE_ROLES[audienceType]]
      );
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
             WHERE r.notification_id = n.id) AS recipient_names,
           (SELECT array_agg(m.name ORDER BY m.name)
              FROM admin_notification_target_merchants tm
              JOIN merchants m ON m.id = tm.merchant_id
             WHERE tm.notification_id = n.id) AS target_merchant_names
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
  const audienceType = req.body.audience_type || 'customer';
  if (!AUDIENCE_ROLES[audienceType]) {
    throw new ApiError('BAD_REQUEST', 'audience_type không hợp lệ', 400);
  }
  const merchantIds = audienceType === 'merchant' && Array.isArray(req.body.merchant_ids)
    ? req.body.merchant_ids.filter(Boolean) : [];
  const userIds = audienceType !== 'merchant' && Array.isArray(req.body.user_ids)
    ? req.body.user_ids.filter(Boolean) : [];
  const showBadge = req.body.show_badge === true;

  const isSpecific = merchantIds.length > 0 || userIds.length > 0;
  const resolvedUserIds = audienceType === 'merchant'
    ? await push.resolveMerchantUserIds(merchantIds)
    : userIds;

  const { sent, total } = isSpecific
    ? await push.sendToUserIds(resolvedUserIds, { title, body, badge: showBadge })
    : await push.sendBroadcastToRoles(AUDIENCE_ROLES[audienceType], { title, body, badge: showBadge });

  const saved = await db.insertRow('admin_notifications', {
    title,
    body,
    audience_type: audienceType,
    target: isSpecific ? 'specific' : 'all',
    show_badge: showBadge,
    sent_count: sent,
    total_count: total,
    created_by: req.ctx.userId
  });

  if (isSpecific && resolvedUserIds.length) {
    await db.insertRows('admin_notification_recipients', resolvedUserIds.map((userId) => ({
      notification_id: saved.id,
      user_id: userId
    })));
  }
  if (audienceType === 'merchant' && merchantIds.length) {
    await db.insertRows('admin_notification_target_merchants', merchantIds.map((merchantId) => ({
      notification_id: saved.id,
      merchant_id: merchantId
    })));
  }

  res.status(201).json({ ok: true, data: saved });
}));

module.exports = router;
