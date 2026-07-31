const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireAuth, requireMerchantAccess } = require('../utils');

router.get('/reviews', asyncHandler(async (req, res) => {
  requireFields(req.query, ['target_type', 'target_id']);
  const { limit, offset } = pagination(req.query);
  const rows = await db.query(
    `SELECT * FROM reviews WHERE target_type = $1 AND target_id = $2 AND NOT is_hidden
     ORDER BY created_at DESC LIMIT $3 OFFSET $4`,
    [req.query.target_type, req.query.target_id, limit, offset]
  );
  res.json({ ok: true, data: rows });
}));

/** Chỉ được đánh giá khi đã có đơn thật và đơn đã delivered/completed. */
router.post('/reviews', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['order_id', 'target_type', 'target_id', 'rating']);
  const order = await db.findById('orders', req.body.order_id);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  if (order.customer_id !== req.ctx.userId) throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
  if (!['delivered', 'completed'].includes(order.status)) {
    throw new ApiError('BAD_REQUEST', 'Chỉ đánh giá được sau khi đơn đã giao', 400);
  }
  if (req.body.rating < 1 || req.body.rating > 5) {
    throw new ApiError('BAD_REQUEST', 'rating phải từ 1 đến 5', 400);
  }

  const created = await db.insertRow('reviews', {
    order_id: req.body.order_id,
    customer_id: req.ctx.userId,
    target_type: req.body.target_type,
    target_id: req.body.target_id,
    rating: req.body.rating,
    comment: req.body.comment || null,
    media_urls: req.body.media_urls || []
  });
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/reviews/:id/reply', asyncHandler(async (req, res) => {
  requireFields(req.body, ['reply']);
  const review = await db.findById('reviews', req.params.id);
  if (!review) throw new ApiError('NOT_FOUND', 'Không tìm thấy đánh giá', 404);
  if (review.target_type === 'merchant') {
    await requireMerchantAccess(req.ctx, review.target_id);
  } else if (req.ctx.role !== 'admin') {
    throw new ApiError('FORBIDDEN', 'Chỉ admin trả lời được đánh giá loại này', 403);
  }
  const updated = await db.updateById('reviews', req.params.id, {
    merchant_reply: req.body.reply, replied_at: new Date().toISOString()
  });
  res.json({ ok: true, data: updated });
}));

/** Ẩn đánh giá vi phạm — không xoá, để còn dấu vết kiểm duyệt. */
router.patch('/reviews/:id/hidden', asyncHandler(async (req, res) => {
  requireFields(req.body, ['is_hidden']);
  const review = await db.findById('reviews', req.params.id);
  if (!review) throw new ApiError('NOT_FOUND', 'Không tìm thấy đánh giá', 404);
  if (req.ctx.role !== 'admin') {
    if (review.target_type !== 'merchant') throw new ApiError('FORBIDDEN', 'Không đủ quyền', 403);
    await requireMerchantAccess(req.ctx, review.target_id);
  }
  const updated = await db.updateById('reviews', req.params.id, { is_hidden: !!req.body.is_hidden });
  res.json({ ok: true, data: updated });
}));

module.exports = router;
