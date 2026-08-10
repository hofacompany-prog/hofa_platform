const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireRole, requireMerchantAccess, requireOrderAccess } = require('../utils');
const dispatch = require('../dispatch');
const config = require('../config');
const push = require('../push');

async function requireOwnDriverRow(ctx) {
  requireRole(ctx, ['driver']);
  const driver = await db.queryOne('SELECT * FROM drivers WHERE user_id = $1', [ctx.userId]);
  if (!driver) throw new ApiError('NOT_FOUND', 'Bạn chưa có hồ sơ tài xế', 404);
  return driver;
}

async function requireOwnDelivery(ctx, deliveryId) {
  const driver = await requireOwnDriverRow(ctx);
  const delivery = await db.findById('deliveries', deliveryId);
  if (!delivery) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);
  if (delivery.driver_id !== driver.id) throw new ApiError('FORBIDDEN', 'Chuyến này không phải của bạn', 403);
  return delivery;
}

/** Đơn mua hộ mà khách CHỌN TAY tài xế (orders.selected_driver_id còn set) — tài xế từ chối/hết
 * hạn thì báo lại cho khách tự chọn người khác thay vì tự động chuyển tài xế gần nhất kế tiếp,
 * xem dispatch.repickNeeded. Đơn mua hộ mà khách chọn "để hệ thống tự tìm" thì selected_driver_id
 * luôn NULL (không set lúc đặt) — vẫn tự động chuyển tài xế khác như đơn thường. */
async function needsCustomerRepick(orderId) {
  const row = await db.queryOne(
    `SELECT m.merchant_type, o.selected_driver_id FROM orders o JOIN merchants m ON m.id = o.merchant_id WHERE o.id = $1`,
    [orderId]
  );
  return row?.merchant_type === 'buy_on_behalf' && row?.selected_driver_id != null;
}

router.get('/orders/:orderId/delivery', asyncHandler(async (req, res) => {
  await requireOrderAccess(req.ctx, req.params.orderId);
  // Kèm tên + rating tài xế — màn "Đánh giá tài xế" phía khách cần hiện tên, không chỉ driver_id.
  const row = await db.queryOne(
    `SELECT d.*, u.full_name AS driver_name, dr.rating_avg AS driver_rating_avg
       FROM deliveries d
       LEFT JOIN drivers dr ON dr.id = d.driver_id
       LEFT JOIN users u ON u.id = dr.user_id
      WHERE d.order_id = $1`,
    [req.params.orderId]
  );
  res.json({ ok: true, data: row });
}));

/** Phải đặt TRƯỚC /deliveries/:id để Express không hiểu nhầm "mine" là 1 giá trị :id
 * (giống lưu ý ở GET /merchants/mine trong merchants.js). Kèm b.name AS branch_name + m.name AS
 * merchant_name (tên quán, khác tên chi nhánh) + m.merchant_type (đơn mua hộ không có OTP lấy
 * hàng) — app tài xế cần cả 3 ngay ở thẻ trang chủ/chi tiết, không chờ gọi thêm GET
 * /branches/:id. */
router.get('/deliveries/mine', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  const { limit, offset } = pagination(req.query);
  const clauses = ['d.driver_id = $1'];
  const params = [driver.id];
  if (req.query.status) { params.push(req.query.status); clauses.push(`d.status = $${params.length}`); }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT d.*, b.name AS branch_name, m.name AS merchant_name, m.merchant_type
       FROM deliveries d
       JOIN orders o ON o.id = d.order_id
       JOIN branches b ON b.id = o.branch_id
       JOIN merchants m ON m.id = o.merchant_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY d.assigned_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/deliveries/:id', asyncHandler(async (req, res) => {
  await requireOwnDelivery(req.ctx, req.params.id);
  const delivery = await db.queryOne(
    `SELECT d.*, b.name AS branch_name, m.name AS merchant_name, m.merchant_type
       FROM deliveries d
       JOIN orders o ON o.id = d.order_id
       JOIN branches b ON b.id = o.branch_id
       JOIN merchants m ON m.id = o.merchant_id
      WHERE d.id = $1`,
    [req.params.id]
  );
  res.json({ ok: true, data: delivery });
}));

/** merchant (hoặc admin) gán 1 tài xế cụ thể cho đơn đã sẵn sàng lấy hàng — chọn tay. */
router.post('/orders/:orderId/assign-driver', asyncHandler(async (req, res) => {
  requireFields(req.body, ['driver_id']);
  const order = await db.findById('orders', req.params.orderId);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  await requireMerchantAccess(req.ctx, order.merchant_id);

  const delivery = await db.callRpc('assign_driver', {
    p_order_id: req.params.orderId,
    p_driver_id: req.body.driver_id,
    p_distance_km: req.body.distance_km || null,
    p_eta_minutes: req.body.eta_minutes || null,
    p_driver_fee: req.body.driver_fee || 0
  });
  res.json({ ok: true, data: delivery });
}));

/** Tự động tìm tài xế online gần nhất và gán (giống Grab/Shopee) — merchant/admin gọi
 * khi đơn đã "ready_for_pickup". Cũng được gọi tự động ở PATCH /orders/:id/status khi
 * đơn chuyển sang ready_for_pickup, endpoint này chỉ để bấm "Tìm tài xế" lại thủ công
 * nếu lần tự động đầu không tìm được ai (không có tài xế online). */
router.post('/orders/:orderId/find-driver', asyncHandler(async (req, res) => {
  const order = await db.findById('orders', req.params.orderId);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  await requireMerchantAccess(req.ctx, order.merchant_id);

  const existing = await db.queryOne('SELECT declined_driver_ids FROM deliveries WHERE order_id = $1', [req.params.orderId]);
  const result = await dispatch.offerToNearestDriver(req.params.orderId, {
    excludeDriverIds: existing?.declined_driver_ids || []
  });
  if (!result) throw new ApiError('NOT_FOUND', 'Hiện không có tài xế nào đang online', 404);
  res.json({ ok: true, data: result.delivery });
}));

/**
 * status: accepted | arrived_store | picked_up | delivering | delivered | failed
 * picked_up và delivered bắt buộc kèm otp đúng (khách đọc cho tài xế).
 */
router.patch('/deliveries/:id/status', asyncHandler(async (req, res) => {
  requireFields(req.body, ['status']);
  const delivery = await requireOwnDelivery(req.ctx, req.params.id);

  if (req.body.status === 'accepted' && delivery.accept_deadline && new Date(delivery.accept_deadline) < new Date()) {
    const driver = await db.queryOne('SELECT auto_accept FROM drivers WHERE user_id = $1', [req.ctx.userId]);
    // BẬT "Tự động nhận đơn": trễ 1 nhịp so với sweepExpiredOffers (client tự gọi accept ngay
    // lúc thanh màu chạy hết, có thể tới sau accept_deadline vài trăm ms vì độ trễ mạng) vẫn
    // đúng Ý ĐỊNH tự nhận — cho qua, không chặn/chuyển tài xế khác.
    if (!driver?.auto_accept) {
      if (await needsCustomerRepick(delivery.order_id)) {
        await dispatch.repickNeeded(req.params.id, 'Tài xế bạn chọn không xác nhận kịp thời gian');
        throw new ApiError('OFFER_EXPIRED', 'Đã quá hạn xác nhận — khách cần chọn lại tài xế khác', 409);
      }
      await dispatch.reassignAfterDecline(req.params.id);
      throw new ApiError('OFFER_EXPIRED', 'Đã quá hạn xác nhận — đơn đã được gán cho tài xế khác', 409);
    }
  }

  const updated = await db.callRpc('update_delivery_status', {
    p_delivery_id: req.params.id,
    p_new_status: req.body.status,
    p_otp: req.body.otp || null,
    p_recipient_name: req.body.recipient_name || null,
    p_proof_photo_urls: req.body.proof_photo_urls || null,
    p_signature_url: req.body.signature_url || null,
    p_failure_reason: req.body.failure_reason || null
  });
  if (req.body.status === 'accepted') {
    await db.query('UPDATE deliveries SET accept_deadline = NULL WHERE id = $1', [req.params.id]);
  }

  // update_delivery_status (RPC) tự đồng bộ order.status = cùng tên khi picked_up/delivering/
  // delivered — báo cho khách ngay ở đây vì SQL không gọi được firebase-admin.
  push.notifyCustomerOrderStatus(delivery.order_id, req.body.status).catch((err) => {
    console.error('[push] Không báo được cho khách về chuyến giao', req.params.id, err.message);
  });

  res.json({ ok: true, data: updated });
}));

/** Tài xế chủ động từ chối đơn vừa được gán (trước khi accepted) — tự động chuyển
 * sang tài xế gần nhất kế tiếp, tài xế hiện tại trở lại online. */
router.post('/deliveries/:id/decline', asyncHandler(async (req, res) => {
  const delivery = await requireOwnDelivery(req.ctx, req.params.id);
  if (delivery.status !== 'assigned') {
    throw new ApiError('BAD_REQUEST', 'Chỉ có thể từ chối đơn chưa xác nhận', 400);
  }
  const result = (await needsCustomerRepick(delivery.order_id))
    ? await dispatch.repickNeeded(req.params.id, 'Tài xế bạn chọn đã từ chối đơn')
    : await dispatch.reassignAfterDecline(req.params.id);
  res.json({ ok: true, data: { reassigned: !!result } });
}));

/** Quét các chuyến quá hạn accept_deadline và tự chuyển tài xế khác — gọi định kỳ
 * từ 1 cron ngoài (Render Cron Job, cron-job.org...) vì repo chưa có job scheduler
 * nội bộ. Bảo vệ bằng secret riêng, không dùng JWT vì đây không phải người dùng gọi. */
router.post('/internal/sweep-expired-offers', asyncHandler(async (req, res) => {
  if (!config.internalSweepSecret || req.headers['x-internal-secret'] !== config.internalSweepSecret) {
    throw new ApiError('FORBIDDEN', 'Thiếu hoặc sai secret', 403);
  }
  const result = await dispatch.sweepExpiredOffers();
  res.json({ ok: true, data: result });
}));

router.post('/deliveries/:id/tracks', asyncHandler(async (req, res) => {
  requireFields(req.body, ['latitude', 'longitude']);
  await requireOwnDelivery(req.ctx, req.params.id);
  const created = await db.insertRow('delivery_tracks', {
    delivery_id: req.params.id,
    latitude: req.body.latitude,
    longitude: req.body.longitude
  });
  res.status(201).json({ ok: true, data: created });
}));

router.get('/deliveries/:id/tracks', asyncHandler(async (req, res) => {
  const delivery = await db.findById('deliveries', req.params.id);
  if (!delivery) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);
  await requireOrderAccess(req.ctx, delivery.order_id); // khách/merchant/admin/chính tài xế đều xem được vệt đường
  const { limit } = pagination(req.query);
  const rows = await db.query(
    'SELECT * FROM delivery_tracks WHERE delivery_id = $1 ORDER BY recorded_at DESC LIMIT $2',
    [req.params.id, limit || 100]
  );
  res.json({ ok: true, data: rows });
}));

const ACTIVE_DELIVERY_STATUSES = ['pending', 'assigned', 'accepted', 'arrived_store', 'picked_up', 'delivering'];

/** Trả tài xế về 'online' nếu đang 'busy' vì đúng chuyến này — admin sửa/xoá tay bỏ qua RPC
 * update_delivery_status (không có side effect nào khác của RPC đó chạy ở đây, xem comment 2
 * route bên dưới), nên phải tự lo phần này để không kẹt tài xế "busy" mãi mãi. */
async function releaseDriverIfBusy(driverId) {
  if (!driverId) return;
  await db.query(`UPDATE drivers SET status = 'online' WHERE id = $1 AND status = 'busy'`, [driverId]);
}

/** Toàn bộ chuyến giao hàng đang "sống" (chưa delivered/failed/returned) kèm tên tài xế + mã
 * đơn/cửa hàng/khách — admin dùng để giám sát tổng thể, không theo từng tài xế riêng lẻ.
 * status=all bỏ lọc trạng thái (xem lịch sử luôn); status=<1 giá trị cụ thể> lọc đúng giá trị đó. */
router.get('/admin/deliveries', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const clauses = [];
  const params = [];
  if (req.query.status === 'all') {
    // không lọc gì thêm
  } else if (req.query.status) {
    params.push(req.query.status);
    clauses.push(`d.status = $${params.length}`);
  } else {
    params.push(ACTIVE_DELIVERY_STATUSES);
    clauses.push(`d.status = ANY($${params.length}::delivery_status[])`);
  }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  const { limit, offset } = pagination(req.query);
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT d.*, o.order_code, o.merchant_id, m.name AS merchant_name, o.ship_recipient_name AS customer_name,
            u.full_name AS driver_name, u.phone AS driver_phone
       FROM deliveries d
       JOIN orders o ON o.id = d.order_id
       LEFT JOIN merchants m ON m.id = o.merchant_id
       LEFT JOIN drivers dr ON dr.id = d.driver_id
       LEFT JOIN users u ON u.id = dr.user_id
       ${where}
      ORDER BY d.assigned_at DESC NULLS LAST, d.created_at DESC
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** 1 chuyến cụ thể, kèm đầy đủ điểm lấy hàng (branches) + điểm giao hàng (orders.ship_*) để
 * màn chi tiết chuyến giao (admin) hiện và cho sửa — khác GET /admin/deliveries (danh sách,
 * ít cột hơn cho gọn). */
router.get('/admin/deliveries/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await db.queryOne(
    `SELECT d.*, o.order_code, o.merchant_id, m.name AS merchant_name,
            o.ship_recipient_name AS customer_name, o.ship_recipient_phone AS customer_phone,
            o.ship_line1, o.ship_ward, o.ship_district, o.ship_province,
            o.ship_latitude, o.ship_longitude, o.branch_id,
            b.name AS branch_name, b.phone AS branch_phone,
            b.line1 AS branch_line1, b.ward AS branch_ward, b.district AS branch_district, b.province AS branch_province,
            b.latitude AS branch_latitude, b.longitude AS branch_longitude,
            u.full_name AS driver_name, u.phone AS driver_phone
       FROM deliveries d
       JOIN orders o ON o.id = d.order_id
       LEFT JOIN merchants m ON m.id = o.merchant_id
       LEFT JOIN branches b ON b.id = o.branch_id
       LEFT JOIN drivers dr ON dr.id = d.driver_id
       LEFT JOIN users u ON u.id = dr.user_id
      WHERE d.id = $1`,
    [req.params.id]
  );
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);
  res.json({ ok: true, data: row });
}));

/** Admin chỉnh tay trạng thái chuyến giao hàng — KHÔNG đi qua RPC update_delivery_status vì RPC
 * đó có side effect thật (trừ tồn kho lúc picked_up, cộng ví COD + đồng bộ orders.status lúc
 * delivered) không phù hợp cho 1 thao tác sửa dữ liệu hành chính; ở đây chỉ đổi đúng cột status,
 * không đụng tiền/tồn kho, tự trả tài xế về online nếu đang bận vì chuyến này. */
router.patch('/admin/deliveries/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const delivery = await db.findById('deliveries', req.params.id);
  if (!delivery) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);

  const updated = await db.updateById('deliveries', req.params.id, { status: req.body.status });
  if (!ACTIVE_DELIVERY_STATUSES.includes(req.body.status)) {
    await releaseDriverIfBusy(delivery.driver_id);
  }
  res.json({ ok: true, data: updated });
}));

/** Xoá thẳng 1 chuyến — cùng lý do không qua RPC như route đổi trạng thái ở trên. Giai đoạn
 * MVP: xoá thẳng, không chặn theo trạng thái (khớp quy ước DELETE /admin/orders/:id). */
router.delete('/admin/deliveries/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const delivery = await db.findById('deliveries', req.params.id);
  if (!delivery) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);
  await db.deleteById('deliveries', req.params.id);
  await releaseDriverIfBusy(delivery.driver_id);
  res.json({ ok: true, data: { deleted: true } });
}));

/** Xoá hàng loạt — {ids: [...]} xoá đúng danh sách, {status_in: [...]} xoá mọi chuyến đang ở 1
 * trong các trạng thái đó (dùng cho nút "Xoá tất cả" ở đúng bộ lọc đang xem), {all: true} xoá
 * toàn bộ bảng deliveries không lọc gì — khớp kiểu 3 hình dạng body của
 * POST /admin/notifications/inbox/delete. */
router.post('/admin/deliveries/delete', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { ids, status_in: statusIn, all } = req.body;

  let deleted;
  if (Array.isArray(ids) && ids.length) {
    deleted = await db.query('DELETE FROM deliveries WHERE id = ANY($1::uuid[]) RETURNING id, driver_id', [ids]);
  } else if (Array.isArray(statusIn) && statusIn.length) {
    deleted = await db.query(
      'DELETE FROM deliveries WHERE status = ANY($1::delivery_status[]) RETURNING id, driver_id',
      [statusIn]
    );
  } else if (all) {
    deleted = await db.query('DELETE FROM deliveries RETURNING id, driver_id');
  } else {
    throw new ApiError('BAD_REQUEST', 'Cần truyền ids, status_in hoặc all', 400);
  }

  const driverIds = [...new Set(deleted.map((r) => r.driver_id).filter(Boolean))];
  await Promise.all(driverIds.map((id) => releaseDriverIfBusy(id)));
  res.json({ ok: true, data: { deleted: deleted.length } });
}));

module.exports = router;
