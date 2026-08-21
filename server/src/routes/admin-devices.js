const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireRole } = require('../utils');

/** Thiết bị đã đăng nhập của MỌI tài khoản admin (không riêng người đang gọi) — để 1 admin tự
 * soát được có máy lạ nào đang đăng nhập admin trên toàn hệ thống không, tắt/xoá nếu cần. Cùng
 * pattern GET /merchants/:id/devices (merchants.js) nhưng phạm vi role='admin' thay vì 1 cửa
 * hàng cụ thể. */
router.get('/admin/admin-devices', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const rows = await db.query(
    `SELECT d.*, u.full_name AS user_full_name
       FROM user_devices d
       JOIN users u ON u.id = d.user_id
      WHERE u.role = 'admin' AND u.deleted_at IS NULL
      ORDER BY d.last_active_at DESC NULLS LAST`
  );
  res.json({ ok: true, data: rows });
}));

/** Chỉ "tắt" (xoá push_token, ngừng gửi thông báo tới máy đó) — giữ lại dòng để vẫn thấy lịch
 * sử đăng nhập. Không thể tự "bật" lại từ đây vì token phải do chính máy đó tạo ra (xem nút
 * "Bật thông báo" ở _AdminDevicesTab — chỉ hoạt động trên đúng máy đang mở). */
router.patch('/admin/admin-devices/:deviceId', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const device = await db.queryOne(
    `SELECT d.id FROM user_devices d JOIN users u ON u.id = d.user_id
      WHERE d.id = $1 AND u.role = 'admin'`,
    [req.params.deviceId]
  );
  if (!device) throw new ApiError('NOT_FOUND', 'Không tìm thấy thiết bị', 404);
  const updated = await db.updateById('user_devices', req.params.deviceId, { push_token: null });
  res.json({ ok: true, data: updated });
}));

router.delete('/admin/admin-devices/:deviceId', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const device = await db.queryOne(
    `SELECT d.id FROM user_devices d JOIN users u ON u.id = d.user_id
      WHERE d.id = $1 AND u.role = 'admin'`,
    [req.params.deviceId]
  );
  if (!device) throw new ApiError('NOT_FOUND', 'Không tìm thấy thiết bị', 404);
  await db.deleteById('user_devices', req.params.deviceId);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
