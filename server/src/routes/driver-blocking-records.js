const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireRole } = require('../utils');

/** Admin xem trước dữ liệu đang CHẶN "Xoá tài xế" (xem DELETE /admin/drivers/:id) — chuyến giao
 * chưa hoàn tất + số dư ví (COD giữ hộ/thu nhập chưa rút) — để admin đi xử lý (gán tài xế
 * khác/huỷ chuyến, quyết toán ví) trước khi xoá lại. Không tự xoá/đổi gì ở đây. */
router.get('/admin/drivers/:id/blocking-records', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const driver = await db.queryOne('SELECT id FROM drivers WHERE id = $1', [req.params.id]);
  if (!driver) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài xế', 404);

  const [activeDeliveries, wallet] = await Promise.all([
    db.query(
      `SELECT dl.id, dl.status, dl.order_id, o.order_code, dl.created_at
         FROM deliveries dl JOIN orders o ON o.id = dl.order_id
        WHERE dl.driver_id = $1 AND dl.status NOT IN ('delivered', 'failed', 'returned')
        ORDER BY dl.created_at DESC`,
      [req.params.id]
    ),
    db.queryOne('SELECT cod_balance, earning_balance FROM driver_wallet_balances WHERE driver_id = $1', [req.params.id])
  ]);

  res.json({
    ok: true,
    data: {
      active_deliveries: activeDeliveries,
      cod_balance: Number(wallet?.cod_balance ?? 0),
      earning_balance: Number(wallet?.earning_balance ?? 0)
    }
  });
}));

module.exports = router;
