const config = require('./config');
const db = require('./db');

let app = null;
let initTried = false;

/** Khởi tạo firebase-admin từ JSON service account trong env — chỉ 1 lần, lười tải
 * (server vẫn phải boot được khi chưa cấu hình Firebase, chỉ việc gửi push bị bỏ qua). */
function getApp() {
  if (initTried) return app;
  initTried = true;
  if (!config.firebaseServiceAccountJson) {
    console.warn('[push] FIREBASE_SERVICE_ACCOUNT_JSON chưa cấu hình — bỏ qua gửi push notification.');
    return null;
  }
  try {
    const admin = require('firebase-admin');
    const credentials = JSON.parse(config.firebaseServiceAccountJson);
    app = admin.apps.length ? admin.app() : admin.initializeApp({ credential: admin.credential.cert(credentials) });
    return app;
  } catch (err) {
    console.error('[push] Không khởi tạo được firebase-admin:', err.message);
    return null;
  }
}

/** FCM chỉ nhận tối đa 500 token/lần gọi sendEachForMulticast — chia nhỏ danh sách. */
const FCM_BATCH_SIZE = 500;

/**
 * Ghi lại 1 dòng vào hộp thư thông báo (bảng notifications) cho MỖI user trong [userIds] —
 * độc lập hoàn toàn với việc gửi push qua FCM có thành công hay không, vì mục đích của hộp
 * thư trong app là user vẫn xem lại được kể cả khi không có push_token/chưa cấp quyền
 * thông báo trình duyệt/thiết bị. Không throw — lỗi ghi không được làm hỏng luồng gửi push.
 * Trả về mảng rỗng nếu lỗi/không có ai để ghi; trả về đúng các dòng vừa tạo (kèm id) khi
 * thành công — sendPushToUser dùng id này để nhét vào data payload FCM (notification_id),
 * cho phép app đánh dấu đã đọc thẳng khi bấm push mà không cần gọi API tra cứu.
 */
async function saveNotifications(userIds, { title, body, data = {}, category = 'system', sourceNotificationId = null }) {
  const ids = [...new Set(userIds)].filter(Boolean);
  if (!ids.length) return [];
  try {
    return await db.insertRows(
      'notifications',
      ids.map((userId) => ({ user_id: userId, title, body, data, category, source_notification_id: sourceNotificationId }))
    );
  } catch (err) {
    console.error('[notifications] Không ghi được hộp thư:', err.message);
    return [];
  }
}

/**
 * Gửi thẳng tới danh sách token (không tra cứu user_devices) — dùng chung cho cả push
 * theo từng user (sendPushToUser) lẫn gửi hàng loạt (sendBroadcastToCustomers).
 * Không throw — lỗi gửi push không bao giờ được làm hỏng luồng gọi nó.
 */
/**
 * [tag] (vd 'order-offer-<id>') để lần gửi SAU với CÙNG tag THAY THẾ banner cũ trên thiết bị
 * thay vì xếp chồng thêm — dùng cho push nhắc lại nhiều lần cùng 1 sự kiện (xem
 * resendPushToUser/orderOffer.remindUnconfirmedOrders). renotify:true bắt buộc kèm tag bên
 * webpush, nếu không trình duyệt coi như "cùng thông báo, đã thấy rồi" và ÂM THẦM thay thế,
 * không rung/kêu lại — mất tác dụng nhắc.
 */
async function sendToTokens(tokens, { title, body, data = {}, badge = false, tag = null }) {
  const firebaseApp = getApp();
  if (!firebaseApp || !tokens.length) return { sent: 0 };

  const admin = require('firebase-admin');
  // badge: cộng thêm số vào biểu tượng PWA đã "Thêm vào màn hình chính" (Badging API) — service
  // worker phía client đọc cờ này, xem web/firebase-messaging-sw.js của customer/driver/store.
  const stringData = Object.fromEntries(
    Object.entries({ ...data, badge: String(!!badge) }).map(([k, v]) => [k, String(v)])
  );
  let sent = 0;
  for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
    const batch = tokens.slice(i, i + FCM_BATCH_SIZE);
    try {
      const result = await admin.messaging(firebaseApp).sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data: stringData,
        android: { priority: 'high', ...(tag ? { notification: { tag } } : {}) },
        apns: { payload: { aps: { sound: 'default' } } },
        // Payload có cả notification lẫn data → firebase-messaging-compat.js phía web TỰ hiện
        // thông báo (đúng field notification này), independent với onBackgroundMessage —
        // web/firebase-messaging-sw.js của 3 app không được tự gọi showNotification() thêm
        // lần nữa nếu không sẽ hiện lặp 2 lần (bug đã xác nhận qua log server chỉ gửi 1 lần
        // nhưng máy hiện 2 banner). webpush.notification.icon để browser dùng đúng icon
        // thương hiệu thay vì icon mặc định khi Firebase tự hiển thị.
        webpush: {
          notification: {
            icon: '/icons/Icon-192.png',
            ...(tag ? { tag, renotify: true } : {})
          }
        }
      });
      sent += result.successCount;
    } catch (err) {
      console.error('[push] Gửi push thất bại:', err.message);
    }
  }
  return { sent };
}

/**
 * Gửi push notification cho MỌI thiết bị đã đăng ký (bảng user_devices) của 1 user.
 * data phải toàn giá trị string (giới hạn của FCM data payload). badge/category mặc định
 * true/'order' vì mọi nơi gọi hàm này đều là thông báo liên quan đơn hàng/chuyến giao
 * (orderOffer.js, dispatch.js, notifyCustomerOrderStatus).
 *
 * Chỉ gửi cho ĐÚNG 1 user (khác sendBroadcastToRoles/sendToUserIds gửi nhiều user cùng lúc
 * với 1 payload chung) nên nhét thẳng được id dòng notifications vừa tạo vào data —
 * notification_id — để app đánh dấu đã đọc ngay khi bấm push, không cần thêm API tra cứu.
 */
async function sendPushToUser(userId, { title, body, data = {}, badge = true, category = 'order', tag = null }) {
  const devices = await db.query(
    'SELECT DISTINCT push_token FROM user_devices WHERE user_id = $1 AND push_token IS NOT NULL',
    [userId]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  const [saved] = await saveNotifications([userId], { title, body, data, category });
  const fcmData = { ...data, category, ...(saved ? { notification_id: saved.id } : {}) };
  return sendToTokens(tokens, { title, body, data: fcmData, badge, tag });
}

/**
 * Gửi LẠI push cho 1 user — KHÔNG ghi thêm dòng notifications mới (khác sendPushToUser), chỉ để
 * "nhắc lại" cùng 1 thông báo đã có sẵn trong hộp thư (vd đơn hàng mới chưa xác nhận, xem
 * orderOffer.remindUnconfirmedOrders) — tránh nhân bản hộp thư trong app dù push tới máy nhiều
 * lần. [tag] nên trùng với lần gửi gốc (sendPushToUser) để thiết bị thay banner cũ, không xếp
 * chồng — xem sendToTokens.
 */
async function resendPushToUser(userId, { title, body, data = {}, badge = true, category = 'order', tag = null }) {
  const devices = await db.query(
    'SELECT DISTINCT push_token FROM user_devices WHERE user_id = $1 AND push_token IS NOT NULL',
    [userId]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  return sendToTokens(tokens, { title, body, data: { ...data, category }, badge, tag });
}

/**
 * Gửi push cho TOÀN BỘ user có 1 trong các role chỉ định đang có thiết bị đăng ký nhận
 * thông báo — dùng cho màn "Thông báo" ở web admin, target=all. [roles] vd ['customer'],
 * ['driver'], ['merchant_owner','merchant_staff']. Trả về { sent, total }.
 */
async function sendBroadcastToRoles(roles, { title, body, badge = false, screen = null, category = 'system', sourceNotificationId = null }) {
  const data = { type: 'admin_broadcast', category, ...(screen ? { screen } : {}) };

  // Toàn bộ user thuộc nhóm role — KHÔNG lọc theo có push_token hay không, vì hộp thư trong
  // app phải thấy được thông báo này kể cả khi thiết bị chưa đăng ký/chưa cấp quyền push.
  const users = await db.query(
    `SELECT id FROM users WHERE role::text = ANY($1::text[]) AND deleted_at IS NULL`,
    [roles]
  );
  await saveNotifications(users.map((u) => u.id), { title, body, data, category, sourceNotificationId });

  const devices = await db.query(
    `SELECT DISTINCT d.push_token
       FROM user_devices d
       JOIN users u ON u.id = d.user_id
      WHERE u.role::text = ANY($1::text[]) AND u.deleted_at IS NULL AND d.push_token IS NOT NULL`,
    [roles]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  // screen: route nội bộ app nhận sẽ mở khi bấm vào thông báo — bỏ hẳn key này nếu không
  // chỉ định, tránh gửi chuỗi "null" (mọi giá trị data đều bị ép thành string cho FCM).
  const { sent } = await sendToTokens(tokens, { title, body, data, badge });
  return { sent, total: tokens.length };
}

/** Chủ + nhân viên của 1 danh sách cửa hàng — dùng để suy ra người nhận thật khi admin
 * chọn "cửa hàng cụ thể" ở màn Thông báo (chọn cửa hàng, không phải chọn từng nhân viên). */
async function resolveMerchantUserIds(merchantIds) {
  if (!merchantIds.length) return [];
  const rows = await db.query(
    `SELECT owner_id AS user_id FROM merchants WHERE id = ANY($1::uuid[])
     UNION
     SELECT user_id FROM merchant_staff WHERE merchant_id = ANY($1::uuid[])`,
    [merchantIds]
  );
  return rows.map((r) => r.user_id);
}

/**
 * Gửi push cho 1 danh sách user_id cụ thể (admin tự chọn ở màn Thông báo) — dùng cho
 * target = specific_users. Trả về { sent, total } để ghi vào admin_notifications.
 */
async function sendToUserIds(userIds, { title, body, badge = false, screen = null, category = 'system', sourceNotificationId = null }) {
  if (!userIds.length) return { sent: 0, total: 0 };
  const data = { type: 'admin_broadcast', category, ...(screen ? { screen } : {}) };
  await saveNotifications(userIds, { title, body, data, category, sourceNotificationId });

  const devices = await db.query(
    'SELECT DISTINCT push_token FROM user_devices WHERE user_id = ANY($1::uuid[]) AND push_token IS NOT NULL',
    [userIds]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  const { sent } = await sendToTokens(tokens, { title, body, data, badge });
  return { sent, total: tokens.length };
}

/** Nội dung push cho khách theo từng mốc trạng thái đơn — chỉ những mốc khách thực
 * sự cần biết (không báo 'preparing'/'assigned', khách không quan tâm mấy bước nội bộ đó). */
const CUSTOMER_STATUS_MESSAGES = {
  confirmed: (code) => ({ title: 'Đơn hàng đã được xác nhận', body: `${code} · Cửa hàng đang chuẩn bị đơn cho bạn` }),
  preparing: (code) => ({ title: 'Cửa hàng bắt đầu chuẩn bị đơn của bạn', body: `${code} · Đã tới giờ làm đơn đặt trước của bạn` }),
  ready_for_pickup: (code) => ({ title: 'Đơn hàng đã chuẩn bị xong', body: `${code} · Đang chờ tài xế đến lấy` }),
  picked_up: (code) => ({ title: 'Tài xế đã lấy đơn hàng', body: `${code} · Chuẩn bị lên đường giao đến bạn` }),
  delivering: (code) => ({ title: 'Tài xế đang trên đường giao đến bạn', body: `${code} · Sắp tới nơi rồi!` }),
  delivered: (code) => ({ title: 'Giao hàng thành công', body: `${code} · Cảm ơn bạn đã đặt hàng qua HOFA` }),
  cancelled: (code) => ({ title: 'Đơn hàng đã bị huỷ', body: `${code}` })
};

/** Báo cho khách mỗi khi đơn của họ đổi sang 1 mốc trạng thái đáng chú ý — gọi từ mọi
 * nơi order status/delivery status đổi (PATCH /orders/:id/status, PATCH /deliveries/:id/status,
 * orderOffer.js). Không throw, im lặng bỏ qua nếu status không nằm trong danh sách trên. */
async function notifyCustomerOrderStatus(orderId, status) {
  const compose = CUSTOMER_STATUS_MESSAGES[status];
  if (!compose) return;
  const order = await db.queryOne('SELECT customer_id, order_code FROM orders WHERE id = $1', [orderId]);
  if (!order) return;
  const { title, body } = compose(order.order_code);
  await sendPushToUser(order.customer_id, {
    title,
    body,
    data: { type: 'order_status_changed', order_id: orderId, status }
  });
}

/** Đơn mua hộ: tài xế khách chọn từ chối/hết hạn/không còn online — báo khách tự chọn tài xế
 * khác (xem dispatch.repickNeeded, orderOffer.dispatchToSelectedDriver). Không dùng
 * CUSTOMER_STATUS_MESSAGES/order_status_changed vì order.status KHÔNG đổi lúc này (vẫn đứng ở
 * ready_for_pickup) — cần type riêng để app khách biết mở đúng màn "Chọn tài xế". */
async function notifyCustomerRepickDriver(orderId, reason) {
  const order = await db.queryOne('SELECT customer_id, order_code FROM orders WHERE id = $1', [orderId]);
  if (!order) return;
  await sendPushToUser(order.customer_id, {
    title: 'Cần chọn tài xế khác',
    body: `${order.order_code} · ${reason} — chọn tài xế khác để đơn tiếp tục nhé!`,
    data: { type: 'buy_on_behalf_repick', order_id: orderId }
  });
}

/** Hồ sơ tài xế bị admin từ chối — báo kèm lý do, tài xế sửa/nộp lại hồ sơ ở PATCH /drivers/me
 * để đưa hồ sơ về lại "đang chờ xét duyệt" (xem routes/drivers.js). [driverId] là drivers.id,
 * không phải user_id — cần tra ngược qua user_id mới gửi push được. */
async function notifyDriverRejected(driverId, reason) {
  const driver = await db.queryOne('SELECT user_id FROM drivers WHERE id = $1', [driverId]);
  if (!driver) return;
  await sendPushToUser(driver.user_id, {
    title: 'Hồ sơ tài xế bị từ chối',
    body: `Lý do: ${reason} — sửa lại hồ sơ và nộp lại để được xét duyệt tiếp.`,
    data: { type: 'driver_verification_rejected' }
  });
}

const DRIVER_WALLET_MESSAGES = {
  deposit_confirmed: (amount) => ({
    title: 'Nạp tiền thành công',
    body: `Ví đã được cộng ${amount.toLocaleString('vi-VN')}đ.`
  }),
  withdrawal_confirmed: (amount) => ({
    title: 'Rút tiền thành công',
    body: `Đã chuyển khoản ${amount.toLocaleString('vi-VN')}đ vào tài khoản ngân hàng của bạn.`
  }),
  withdrawal_rejected: (amount, reason) => ({
    title: 'Yêu cầu rút tiền bị từ chối',
    body: `Đã hoàn lại ${amount.toLocaleString('vi-VN')}đ vào ví.${reason ? ` Lý do: ${reason}` : ''}`
  }),
  cod_settlement_confirmed: (amount) => ({
    title: 'Đã xác nhận nộp COD',
    body: `Ví COD đã trừ ${amount.toLocaleString('vi-VN')}đ.`
  }),
  cod_settlement_rejected: (amount, reason) => ({
    title: 'Yêu cầu nộp COD bị từ chối',
    body: `Chưa trừ ${amount.toLocaleString('vi-VN')}đ khỏi ví COD.${reason ? ` Lý do: ${reason}` : ''}`
  }),
  admin_adjustment: (amount, reason) => ({
    title: amount >= 0 ? 'Ví được cộng thêm' : 'Ví bị trừ',
    body: `${amount >= 0 ? '+' : ''}${amount.toLocaleString('vi-VN')}đ.${reason ? ` Lý do: ${reason}` : ''}`
  })
};

/** Kết quả duyệt nạp/rút ví — [driverId] là drivers.id, tra ngược user_id giống
 * notifyDriverRejected. [kind] khớp key của DRIVER_WALLET_MESSAGES. */
async function notifyDriverWallet(driverId, kind, amount, reason) {
  const compose = DRIVER_WALLET_MESSAGES[kind];
  if (!compose) return;
  const driver = await db.queryOne('SELECT user_id FROM drivers WHERE id = $1', [driverId]);
  if (!driver) return;
  const { title, body } = compose(amount, reason);
  await sendPushToUser(driver.user_id, { title, body, data: { type: 'driver_wallet_update', kind } });
}

const MERCHANT_WALLET_MESSAGES = {
  withdrawal_confirmed: (amount) => ({
    title: 'Rút tiền thành công',
    body: `Đã chuyển khoản ${amount.toLocaleString('vi-VN')}đ vào tài khoản ngân hàng cửa hàng.`
  }),
  withdrawal_rejected: (amount, reason) => ({
    title: 'Yêu cầu rút tiền bị từ chối',
    body: `Đã hoàn lại ${amount.toLocaleString('vi-VN')}đ vào ví.${reason ? ` Lý do: ${reason}` : ''}`
  }),
  admin_adjustment: (amount, reason) => ({
    title: amount >= 0 ? 'Ví được cộng thêm' : 'Ví bị trừ',
    body: `${amount >= 0 ? '+' : ''}${amount.toLocaleString('vi-VN')}đ.${reason ? ` Lý do: ${reason}` : ''}`
  })
};

/** Kết quả duyệt rút ví cửa hàng — báo cho cả chủ lẫn nhân viên (resolveMerchantUserIds, giống
 * cách push đơn mới đã làm), khác notifyDriverWallet (chỉ 1 user) vì 1 cửa hàng có thể nhiều
 * người quản lý cùng xem ví. [kind] khớp key của MERCHANT_WALLET_MESSAGES. */
async function notifyMerchantWallet(merchantId, kind, amount, reason) {
  const compose = MERCHANT_WALLET_MESSAGES[kind];
  if (!compose) return;
  const userIds = await resolveMerchantUserIds([merchantId]);
  if (!userIds.length) return;
  const { title, body } = compose(amount, reason);
  await sendToUserIds(userIds, { title, body, category: 'system' });
}

/**
 * Báo cho MỌI admin (role='admin') mỗi khi có việc cần admin xử lý tay — đơn chuyển khoản
 * cần xác nhận đã nhận tiền, tài xế/cửa hàng yêu cầu nạp/rút ví (xem payment_settings_screen.dart
 * ở web admin, 4 tab tương ứng). Cùng cấu trúc data với admin_broadcast (type + screen) để
 * push_service.dart phía admin dùng lại được đúng cách điều hướng "bấm thông báo mở đúng màn".
 * Không dùng sendBroadcastToRoles (hardcode type='admin_broadcast', dành cho admin GỬI đi) vì
 * đây là thông báo HỆ THỐNG gửi ĐẾN admin — cần type riêng (admin_alert) để phân biệt.
 */
async function notifyAdmins({ title, body, kind, screen = '/finance?tab=3' }) {
  const data = { type: 'admin_alert', kind, screen };
  const admins = await db.query(`SELECT id FROM users WHERE role = 'admin' AND deleted_at IS NULL`);
  const adminIds = admins.map((a) => a.id);
  await saveNotifications(adminIds, { title, body, data, category: 'system' });

  const devices = await db.query(
    `SELECT DISTINCT d.push_token
       FROM user_devices d
       JOIN users u ON u.id = d.user_id
      WHERE u.role = 'admin' AND u.deleted_at IS NULL AND d.push_token IS NOT NULL`
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  const { sent } = await sendToTokens(tokens, { title, body, data, badge: false });
  return { sent, total: tokens.length };
}

/** Tự xoá các dòng hộp thư (bảng notifications) cũ hơn notification_settings.ttl_hours — bỏ
 * qua lặng lẽ nếu chưa cấu hình (ttl_hours NULL, mặc định) hoặc chưa có dòng settings nào.
 * Gọi định kỳ từ index.js, cùng kiểu sweepExpiredOffers (dispatch.js). */
async function sweepOldNotifications() {
  const settings = await db.queryOne('SELECT ttl_hours FROM notification_settings ORDER BY updated_at DESC LIMIT 1');
  if (!settings?.ttl_hours) return { deleted: 0 };
  const deleted = await db.query(
    `DELETE FROM notifications WHERE created_at < now() - ($1 || ' hours')::interval RETURNING id`,
    [settings.ttl_hours]
  );
  return { deleted: deleted.length };
}

module.exports = {
  sendPushToUser,
  resendPushToUser,
  notifyCustomerOrderStatus,
  notifyCustomerRepickDriver,
  notifyDriverRejected,
  notifyDriverWallet,
  notifyMerchantWallet,
  notifyAdmins,
  sendBroadcastToRoles,
  resolveMerchantUserIds,
  sendToUserIds,
  sweepOldNotifications
};
