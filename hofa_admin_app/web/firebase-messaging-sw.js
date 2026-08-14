importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDxy5zm1SaYYZh5Z3TbTeMZBSaqqmxlbPA',
  authDomain: 'hofa-production.firebaseapp.com',
  projectId: 'hofa-production',
  storageBucket: 'hofa-production.firebasestorage.app',
  messagingSenderId: '265406466413',
  appId: '1:265406466413:web:cca1f24788dafe39143264',
});

const messaging = firebase.messaging();

// Trình duyệt mặc định giữ service worker CŨ chạy cho tới khi mọi tab/instance của app đóng
// hẳn, kể cả khi đã tải xong bản service worker mới — mọi sửa đổi ở file này có thể ÂM THẦM
// không có hiệu lực trên máy thật vì lý do này, không phải vì logic sai. skipWaiting() bỏ qua
// bước "waiting", clients.claim() chiếm quyền kiểm soát các tab đang mở ngay lập tức — bản mới
// có hiệu lực ngay lần mở app kế tiếp.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(clients.claim()));

/**
 * Lưu lại data của push gần nhất — notificationclick bên dưới đọc lại để biết mở đúng màn.
 * KHÔNG tự gọi self.registration.showNotification() — payload luôn có sẵn field "notification"
 * (xem server/src/push.js sendToTokens), firebase-messaging-compat.js đã TỰ hiện thông báo,
 * gọi thêm sẽ hiện lặp 2 lần (bug đã xác nhận ở 3 app kia, xem firebase-messaging-sw.js của
 * hofa_customer_app).
 */
function writeLastPushData(data) {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-admin-push', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('kv');
    req.onsuccess = () => {
      const tx = req.result.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(data, 'lastPush');
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    };
    req.onerror = () => resolve();
  });
}

function readLastPushData() {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-admin-push', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('kv');
    req.onsuccess = () => {
      const getReq = req.result.transaction('kv', 'readonly').objectStore('kv').get('lastPush');
      getReq.onsuccess = () => resolve(getReq.result || {});
      getReq.onerror = () => resolve({});
    };
    req.onerror = () => resolve({});
  });
}

messaging.onBackgroundMessage(async (payload) => {
  await writeLastPushData(payload.data || {});
});

/** Đường dẫn trong app tương ứng với data của push — khớp push_service.dart#handleData. */
function targetPathFor(data) {
  if (data.type === 'admin_alert' && data.screen) return data.screen;
  return '/';
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    readLastPushData().then((data) => {
      const path = targetPathFor(data);
      const targetUrl = new URL(path, self.registration.scope).href;
      return clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
        for (const client of windowClients) {
          if (client.url.startsWith(self.registration.scope) && 'focus' in client) {
            return client.navigate(targetUrl).then((c) => (c || client).focus()).catch(() => client.focus());
          }
        }
        if (clients.openWindow) return clients.openWindow(targetUrl);
      });
    })
  );
});
