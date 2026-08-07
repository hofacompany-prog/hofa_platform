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
 * Gửi thẳng tới danh sách token (không tra cứu user_devices) — dùng chung cho cả push
 * theo từng user (sendPushToUser) lẫn gửi hàng loạt (sendBroadcastToCustomers).
 * Không throw — lỗi gửi push không bao giờ được làm hỏng luồng gọi nó.
 */
async function sendToTokens(tokens, { title, body, data = {}, badge = false }) {
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
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } }
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
 * data phải toàn giá trị string (giới hạn của FCM data payload). badge mặc định true vì mọi
 * nơi gọi hàm này đều là thông báo liên quan đơn hàng (orderOffer.js, dispatch.js,
 * notifyCustomerOrderStatus) — loại thông báo mặc định cộng badge theo yêu cầu nghiệp vụ.
 */
async function sendPushToUser(userId, { title, body, data = {}, badge = true }) {
  const devices = await db.query(
    'SELECT push_token FROM user_devices WHERE user_id = $1 AND push_token IS NOT NULL',
    [userId]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  return sendToTokens(tokens, { title, body, data, badge });
}

/**
 * Gửi push cho TOÀN BỘ user có 1 trong các role chỉ định đang có thiết bị đăng ký nhận
 * thông báo — dùng cho màn "Thông báo" ở web admin, target=all. [roles] vd ['customer'],
 * ['driver'], ['merchant_owner','merchant_staff']. Trả về { sent, total }.
 */
async function sendBroadcastToRoles(roles, { title, body, badge = false }) {
  const devices = await db.query(
    `SELECT DISTINCT d.push_token
       FROM user_devices d
       JOIN users u ON u.id = d.user_id
      WHERE u.role = ANY($1::text[]) AND u.deleted_at IS NULL AND d.push_token IS NOT NULL`,
    [roles]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  const { sent } = await sendToTokens(tokens, {
    title,
    body,
    data: { type: 'admin_broadcast' },
    badge
  });
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
async function sendToUserIds(userIds, { title, body, badge = false }) {
  if (!userIds.length) return { sent: 0, total: 0 };
  const devices = await db.query(
    'SELECT DISTINCT push_token FROM user_devices WHERE user_id = ANY($1::uuid[]) AND push_token IS NOT NULL',
    [userIds]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  const { sent } = await sendToTokens(tokens, {
    title,
    body,
    data: { type: 'admin_broadcast' },
    badge
  });
  return { sent, total: tokens.length };
}

/** Nội dung push cho khách theo từng mốc trạng thái đơn — chỉ những mốc khách thực
 * sự cần biết (không báo 'preparing'/'assigned', khách không quan tâm mấy bước nội bộ đó). */
const CUSTOMER_STATUS_MESSAGES = {
  confirmed: (code) => ({ title: 'Đơn hàng đã được xác nhận', body: `${code} · Cửa hàng đang chuẩn bị đơn cho bạn` }),
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

module.exports = {
  sendPushToUser,
  notifyCustomerOrderStatus,
  sendBroadcastToRoles,
  resolveMerchantUserIds,
  sendToUserIds
};
