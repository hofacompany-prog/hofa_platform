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
    data: { type: 'order_offer', order_id: orderId },
    tag: `order-offer-${orderId}`
  })));
}

/** Nhắc LẠI cho cửa hàng mỗi ORDER_REMIND_INTERVAL_MS (xem index.js) các đơn CHƯA XÁC NHẬN
 * (status='placed', đã lộ cho cửa hàng — loại đơn mua hộ vì hệ thống tự xử lý không cần xác
 * nhận, loại đơn giao ngay đặt trước còn "ngủ" chưa tới lúc báo) — tới khi cửa hàng bấm xác
 * nhận (đơn rời khỏi 'placed') thì tự hết bị quét trúng, không cần cờ đánh dấu riêng. Gửi LẠI
 * qua resendPushToUser (không ghi thêm dòng notifications mới, tránh nhân bản hộp thư trong
 * app) — cùng tag với offerOrderToMerchant để thiết bị thay banner cũ, không xếp chồng, chỉ lặp
 * lại chuông/rung nhắc cửa hàng chứ không tạo thêm thông báo nào mới. */
async function remindUnconfirmedOrders() {
  const rows = await db.query(
    `SELECT o.id, o.merchant_id, o.order_code, o.total_amount
       FROM orders o
       JOIN merchants m ON m.id = o.merchant_id
      WHERE o.status = 'placed'
        AND m.merchant_type != 'buy_on_behalf'
        AND NOT (o.sales_model = 'instant' AND o.scheduled_for IS NOT NULL AND o.scheduled_activated_at IS NULL)`
  );
  if (!rows.length) return;
  const merchantIds = [...new Set(rows.map((r) => r.merchant_id))];
  const userIdsByMerchant = Object.fromEntries(
    await Promise.all(merchantIds.map(async (mid) => [mid, await getMerchantUserIds(mid)]))
  );
  for (const row of rows) {
    const userIds = userIdsByMerchant[row.merchant_id] || [];
    await Promise.all(userIds.map((uid) => push.resendPushToUser(uid, {
      title: 'Đơn hàng mới!',
      body: `${row.order_code} · ${Number(row.total_amount).toLocaleString('vi-VN')}đ — trượt để nhận đơn`,
      data: { type: 'order_offer', order_id: row.id },
      tag: `order-offer-${row.id}`
    }).catch((err) => {
      console.error('[remind-unconfirmed-orders] Không gửi lại được', row.id, err.message);
    })));
  }
}

/** Quét định kỳ (xem index.js) các đơn đặt trước ĐÃ được cửa hàng xác nhận sớm (status=
 * 'confirmed', xem offerOrderToMerchant + POST /orders — không còn "ngủ" chờ tới gần giờ giao
 * nữa, cửa hàng xác nhận ngay từ lúc đặt) và giờ đã tới ngưỡng bắt đầu chuẩn bị — còn đúng
 * default_prep_minutes phút nữa là tới scheduled_for — tự chuyển sang 'preparing', không cần
 * cửa hàng bấm "Đã làm xong" ở bước này (họ đã xác nhận từ trước, phần còn lại xử lý như đơn
 * bình thường: bấm "Đã làm xong" khi bếp xong việc để chuyển tiếp sang ready_for_pickup).
 * preorder_notified_at dùng làm cờ chống chạy trùng (đánh dấu NGAY sau khi sweep này xử lý). */
async function sweepDuePreorders() {
  const due = await db.query(
    `SELECT id FROM orders
      WHERE sales_model = 'scheduled' AND status = 'confirmed' AND preorder_notified_at IS NULL
        AND scheduled_for - (COALESCE(default_prep_minutes, 15) || ' minutes')::interval <= now()`
  );
  for (const row of due) {
    await db.updateById('orders', row.id, { preorder_notified_at: new Date().toISOString() });
    await db.callRpc('update_order_status', {
      p_order_id: row.id,
      p_new_status: 'preparing',
      p_changed_by: null,
      p_actor_role: 'admin',
      p_note: 'Tự động — tới giờ chuẩn bị đơn đặt trước',
      p_force: true
    });
    push.notifyCustomerOrderStatus(row.id, 'preparing').catch((err) => {
      console.error('[sweep-due-preorders] Không báo được cho khách', row.id, err.message);
    });
  }
}

/** Quét định kỳ (xem index.js) các đơn GIAO NGAY đặt trước ở màn thanh toán (sales_model=
 * 'instant', scheduled_for khác NULL) còn đang "ngủ" (scheduled_activated_at NULL, chưa báo
 * cửa hàng — xem hofa-db/84_instant_scheduled_order.sql + POST /orders) và giờ đã tới ngưỡng
 * còn đúng default_prep_minutes phút nữa là tới scheduled_for — "nổ" cho cửa hàng: tính lại
 * confirm_sweep_deadline theo cấu hình HIỆN TẠI (chi nhánh có thể đổi auto_accept_orders từ lúc
 * đặt đơn tới giờ) rồi báo y hệt 1 đơn tức thời vừa đặt (offerOrderToMerchant). */
async function sweepDueScheduledInstant() {
  const due = await db.query(
    `SELECT id, branch_id FROM orders
      WHERE sales_model = 'instant' AND status = 'placed'
        AND scheduled_for IS NOT NULL AND scheduled_activated_at IS NULL
        AND scheduled_for - (COALESCE(default_prep_minutes, 15) || ' minutes')::interval <= now()`
  );
  if (!due.length) return;
  const settings = await db.queryOne(
    'SELECT confirm_sweep_seconds, manual_confirm_sweep_seconds FROM auto_accept_settings ORDER BY updated_at DESC LIMIT 1'
  );
  for (const row of due) {
    const branch = await db.queryOne('SELECT auto_accept_orders FROM branches WHERE id = $1', [row.branch_id]);
    const seconds = (branch?.auto_accept_orders ? settings?.confirm_sweep_seconds : settings?.manual_confirm_sweep_seconds) ?? 10;
    await db.query(
      `UPDATE orders SET scheduled_activated_at = now(), confirm_sweep_deadline = now() + ($2 || ' seconds')::interval WHERE id = $1`,
      [row.id, seconds]
    );
    offerOrderToMerchant(row.id).catch((err) => {
      console.error('[sweep-due-scheduled-instant] Không báo được cửa hàng cho đơn', row.id, err.message);
    });
  }
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

  // Khách chọn 1 trong 2 ở checkout: tự chọn tài xế (selected_driver_id có giá trị) hoặc để hệ
  // thống tự tìm gần nhất (bỏ trống) — xem checkout_screen.dart app khách.
  const result = order.selected_driver_id
    ? await dispatchToSelectedDriver(orderId)
    : await dispatch.offerToNearestDriver(orderId);
  if (!result) {
    console.warn('[orderOffer] Đơn mua hộ', orderId, 'chưa gán được tài xế — chờ khách chọn hoặc admin can thiệp.');
  }
}

module.exports = {
  offerOrderToMerchant,
  dispatchBuyOnBehalfOrder,
  dispatchToSelectedDriver,
  sweepDuePreorders,
  sweepDueScheduledInstant,
  remindUnconfirmedOrders
};
