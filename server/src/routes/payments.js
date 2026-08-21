const router = require('express').Router();
const db = require('../db');
const config = require('../config');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireProfile, requireRole, requireMerchantAccess, requireOrderAccess } = require('../utils');
const orderOffer = require('../orderOffer');
const push = require('../push');

router.get('/orders/:orderId/payments', asyncHandler(async (req, res) => {
  await requireOrderAccess(req.ctx, req.params.orderId);
  const rows = await db.query(
    'SELECT * FROM payments WHERE order_id = $1 ORDER BY created_at DESC',
    [req.params.orderId]
  );
  res.json({ ok: true, data: rows });
}));

/**
 * Ai được ghi nhận thanh toán:
 * - driver: chỉ khi COD và chính là tài xế phụ trách đơn đó (thu tiền tận nơi)
 * - merchant_owner/merchant_staff/admin: chuyển khoản, QR, ghi tay
 */
router.post('/payments', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['order_id', 'method', 'amount']);
  const order = await db.findById('orders', req.body.order_id);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);

  if (req.ctx.role === 'driver') {
    const delivery = await db.queryOne('SELECT driver_id FROM deliveries WHERE order_id = $1', [req.body.order_id]);
    const driver = await db.queryOne('SELECT id FROM drivers WHERE user_id = $1', [req.ctx.userId]);
    if (!delivery || !driver || delivery.driver_id !== driver.id) {
      throw new ApiError('FORBIDDEN', 'Bạn không phụ trách đơn này', 403);
    }
  } else {
    await requireMerchantAccess(req.ctx, order.merchant_id);
  }

  // Đơn chuyển khoản tạo ra ở status 'pending_payment' (khác đơn COD vào thẳng 'placed' —
  // xem POST /orders) nên KHÔNG được orderOffer.offerOrderToMerchant() báo lúc tạo đơn. Ghi
  // nhớ trạng thái TRƯỚC khi ghi nhận thanh toán để biết đúng lúc nào record_payment (RPC, tự
  // gọi update_order_status chuyển pending_payment -> placed) vừa "mở khoá" đơn — chỉ báo cửa
  // hàng ở lần chuyển đó, tránh báo trùng "Đơn hàng mới!" mỗi lần ghi thêm thanh toán vào 1
  // đơn đã placed từ trước (vd tài xế thu COD, ghi thanh toán từng phần).
  const wasPendingPayment = order.status === 'pending_payment';
  const merchant = await db.queryOne('SELECT merchant_type FROM merchants WHERE id = $1', [order.merchant_id]);

  const payment = await db.callRpc('record_payment', {
    p_order_id: req.body.order_id,
    p_method: req.body.method,
    p_amount: req.body.amount,
    p_gateway: req.body.gateway || null,
    p_transaction_code: req.body.transaction_code || null,
    p_collected_by: req.ctx.userId,
    p_gateway_response: req.body.gateway_response || null
  });
  // Cửa hàng mua hộ không xác nhận/chuẩn bị gì cả (đơn không qua cửa hàng) — không báo "Đơn
  // hàng mới!", chỉ orderOffer.dispatchBuyOnBehalfOrder bên dưới lo chuyển thẳng cho tài xế.
  // Đơn giao ngay đặt trước còn đang "ngủ" (xem hofa-db/84_instant_scheduled_order.sql) cũng
  // không báo ngay dù vừa được xác nhận đã chuyển khoản — để orderOffer.sweepDueScheduledInstant
  // tự "nổ" đúng lúc như đã ngủ chờ từ đầu.
  const isSleepingScheduledInstant =
    order.sales_model === 'instant' && order.scheduled_for && !order.scheduled_activated_at;
  if (wasPendingPayment && merchant?.merchant_type !== 'buy_on_behalf' && !isSleepingScheduledInstant) {
    orderOffer.offerOrderToMerchant(req.body.order_id).catch((err) => {
      console.error('[orderOffer] Không báo được cửa hàng cho đơn chuyển khoản', req.body.order_id, err.message);
    });
  } else if (wasPendingPayment && isSleepingScheduledInstant) {
    // Vừa xác nhận chuyển khoản cho 1 đơn đặt trước còn đang "ngủ" — đây là lần ĐẦU TIÊN đủ
    // điều kiện báo cho cửa hàng xem trước (lúc POST /orders tạo đơn còn pending_payment nên
    // chưa báo), cùng nội dung với nhánh "Đơn đặt trước mới" ở POST /orders.
    push.resolveMerchantUserIds([order.merchant_id]).then((userIds) =>
      Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
        title: 'Đơn đặt trước mới',
        body: `${order.order_code} — hẹn giao ${new Date(order.scheduled_for).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })} (chỉ xem trước, chưa cần chuẩn bị)`,
        data: { type: 'order_upcoming', order_id: req.body.order_id }
      })))
    ).catch((err) => {
      console.error('[push] Không báo trước được cửa hàng cho đơn đặt trước sau khi xác nhận thanh toán', req.body.order_id, err.message);
    });
  }
  orderOffer.dispatchBuyOnBehalfOrder(req.body.order_id).catch((err) => {
    console.error('[orderOffer] Không tự chuyển được đơn mua hộ sau khi ghi nhận thanh toán', req.body.order_id, err.message);
  });
  res.status(201).json({ ok: true, data: payment });
}));

router.post('/payments/:id/refund', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin', 'merchant_owner', 'merchant_staff']);
  requireFields(req.body, ['amount']);
  if (req.ctx.role !== 'admin') {
    const payment = await db.findById('payments', req.params.id);
    if (!payment) throw new ApiError('NOT_FOUND', 'Không tìm thấy giao dịch', 404);
    const order = await db.findById('orders', payment.order_id);
    await requireMerchantAccess(req.ctx, order.merchant_id);
  }
  const refunded = await db.callRpc('refund_payment', {
    p_payment_id: req.params.id,
    p_amount: req.body.amount,
    p_note: req.body.note || null
  });
  res.json({ ok: true, data: refunded });
}));

/**
 * Webhook nhận callback từ cổng thanh toán (MoMo/VNPay/ZaloPay) — không có JWT vì
 * cổng thanh toán không đăng nhập được, thay vào đó kiểm 1 khoá bí mật riêng.
 *
 * QUAN TRỌNG: đây chỉ là khung sườn. Trước khi dùng thật, PHẢI thay đoạn kiểm tra bằng
 * đúng thuật toán ký số của từng cổng, nếu không ai cũng gọi được webhook này để giả
 * thanh toán thành công.
 */
router.post('/payments/webhook', asyncHandler(async (req, res) => {
  if (!config.paymentWebhookSecret || req.body.webhook_secret !== config.paymentWebhookSecret) {
    throw new ApiError('UNAUTHORIZED', 'Webhook secret sai hoặc chưa cấu hình PAYMENT_WEBHOOK_SECRET', 401);
  }
  requireFields(req.body, ['order_id', 'method', 'amount', 'transaction_code']);
  const payment = await db.callRpc('record_payment', {
    p_order_id: req.body.order_id,
    p_method: req.body.method,
    p_amount: req.body.amount,
    p_gateway: req.body.gateway || null,
    p_transaction_code: req.body.transaction_code,
    p_collected_by: null,
    p_gateway_response: req.body.raw || null
  });
  orderOffer.dispatchBuyOnBehalfOrder(req.body.order_id).catch((err) => {
    console.error('[orderOffer] Không tự chuyển được đơn mua hộ sau khi ghi nhận thanh toán', req.body.order_id, err.message);
  });
  res.json({ ok: true, data: payment });
}));

module.exports = router;
