const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireAuth, requireRole, requireMerchantAccess, requireOrderAccess } = require('../utils');
const dispatch = require('../dispatch');
const orderOffer = require('../orderOffer');

/** roles cho phép đổi SANG từng trạng thái; state machine chi tiết nằm trong RPC update_order_status. */
const ORDER_STATUS_ROLES = {
  confirmed: ['merchant_owner', 'merchant_staff', 'admin'],
  preparing: ['merchant_owner', 'merchant_staff', 'admin'],
  ready_for_pickup: ['merchant_owner', 'merchant_staff', 'admin'],
  cancelled: ['customer', 'merchant_owner', 'merchant_staff', 'admin'],
  completed: ['admin'],
  refunded: ['admin']
};

router.post('/orders', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const body = req.body;
  requireFields(body, ['merchant_id', 'branch_id', 'items', 'ship_recipient_name', 'ship_recipient_phone', 'ship_line1', 'ship_province']);
  if (!Array.isArray(body.items) || body.items.length === 0) {
    throw new ApiError('BAD_REQUEST', 'items phải là mảng và có ít nhất 1 món', 400);
  }

  const order = await db.callRpc('create_order', {
    p_customer_id: req.ctx.userId,
    p_merchant_id: body.merchant_id,
    p_branch_id: body.branch_id,
    p_sales_model: body.sales_model || 'instant',
    p_items: body.items, // [{variant_id, quantity, note}]
    p_ship_recipient_name: body.ship_recipient_name,
    p_ship_recipient_phone: body.ship_recipient_phone,
    p_ship_line1: body.ship_line1,
    p_ship_province: body.ship_province,
    p_ship_ward: body.ship_ward || null,
    p_ship_district: body.ship_district || null,
    p_ship_latitude: body.ship_latitude || null,
    p_ship_longitude: body.ship_longitude || null,
    p_ship_note: body.ship_note || null,
    p_payment_method: body.payment_method || 'cod',
    p_delivery_fee: body.delivery_fee || 0,
    p_tax_amount: body.tax_amount || 0,
    p_voucher_code: body.voucher_code || null,
    p_scheduled_for: body.scheduled_for || null,
    p_customer_note: body.customer_note || null
  });

  // Báo ngay cho cửa hàng (push + màn xác nhận có đếm ngược), giống luồng offer bên
  // tài xế — không tìm được cấu hình cửa hàng thì bỏ qua lặng lẽ, cửa hàng vẫn thấy
  // đơn trong danh sách "Chờ xác nhận" như bình thường.
  orderOffer.offerOrderToMerchant(order.id).catch((err) => {
    console.error('[orderOffer] Không báo được cửa hàng cho đơn', order.id, err.message);
  });

  res.status(201).json({ ok: true, data: order });
}));

router.get('/orders/mine', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const { limit, offset } = pagination(req.query);
  const clauses = ['customer_id = $1'];
  const params = [req.ctx.userId];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM orders WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** Toàn bộ đơn của mọi cửa hàng — chỉ admin. Kèm tên cửa hàng + tên khách để hiển thị
 * thẳng trong bảng, khỏi phải gọi thêm API cho từng dòng. */
router.get('/admin/orders', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`o.status = $${params.length}`); }
  if (req.query.merchant_id) { params.push(req.query.merchant_id); clauses.push(`o.merchant_id = $${params.length}`); }
  if (req.query.q) { params.push(`%${req.query.q}%`); clauses.push(`(o.order_code ILIKE $${params.length} OR o.ship_recipient_name ILIKE $${params.length})`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT o.*, m.name AS merchant_name, u.full_name AS customer_name
       FROM orders o
       JOIN merchants m ON m.id = o.merchant_id
       JOIN users u ON u.id = o.customer_id
       ${where}
      ORDER BY o.created_at DESC
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/merchants/:merchantId/orders', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const { limit, offset } = pagination(req.query);
  const clauses = ['merchant_id = $1'];
  const params = [req.params.merchantId];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  if (req.query.branch_id) { params.push(req.query.branch_id); clauses.push(`branch_id = $${params.length}`); }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM orders WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/orders/:id', asyncHandler(async (req, res) => {
  const order = await requireOrderAccess(req.ctx, req.params.id);
  const items = await db.query('SELECT * FROM order_items WHERE order_id = $1', [req.params.id]);
  res.json({ ok: true, data: { ...order, items } });
}));

router.get('/orders/:id/history', asyncHandler(async (req, res) => {
  await requireOrderAccess(req.ctx, req.params.id);
  const rows = await db.query('SELECT * FROM order_status_history WHERE order_id = $1 ORDER BY created_at ASC', [req.params.id]);
  res.json({ ok: true, data: rows });
}));

router.patch('/orders/:id/status', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['status']);
  const order = await requireOrderAccess(req.ctx, req.params.id);

  if (req.ctx.role !== 'admin') {
    const allowedRoles = ORDER_STATUS_ROLES[req.body.status];
    if (!allowedRoles || !allowedRoles.includes(req.ctx.role)) {
      throw new ApiError('FORBIDDEN', 'Vai trò của bạn không được đổi đơn sang trạng thái này', 403);
    }
    if (req.body.status === 'cancelled' && req.ctx.role === 'customer' && order.customer_id !== req.ctx.userId) {
      throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
    }
  }

  if (req.body.status === 'confirmed' && order.accept_deadline && new Date(order.accept_deadline) < new Date()) {
    await orderOffer.autoCancelExpiredOrder(req.params.id);
    throw new ApiError('OFFER_EXPIRED', 'Đã quá hạn xác nhận — đơn đã tự huỷ', 409);
  }

  const updated = await db.callRpc('update_order_status', {
    p_order_id: req.params.id,
    p_new_status: req.body.status,
    p_changed_by: req.ctx.userId,
    p_actor_role: req.ctx.role,
    p_note: req.body.note || null,
    p_force: req.ctx.role === 'admin'
  });
  if (req.body.status === 'confirmed') {
    await db.query('UPDATE orders SET accept_deadline = NULL WHERE id = $1', [req.params.id]);
  }

  // Đơn đã sẵn sàng lấy hàng — tự tìm tài xế online gần nhất, không bắt cửa hàng
  // phải tự chọn tài xế (giống Grab/Shopee). Không tìm được ai thì bỏ qua lặng lẽ,
  // cửa hàng vẫn có thể bấm "Tìm tài xế" thủ công (POST /orders/:id/find-driver).
  if (req.body.status === 'ready_for_pickup') {
    dispatch.offerToNearestDriver(req.params.id).catch((err) => {
      console.error('[dispatch] Không tự gán được tài xế cho đơn', req.params.id, err.message);
    });
  }

  res.json({ ok: true, data: updated });
}));

module.exports = router;
