const router = require('express').Router();
const db = require('../db');
const config = require('../config');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireRole } = require('../utils');

/** Admin xem trước dữ liệu đang CHẶN "Xoá vĩnh viễn" 1 người dùng (merchants.owner_id/
 * drivers.user_id/orders.customer_id đều ON DELETE RESTRICT, xem DELETE /admin/users/:id) —
 * để admin đối chiếu cụ thể cửa hàng/hồ sơ tài xế/đơn hàng nào trước khi quyết định xử lý
 * (chuyển chủ cửa hàng cho Admin, xoá hồ sơ tài xế...) hay chỉ "Tạm khoá" thay vì xoá hẳn. Chỉ
 * hiện thông tin, KHÔNG xoá gì ở đây — khác order-blocking-records vì đây là dữ liệu nghiệp vụ
 * thật (cửa hàng/đơn hàng của người khác), không phải bảng sổ sách an toàn để dọn hàng loạt. */
router.get('/admin/users/:id/blocking-records', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const user = await db.queryOne('SELECT id, full_name FROM users WHERE id = $1', [req.params.id]);
  if (!user) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);

  const [merchants, driver, orders, orderCount] = await Promise.all([
    db.query(
      'SELECT id, name, status, merchant_type, created_at FROM merchants WHERE owner_id = $1 ORDER BY created_at DESC',
      [req.params.id]
    ),
    db.queryOne(
      'SELECT id, status, vehicle_type, vehicle_plate, created_at FROM drivers WHERE user_id = $1',
      [req.params.id]
    ),
    db.query(
      `SELECT id, order_code, status, total_amount, created_at FROM orders
        WHERE customer_id = $1 ORDER BY created_at DESC LIMIT 20`,
      [req.params.id]
    ),
    db.queryOne('SELECT COUNT(*) AS count FROM orders WHERE customer_id = $1', [req.params.id])
  ]);

  res.json({
    ok: true,
    data: {
      full_name: user.full_name,
      merchants,
      driver,
      orders: { count: Number(orderCount.count), items: orders }
    }
  });
}));

/** Gỡ chặn nhanh: chuyển 1 cửa hàng đang đứng tên user sắp xoá sang tài khoản "HOFA Admin" dùng
 * chung (config.gasSyncOwnerId — CÙNG tài khoản GAS sync gán cho cửa hàng mua hộ chưa có chủ
 * thật, xem resolveOwnerIdByPhone/PATCH /merchants/:id trong merchants.js), thay vì phải tự vào
 * từng cửa hàng đổi chủ tay. Cửa hàng vẫn hoạt động bình thường, chỉ không còn ai đăng nhập app
 * Cửa hàng quản lý được nữa cho tới khi admin gán chủ thật khác (owner_phone, cùng route đó). */
router.post('/admin/merchants/:id/transfer-to-admin-owner', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  if (!config.gasSyncOwnerId) {
    throw new ApiError('NOT_CONFIGURED', 'Server chưa cấu hình GAS_SYNC_OWNER_ID, không có tài khoản Admin để chuyển chủ', 400);
  }
  const merchant = await db.findById('merchants', req.params.id);
  if (!merchant) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);

  const updated = await db.updateById('merchants', req.params.id, { owner_id: config.gasSyncOwnerId });
  res.json({ ok: true, data: updated });
}));

module.exports = router;
