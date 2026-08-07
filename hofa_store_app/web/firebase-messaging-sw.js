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
 * Firebase JS SDK chỉ định tuyến message vào đây khi KHÔNG có tab nào của app đang mở/focus
 * — đúng lúc icon màn hình chính là thứ người dùng thật sự nhìn thấy. Badge của app Cửa hàng
 * đại diện CHÍNH XÁC cho số thông báo "Đơn hàng" chưa đọc (không phải mọi push nói chung) —
 * cộng dồn ở đây chỉ là ước lượng tạm thời lúc app đang đóng (không gọi được API vì service
 * worker không có sẵn access token); ngay khi app mở lên, unreadOrderCountProvider (xem
 * lib/providers/notification_providers.dart, BadgeService) tự chỉnh lại đúng số thật.
 */
messaging.onBackgroundMessage(async (payload) => {
  const data = payload.data || {};

  if (data.category === 'order' && 'setAppBadge' in self.registration) {
    const count = (await readBadgeCount()) + 1;
    await writeBadgeCount(count);
    self.registration.setAppBadge(count).catch(() => {});
  }

  const title = (payload.notification && payload.notification.title) || data.title;
  const body = (payload.notification && payload.notification.body) || data.body;
  if (title) {
    self.registration.showNotification(title, {
      body,
      icon: 'icons/Icon-192.png',
      data,
    });
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(self.registration.scope));
});
