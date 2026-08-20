const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireProfile, requireRole } = require('../utils');
const push = require('../push');

// Khách/tài xế báo giá sai của 1 biến thể sản phẩm — xem hofa-db/89_product_price_reports.sql.
router.post('/price-reports', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['variant_id', 'reported_price']);
  const reportedPrice = Number(req.body.reported_price);
  if (!Number.isFinite(reportedPrice) || reportedPrice < 0) {
    throw new ApiError('BAD_REQUEST', 'Giá thực tế không hợp lệ', 400);
  }

  const info = await db.queryOne(
    `SELECT pv.id AS variant_id, pv.name AS variant_name, pv.price,
            p.id AS product_id, p.name AS product_name,
            m.id AS merchant_id, m.name AS merchant_name
       FROM product_variants pv
       JOIN products p ON p.id = pv.product_id
       JOIN merchants m ON m.id = p.merchant_id
      WHERE pv.id = $1`,
    [req.body.variant_id]
  );
  if (!info) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);

  const created = await db.insertRow('product_price_reports', {
    variant_id: info.variant_id,
    merchant_id: info.merchant_id,
    reported_by: req.ctx.userId,
    reporter_role: req.ctx.role,
    price_at_report: info.price,
    reported_price: Math.round(reportedPrice)
  });

  const reporter = await db.queryOne('SELECT full_name FROM users WHERE id = $1', [req.ctx.userId]);
  const reporterLabel = req.ctx.role === 'driver' ? 'Tài xế' : 'Khách hàng';
  await push.notifyAdmins({
    title: 'Báo cáo giá sai',
    body: `${reporterLabel} ${reporter?.full_name || ''} báo "${info.product_name}${info.variant_name ? ' - ' + info.variant_name : ''}" ` +
      `ở "${info.merchant_name}" đang hiện ${info.price}đ, giá thực tế ${Math.round(reportedPrice)}đ.`,
    kind: 'price_report',
    screen: '/merchants?tab=9'
  });

  res.status(201).json({ ok: true, data: created });
}));

router.get('/admin/price-reports', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`r.status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  const rows = await db.query(
    `SELECT r.*, pv.name AS variant_name, pv.price AS current_price,
            p.name AS product_name, m.name AS merchant_name,
            u.full_name AS reporter_name, u.phone AS reporter_phone
       FROM product_price_reports r
       JOIN product_variants pv ON pv.id = r.variant_id
       JOIN products p ON p.id = pv.product_id
       JOIN merchants m ON m.id = r.merchant_id
       JOIN users u ON u.id = r.reported_by
       ${where}
      ORDER BY r.created_at DESC
      LIMIT 100`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.patch('/admin/price-reports/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const report = await db.queryOne('SELECT * FROM product_price_reports WHERE id = $1', [req.params.id]);
  if (!report) throw new ApiError('NOT_FOUND', 'Không tìm thấy báo cáo', 404);
  if (report.status !== 'pending') {
    throw new ApiError('BAD_REQUEST', 'Báo cáo này đã được xử lý', 400);
  }
  if (!['approved', 'rejected'].includes(req.body.status)) {
    throw new ApiError('BAD_REQUEST', 'status phải là approved hoặc rejected', 400);
  }

  let finalPrice = null;
  if (req.body.status === 'approved') {
    finalPrice = req.body.final_price != null ? Math.round(Number(req.body.final_price)) : report.reported_price;
    if (!Number.isFinite(finalPrice) || finalPrice < 0) {
      throw new ApiError('BAD_REQUEST', 'Giá áp dụng không hợp lệ', 400);
    }
    await db.updateById('product_variants', report.variant_id, { price: finalPrice });
  }

  const updated = await db.updateById('product_price_reports', req.params.id, {
    status: req.body.status,
    final_price: finalPrice,
    reviewed_by: req.ctx.userId,
    reviewed_at: new Date().toISOString()
  });
  res.json({ ok: true, data: updated });
}));

module.exports = router;
