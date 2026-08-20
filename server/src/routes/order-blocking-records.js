const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireRole } = require('../utils');

/** 4 bảng có order_id REFERENCES orders(id) KHÔNG dùng ON DELETE CASCADE (RESTRICT/NO ACTION
 * ngầm định) — còn dòng nào trỏ tới 1 đơn thì DELETE /admin/orders/:id sẽ bị Postgres chặn với
 * lỗi khoá ngoại thô (vd "driver_wallet_transactions_order_id_fkey"). Dùng cùng danh sách này
 * cho cả GET (xem trước) lẫn DELETE (chỉ cho xoá đúng 4 bảng này, không nhận tên bảng tuỳ ý từ
 * client — tránh SQL injection qua tên bảng). Xem hofa-db/62_driver_wallet_ledger.sql,
 * 01_schema.sql (payments), 64_merchant_wallet_ledger.sql. */
const BLOCKING_TABLES = [
  'driver_wallet_transactions',
  'payments',
  'merchant_wallet_transactions',
  'driver_cod_settlement_items'
];

/** Admin xem trước dữ liệu đang CHẶN XOÁ 1 đơn (trước khi bấm "Xoá đơn hàng" mà dính lỗi khoá
 * ngoại) — trả nguyên các dòng của cả 4 bảng để admin đối chiếu số tiền/loại giao dịch trước
 * khi quyết định xoá, không chỉ đếm số lượng. */
router.get('/admin/orders/:id/blocking-records', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const order = await db.queryOne('SELECT id, order_code FROM orders WHERE id = $1', [req.params.id]);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);

  const data = {};
  for (const table of BLOCKING_TABLES) {
    data[table] = await db.query(
      `SELECT * FROM ${table} WHERE order_id = $1 ORDER BY created_at DESC`,
      [req.params.id]
    );
  }
  res.json({ ok: true, data: { order_code: order.order_code, tables: data } });
}));

/** Xoá dữ liệu chặn — query ?tables=a,b,c (tên bảng trong BLOCKING_TABLES, để trống = xoá cả
 * 4). Dùng query string thay vì body vì ApiClient.delete() phía Flutter không gửi kèm body.
 * KHÔNG xoá luôn đơn hàng ở đây — admin tự bấm "Xoá đơn hàng" lại sau khi dọn xong, để còn thấy
 * rõ bước nào xảy ra trước/sau nếu có gì bất thường. */
router.delete('/admin/orders/:id/blocking-records', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const order = await db.queryOne('SELECT id FROM orders WHERE id = $1', [req.params.id]);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);

  const requested = typeof req.query.tables === 'string' && req.query.tables.trim()
    ? req.query.tables.split(',').map((t) => t.trim())
    : BLOCKING_TABLES;
  const tables = requested.filter((t) => BLOCKING_TABLES.includes(t));
  if (!tables.length) throw new ApiError('BAD_REQUEST', 'Không có bảng hợp lệ để xoá', 400);

  const deleted = {};
  for (const table of tables) {
    const rows = await db.query(`DELETE FROM ${table} WHERE order_id = $1 RETURNING id`, [req.params.id]);
    deleted[table] = rows.length;
  }
  res.json({ ok: true, data: { deleted } });
}));

module.exports = router;
