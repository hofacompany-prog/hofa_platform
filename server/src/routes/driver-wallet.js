const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireRole } = require('../utils');
const push = require('../push');

/** Tài xế hiện tại — dùng cho mọi route /drivers/me/wallet/* ở file này (bản sao nhỏ của
 * requireOwnDriverRow trong drivers.js, không export qua module để tránh phụ thuộc chéo giữa
 * 2 route file — cùng pattern các route file khác trong repo tự định nghĩa helper cục bộ). */
async function requireOwnDriverRow(ctx) {
  requireRole(ctx, ['driver']);
  const driver = await db.queryOne('SELECT * FROM drivers WHERE user_id = $1', [ctx.userId]);
  if (!driver) throw new ApiError('NOT_FOUND', 'Bạn chưa có hồ sơ tài xế', 404);
  return driver;
}

// ---- Tài xế: đối soát COD + lịch sử ví ----

/** Đơn COD đã giao xong, thuộc tài xế này, CHƯA nằm trong lần nộp nào đang pending/confirmed —
 * hiện ở màn "Nộp COD" (hofa_driver_app) để tài xế tick chọn. */
router.get('/drivers/me/wallet/cod-pending-orders', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  const rows = await db.query(
    `SELECT o.id AS order_id, o.order_code, o.total_amount, d.delivered_at
       FROM orders o JOIN deliveries d ON d.order_id = o.id
      WHERE d.driver_id = $1 AND o.payment_method = 'cod' AND o.status IN ('delivered','completed')
        AND NOT EXISTS (
          SELECT 1 FROM driver_cod_settlement_items i
            JOIN driver_cod_settlements s ON s.id = i.settlement_id
           WHERE i.order_id = o.id AND s.status IN ('pending','confirmed')
        )
      ORDER BY d.delivered_at DESC`,
    [driver.id]
  );
  res.json({ ok: true, data: rows });
}));

/** Nộp COD theo lô — chọn nhiều đơn 1 lúc, kèm ảnh chuyển khoản (không bắt buộc). Server tự
 * tính total_amount + lọc đúng đơn hợp lệ (xem RPC submit_driver_cod_settlement,
 * hofa-db/62_driver_wallet_ledger.sql), không tin dữ liệu tài xế gửi lên ngoài order_ids. */
router.post('/drivers/me/wallet/cod-settlements', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  requireFields(req.body, ['order_ids']);
  if (!Array.isArray(req.body.order_ids) || req.body.order_ids.length === 0) {
    throw new ApiError('BAD_REQUEST', 'Chưa chọn đơn nào để nộp COD', 400);
  }
  const created = await db.callRpc('submit_driver_cod_settlement', {
    p_driver_id: driver.id,
    p_order_ids: req.body.order_ids,
    p_proof_image_url: req.body.proof_image_url || null
  });
  res.status(201).json({ ok: true, data: created });
}));

/** Lịch sử ví (cả 2 ví gộp chung, sắp mới nhất trước) — màn "Lịch sử ví" app tài xế. */
router.get('/drivers/me/wallet/transactions', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  const { limit, offset } = pagination(req.query);
  const rows = await db.query(
    `SELECT * FROM driver_wallet_transactions
      WHERE driver_id = $1
      ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
    [driver.id, limit, offset]
  );
  res.json({ ok: true, data: rows, hasMore: rows.length === limit });
}));

// ---- Admin: đối soát COD ----

router.get('/admin/driver-cod-settlements', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`s.status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT s.*, u.full_name AS driver_name, u.phone AS driver_phone,
            (SELECT COUNT(*) FROM driver_cod_settlement_items i WHERE i.settlement_id = s.id) AS order_count
       FROM driver_cod_settlements s
       JOIN drivers d ON d.id = s.driver_id
       JOIN users u ON u.id = d.user_id
      ${where}
      ORDER BY s.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** Chi tiết 1 lần nộp — đúng các đơn nằm trong lô đó, admin đối chiếu trước khi xác nhận. */
router.get('/admin/driver-cod-settlements/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const settlement = await db.queryOne(
    `SELECT s.*, u.full_name AS driver_name, u.phone AS driver_phone
       FROM driver_cod_settlements s
       JOIN drivers d ON d.id = s.driver_id
       JOIN users u ON u.id = d.user_id
      WHERE s.id = $1`,
    [req.params.id]
  );
  if (!settlement) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu nộp COD', 404);
  const items = await db.query(
    `SELECT i.*, o.order_code FROM driver_cod_settlement_items i
       JOIN orders o ON o.id = i.order_id
      WHERE i.settlement_id = $1`,
    [req.params.id]
  );
  res.json({ ok: true, data: { ...settlement, items } });
}));

router.post('/admin/driver-cod-settlements/:id/confirm', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const settlement = await db.queryOne(`SELECT * FROM driver_cod_settlements WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!settlement) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu nộp COD đang chờ', 404);

  const updated = await db.updateById('driver_cod_settlements', req.params.id, {
    status: 'confirmed',
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  await db.insertRow('driver_wallet_transactions', {
    driver_id: settlement.driver_id,
    wallet: 'cod',
    entry_type: 'cod_settled',
    amount: -settlement.total_amount,
    settlement_id: settlement.id,
    created_by: req.ctx.userId
  });
  push.notifyDriverWallet(settlement.driver_id, 'cod_settlement_confirmed', settlement.total_amount).catch(() => {});
  res.json({ ok: true, data: updated });
}));

router.post('/admin/driver-cod-settlements/:id/reject', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const settlement = await db.queryOne(`SELECT * FROM driver_cod_settlements WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!settlement) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu nộp COD đang chờ', 404);

  const updated = await db.updateById('driver_cod_settlements', req.params.id, {
    status: 'rejected',
    reject_reason: req.body.reason || null,
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  // Không đụng ledger — đơn trong lô này tự động lại "chưa nộp" (GET .../cod-pending-orders lọc
  // theo status pending/confirmed, rejected không tính), tài xế chọn nộp lại lần khác được ngay.
  push.notifyDriverWallet(settlement.driver_id, 'cod_settlement_rejected', settlement.total_amount, req.body.reason).catch(() => {});
  res.json({ ok: true, data: updated });
}));

// ---- Admin: tổng quan ví tài xế + điều chỉnh tay ----

/** Số tổng toàn sàn cho dashboard "Quản lý tiền tài xế" (hofa_admin_app) — bảng chi tiết từng
 * tài xế dùng lại GET /admin/drivers (đã kèm sẵn cod_balance/earning_balance), không tạo route
 * liệt kê trùng lặp ở đây. */
router.get('/admin/driver-wallets/summary', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await db.queryOne(
    `SELECT
       COALESCE((SELECT SUM(cod_balance) FROM driver_wallet_balances), 0) AS cod_held,
       COALESCE((SELECT SUM(earning_balance) FROM driver_wallet_balances), 0) AS earning_total,
       COALESCE((SELECT SUM(amount) FROM driver_wallet_withdrawals WHERE status = 'pending'), 0) AS pending_withdrawals,
       COALESCE((SELECT SUM(total_amount) FROM driver_cod_settlements WHERE status = 'pending'), 0) AS pending_settlements`
  );
  res.json({ ok: true, data: row });
}));

/** Điều chỉnh tay ví tài xế — luôn qua 1 dòng sổ cái kèm lý do bắt buộc (không bao giờ UPDATE
 * số dư trực tiếp), xem CHECK driver_wallet_tx_adjustment_needs_note. */
router.post('/admin/drivers/:id/wallet-adjustment', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['wallet', 'amount', 'reason']);
  if (!['cod', 'earning'].includes(req.body.wallet)) {
    throw new ApiError('BAD_REQUEST', 'wallet phải là cod hoặc earning', 400);
  }
  const amount = Number(req.body.amount);
  if (!Number.isInteger(amount) || amount === 0) {
    throw new ApiError('BAD_REQUEST', 'Số tiền điều chỉnh không hợp lệ', 400);
  }
  const driver = await db.findById('drivers', req.params.id);
  if (!driver) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài xế', 404);

  const created = await db.insertRow('driver_wallet_transactions', {
    driver_id: driver.id,
    wallet: req.body.wallet,
    entry_type: 'admin_adjustment',
    amount,
    note: req.body.reason,
    created_by: req.ctx.userId
  });
  push.notifyDriverWallet(driver.id, 'admin_adjustment', amount, req.body.reason).catch(() => {});
  res.status(201).json({ ok: true, data: created });
}));

module.exports = router;
