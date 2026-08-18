const router = require('express').Router();
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { routeDistanceKm } = require('../routing');

// Công khai (không cần đăng nhập) — app khách gọi lúc checkout để ước tính phí ship theo đường
// đi thực tế (thay vì tự tính đường chim bay trong Dart, xem checkout_screen.dart), app tài xế
// có thể dùng tương tự nếu cần. Không có ý nghĩa bảo mật gì (chỉ trả về 1 số km).
router.get('/route-distance', asyncHandler(async (req, res) => {
  const lat1 = Number(req.query.lat1);
  const lng1 = Number(req.query.lng1);
  const lat2 = Number(req.query.lat2);
  const lng2 = Number(req.query.lng2);
  if ([lat1, lng1, lat2, lng2].some((n) => !Number.isFinite(n))) {
    throw new ApiError('BAD_REQUEST', 'Thiếu/sai lat1, lng1, lat2, lng2', 400);
  }
  const km = await routeDistanceKm(lat1, lng1, lat2, lng2);
  res.json({ ok: true, data: { distance_km: km } });
}));

module.exports = router;
