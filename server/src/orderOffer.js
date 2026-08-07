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
 * Đơn mới vừa tạo (status='placed') — luôn hiện màn nhận đơn (không còn nhánh tự xác nhận
 * ngay không hiện màn hình). Chi nhánh bật "Tự động nhận đơn" thì có 1 hạn dựa trên
 * auto_accept_default_minutes (trần theo số món, xem merchants.auto_accept_prep_*) — hết hạn
 * mà cửa hàng chưa trượt, hệ thống tự xác nhận hộ (autoConfirmExpiredOrder). Tắt thì hạn cố
 * định manual_confirm_window_minutes — hết hạn thì đơn tự huỷ và chi nhánh tự đóng cửa
 * (autoCancelExpiredOrder), vì cửa hàng im lặng quá lâu coi như đang không theo dõi đơn.
 */
async function offerOrderToMerchant(orderId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order || order.status !== 'placed') return;
  const branch = await db.queryOne('SELECT * FROM branches WHERE id = $1', [order.branch_id]);
  const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [order.merchant_id]);
  const settings = await db.queryOne('SELECT * FROM auto_accept_settings ORDER BY updated_at DESC LIMIT 1');
  if (!branch || !merchant || !settings) return;
  const userIds = await getMerchantUserIds(order.merchant_id);

  let minutes;
  if (branch.auto_accept_orders) {
    const itemCountRow = await db.queryOne('SELECT COUNT(*)::int AS c FROM order_items WHERE order_id = $1', [orderId]);
    const itemCount = itemCountRow?.c || 1;
    const tierCap = Math.min(
      settings.auto_accept_prep_base_minutes + settings.auto_accept_prep_increment_minutes * Math.max(0, itemCount - 1),
      settings.auto_accept_prep_max_minutes
    );
    minutes = Math.min(settings.auto_accept_default_minutes, tierCap);
  } else {
    minutes = settings.manual_confirm_window_minutes;
  }

  const deadline = new Date(Date.now() + minutes * 60_000).toISOString();
  await db.query('UPDATE orders SET accept_deadline = $1 WHERE id = $2', [deadline, orderId]);
  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn hàng mới!',
    body: `${order.order_code} · ${order.total_amount.toLocaleString('vi-VN')}đ — trượt để nhận đơn`,
    data: { type: 'order_offer', order_id: orderId, accept_deadline: deadline, auto_accept: branch.auto_accept_orders }
  })));
}

/** Đơn quá hạn xác nhận, chi nhánh đang bật "Tự động nhận đơn" — TỰ ĐỘNG NHẬN hộ cửa hàng. */
async function autoConfirmExpiredOrder(orderId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order || order.status !== 'placed') return null;
  const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [order.merchant_id]);

  const updated = await db.callRpc('update_order_status', {
    p_order_id: orderId,
    p_new_status: 'confirmed',
    p_changed_by: merchant?.owner_id || null,
    p_actor_role: 'merchant_owner',
    p_note: 'Tự động xác nhận (chi nhánh bật "Tự động nhận đơn")'
  });
  await db.query('UPDATE orders SET accept_deadline = NULL WHERE id = $1', [orderId]);

  const userIds = await getMerchantUserIds(order.merchant_id);
  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn đã tự động xác nhận',
    body: `${order.order_code} đã tự động xác nhận vì cửa hàng không phản hồi kịp — nhớ chuẩn bị đơn nhé!`,
    data: { type: 'order_auto_confirmed', order_id: orderId }
  })));
  await push.notifyCustomerOrderStatus(orderId, 'confirmed');
  return updated;
}

/** Đơn quá hạn xác nhận, chi nhánh đang TẮT "Tự động nhận đơn" — coi như cửa hàng không theo
 * dõi đơn, tự HUỶ đơn và chuyển chi nhánh sang tạm đóng cửa để không nhận thêm đơn mới cho
 * tới khi cửa hàng tự mở lại. */
async function autoCancelExpiredOrder(orderId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order || order.status !== 'placed') return null;

  const updated = await db.callRpc('update_order_status', {
    p_order_id: orderId,
    p_new_status: 'cancelled',
    p_changed_by: null,
    p_actor_role: null,
    p_note: 'Tự động huỷ do cửa hàng không phản hồi trong thời gian chờ xác nhận'
  });
  await db.query('UPDATE orders SET accept_deadline = NULL WHERE id = $1', [orderId]);
  await db.query('UPDATE branches SET is_open = false WHERE id = $1', [order.branch_id]);

  const userIds = await getMerchantUserIds(order.merchant_id);
  await Promise.all(userIds.map((uid) => push.sendPushToUser(uid, {
    title: 'Đơn tự huỷ — cửa hàng đã tạm đóng',
    body: `${order.order_code} đã tự huỷ vì không có phản hồi kịp thời. Cửa hàng đã tự chuyển sang "Tạm đóng cửa" — vào Trang chủ để mở lại khi sẵn sàng nhận đơn.`,
    data: { type: 'order_auto_cancelled', order_id: orderId }
  })));
  await push.notifyCustomerOrderStatus(orderId, 'cancelled');
  return updated;
}

/** Quét các đơn đang chờ cửa hàng xác nhận nhưng đã quá accept_deadline — gọi định kỳ
 * (xem setInterval trong index.js). */
async function sweepExpiredOrderOffers() {
  const expired = await db.query(
    `SELECT o.id, b.auto_accept_orders
       FROM orders o
       JOIN branches b ON b.id = o.branch_id
      WHERE o.status = 'placed' AND o.accept_deadline IS NOT NULL AND o.accept_deadline < now()`
  );
  const results = [];
  for (const row of expired) {
    results.push(row.auto_accept_orders
      ? await autoConfirmExpiredOrder(row.id)
      : await autoCancelExpiredOrder(row.id));
  }
  return { swept: expired.length, results };
}

module.exports = { offerOrderToMerchant, sweepExpiredOrderOffers };
