const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireProfile, requireRole, requireMerchantAccess, pagination } = require('../utils');
const push = require('../push');

// Danh mục vấn đề cố định — nhãn tiếng Việt map ở tầng Flutter, xem hofa-db/92_issue_reports.sql.
const DRIVER_ISSUE_TYPES = ['slow', 'no_parking', 'other'];
const MERCHANT_ISSUE_TYPES = ['late', 'attitude', 'no_show', 'other'];

/** Tài xế báo cáo cửa hàng (kèm đánh giá khách hàng) hoặc cửa hàng báo cáo tài xế cho 1 đơn —
 * reporter_type suy ra thẳng từ ctx.role, không nhận từ client (tránh giả mạo). */
router.post('/issue-reports', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['order_id', 'issue_types']);

  const isDriver = req.ctx.role === 'driver';
  const isMerchant = ['merchant_owner', 'merchant_staff'].includes(req.ctx.role);
  if (!isDriver && !isMerchant) {
    throw new ApiError('FORBIDDEN', 'Chỉ tài xế hoặc cửa hàng mới báo cáo được', 403);
  }
  const reporterType = isDriver ? 'driver' : 'merchant';

  const order = await db.queryOne('SELECT id, merchant_id, order_code FROM orders WHERE id = $1', [req.body.order_id]);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);

  if (isDriver) {
    const delivery = await db.queryOne(
      `SELECT dl.id FROM deliveries dl
         JOIN drivers d ON d.id = dl.driver_id
        WHERE dl.order_id = $1 AND d.user_id = $2`,
      [order.id, req.ctx.userId]
    );
    if (!delivery) throw new ApiError('FORBIDDEN', 'Bạn không phải tài xế của đơn này', 403);
  } else {
    await requireMerchantAccess(req.ctx, order.merchant_id);
  }

  const allowedTypes = isDriver ? DRIVER_ISSUE_TYPES : MERCHANT_ISSUE_TYPES;
  const issueTypes = Array.isArray(req.body.issue_types) ? req.body.issue_types : [];
  if (!issueTypes.length || issueTypes.some((t) => !allowedTypes.includes(t))) {
    throw new ApiError('BAD_REQUEST', `issue_types phải là danh sách con của: ${allowedTypes.join(', ')}`, 400);
  }
  const needsMinutes = issueTypes.includes('slow') || issueTypes.includes('late');
  const waitMinutes = needsMinutes ? Number(req.body.wait_minutes) : null;
  if (needsMinutes && (!Number.isFinite(waitMinutes) || waitMinutes <= 0)) {
    throw new ApiError('BAD_REQUEST', 'Cần nhập số phút hợp lệ', 400);
  }
  const note = typeof req.body.note === 'string' ? req.body.note.trim() : '';
  if (issueTypes.includes('other') && !note) {
    throw new ApiError('BAD_REQUEST', 'Cần ghi chú khi chọn "Khác"', 400);
  }
  let customerRating = null;
  if (isDriver && req.body.customer_rating != null) {
    customerRating = Number(req.body.customer_rating);
    if (!Number.isInteger(customerRating) || customerRating < 1 || customerRating > 5) {
      throw new ApiError('BAD_REQUEST', 'customer_rating phải từ 1 đến 5', 400);
    }
  }

  const created = await db.insertRow('issue_reports', {
    order_id: order.id,
    reporter_type: reporterType,
    reporter_id: req.ctx.userId,
    issue_types: issueTypes,
    wait_minutes: waitMinutes,
    note: note || null,
    customer_rating: customerRating
  });

  const reporter = await db.queryOne('SELECT full_name FROM users WHERE id = $1', [req.ctx.userId]);
  push.notifyAdmins({
    title: reporterType === 'driver' ? 'Tài xế báo cáo cửa hàng' : 'Cửa hàng báo cáo tài xế',
    body: `${reporter?.full_name || ''} vừa gửi báo cáo cho đơn ${order.order_code}.`,
    kind: 'issue_report',
    screen: '/reports'
  }).catch((err) => {
    console.error('[push] Không báo được cho admin về issue report', err.message);
  });

  res.status(201).json({ ok: true, data: created });
}));

router.get('/admin/issue-reports', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`r.status = $${params.length}`); }
  if (req.query.reporter_type) { params.push(req.query.reporter_type); clauses.push(`r.reporter_type = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT r.*, o.order_code, o.merchant_id, m.name AS merchant_name,
            u.full_name AS reporter_name, u.phone AS reporter_phone,
            cu.full_name AS customer_name
       FROM issue_reports r
       JOIN orders o ON o.id = r.order_id
       JOIN merchants m ON m.id = o.merchant_id
       JOIN users u ON u.id = r.reporter_id
       JOIN users cu ON cu.id = o.customer_id
       ${where}
      ORDER BY r.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.patch('/admin/issue-reports/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const report = await db.queryOne('SELECT * FROM issue_reports WHERE id = $1', [req.params.id]);
  if (!report) throw new ApiError('NOT_FOUND', 'Không tìm thấy báo cáo', 404);
  if (report.status === 'resolved') {
    throw new ApiError('BAD_REQUEST', 'Báo cáo này đã được xử lý', 400);
  }
  const updated = await db.updateById('issue_reports', req.params.id, {
    status: 'resolved',
    admin_note: typeof req.body.admin_note === 'string' ? req.body.admin_note.trim() || null : null,
    resolved_by: req.ctx.userId,
    resolved_at: new Date().toISOString()
  });
  res.json({ ok: true, data: updated });
}));

module.exports = router;
