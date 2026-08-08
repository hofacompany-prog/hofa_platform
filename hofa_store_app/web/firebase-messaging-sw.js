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
 * Ghi lại đường dẫn cần tới NGAY LÚC BẤM (không phải lúc nhận push) — Dart phía app
 * (push_service.dart) tự đọc + xoá cái này lúc khởi động để tự điều hướng bằng go_router.
 * Lý do cần thêm bước này thay vì chỉ dựa vào clients.openWindow(url)/client.navigate(url):
 * app cài như PWA (WebAPK trên Android) lúc bị tắt hẳn rồi mở lại từ thông báo có thể bỏ qua
 * URL truyền vào, luôn khởi động lại ở start_url khai trong manifest.json — xác nhận qua thực
 * tế bấm push lúc app đã tắt hẳn luôn rơi về trang chủ dù URL truyền cho openWindow đã đúng.
 * IndexedDB là kênh duy nhất chắc chắn "sống sót" qua việc khởi động lại đó để Dart đọc lại.
 */
function writePendingDeepLink(path) {
  return new Promise((resolve) => {
    const req = indexedDB.open('hofa-badge', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('counter');
    req.onsuccess = () => {
      const tx = req.result.transaction('counter', 'readwrite');
      tx.objectStore('counter').put(path, 'pendingDeepLink');
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
// KHÔNG tự gọi self.registration.showNotification() ở đây — payload luôn có sẵn field
// "notification" (xem server/src/push.js sendToTokens), nên firebase-messaging-compat.js đã
// TỰ hiện thông báo trước khi callback này chạy. Gọi thêm 1 lần nữa sẽ hiện lặp 2 thông báo
// giống hệt nhau cho MỌI push (bug thật đã xảy ra, xác nhận qua log server chỉ gửi 1 lần).
// onBackgroundMessage ở đây chỉ còn dùng để cộng dồn badge — side effect độc lập, không đụng
// gì tới việc hiển thị.
messaging.onBackgroundMessage(async (payload) => {
  const data = payload.data || {};
  console.log('[hofa-sw] onBackgroundMessage nhận data =', data);
  await writeLastPushData(data);

  if (data.category === 'order' && 'setAppBadge' in self.registration) {
    const count = (await readBadgeCount()) + 1;
    await writeBadgeCount(count);
    self.registration.setAppBadge(count).catch(() => {});
  }
});

/**
 * Đường dẫn trong app tương ứng với data của push — chạy ở đây (service worker, ngoài Dart)
 * vì lúc app đang đóng/nền, Dart code không chạy nên handleData (push_service.dart) không có
 * cơ hội được gọi. Đích tạm thời chỉ để tab "Đơn hàng" (không tới thẳng chi tiết 1 đơn cụ
 * thể) — đơn giản hoá tối đa lúc chưa xác định được vì sao điều hướng khi app tắt hẳn không
 * có tác dụng trên iOS, để tách xem lỗi nằm ở việc điều hướng nói chung hay ở phần order_id.
 */
function targetPathFor(data) {
  if (data.type === 'admin_broadcast' && data.screen) return data.screen;
  if (['order_offer', 'order_auto_confirmed', 'order_auto_cancelled'].includes(data.type)) {
    return '/orders';
  }
  return '/';
}

self.addEventListener('notificationclick', (event) => {
  console.log('[hofa-sw] notificationclick nhận được, notification =', event.notification);
  event.notification.close();
  event.waitUntil(
    readLastPushData()
      .then((data) => {
        console.log('[hofa-sw] readLastPushData() =', data);
        const path = targetPathFor(data);
        console.log('[hofa-sw] targetPathFor() =', path);
        return writePendingDeepLink(path).then(() => {
          console.log('[hofa-sw] đã ghi pendingDeepLink =', path);
          const targetUrl = new URL(path, self.registration.scope).href;
          console.log('[hofa-sw] targetUrl =', targetUrl, ', scope =', self.registration.scope);
          return clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
            console.log('[hofa-sw] số client đang mở =', windowClients.length, windowClients.map((c) => c.url));
            for (const client of windowClients) {
              if (client.url.startsWith(self.registration.scope) && 'focus' in client) {
                console.log('[hofa-sw] navigate client có sẵn tới', targetUrl);
                return client
                  .navigate(targetUrl)
                  .then((c) => {
                    console.log('[hofa-sw] client.navigate() thành công');
                    return (c || client).focus();
                  })
                  .catch((e) => {
                    console.log('[hofa-sw] client.navigate() lỗi', e);
                    return client.focus();
                  });
              }
            }
            if (clients.openWindow) {
              console.log('[hofa-sw] không có client nào đang mở, gọi clients.openWindow()');
              return clients.openWindow(targetUrl);
            }
          });
        });
      })
      .catch((e) => console.log('[hofa-sw] notificationclick lỗi', e))
  );
});
