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
 * — đúng lúc icon màn hình chính là thứ người dùng thật sự nhìn thấy, nên badge chỉ cần xử lý
 * ở service worker. data.badge do server/src/push.js quyết định: 'true' cho thông báo đơn
 * hàng (mặc định) hoặc khi admin tick "Hiển thị số trên biểu tượng ứng dụng".
 */
// KHÔNG tự gọi self.registration.showNotification() ở đây — payload luôn có sẵn field
// "notification" (xem server/src/push.js sendToTokens), nên firebase-messaging-compat.js đã
// TỰ hiện thông báo trước khi callback này chạy. Gọi thêm 1 lần nữa sẽ hiện lặp 2 thông báo
// giống hệt nhau cho MỌI push (bug thật đã xảy ra, xác nhận qua log server chỉ gửi 1 lần).
// onBackgroundMessage ở đây chỉ còn dùng để cộng dồn badge — side effect độc lập, không đụng
// gì tới việc hiển thị.
messaging.onBackgroundMessage(async (payload) => {
  const data = payload.data || {};

  if (data.badge === 'true' && 'setAppBadge' in self.registration) {
    const count = (await readBadgeCount()) + 1;
    await writeBadgeCount(count);
    self.registration.setAppBadge(count).catch(() => {});
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(self.registration.scope));
});
