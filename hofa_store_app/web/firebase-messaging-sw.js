// Trình duyệt mặc định giữ service worker CŨ chạy cho tới khi mọi tab/instance của app đóng
// hẳn, kể cả khi đã tải xong bản service worker mới — mọi sửa đổi ở file này có thể ÂM THẦM
// không có hiệu lực trên máy thật vì lý do này, không phải vì logic sai. skipWaiting() bỏ qua
// bước "waiting", clients.claim() chiếm quyền kiểm soát các tab đang mở ngay lập tức — bản mới
// có hiệu lực ngay lần mở app kế tiếp.
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
 * event.notification.data — cấu trúc đó không ổn định giữa các nền tảng/SDK, thực tế đã xác
 * nhận không lấy được data đúng. Ghi lại data thẳng từ push event (đáng tin cậy — dùng chung
 * cho đếm badge) là cách chắc chắn duy nhất. Cùng 1 object store 'counter' với hàm đếm badge
 * ở trên, khác key.
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
 * app cài như PWA (WebAPK/Home Screen web app) lúc bị tắt hẳn rồi mở lại từ thông báo có thể
 * bỏ qua URL truyền vào, luôn khởi động lại ở start_url khai trong manifest.json. IndexedDB là
 * kênh duy nhất chắc chắn "sống sót" qua việc khởi động lại đó để Dart đọc lại.
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
 * Xử lý push event THẲNG (không qua firebase-messaging-compat.js/onBackgroundMessage nữa) —
 * xác nhận qua Web Inspector thật trên iOS: dùng messaging.onBackgroundMessage() khiến
 * showNotification() bị gọi "outside of any push event lifetime" (cảnh báo thật từ trình
 * duyệt), gây thông báo hiện lặp 2 lần (rất có thể do trình duyệt coi push chưa được xử lý
 * xong và gửi lại) và khiến notification tạo ra không phải 1 Notification object thật để
 * notificationclick gắn vào. Tự đọc event.data + tự gọi showNotification() bên trong
 * event.waitUntil() của CHÍNH push event là cách chuẩn, đúng vòng đời Push API, không cần
 * phụ thuộc SDK Firebase trong service worker nữa (SDK chỉ còn cần ở phía Dart để lấy token).
 */
self.addEventListener('push', (event) => {
  event.waitUntil(handlePush(event));
});

async function handlePush(event) {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (e) {
    console.log('[hofa-sw] không đọc được push data dạng JSON', e);
  }
  const data = payload.data || {};
  console.log('[hofa-sw] push event nhận data =', data);
  await writeLastPushData(data);

  if (data.category === 'order' && 'setAppBadge' in self.registration) {
    const count = (await readBadgeCount()) + 1;
    await writeBadgeCount(count);
    self.registration.setAppBadge(count).catch(() => {});
  }

  const title = (payload.notification && payload.notification.title) || data.title || 'HOFA';
  const body = (payload.notification && payload.notification.body) || data.body || '';
  console.log('[hofa-sw] gọi showNotification()', title, body);
  await self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    data,
  });
}

/**
 * Đường dẫn trong app tương ứng với data của push — chạy ở đây (service worker, ngoài Dart)
 * vì lúc app đang đóng/nền, Dart code không chạy nên handleData (push_service.dart) không có
 * cơ hội được gọi. Đích tạm thời chỉ để tab "Đơn hàng" (không tới thẳng chi tiết 1 đơn cụ
 * thể) — đơn giản hoá tối đa lúc đang chẩn đoán, để tách xem lỗi nằm ở việc điều hướng nói
 * chung hay ở phần order_id/màn chi tiết.
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
  // Một số nền tảng (Safari/iOS) từ chối đóng thông báo NGAY lúc vừa hiện ("Persistent
  // notifications cannot be closed shortly after they are shown") — lỗi này ném ra đồng bộ,
  // bọc try/catch để không làm dừng cả hàm nếu gặp.
  try {
    event.notification.close();
  } catch (e) {
    console.log('[hofa-sw] notification.close() lỗi, bỏ qua và tiếp tục điều hướng', e);
  }
  event.waitUntil(
    readLastPushData()
      .then((data) => {
        console.log('[hofa-sw] readLastPushData() =', data);
        const path = targetPathFor(data);
        console.log('[hofa-sw] targetPathFor() =', path);
        return writePendingDeepLink(path).then(() => {
          console.log('[hofa-sw] đã ghi pendingDeepLink =', path);
          // self.registration.scope KHÔNG phải origin của app — Firebase đăng ký worker này ở
          // scope riêng '/firebase-cloud-messaging-push-scope' (xác nhận qua Web Inspector
          // thật), khác hẳn '/' nơi các trang thật của app chạy. Dùng self.location.origin để
          // so khớp tab đang mở, không dùng self.registration.scope.
          const origin = self.location.origin;
          const targetUrl = new URL(path, origin).href;
          console.log('[hofa-sw] targetUrl =', targetUrl, ', origin =', origin);
          return clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
            console.log('[hofa-sw] số client đang mở =', windowClients.length, windowClients.map((c) => c.url));
            for (const client of windowClients) {
              if (client.url.startsWith(origin) && 'focus' in client) {
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
