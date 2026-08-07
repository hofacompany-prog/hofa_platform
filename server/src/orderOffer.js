const db = require('./db');
const push = require('./push');

const ACCEPT_WINDOW_SECONDS = 20; // kiểu Grab: quầy có 20s để trượt nhận/huỷ, khác với 25s bên tài xế

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
 * thẳng, không thì đặt accept_deadline và gửi push kèm màn trượt nhận đơn (giống Grab) cho
 * toàn bộ chủ + nhân viên cửa hàng.
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

  const deadline = new Date(Date.now() + ACCEPT_WINDOW_SECONDS * 1000).toISOString();
  await db.query('UPDATE orders SET accept_deadline = $1 WHERE id = $2', [deadline, orderId]);
  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn hàng mới!',
    body: `${order.order_code} · ${order.total_amount.toLocaleString('vi-VN')}đ — trượt để nhận trong ${ACCEPT_WINDOW_SECONDS}s`,
    data: {
      type: 'order_offer',
      order_id: orderId,
      accept_deadline: deadline,
      accept_window_seconds: ACCEPT_WINDOW_SECONDS
    }
  })));
}

/** Đơn quá hạn xác nhận (accept_deadline trôi qua mà vẫn 'placed') — TỰ ĐỘNG NHẬN, không
 * tự huỷ, vì mất đơn của khách chỉ vì cửa hàng chậm phản hồi 20s là trải nghiệm tệ hơn nhiều
 * so với việc cửa hàng phải tự xử lý 1 đơn họ lỡ không trượt xác nhận kịp. Cửa hàng vẫn có
 * thể chủ động bấm "Huỷ đơn" bất cứ lúc nào trong 20s đó nếu thật sự không nhận được. */
async function autoConfirmExpiredOrder(orderId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order || order.status !== 'placed') return null;
  const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [order.merchant_id]);

  const updated = await db.callRpc('update_order_status', {
    p_order_id: orderId,
    p_new_status: 'confirmed',
    p_changed_by: merchant?.owner_id || null,
    p_actor_role: 'merchant_owner',
    p_note: `Tự động xác nhận do quá ${ACCEPT_WINDOW_SECONDS}s cửa hàng không phản hồi`
  });

  const userIds = await getMerchantUserIds(order.merchant_id);
  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn đã tự động xác nhận',
    body: `${order.order_code} đã tự động xác nhận vì cửa hàng không phản hồi kịp — nhớ chuẩn bị đơn nhé!`,
    data: { type: 'order_auto_confirmed', order_id: orderId }
  })));
  await push.notifyCustomerOrderStatus(orderId, 'confirmed');
  return updated;
}

/** Quét các đơn đang chờ cửa hàng xác nhận nhưng đã quá accept_deadline — gọi định kỳ
 * (xem setInterval trong index.js). */
async function sweepExpiredOrderOffers() {
  const expired = await db.query(
    `SELECT id FROM orders WHERE status = 'placed' AND accept_deadline IS NOT NULL AND accept_deadline < now()`
  );
  const results = [];
  for (const row of expired) {
    results.push(await autoConfirmExpiredOrder(row.id));
  }
  return { swept: expired.length, results };
}

module.exports = { offerOrderToMerchant, autoConfirmExpiredOrder, sweepExpiredOrderOffers, ACCEPT_WINDOW_SECONDS };
