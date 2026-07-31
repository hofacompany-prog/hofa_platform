const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { requireRole } = require('../utils');

/**
 * Số liệu tổng quan cho màn hình đầu tiên của web admin.
 * Gộp trong 1 request để trang không phải gọi 8 API rời rạc lúc mở lên.
 * Doanh thu chỉ tính đơn đã giao/hoàn tất — đơn đang chạy hoặc đã huỷ không tính.
 */
router.get('/admin/stats', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);

  const [users, merchants, orders, revenue, recentOrders] = await Promise.all([
    db.queryOne(`
      SELECT
        COUNT(*)                                              AS total,
        COUNT(*) FILTER (WHERE role = 'customer')             AS customers,
        COUNT(*) FILTER (WHERE role IN ('merchant_owner','merchant_staff')) AS merchants,
        COUNT(*) FILTER (WHERE role = 'driver')               AS drivers,
        COUNT(*) FILTER (WHERE status = 'suspended' OR status = 'banned') AS blocked
      FROM users WHERE deleted_at IS NULL`),
    db.queryOne(`
      SELECT
        COUNT(*)                                            AS total,
        COUNT(*) FILTER (WHERE status = 'active')           AS active,
        COUNT(*) FILTER (WHERE status = 'pending_review')   AS pending_review,
        COUNT(*) FILTER (WHERE status = 'paused')           AS paused
      FROM merchants WHERE deleted_at IS NULL`),
    db.queryOne(`
      SELECT
        COUNT(*)                                                            AS total,
        COUNT(*) FILTER (WHERE created_at >= date_trunc('day', now()))      AS today,
        COUNT(*) FILTER (WHERE status NOT IN ('completed','cancelled','refunded')) AS in_progress,
        COUNT(*) FILTER (WHERE status = 'cancelled')                        AS cancelled
      FROM orders`),
    db.queryOne(`
      SELECT
        COALESCE(SUM(total_amount), 0)      AS gross,
        COALESCE(SUM(commission_amount), 0) AS commission
      FROM orders WHERE status IN ('delivered','completed')`),
    db.query(`
      SELECT o.id, o.order_code, o.status, o.total_amount, o.created_at,
             m.name AS merchant_name, u.full_name AS customer_name
        FROM orders o
        JOIN merchants m ON m.id = o.merchant_id
        JOIN users u ON u.id = o.customer_id
       ORDER BY o.created_at DESC LIMIT 8`)
  ]);

  res.json({ ok: true, data: { users, merchants, orders, revenue, recent_orders: recentOrders } });
}));

module.exports = router;
