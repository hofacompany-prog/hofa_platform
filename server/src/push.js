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

/**
 * Gửi push notification cho MỌI thiết bị đã đăng ký (bảng user_devices) của 1 user.
 * data phải toàn giá trị string (giới hạn của FCM data payload).
 * Không throw — lỗi gửi push không bao giờ được làm hỏng luồng nghiệp vụ chính.
 */
async function sendPushToUser(userId, { title, body, data = {} }) {
  const firebaseApp = getApp();
  if (!firebaseApp) return { sent: 0 };

  const devices = await db.query(
    'SELECT push_token FROM user_devices WHERE user_id = $1 AND push_token IS NOT NULL',
    [userId]
  );
  const tokens = devices.map((d) => d.push_token).filter(Boolean);
  if (!tokens.length) return { sent: 0 };

  try {
    const admin = require('firebase-admin');
    const stringData = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)]));
    const result = await admin.messaging(firebaseApp).sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: stringData,
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } }
    });
    return { sent: result.successCount };
  } catch (err) {
    console.error('[push] Gửi push thất bại:', err.message);
    return { sent: 0 };
  }
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

module.exports = { sendPushToUser, notifyCustomerOrderStatus };
