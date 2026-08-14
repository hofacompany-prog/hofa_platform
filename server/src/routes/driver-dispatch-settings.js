const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['rescan_interval_seconds', 'max_rescan_attempts'];

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

module.exports = router;
