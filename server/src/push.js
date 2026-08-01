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

module.exports = { sendPushToUser };
