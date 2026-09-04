const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireRole } = require('../utils');
const dispatch = require('../dispatch');

const FIELDS = [
  'rescan_interval_seconds',
  'max_rescan_attempts',
  'backup_pool_enabled',
  'search_before_ready_minutes',
  'search_on_confirm'
];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM driver_dispatch_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai — admin app đọc để hiện Thông số; dispatch.sweepDriverSearch tự đọc lại trong
// process server, không qua route này.
router.get('/driver-dispatch-settings', asyncHandler(async (req, res) => {
  const row = await currentSettings();
  res.json({ ok: true, data: row });
}));

router.patch('/driver-dispatch-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('driver_dispatch_settings', existing.id, data)
    : await db.insertRow('driver_dispatch_settings', data);
  res.json({ ok: true, data: updated });
}));

/** Admin chọn "Quét tiếp" ở đơn đang kẹt chờ tài xế (đã báo qua notifyAdmins, xem
 * dispatch.sweepDriverSearch) — reset về 0 lần, sweep quét lại ngay từ chu kỳ tiếp theo. */
router.post('/admin/orders/:id/driver-search/continue', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const order = await db.queryOne('SELECT id FROM orders WHERE id = $1', [req.params.id]);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  const updated = await db.updateById('orders', req.params.id, {
    driver_search_attempts: 0,
    driver_search_last_attempt_at: null,
    driver_search_alerted_at: null
  });
  res.json({ ok: true, data: updated });
}));

/** Admin bấm "Quét tài xế" cho 1 đơn cụ thể (chủ yếu dùng cho đơn mua hộ bị kẹt — chưa có ai
 * nhận) — quét NGAY lập tức (khác /driver-search/continue chỉ reset để chờ sweep tự động chạy
 * lại ở chu kỳ tiếp theo). Cùng logic offerToNearestDriver dùng ở nút "Tìm tài xế" của cửa hàng
 * (POST /orders/:orderId/find-driver, deliveries.js) nhưng không cần requireMerchantAccess vì
 * admin xử lý được đơn của MỌI cửa hàng, kể cả cửa hàng mua hộ dùng chung tài khoản GAS_SYNC. */
router.post('/admin/orders/:id/rescan-driver', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const order = await db.queryOne('SELECT id FROM orders WHERE id = $1', [req.params.id]);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);

  const existing = await db.queryOne('SELECT declined_driver_ids FROM deliveries WHERE order_id = $1', [req.params.id]);
  // forceBackupPool: true — admin bấm nút này CHÍNH LÀ để gỡ đơn kẹt, nên luôn thử cả nhóm tài
  // xế dự phòng bất kể công tắc toàn sàn backup_pool_enabled đang tắt hay bật.
  const result = await dispatch.offerToNearestDriver(req.params.id, {
    excludeDriverIds: existing?.declined_driver_ids || [],
    forceBackupPool: true
  });
  if (!result) throw new ApiError('NOT_FOUND', 'Hiện không có tài xế nào đang online phù hợp (kể cả dự phòng)', 404);
  const driverUser = await db.queryOne('SELECT full_name FROM users WHERE id = $1', [result.driver.user_id]);
  res.json({ ok: true, data: { ...result.delivery, driver_name: driverUser?.full_name ?? null } });
}));

module.exports = router;
