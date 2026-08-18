const { haversineKm } = require('./utils');

// Server routing công khai của dự án OSRM (router.project-osrm.org) — miễn phí, không cần khoá
// API, nhưng KHÔNG cam kết SLA production (chính OSRM ghi rõ demo server có thể giới hạn tốc độ
// hoặc ngừng bất kỳ lúc nào). Mọi hàm ở file này PHẢI rớt về haversineKm (đường chim bay) khi
// lỗi/timeout — không được để 1 dịch vụ ngoài làm treo luồng đặt đơn/ghép tài xế.
const OSRM_BASE = 'https://router.project-osrm.org';
const TIMEOUT_MS = 4000;

/** Khoảng cách ĐƯỜNG ĐI THỰC TẾ (km) giữa 2 toạ độ, dùng profile "driving" (OSRM không có
 * profile xe máy riêng — driving là xấp xỉ gần nhất cho xe máy chạy chung đường với ô tô ở VN).
 * Lưu ý OSRM nhận toạ độ theo thứ tự lng,lat (ngược với lat,lng quen dùng trong repo này). */
async function routeDistanceKm(lat1, lng1, lat2, lng2) {
  try {
    const url = `${OSRM_BASE}/route/v1/driving/${lng1},${lat1};${lng2},${lat2}?overview=false&alternatives=false&steps=false`;
    const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!res.ok) throw new Error(`OSRM HTTP ${res.status}`);
    const data = await res.json();
    const meters = data?.routes?.[0]?.distance;
    if (typeof meters !== 'number') throw new Error('OSRM: thiếu routes[0].distance');
    return meters / 1000;
  } catch (err) {
    console.error('[routing] routeDistanceKm lỗi, rớt về haversine:', err.message);
    return haversineKm(lat1, lng1, lat2, lng2);
  }
}

/** Khoảng cách đường đi thực tế từ 1 điểm gốc tới NHIỀU điểm đích trong 1 lần gọi (OSRM Table
 * service) — dùng cho danh sách cần biết khoảng cách nhiều nơi cùng lúc (ghép tài xế gần nhất,
 * sắp cửa hàng/tài xế theo khoảng cách...) thay vì gọi routeDistanceKm() lặp lại N lần, vừa
 * chậm vừa dễ vượt giới hạn tốc độ của server demo công khai.
 * destinations: [{lat, lng}, ...] — trả về mảng km CÙNG THỨ TỰ, phần tử nào OSRM báo không tới
 * được (null) thì tự rớt về haversine riêng cho phần tử đó. Lỗi cả request thì rớt về haversine
 * cho toàn bộ danh sách. */
async function routeDistancesKm(originLat, originLng, destinations) {
  if (!destinations.length) return [];
  try {
    const coords = [
      `${originLng},${originLat}`,
      ...destinations.map((d) => `${d.lng},${d.lat}`)
    ].join(';');
    const destIdx = destinations.map((_, i) => i + 1).join(';');
    const url = `${OSRM_BASE}/table/v1/driving/${coords}?sources=0&destinations=${destIdx}&annotations=distance`;
    const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!res.ok) throw new Error(`OSRM HTTP ${res.status}`);
    const data = await res.json();
    const row = data?.distances?.[0];
    if (!Array.isArray(row)) throw new Error('OSRM: thiếu distances[0]');
    return row.map((meters, i) =>
      typeof meters === 'number'
        ? meters / 1000
        : haversineKm(originLat, originLng, destinations[i].lat, destinations[i].lng)
    );
  } catch (err) {
    console.error('[routing] routeDistancesKm lỗi, rớt về haversine cho cả danh sách:', err.message);
    return destinations.map((d) => haversineKm(originLat, originLng, d.lat, d.lng));
  }
}

module.exports = { routeDistanceKm, routeDistancesKm };
