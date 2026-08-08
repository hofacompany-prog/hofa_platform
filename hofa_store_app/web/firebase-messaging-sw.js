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
// hẳn, kể cả khi đã tải xong bản service worker mới — mọi sửa đổi ở file này (kể cả các bản
// vá điều hướng push trước đó) có thể ÂM THẦM không có hiệu lực trên máy thật vì lý do này,
// không phải vì logic sai. skipWaiting() bỏ qua bước "waiting", clients.claim() chiếm quyền
// kiểm soát các tab đang mở ngay lập tức — bản mới có hiệu lực ngay lần mở app kế tiếp.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(clients.claim()));

/**
 * Đếm dồn số badge trên icon PWA ở màn hình chính (Badging API). localStorage không dùng
 * được trong service worker nên lưu ở IndexedDB — cùng 1 store với script xoá badge trong
 * index.html (chạy lúc app được mở/focus lại).
 */
function readBadgeCount() {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-badge', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('counter');
    req.onsuccess = () => {
      const getReq = req.result
        .transaction('counter', 'readonly')
        .objectStore('counter')
        .get('count');
      getReq.onsuccess = () => resolve(getReq.result || 0);
      getReq.onerror = () => resolve(0);
    };
    req.onerror = () => resolve(0);
  });
}

function writeBadgeCount(count) {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-badge', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('counter');
    req.onsuccess = () => {
      const tx = req.result.transaction('counter', 'readwrite');
      tx.objectStore('counter').put(count, 'count');
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    };
    req.onerror = () => resolve();
  });
}

/**
 * Lưu lại data của push gần nhất — để notificationclick bên dưới đọc lại. KHÔNG đọc từ
 * event.notification.data (đã thử — cấu trúc đó do firebase-messaging-compat.js tự quyết định
 * lúc tự hiện thông báo và không ổn định/không tài liệu hoá rõ ràng giữa các bản SDK, thực tế
 * đã xác nhận không lấy được data đúng, khiến bấm push mở app nhưng không nhảy đúng màn). Ghi
 * lại data thẳng từ onBackgroundMessage (đáng tin cậy — dùng chung cho đếm badge) là cách chắc
 * chắn duy nhất. Cùng 1 object store 'counter' với hàm đếm badge ở trên, khác key.
 */
function writeLastPushData(data) {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-badge', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('counter');
    req.onsuccess = () => {
      const tx = req.result.transaction('counter', 'readwrite');
      tx.objectStore('counter').put(data, 'lastPush');
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    };
    req.onerror = () => resolve();
  });
}

function readLastPushData() {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-badge', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('counter');
    req.onsuccess = () => {
      const getReq = req.result
        .transaction('counter', 'readonly')
        .objectStore('counter')
        .get('lastPush');
      getReq.onsuccess = () => resolve(getReq.result || {});
      getReq.onerror = () => resolve({});
    };
    req.onerror = () => resolve({});
  });
}

/**
 * Firebase JS SDK chỉ định tuyến message vào đây khi KHÔNG có tab nào của app đang mở/focus
 * — đúng lúc icon màn hình chính là thứ người dùng thật sự nhìn thấy. Badge của app Cửa hàng
 * đại diện CHÍNH XÁC cho số thông báo "Đơn hàng" chưa đọc (không phải mọi push nói chung) —
 * cộng dồn ở đây chỉ là ước lượng tạm thời lúc app đang đóng (không gọi được API vì service
 * worker không có sẵn access token); ngay khi app mở lên, unreadOrderCountProvider (xem
 * lib/providers/notification_providers.dart, BadgeService) tự chỉnh lại đúng số thật.
 */
// KHÔNG tự gọi self.registration.showNotification() ở đây — payload luôn có sẵn field
// "notification" (xem server/src/push.js sendToTokens), nên firebase-messaging-compat.js đã
// TỰ hiện thông báo trước khi callback này chạy. Gọi thêm 1 lần nữa sẽ hiện lặp 2 thông báo
// giống hệt nhau cho MỌI push (bug thật đã xảy ra, xác nhận qua log server chỉ gửi 1 lần).
// onBackgroundMessage ở đây chỉ còn dùng để cộng dồn badge — side effect độc lập, không đụng
// gì tới việc hiển thị.
messaging.onBackgroundMessage(async (payload) => {
  const data = payload.data || {};
  await writeLastPushData(data);

  if (data.category === 'order' && 'setAppBadge' in self.registration) {
    const count = (await readBadgeCount()) + 1;
    await writeBadgeCount(count);
    self.registration.setAppBadge(count).catch(() => {});
  }
});

/**
 * Đường dẫn trong app tương ứng với data của push — khớp switch trong
 * lib/core/push_service.dart#handleData, NHƯNG chạy ở đây (service worker, ngoài Dart) vì lúc
 * app đang đóng/nền, Dart code không chạy nên handleData không có cơ hội được gọi — trước đây
 * bấm vào thông báo chỉ mở trang chủ (self.registration.scope), bỏ qua hẳn order_id, nên
 * không bao giờ nhảy tới đúng màn Chi tiết đơn được.
 */
function targetPathFor(data) {
  if (data.type === 'admin_broadcast' && data.screen) return data.screen;
  if (data.order_id && ['order_offer', 'order_auto_confirmed', 'order_auto_cancelled'].includes(data.type)) {
    return '/orders/' + data.order_id;
  }
  return '/';
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    readLastPushData().then((data) => {
      const targetUrl = new URL(targetPathFor(data), self.registration.scope).href;
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
