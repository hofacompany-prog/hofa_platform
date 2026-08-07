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
 * Đơn mới vừa tạo (status='placed') — chi nhánh bật auto_accept_orders thì tự xác nhận
 * thẳng, không thì gửi push kèm màn trượt nhận đơn (giống Grab) cho toàn bộ chủ + nhân
 * viên cửa hàng; cửa hàng tự bấm xác nhận, không có thời hạn ép buộc hệ thống tự làm thay.
 */
async function offerOrderToMerchant(orderId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order || order.status !== 'placed') return;
  const branch = await db.queryOne('SELECT * FROM branches WHERE id = $1', [order.branch_id]);
  const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [order.merchant_id]);
  if (!branch || !merchant) return;
  const userIds = await getMerchantUserIds(order.merchant_id);

  if (branch.auto_accept_orders) {
    const updated = await db.callRpc('update_order_status', {
      p_order_id: orderId,
      p_new_status: 'confirmed',
      p_changed_by: merchant.owner_id,
      p_actor_role: 'merchant_owner',
      p_note: 'Tự động xác nhận (chi nhánh bật "Tự động nhận đơn")'
    });
    await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
      title: 'Đơn mới đã tự động xác nhận',
      body: `${order.order_code} · ${order.total_amount.toLocaleString('vi-VN')}đ`,
      data: { type: 'order_auto_confirmed', order_id: orderId }
    })));
    await push.notifyCustomerOrderStatus(orderId, 'confirmed');
    return updated;
  }

  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn hàng mới!',
    body: `${order.order_code} · ${order.total_amount.toLocaleString('vi-VN')}đ — trượt để nhận đơn`,
    data: { type: 'order_offer', order_id: orderId }
  })));
}

module.exports = { offerOrderToMerchant };
