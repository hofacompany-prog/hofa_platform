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

/** Ra đúng danh sách user_id theo 3 kiểu chọn đối tượng dùng chung cho gửi/xem/xoá hộp thư:
 * "cửa hàng cụ thể" (merchantIds), "khách hàng/tài xế cụ thể" (userIds), hoặc để trống cả 2
 * thì hiểu là TOÀN BỘ audienceType đó (mọi user có role tương ứng, kể cả chủ + nhân viên nếu
 * là 'merchant'). */
async function resolveAudienceUserIds({ audienceType, merchantIds, userIds }) {
  if (!AUDIENCE_ROLES[audienceType]) {
    throw new ApiError('BAD_REQUEST', 'audience_type không hợp lệ', 400);
  }
  if (audienceType === 'merchant' && merchantIds && merchantIds.length) {
    return push.resolveMerchantUserIds(merchantIds);
  }
  if (audienceType !== 'merchant' && userIds && userIds.length) {
    return userIds;
  }
  const rows = await db.query(
    `SELECT id FROM users WHERE role::text = ANY($1::text[]) AND deleted_at IS NULL`,
    [AUDIENCE_ROLES[audienceType]]
  );
  return rows.map((r) => r.id);
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
  const targetScreen = typeof req.body.target_screen === 'string' && req.body.target_screen.trim()
    ? req.body.target_screen.trim() : null;
  const NOTIFICATION_CATEGORIES = ['order', 'promotion', 'ad', 'system'];
  const category = NOTIFICATION_CATEGORIES.includes(req.body.category) ? req.body.category : 'system';

  const isSpecific = merchantIds.length > 0 || userIds.length > 0;
  const resolvedUserIds = audienceType === 'merchant'
    ? await push.resolveMerchantUserIds(merchantIds)
    : userIds;

  const { sent, total } = isSpecific
    ? await push.sendToUserIds(resolvedUserIds, { title, body, badge: showBadge, screen: targetScreen, category })
    : await push.sendBroadcastToRoles(AUDIENCE_ROLES[audienceType], { title, body, badge: showBadge, screen: targetScreen, category });

  const saved = await db.insertRow('admin_notifications', {
    title,
    body,
    audience_type: audienceType,
    target: isSpecific ? 'specific' : 'all',
    show_badge: showBadge,
    target_screen: targetScreen,
    category,
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

/** Hộp thư CỦA TỪNG NGƯỜI NHẬN (bảng notifications) lọc theo 1 phạm vi đối tượng — khác hẳn
 * GET /admin/notifications ở trên (đó là log các đợt gửi, không phải từng dòng người nhận
 * thật sự thấy). audience_type bắt buộc (customer/merchant/driver); không truyền
 * merchant_ids/user_ids thì hiểu là TOÀN BỘ audience_type đó — không cho duyệt toàn sàn
 * không lọc gì theo audience_type để tránh tải về quá nhiều dòng cùng lúc. */
router.get('/admin/notifications/inbox', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.query, ['audience_type']);
  const { limit, offset } = pagination(req.query);
  const userIds = await resolveAudienceUserIds({
    audienceType: req.query.audience_type,
    merchantIds: parseCsv(req.query.merchant_ids),
    userIds: parseCsv(req.query.user_ids)
  });
  if (!userIds.length) return res.json({ ok: true, data: [] });
  const rows = await db.query(
    `SELECT n.*, u.full_name AS recipient_name
       FROM notifications n
       JOIN users u ON u.id = n.user_id
      WHERE n.user_id = ANY($1::uuid[])
      ORDER BY n.created_at DESC
      LIMIT $2 OFFSET $3`,
    [userIds, limit, offset]
  );
  res.json({ ok: true, data: rows });
}));

/** Xoá 1/nhiều/tất cả dòng trong hộp thư người nhận — đúng 1 trong 3 kiểu body:
 * {ids: [...]} xoá đúng các dòng đó, {audience_type, merchant_ids?, user_ids?} xoá hết hộp
 * thư của 1 phạm vi đối tượng (toàn bộ audience_type đó nếu bỏ trống 2 tham số kia, hoặc chỉ
 * các cửa hàng/người dùng/tài xế cụ thể nếu có), {all: true} xoá TOÀN BỘ hộp thư mọi người
 * dùng trên sàn (nặng tay nhất, admin app phải tự xác nhận rõ ràng trước khi gọi). */
router.post('/admin/notifications/inbox/delete', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { ids, audience_type: audienceType, merchant_ids: merchantIds, user_ids: userIdsBody, all } = req.body;

  if (Array.isArray(ids) && ids.length) {
    const deleted = await db.query('DELETE FROM notifications WHERE id = ANY($1::uuid[]) RETURNING id', [ids]);
    return res.json({ ok: true, data: { deleted: deleted.length } });
  }
  if (audienceType) {
    const userIds = await resolveAudienceUserIds({
      audienceType,
      merchantIds: Array.isArray(merchantIds) ? merchantIds : [],
      userIds: Array.isArray(userIdsBody) ? userIdsBody : []
    });
    if (!userIds.length) return res.json({ ok: true, data: { deleted: 0 } });
    const deleted = await db.query(
      'DELETE FROM notifications WHERE user_id = ANY($1::uuid[]) RETURNING id',
      [userIds]
    );
    return res.json({ ok: true, data: { deleted: deleted.length } });
  }
  if (all === true) {
    const deleted = await db.query('DELETE FROM notifications RETURNING id');
    return res.json({ ok: true, data: { deleted: deleted.length } });
  }
  throw new ApiError('BAD_REQUEST', 'Cần đúng 1 trong: ids, audience_type, all', 400);
}));

module.exports = router;
