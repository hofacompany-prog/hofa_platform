const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireAuth, requireMerchantAccess } = require('../utils');

/** order_id: liệt kê mọi đánh giá (mọi target_type) của 1 đơn cụ thể — màn "Đánh giá đơn hàng"
 * phía khách dùng để biết đã đánh giá món/cửa hàng/tài xế nào rồi. Không thì lọc theo
 * target_type + target_id như cũ (màn danh sách đánh giá của 1 cửa hàng/sản phẩm/tài xế). */
router.get('/reviews', asyncHandler(async (req, res) => {
  const { limit, offset } = pagination(req.query);
  const clauses = ['NOT r.is_hidden'];
  const params = [];
  if (req.query.order_id) {
    params.push(req.query.order_id);
    clauses.push(`r.order_id = $${params.length}`);
  } else {
    requireFields(req.query, ['target_type', 'target_id']);
    params.push(req.query.target_type);
    clauses.push(`r.target_type = $${params.length}`);
    params.push(req.query.target_id);
    clauses.push(`r.target_id = $${params.length}`);
  }
  if (req.query.rating) {
    params.push(req.query.rating);
    clauses.push(`r.rating = $${params.length}`);
  }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT r.*, u.full_name AS customer_name
       FROM reviews r
       LEFT JOIN users u ON u.id = r.customer_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY r.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows, hasMore: rows.length === limit });
}));

const REVIEW_WINDOW_DAYS = 3;

/** target_id có thực sự thuộc về đơn này không — chặn khách đánh giá nhầm/khống 1 cửa
 * hàng/sản phẩm/tài xế không liên quan tới đơn hàng của họ. */
async function assertTargetBelongsToOrder(order, targetType, targetId) {
  if (targetType === 'merchant') {
    if (order.merchant_id !== targetId) {
      throw new ApiError('BAD_REQUEST', 'Cửa hàng này không thuộc đơn hàng', 400);
    }
  } else if (targetType === 'driver') {
    const delivery = await db.queryOne(
      'SELECT 1 FROM deliveries WHERE order_id = $1 AND driver_id = $2', [order.id, targetId]
    );
    if (!delivery) throw new ApiError('BAD_REQUEST', 'Tài xế này không thuộc đơn hàng', 400);
  } else if (targetType === 'product') {
    const item = await db.queryOne(
      `SELECT 1 FROM order_items oi
         JOIN product_variants pv ON pv.id = oi.variant_id
        WHERE oi.order_id = $1 AND pv.product_id = $2`,
      [order.id, targetId]
    );
    if (!item) throw new ApiError('BAD_REQUEST', 'Sản phẩm này không thuộc đơn hàng', 400);
  } else {
    throw new ApiError('BAD_REQUEST', 'target_type không hợp lệ', 400);
  }
}

/** Chỉ được đánh giá khi đã có đơn thật, đơn đã delivered/completed, và trong vòng
 * REVIEW_WINDOW_DAYS ngày kể từ lúc giao — quá hạn thì ẩn hẳn màn đánh giá phía khách,
 * chặn luôn ở server phòng khách gọi thẳng API. */
router.post('/reviews', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['order_id', 'target_type', 'target_id', 'rating']);
  const order = await db.findById('orders', req.body.order_id);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  if (order.customer_id !== req.ctx.userId) throw new ApiError('FORBIDDEN', 'Không phải đơn của bạn', 403);
  if (!['delivered', 'completed'].includes(order.status)) {
    throw new ApiError('BAD_REQUEST', 'Chỉ đánh giá được sau khi đơn đã giao', 400);
  }
  if (order.delivered_at) {
    const deadline = new Date(order.delivered_at).getTime() + REVIEW_WINDOW_DAYS * 24 * 60 * 60 * 1000;
    if (Date.now() > deadline) {
      throw new ApiError('BAD_REQUEST', `Đã quá ${REVIEW_WINDOW_DAYS} ngày kể từ lúc giao hàng, không thể đánh giá nữa`, 400);
    }
  }
  if (req.body.rating < 1 || req.body.rating > 5) {
    throw new ApiError('BAD_REQUEST', 'rating phải từ 1 đến 5', 400);
  }
  await assertTargetBelongsToOrder(order, req.body.target_type, req.body.target_id);

  let created;
  try {
    created = await db.insertRow('reviews', {
      order_id: req.body.order_id,
      customer_id: req.ctx.userId,
      target_type: req.body.target_type,
      target_id: req.body.target_id,
      rating: req.body.rating,
      comment: req.body.comment || null,
      media_urls: req.body.media_urls || []
    });
  } catch (e) {
    if (e.code === '23505') throw new ApiError('CONFLICT', 'Bạn đã đánh giá mục này rồi', 409);
    throw e;
  }
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
