const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pickFields, pagination, requireAuth, requireRole, requireMerchantAccess, requireOrderAccess } = require('../utils');
const dispatch = require('../dispatch');
const orderOffer = require('../orderOffer');
const push = require('../push');

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

  // Chặn thật ở server, không chỉ dựa vào UI app khách đã xám nút đặt hàng — khách vẫn có
  // thể gọi thẳng API. Chi nhánh tạm đóng (is_open=false, công tắc ở màn Trang chủ store
  // app) thì không tạo đơn mới được, dù vẫn xem được sản phẩm bình thường.
  const branch = await db.queryOne('SELECT is_open FROM branches WHERE id = $1', [body.branch_id]);
  if (!branch || !branch.is_open) {
    throw new ApiError('BRANCH_CLOSED', 'Cửa hàng đang tạm đóng, chưa thể đặt hàng lúc này', 409);
  }

  // Cửa hàng mua hộ bắt buộc thanh toán trước (chuyển khoản) — cửa hàng phải ứng tiền mua hộ
  // khách trước khi có hàng, không thể để khách trả sau (COD) như đơn thường. Chặn thật ở
  // server, không chỉ ẩn nút COD trên UI vì khách vẫn gọi thẳng API được.
  const merchant = await db.queryOne('SELECT merchant_type FROM merchants WHERE id = $1', [body.merchant_id]);
  if (merchant?.merchant_type === 'buy_on_behalf' && (body.payment_method || 'cod') === 'cod') {
    throw new ApiError(
      'PREPAYMENT_REQUIRED',
      'Cửa hàng mua hộ yêu cầu thanh toán trước — chọn Chuyển khoản ngân hàng thay vì COD',
      400
    );
  }

  // Cửa hàng mua hộ: khách chọn 1 trong 2 — tự chọn tài xế (selected_driver_id) hoặc để hệ
  // thống tự tìm gần nhất (bỏ trống, xem GET /drivers/available cho màn chọn tay). Không bắt
  // buộc nữa — chỉ validate KHI khách có chọn, để tài xế đã chọn còn thật sự online.
  if (merchant?.merchant_type === 'buy_on_behalf' && body.selected_driver_id) {
    const selectedDriver = await db.queryOne(`SELECT id FROM drivers WHERE id = $1 AND status = 'online'`, [body.selected_driver_id]);
    if (!selectedDriver) {
      throw new ApiError('DRIVER_UNAVAILABLE', 'Tài xế đã chọn hiện không còn online, vui lòng chọn lại', 409);
    }
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
    p_voucher_codes: Array.isArray(body.voucher_codes) ? body.voucher_codes : null,
    p_scheduled_for: body.scheduled_for || null,
    p_customer_note: body.customer_note || null
  });

  if (merchant?.merchant_type === 'buy_on_behalf' && body.selected_driver_id) {
    await db.query('UPDATE orders SET selected_driver_id = $2 WHERE id = $1', [order.id, body.selected_driver_id]);
    order.selected_driver_id = body.selected_driver_id;
  }

  // Đơn đặt trước (sales_model=scheduled) đặt đủ sớm thì KHÔNG báo ngay — để "ngủ" tới lúc còn
  // default_prep_minutes phút nữa là tới scheduled_for, sweepDuePreorders (index.js) sẽ kích
  // hoạt + báo sau, xem hofa-db/49_preorder_gating.sql. Đặt gấp (đã trong ngưỡng đó ngay lúc
  // tạo) thì coi như đơn tức thời, báo ngay như bình thường.
  if (order.status === 'placed' && orderOffer.isPreorderDormant(order)) {
    // để nguyên preorder_notified_at = NULL, không báo — sweep lo phần còn lại.
  } else {
    if (order.status === 'placed' && order.sales_model === 'scheduled') {
      await db.updateById('orders', order.id, { preorder_notified_at: new Date().toISOString() });
    }
    // Báo ngay cho cửa hàng (push + màn xác nhận có đếm ngược), giống luồng offer bên
    // tài xế — không tìm được cấu hình cửa hàng thì bỏ qua lặng lẽ, cửa hàng vẫn thấy
    // đơn trong danh sách "Chờ xác nhận" như bình thường.
    orderOffer.offerOrderToMerchant(order.id).catch((err) => {
      console.error('[orderOffer] Không báo được cửa hàng cho đơn', order.id, err.message);
    });
  }

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

/** Giai đoạn MVP: xoá thẳng, không chặn theo trạng thái/thanh toán. Nếu đơn còn bị ràng
 * buộc khoá ngoại (vd payments ON DELETE RESTRICT) thì Postgres tự chặn và trả lỗi cụ thể
 * qua fromPgError() trong db.js — không cần tự kiểm tra trước ở đây. */
router.delete('/admin/orders/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deleted = await db.deleteById('orders', req.params.id);
  if (!deleted) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  res.json({ ok: true, data: { deleted: true } });
}));

const SHIP_FIELDS = [
  'ship_recipient_name', 'ship_recipient_phone', 'ship_line1', 'ship_ward',
  'ship_district', 'ship_province', 'ship_latitude', 'ship_longitude'
];

/** Admin sửa tay điểm giao hàng của 1 đơn — dùng khi toạ độ sai/thiếu (ship_latitude/longitude
 * cho phép NULL, xem 01_schema.sql) khiến màn "Chuyến giao hàng" (admin) hoặc bản đồ tài xế
 * không hiện đúng vị trí. Không đụng gì tới deliveries hiện có (distance_km/eta_minutes/
 * driver_fee đã tính từ trước giữ nguyên) — chỉ áp dụng cho lần gán tài xế MỚI sau khi sửa. */
router.patch('/admin/orders/:id/shipping', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const order = await db.findById('orders', req.params.id);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  const data = pickFields(req.body, SHIP_FIELDS);
  const updated = await db.updateById('orders', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

router.get('/merchants/:merchantId/orders', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const { limit, offset } = pagination(req.query);
  const clauses = ['merchant_id = $1'];
  const params = [req.params.merchantId];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  if (req.query.branch_id) { params.push(req.query.branch_id); clauses.push(`branch_id = $${params.length}`); }
  // from/to: ngày dương lịch theo giờ Việt Nam (YYYY-MM-DD), dùng cho tab "Giao dịch" ở màn
  // Tài chính store app — cùng cách tính mốc ngày với /merchants/:id/finance/summary.
  if (req.query.from) {
    params.push(req.query.from);
    clauses.push(`(created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date >= $${params.length}::date`);
  }
  if (req.query.to) {
    params.push(req.query.to);
    clauses.push(`(created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date <= $${params.length}::date`);
  }
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
  if (items.length) {
    const toppings = await db.query(
      'SELECT * FROM order_item_toppings WHERE order_item_id = ANY($1::uuid[]) ORDER BY created_at ASC',
      [items.map((i) => i.id)]
    );
    const byItem = {};
    toppings.forEach((t) => { (byItem[t.order_item_id] ||= []).push(t); });
    items.forEach((i) => { i.toppings = byItem[i.id] || []; });
  }
  // Kèm tên + loại cửa hàng — app khách cần merchant_type để biết đơn mua hộ (hiện nút
  // "Chọn tài xế" khi cần chọn lại) và merchant_name để hiện tên quán ở màn chi tiết đơn.
  const merchant = await db.queryOne('SELECT name, merchant_type FROM merchants WHERE id = $1', [order.merchant_id]);
  res.json({
    ok: true,
    data: { ...order, merchant_name: merchant?.name ?? null, merchant_type: merchant?.merchant_type ?? null, items }
  });
}));

/**
 * Khách tự chọn (hoặc chọn LẠI, sau khi tài xế trước từ chối/hết hạn) 1 tài xế cho đơn mua hộ
 * — chỉ chủ đơn mới gọi được. Validate tài xế đang online rồi gán ngay (dispatchToSelectedDriver
 * dùng lại đúng logic gọi lúc thanh toán xong, xem orderOffer.js).
 */
router.post('/orders/:id/select-driver', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['driver_id']);
  const order = await requireOrderAccess(req.ctx, req.params.id);
  if (order.customer_id !== req.ctx.userId && req.ctx.role !== 'admin') {
    throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
  }
  const merchant = await db.queryOne('SELECT merchant_type FROM merchants WHERE id = $1', [order.merchant_id]);
  if (merchant?.merchant_type !== 'buy_on_behalf') {
    throw new ApiError('BAD_REQUEST', 'Chỉ đơn mua hộ mới cần chọn tài xế', 400);
  }
  const driver = await db.queryOne(`SELECT id FROM drivers WHERE id = $1 AND status = 'online'`, [req.body.driver_id]);
  if (!driver) {
    throw new ApiError('DRIVER_UNAVAILABLE', 'Tài xế đã chọn hiện không còn online, vui lòng chọn lại', 409);
  }
  await db.query('UPDATE orders SET selected_driver_id = $2 WHERE id = $1', [req.params.id, req.body.driver_id]);

  const result = await orderOffer.dispatchToSelectedDriver(req.params.id);
  res.json({ ok: true, data: { assigned: !!result } });
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
  orderOffer.assertPreorderActive(order, req.ctx.role);

  if (req.ctx.role !== 'admin') {
    const allowedRoles = ORDER_STATUS_ROLES[req.body.status];
    if (!allowedRoles || !allowedRoles.includes(req.ctx.role)) {
      throw new ApiError('FORBIDDEN', 'Vai trò của bạn không được đổi đơn sang trạng thái này', 403);
    }
    if (req.body.status === 'cancelled' && req.ctx.role === 'customer' && order.customer_id !== req.ctx.userId) {
      throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
    }
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
    // estimated_prep_minutes: cửa hàng tự chỉnh lúc trượt nhận đơn (màn nhận đơn store app) —
    // không bắt buộc, admin ép trạng thái thì không có giá trị này, cứ để NULL.
    const prepMinutes = Number.isInteger(req.body.estimated_prep_minutes) && req.body.estimated_prep_minutes > 0
      ? req.body.estimated_prep_minutes
      : null;
    if (prepMinutes !== null) {
      await db.query(
        'UPDATE orders SET estimated_prep_minutes = $2 WHERE id = $1',
        [req.params.id, prepMinutes]
      );
    }
  }

  // Đơn "làm xong" trễ hơn estimated_prep_minutes đã hứa lúc xác nhận — đánh dấu trễ bao
  // nhiêu phút để hiện badge ở danh sách đơn hàng (orders_list_screen.dart).
  if (req.body.status === 'ready_for_pickup' && updated.confirmed_at && updated.estimated_prep_minutes != null) {
    const elapsedMinutes = (new Date(updated.ready_at) - new Date(updated.confirmed_at)) / 60000;
    const lateMinutes = Math.round(elapsedMinutes - updated.estimated_prep_minutes);
    if (lateMinutes > 0) {
      await db.query('UPDATE orders SET late_minutes = $2 WHERE id = $1', [req.params.id, lateMinutes]);
      updated.late_minutes = lateMinutes;
    }
  }

  // Không tự báo cho khách khi chính khách là người vừa bấm huỷ — họ đã biết rồi.
  if (!(req.body.status === 'cancelled' && req.ctx.role === 'customer')) {
    push.notifyCustomerOrderStatus(req.params.id, req.body.status).catch((err) => {
      console.error('[push] Không báo được cho khách về đơn', req.params.id, err.message);
    });
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
