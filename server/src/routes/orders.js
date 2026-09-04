const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pickFields, pagination, requireProfile, requireRole, requireMerchantAccess, requireOrderAccess, requirePermission } = require('../utils');
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
  requireProfile(req.ctx);
  const body = req.body;
  requireFields(body, ['merchant_id', 'branch_id', 'items', 'ship_recipient_name', 'ship_recipient_phone', 'ship_line1', 'ship_province']);
  if (!Array.isArray(body.items) || body.items.length === 0) {
    throw new ApiError('BAD_REQUEST', 'items phải là mảng và có ít nhất 1 món', 400);
  }

  // Chặn thật ở server, không chỉ dựa vào UI app khách đã xám nút đặt hàng — khách vẫn có
  // thể gọi thẳng API. Chi nhánh không nhận đơn được nếu đang "tạm nghỉ" (công tắc ở màn Trang
  // chủ store app) HOẶC đang ngoài khung giờ hoạt động đã cấu hình (branch_hours) — kết hợp cả
  // 2, tính live qua branch_effective_status(), xem hofa-db/78_branch_operating_hours_gate.sql.
  const branch = await db.queryOne('SELECT branch_effective_status(id) AS status FROM branches WHERE id = $1', [body.branch_id]);
  if (!branch) {
    throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  }
  if (branch.status !== 'open') {
    const message = branch.status === 'on_break'
      ? 'Cửa hàng đang tạm nghỉ, chưa thể đặt hàng lúc này'
      : 'Cửa hàng đang ngoài giờ hoạt động, chưa thể đặt hàng lúc này';
    throw new ApiError('BRANCH_CLOSED', message, 409);
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

  // "Thanh toán theo tuần" (đặt trước tạo nhiều đơn/lần giao) — đơn này gộp thanh toán với
  // payment_group_order_id, chỉ là nhãn tham chiếu (không tự đổi payment_status, xem
  // hofa-db/56_order_payment_group.sql). Validate đơn được tham chiếu THẬT SỰ là của chính
  // khách này và cùng cửa hàng — khách không tự gắn được vào đơn của người khác.
  if (body.payment_group_order_id) {
    const target = await db.queryOne(
      'SELECT id FROM orders WHERE id = $1 AND customer_id = $2 AND merchant_id = $3',
      [body.payment_group_order_id, req.ctx.userId, body.merchant_id]
    );
    if (target) {
      await db.query('UPDATE orders SET payment_group_order_id = $2 WHERE id = $1', [order.id, target.id]);
      order.payment_group_order_id = target.id;
    }
  }

  // Đơn đặt trước/giá sỉ (sales_model=scheduled) KHÔNG còn "ngủ" chờ tới gần giờ giao nữa —
  // báo ngay cho cửa hàng xác nhận sớm như đơn tức thời (màn xác nhận phía store app LUÔN ép
  // kiểu "tắt tự động nhận đơn" cho loại đơn này bất kể chi nhánh có bật auto-accept hay không,
  // xem order_detail_screen.dart#_buildBody phía store app) — cửa hàng xác nhận xong thì khách
  // hết quyền tự huỷ (Order.canCancel phía app khách). preorder_notified_at giờ đổi ý nghĩa:
  // không còn đánh dấu "đã báo", mà đánh dấu "đã tự chuyển sang preparing đúng giờ" (xem
  // orderOffer.sweepDuePreorders), nên để nguyên NULL ở đây.
  //
  // Đơn GIAO NGAY đặt trước (sales_model=instant, scheduled_for khác NULL) còn đang "ngủ"
  // (scheduled_activated_at NULL — create_order() đã tự chốt, xem
  // hofa-db/84_instant_scheduled_order.sql) thì KHÔNG báo cửa hàng ngay, để orderOffer.
  // sweepDueScheduledInstant tự "nổ" đúng lúc.
  const isSleepingScheduledInstant =
    order.sales_model === 'instant' && order.scheduled_for && !order.scheduled_activated_at;
  if (order.status === 'placed' && !isSleepingScheduledInstant) {
    orderOffer.offerOrderToMerchant(order.id).catch((err) => {
      console.error('[orderOffer] Không báo được cửa hàng cho đơn', order.id, err.message);
    });
    // Báo cả admin mỗi khi có đơn mới — không chỉ chủ cửa hàng — để admin theo dõi được sát
    // sao mọi đơn phát sinh trên sàn, không riêng các đơn cần admin can thiệp tay (chuyển
    // khoản chờ xác nhận, tìm tài xế bị kẹt...). screen trỏ thẳng vào đúng đơn.
    push.notifyAdmins({
      title: 'Đơn hàng mới',
      body: `${order.order_code} · ${Number(order.total_amount).toLocaleString('vi-VN')}đ`,
      kind: 'new_order',
      screen: `/orders/${order.id}`
    }).catch((err) => {
      console.error('[push] Không báo được admin cho đơn mới', order.id, err.message);
    });
  } else if (order.status === 'placed' && isSleepingScheduledInstant) {
    // Báo TRƯỚC cho cửa hàng ngay lúc đặt — chỉ để xem trước (order_detail_screen.dart tự ẩn
    // hết nút hành động khi scheduled_activated_at NULL), CHƯA phải lượt "nổ" đơn thật sự (đó
    // là việc của orderOffer.sweepDueScheduledInstant khi gần tới giờ).
    push.resolveMerchantUserIds([order.merchant_id]).then((userIds) =>
      Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
        title: 'Đơn đặt trước mới',
        body: `${order.order_code} — hẹn giao ${new Date(order.scheduled_for).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })} (chỉ xem trước, chưa cần chuẩn bị)`,
        data: { type: 'order_upcoming', order_id: order.id }
      })))
    ).catch((err) => {
      console.error('[push] Không báo trước được cửa hàng cho đơn đặt trước', order.id, err.message);
    });
  } else if (order.status === 'pending_payment') {
    // Đơn chuyển khoản — chờ admin xác nhận đã nhận tiền (_PendingOrdersTab ở web admin) trước
    // khi cửa hàng được báo có đơn mới (xem POST /payments).
    push.notifyAdmins({
      title: 'Đơn cần xác nhận thanh toán',
      body: `${order.order_code} · ${Number(order.total_amount).toLocaleString('vi-VN')}đ chuyển khoản`,
      kind: 'order_pending_payment'
    }).catch((err) => {
      console.error('[push] Không báo được admin cho đơn chờ thanh toán', order.id, err.message);
    });
  }

  res.status(201).json({ ok: true, data: order });
}));

router.get('/orders/mine', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const { limit, offset } = pagination(req.query);
  const clauses = ['customer_id = $1'];
  const params = [req.ctx.userId];
  // ?status=a hoặc ?status=a,b,c — màn "Đơn hàng của tôi" gom nhiều trạng thái thật lại thành 1
  // nhóm hiển thị cho khách (vd "Đang giao" = ready_for_pickup+assigned+picked_up+delivering),
  // xem customerOrderStatusGroups trong hofa_customer_app/lib/models/order.dart.
  if (req.query.status) {
    const statuses = req.query.status.split(',').map((s) => s.trim()).filter(Boolean);
    if (statuses.length === 1) {
      params.push(statuses[0]);
      clauses.push(`status = $${params.length}`);
    } else if (statuses.length > 1) {
      params.push(statuses);
      clauses.push(`status = ANY($${params.length}::order_status[])`);
    }
  }
  // from/to: ngày dương lịch theo giờ Việt Nam (YYYY-MM-DD) — màn "Đơn hàng của tôi" bắt buộc
  // chọn 1 trong 4 khoảng (Hôm nay/Hôm qua/Tuần qua/Tháng qua), không còn xem "tất cả" không
  // giới hạn thời gian, cùng cách tính mốc ngày với /merchants/:merchantId/orders.
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
    `SELECT * FROM orders WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC, id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows, hasMore: rows.length === limit });
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
  // from/to: ngày dương lịch theo giờ Việt Nam (YYYY-MM-DD) — ngoại lệ cho admin, không bắt
  // buộc chọn (để trống = xem mọi đơn không giới hạn thời gian, khác app khách/cửa hàng).
  if (req.query.from) {
    params.push(req.query.from);
    clauses.push(`(o.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date >= $${params.length}::date`);
  }
  if (req.query.to) {
    params.push(req.query.to);
    clauses.push(`(o.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date <= $${params.length}::date`);
  }
  // Đơn mua hộ đang chờ tài xế lấy nhưng CHƯA có ai nhận (deliveries chưa có dòng nào, hoặc có
  // nhưng driver_id còn NULL) — dùng cho màn "Đơn hàng" lọc nhanh những đơn bị kẹt cần admin
  // quét/chọn tài xế thủ công, xem order_detail_screen.dart.
  if (req.query.needs_driver === 'true') {
    clauses.push(
      `m.merchant_type = 'buy_on_behalf' AND o.status = 'ready_for_pickup' AND (d.id IS NULL OR d.driver_id IS NULL)`
    );
  }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT o.*, m.name AS merchant_name, m.merchant_type, u.full_name AS customer_name,
            d.status AS delivery_status, d.driver_id AS delivery_driver_id
       FROM orders o
       JOIN merchants m ON m.id = o.merchant_id
       JOIN users u ON u.id = o.customer_id
       LEFT JOIN deliveries d ON d.order_id = o.id
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
  // upcoming_scheduled=true — tab "Sắp tới" (store app) xem TRƯỚC các đơn giao ngay đặt trước
  // còn đang "ngủ" (chưa tới ngưỡng báo/chưa "nổ", xem hofa-db/84_instant_scheduled_order.sql):
  // chỉ xem, KHÔNG thao tác được gì (order_detail_screen.dart tự ẩn hết nút hành động khi
  // scheduled_activated_at NULL) — không giới hạn theo created_at như luồng mặc định vì khách
  // có thể đặt trước nhiều ngày, cửa hàng cần thấy ngay từ lúc đặt chứ không chỉ đúng ngày đặt.
  const upcomingScheduled = req.query.upcoming_scheduled === 'true';
  const clauses = ['merchant_id = $1'];
  if (upcomingScheduled) {
    // pending_payment (chuyển khoản chưa được admin xác nhận) cũng loại — cùng nguyên tắc với
    // đơn thường: chưa có tiền thì cửa hàng chưa cần biết, kể cả để xem trước.
    clauses.push(
      "sales_model = 'instant' AND scheduled_for IS NOT NULL AND scheduled_activated_at IS NULL " +
      "AND status NOT IN ('cancelled', 'refunded', 'pending_payment')"
    );
  } else {
    // Đơn đang "ngủ" ẩn hẳn khỏi danh sách mặc định — cửa hàng chỉ thấy ở đây khi
    // orderOffer.sweepDueScheduledInstant "nổ" đơn (scheduled_activated_at có giá trị), hoặc
    // xem trước qua upcoming_scheduled=true ở trên.
    clauses.push("NOT (sales_model = 'instant' AND scheduled_for IS NOT NULL AND scheduled_activated_at IS NULL)");
  }
  const params = [req.params.merchantId];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  if (req.query.branch_id) { params.push(req.query.branch_id); clauses.push(`branch_id = $${params.length}`); }
  // payout_only=true — tab "Giao dịch" ở màn Tài chính (store app): chỉ đơn ĐÃ GIAO
  // (delivered_at khác NULL, đã được cộng sổ cái merchant_wallet_transactions, xem
  // hofa-db/64_merchant_wallet_ledger.sql) mới tính là 1 giao dịch thật — đơn còn đang chạy dù
  // chưa huỷ KHÔNG được tính. Đổi luôn cột dùng để lọc from/to sang delivered_at (ngày tiền
  // thực sự về) thay vì created_at (ngày đặt), khớp with /merchants/:id/finance/summary.
  const payoutOnly = req.query.payout_only === 'true';
  const dateColumn = payoutOnly ? 'delivered_at' : 'created_at';
  if (payoutOnly) clauses.push('delivered_at IS NOT NULL');
  // from/to: ngày dương lịch theo giờ Việt Nam (YYYY-MM-DD), dùng cho tab "Giao dịch" ở màn
  // Tài chính store app — cùng cách tính mốc ngày với /merchants/:id/finance/summary.
  if (req.query.from) {
    params.push(req.query.from);
    clauses.push(`(${dateColumn} AT TIME ZONE 'Asia/Ho_Chi_Minh')::date >= $${params.length}::date`);
  }
  if (req.query.to) {
    params.push(req.query.to);
    clauses.push(`(${dateColumn} AT TIME ZONE 'Asia/Ho_Chi_Minh')::date <= $${params.length}::date`);
  }
  params.push(limit, offset);
  // upcoming_scheduled: sắp xếp theo giờ hẹn giao SẮP TỚI trước (không phải mới đặt trước) —
  // cửa hàng cần thấy đơn nào gần tới giờ nhất lên đầu để chuẩn bị tinh thần trước.
  const orderBy = upcomingScheduled ? 'scheduled_for ASC' : 'created_at DESC';
  const rows = await db.query(
    `SELECT * FROM orders WHERE ${clauses.join(' AND ')} ORDER BY ${orderBy} LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/orders/:id', asyncHandler(async (req, res) => {
  const order = await requireOrderAccess(req.ctx, req.params.id);
  // Kèm product_id (qua product_variants) — cần để màn "Đánh giá món ăn" biết đánh giá đúng
  // sản phẩm nào, order_items chỉ lưu variant_id chứ không có product_id trực tiếp.
  const items = await db.query(
    `SELECT oi.*, pv.product_id
       FROM order_items oi
       LEFT JOIN product_variants pv ON pv.id = oi.variant_id
      WHERE oi.order_id = $1`,
    [req.params.id]
  );
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
  // delivery_driver_id — admin cần biết đơn mua hộ đã có tài xế hay chưa để hiện đúng thẻ
  // "Quét tài xế"/"Chọn tài xế" (order_detail_screen.dart), không phải tự suy luận qua status.
  const delivery = await db.queryOne('SELECT status, driver_id FROM deliveries WHERE order_id = $1', [order.id]);
  res.json({
    ok: true,
    data: {
      ...order,
      merchant_name: merchant?.name ?? null,
      merchant_type: merchant?.merchant_type ?? null,
      delivery_status: delivery?.status ?? null,
      delivery_driver_id: delivery?.driver_id ?? null,
      items
    }
  });
}));

/**
 * Khách tự chọn (hoặc chọn LẠI, sau khi tài xế trước từ chối/hết hạn) 1 tài xế cho đơn mua hộ
 * — chỉ chủ đơn mới gọi được. Validate tài xế đang online rồi gán ngay (dispatchToSelectedDriver
 * dùng lại đúng logic gọi lúc thanh toán xong, xem orderOffer.js). ADMIN gọi được cho MỌI đơn
 * (kể cả đơn thường, không riêng mua hộ) — dùng ở màn "Quét tài xế" web admin khi quét tự động
 * không ra ai, admin tự chỉ định tài xế phù hợp hơn.
 */
router.post('/orders/:id/select-driver', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['driver_id']);
  const order = await requireOrderAccess(req.ctx, req.params.id);
  if (order.customer_id !== req.ctx.userId && req.ctx.role !== 'admin') {
    throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
  }
  // Đơn thường (không phải mua hộ) mặc định để hệ thống tự tìm tài xế gần nhất — chỉ ADMIN mới
  // được tự chỉ định tay (vd quét không ra ai, admin can thiệp chọn tài xế phù hợp hơn ở màn
  // chi tiết đơn), khách hàng KHÔNG tự chọn được cho đơn thường (khác đơn mua hộ, khách được
  // chọn thẳng — merchant_type check dưới đây bỏ qua nếu đã là admin).
  const merchant = await db.queryOne('SELECT merchant_type FROM merchants WHERE id = $1', [order.merchant_id]);
  if (merchant?.merchant_type !== 'buy_on_behalf' && req.ctx.role !== 'admin') {
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
  requireProfile(req.ctx);
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
    // Đơn đặt trước/giá sỉ (sales_model 'scheduled') — khách chỉ tự huỷ được TRƯỚC khi cửa
    // hàng xác nhận (status 'pending_payment'/'placed'); cửa hàng xác nhận xong (status
    // 'confirmed' trở đi, coi như đã bắt đầu giữ chỗ nguyên liệu theo lịch) thì khách hết
    // quyền tự huỷ, chỉ liên hệ cửa hàng nhờ huỷ hộ — chặn thật ở đây, không chỉ ẩn nút ở app
    // khách, xem Order.canCancel/canContactMerchantToCancel phía Flutter.
    if (
      req.body.status === 'cancelled' &&
      req.ctx.role === 'customer' &&
      order.sales_model === 'scheduled' &&
      !['pending_payment', 'placed'].includes(order.status)
    ) {
      throw new ApiError(
        'FORBIDDEN',
        'Đơn đặt trước/giá sỉ đã được cửa hàng xác nhận, không tự huỷ được nữa — vui lòng liên hệ trực tiếp cửa hàng',
        403
      );
    }
    // Nhân viên đổi trạng thái đơn (khác 'cancelled' của khách ở trên) cần đúng quyền
    // orders.manage — chủ cửa hàng/admin đã qua ORDER_STATUS_ROLES ở trên là đủ.
    if (req.ctx.role === 'merchant_staff') {
      await requirePermission(req.ctx, order.merchant_id, 'orders.manage');
    }
  }

  // Cửa hàng bấm "Đã làm xong" (status=ready_for_pickup) nhưng tài xế đã XÁC NHẬN NHẬN ĐƠN từ
  // trước (tìm sớm, xem hofa-db/105_early_driver_search.sql) — orders.status đã tự nhảy sang
  // 'assigned' ngay lúc tài xế bấm nhận (update_delivery_status RPC, xem hofa-db/
  // 106_driver_confirm_before_assigned.sql), không phải lúc mời như trước. Chuyển tiếp
  // 'assigned' → 'ready_for_pickup' không còn hợp lệ với state machine (đi lùi) — không cần tìm
  // lại tài xế, chỉ đánh dấu ready_at (mốc "món đã xong" để tính trễ) + báo tài xế "hàng đã
  // xong, tới lấy được rồi", bỏ qua toàn bộ phần dưới.
  if (req.body.status === 'ready_for_pickup' && order.status === 'assigned') {
    let readyRow = order;
    if (!order.ready_at) {
      readyRow = await db.queryOne('UPDATE orders SET ready_at = now() WHERE id = $1 RETURNING *', [req.params.id]);
      if (order.confirmed_at && order.estimated_prep_minutes != null) {
        const elapsedMinutes = (new Date(readyRow.ready_at) - new Date(order.confirmed_at)) / 60000;
        const lateMinutes = Math.round(elapsedMinutes - order.estimated_prep_minutes);
        if (lateMinutes > 0) {
          await db.query('UPDATE orders SET late_minutes = $2 WHERE id = $1', [req.params.id, lateMinutes]);
          readyRow.late_minutes = lateMinutes;
        }
      }
      dispatch.notifyDriverOrderReady(req.params.id).catch((err) => {
        console.error('[dispatch] Không báo được tài xế đơn đã sẵn sàng', req.params.id, err.message);
      });
    }
    return res.json({ ok: true, data: readyRow });
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
    // Công tắc "tối đa" (driver_dispatch_settings.search_on_confirm, admin cấu hình) — MỜI tài
    // xế NGAY lúc xác nhận thay vì đợi tới ngưỡng search_before_ready_minutes (xem
    // dispatch.sweepEarlyDriverSearch, quét định kỳ, chỉ xử lý nhánh TẮT công tắc này). Chỉ MỜI
    // — orders.status không đổi cho tới khi tài xế thật sự bấm nhận (xem hofa-db/
    // 106_driver_confirm_before_assigned.sql).
    if (!order.selected_driver_id) {
      dispatch.currentDriverDispatchSettings().then((settings) => {
        if (!settings.search_on_confirm) return;
        return dispatch.offerToNearestDriver(req.params.id);
      }).catch((err) => {
        console.error('[dispatch] Không tự gán được tài xế sớm cho đơn (search_on_confirm)', req.params.id, err.message);
      });
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
    // Có thể đã có 1 lời mời đang treo từ trước (tìm sớm mời 1 tài xế, họ chưa phản hồi —
    // deliveries.driver_id đã set nhưng chưa 'accepted') — không tìm mới đè lên, deliveries.
    // order_id UNIQUE nên tìm lại sẽ ghi đè mất lời mời đang treo mà tài xế kia không hề hay
    // biết. Chỉ tìm khi CHƯA có ai được mời (chưa từng tìm, hoặc tìm sớm thất bại hoàn toàn —
    // driver_id NULL).
    const pendingOffer = await db.queryOne(
      'SELECT id FROM deliveries WHERE order_id = $1 AND driver_id IS NOT NULL',
      [req.params.id]
    );
    if (!pendingOffer) {
      dispatch.offerToNearestDriver(req.params.id).catch((err) => {
        console.error('[dispatch] Không tự gán được tài xế cho đơn', req.params.id, err.message);
      });
    }
  }

  res.json({ ok: true, data: updated });
}));

/** Đổi giờ hẹn giao của đơn GIAO NGAY có đặt trước (sales_model='instant', scheduled_for khác
 * NULL — khác hẳn đơn "Đặt trước/Giá sỉ" sales_model='scheduled', route này KHÔNG áp dụng cho
 * loại đó, đã có luồng xác nhận riêng). Khách tự đổi được giờ đơn CỦA MÌNH khi còn sớm (trước
 * khi cửa hàng xác nhận/bắt đầu chuẩn bị); admin đổi được bất kỳ lúc nào cho bất kỳ đơn nào.
 * Cửa hàng thấy đơn này ngay từ lúc đặt (tab "Sắp tới", xem trước — GET /merchants/:id/orders?
 * upcoming_scheduled=true), trừ lúc còn pending_payment (chưa xác nhận chuyển khoản, chưa lộ
 * cho cửa hàng) — nên hễ đơn đã qua giai đoạn đó là báo luôn giờ mới, không đợi tới lúc
 * "activated" (order_offer nếu đã activated, order_upcoming nếu còn đang xem trước). */
router.patch('/orders/:id/scheduled-for', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const order = await db.findById('orders', req.params.id);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);

  const isAdmin = req.ctx.role === 'admin';
  if (!isAdmin && order.customer_id !== req.ctx.userId) {
    throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
  }
  if (order.sales_model !== 'instant') {
    throw new ApiError('BAD_REQUEST', 'Chỉ áp dụng cho đơn giao ngay có đặt giờ trước, không phải đơn Đặt trước/Giá sỉ', 400);
  }

  let scheduledFor = null;
  if (req.body.scheduled_for) {
    scheduledFor = new Date(req.body.scheduled_for);
    if (Number.isNaN(scheduledFor.getTime())) {
      throw new ApiError('BAD_REQUEST', 'scheduled_for không hợp lệ', 400);
    }
  }
  if (!isAdmin) {
    if (!['pending_payment', 'placed', 'confirmed'].includes(order.status)) {
      throw new ApiError('BAD_REQUEST', 'Đơn đã sang giai đoạn chuẩn bị, không tự đổi giờ được nữa — liên hệ cửa hàng', 400);
    }
    // scheduledFor = null hợp lệ ở đây — khách tự chuyển đơn về giao ngay (bỏ hẳn giờ hẹn),
    // xem nút "Giao ngay" cạnh "Đổi giờ" trên order_detail_screen.dart.
    if (scheduledFor && scheduledFor.getTime() <= Date.now()) {
      throw new ApiError('BAD_REQUEST', 'Giờ hẹn giao phải ở tương lai', 400);
    }
  }

  const wasSleeping = order.scheduled_for && !order.scheduled_activated_at;
  const patch = { scheduled_for: scheduledFor ? scheduledFor.toISOString() : null };

  // Chuyển về giao ngay (scheduledFor null) — chốt lại confirm_sweep_deadline MỚI TINH y hệt 1
  // đơn tức thời vừa đặt (cùng cách tính với orderOffer.sweepDueScheduledInstant), không để dính
  // deadline cũ (đã chốt lúc tạo đơn hoặc lúc "nổ" theo giờ hẹn trước đó — nếu không đổi, thanh
  // trượt xác nhận phía cửa hàng sẽ chạy sai, không phản ánh đúng "vừa chuyển sang giao ngay").
  // Chỉ áp dụng khi đơn đã 'placed' (đã lộ cho cửa hàng) — 'pending_payment' chưa lộ, 'confirmed'
  // cửa hàng đã xác nhận nên thanh trượt không còn ý nghĩa.
  if (!scheduledFor && order.status === 'placed') {
    const branch = await db.queryOne('SELECT auto_accept_orders FROM branches WHERE id = $1', [order.branch_id]);
    const settings = await db.queryOne(
      'SELECT confirm_sweep_seconds, manual_confirm_sweep_seconds FROM auto_accept_settings ORDER BY updated_at DESC LIMIT 1'
    );
    const seconds = (branch?.auto_accept_orders ? settings?.confirm_sweep_seconds : settings?.manual_confirm_sweep_seconds) ?? 10;
    patch.scheduled_activated_at = new Date().toISOString();
    patch.confirm_sweep_deadline = new Date(Date.now() + seconds * 1000).toISOString();
  }

  const updated = await db.updateById('orders', req.params.id, patch);

  if (!scheduledFor && wasSleeping && order.status === 'placed') {
    orderOffer.offerOrderToMerchant(order.id).catch((err) => {
      console.error('[orderOffer] Không báo được cửa hàng cho đơn chuyển giao ngay', order.id, err.message);
    });
  }

  if (order.status !== 'pending_payment') {
    push.resolveMerchantUserIds([order.merchant_id]).then((userIds) =>
      Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
        title: 'Đơn hàng đổi giờ hẹn giao',
        body: scheduledFor
          ? `${order.order_code} — giờ giao mới: ${scheduledFor.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}`
          : `${order.order_code} — đã bỏ giờ hẹn giao, chuyển về giao ngay`,
        data: {
          type: order.scheduled_activated_at ? 'order_offer' : 'order_upcoming',
          order_id: req.params.id
        }
      })))
    ).catch((err) => {
      console.error('[push] Không báo được cho cửa hàng về đổi giờ hẹn giao', req.params.id, err.message);
    });
  }

  res.json({ ok: true, data: updated });
}));

module.exports = router;
