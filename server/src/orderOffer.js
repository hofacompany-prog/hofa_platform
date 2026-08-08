const db = require('./db');
const push = require('./push');
const dispatch = require('./dispatch');

/** Tất cả user quản lý 1 cửa hàng (chủ + nhân viên) — để gửi push đơn mới cho tất cả, ai xem trước thì bấm trước. */
async function getMerchantUserIds(merchantId) {
  const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [merchantId]);
  const staff = await db.query('SELECT user_id FROM merchant_staff WHERE merchant_id = $1', [merchantId]);
  const ids = new Set(staff.map((s) => s.user_id));
  if (merchant?.owner_id) ids.add(merchant.owner_id);
  return [...ids];
}

/**
 * Đơn mới vừa tạo (status='placed') — báo cho cửa hàng bằng push, mở thẳng màn chi tiết đơn
 * (order_detail_screen.dart, store app). Không còn hạn tự xác nhận/tự huỷ ở đây nữa — màn chi
 * tiết đơn tự có thanh trượt xác nhận với dải màu chạy confirm_sweep_seconds giây (thuần phía
 * client, xem auto_accept_settings.confirm_sweep_seconds), hết giờ tự chốt luôn không cần
 * server quét định kỳ như trước.
 */
async function offerOrderToMerchant(orderId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order || order.status !== 'placed') return;
  const userIds = await getMerchantUserIds(order.merchant_id);

  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn hàng mới!',
    body: `${order.order_code} · ${order.total_amount.toLocaleString('vi-VN')}đ — trượt để nhận đơn`,
    data: { type: 'order_offer', order_id: orderId }
  })));
}

/**
 * Gán đơn mua hộ cho ĐÚNG tài xế khách đã chọn (orders.selected_driver_id) — dùng chung cho lần
 * gán đầu tiên (ngay sau khi thanh toán, xem dispatchBuyOnBehalfOrder) LẪN mỗi lần khách chọn
 * lại sau khi tài xế trước từ chối/hết hạn (POST /orders/:id/select-driver). Tài xế đã chọn
 * không còn online thì báo lại NGAY cho khách tự chọn người khác — không tự tìm người thay
 * khách, đúng yêu cầu để khách chọn được tài xế ưng ý chứ không phải hệ thống tự quyết.
 */
async function dispatchToSelectedDriver(orderId) {
  const order = await db.queryOne('SELECT selected_driver_id FROM orders WHERE id = $1', [orderId]);
  if (!order?.selected_driver_id) return null;
  const result = await dispatch.offerToSpecificDriver(orderId, order.selected_driver_id);
  if (!result) {
    await push.notifyCustomerRepickDriver(orderId, 'Tài xế bạn chọn hiện không còn online');
  }
  return result;
}

/**
 * Đơn ở cửa hàng mua hộ (merchant_type='buy_on_behalf') — cửa hàng không chuẩn bị/xác nhận gì
 * cả, tài xế mới là người trực tiếp đi mua, nên bỏ hẳn 2 bước 'confirmed'/'preparing' (không có
 * ý nghĩa gì với đơn này) và chuyển thẳng sang 'ready_for_pickup' rồi gọi dispatch ngay khi
 * thanh toán được ghi nhận (record_payment RPC chuyển pending_payment -> placed, xem
 * routes/payments.js gọi hàm này ngay sau đó). Không throw — lỗi ở đây không được làm hỏng
 * luồng ghi nhận thanh toán đã thành công.
 */
async function dispatchBuyOnBehalfOrder(orderId) {
  const order = await db.queryOne(
    `SELECT o.status, o.selected_driver_id, m.merchant_type
       FROM orders o JOIN merchants m ON m.id = o.merchant_id
      WHERE o.id = $1`,
    [orderId]
  );
  if (!order || order.merchant_type !== 'buy_on_behalf' || order.status !== 'placed') return;

  await db.callRpc('update_order_status', {
    p_order_id: orderId,
    p_new_status: 'ready_for_pickup',
    p_changed_by: null,
    p_actor_role: 'admin',
    p_note: 'Tự động — cửa hàng mua hộ',
    p_force: true
  });
  push.notifyCustomerOrderStatus(orderId, 'ready_for_pickup').catch(() => {});

  // selected_driver_id lẽ ra luôn có (bắt buộc chọn ở checkout) — fallback tự tìm gần nhất chỉ
  // để không kẹt đơn nếu vì lý do gì đó (đơn cũ trước khi có tính năng này...) chưa có lựa chọn.
  const result = order.selected_driver_id
    ? await dispatchToSelectedDriver(orderId)
    : await dispatch.offerToNearestDriver(orderId);
  if (!result) {
    console.warn('[orderOffer] Đơn mua hộ', orderId, 'chưa gán được tài xế — chờ khách chọn hoặc admin can thiệp.');
  }
}

module.exports = { offerOrderToMerchant, dispatchBuyOnBehalfOrder, dispatchToSelectedDriver };
