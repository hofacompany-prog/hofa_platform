const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireProfile } = require('../utils');

/** Danh sách cửa hàng yêu thích (đầy đủ thông tin merchant, phân trang) — dùng cho màn
 * "Cửa hàng yêu thích" phía app khách, mở từ icon trái tim ở trang chủ. */
router.get('/favorites', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const { limit, offset } = pagination(req.query);
  const rows = await db.query(
    `SELECT m.*,
            EXISTS (
              SELECT 1 FROM branches b
               WHERE b.merchant_id = m.id AND b.deleted_at IS NULL AND b.is_open = true
            ) AS has_open_branch
       FROM merchant_favorites f
       JOIN merchants m ON m.id = f.merchant_id AND m.deleted_at IS NULL
      WHERE f.customer_id = $1
      ORDER BY f.created_at DESC
      LIMIT $2 OFFSET $3`,
    [req.ctx.userId, limit, offset]
  );
  res.json({ ok: true, data: rows, hasMore: rows.length === limit });
}));

/** Chỉ trả về id — nhẹ, dùng để tô/tắt icon tim ở mọi nơi khác (thẻ cửa hàng, chi tiết cửa
 * hàng) mà không cần tải lại toàn bộ thông tin merchant mỗi lần. */
router.get('/favorites/ids', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const rows = await db.query('SELECT merchant_id FROM merchant_favorites WHERE customer_id = $1', [req.ctx.userId]);
  res.json({ ok: true, data: rows.map((r) => r.merchant_id) });
}));

router.post('/favorites', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['merchant_id']);
  const merchant = await db.findById('merchants', req.body.merchant_id);
  if (!merchant) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);
  // Bấm tim 2 lần liên tiếp (mạng chậm, double-tap...) không nên báo lỗi — coi như đã yêu
  // thích rồi, im lặng bỏ qua vi phạm UNIQUE(customer_id, merchant_id).
  try {
    await db.insertRow('merchant_favorites', {
      customer_id: req.ctx.userId,
      merchant_id: req.body.merchant_id
    });
  } catch (e) {
    if (e.code !== '23505') throw e;
  }
  res.status(201).json({ ok: true, data: { favorited: true } });
}));

router.delete('/favorites/:merchantId', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  await db.query(
    'DELETE FROM merchant_favorites WHERE customer_id = $1 AND merchant_id = $2',
    [req.ctx.userId, req.params.merchantId]
  );
  res.json({ ok: true, data: { favorited: false } });
}));

module.exports = router;
