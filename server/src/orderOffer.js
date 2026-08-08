const db = require('./db');
const push = require('./push');

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

module.exports = { offerOrderToMerchant };
