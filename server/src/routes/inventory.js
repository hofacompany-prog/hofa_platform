const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireAuth, pagination, requireMerchantAccess } = require('../utils');

async function requireBranchAccess(ctx, branchId) {
  const branch = await db.queryOne('SELECT id, merchant_id FROM branches WHERE id = $1', [branchId]);
  if (!branch) throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  await requireMerchantAccess(ctx, branch.merchant_id);
  return branch;
}

router.get('/branches/:branchId/inventory', asyncHandler(async (req, res) => {
  await requireBranchAccess(req.ctx, req.params.branchId);
  const clauses = ['branch_id = $1'];
  const params = [req.params.branchId];
  if (req.query.variant_id) { params.push(req.query.variant_id); clauses.push(`variant_id = $${params.length}`); }
  const rows = await db.query(`SELECT * FROM inventory_available WHERE ${clauses.join(' AND ')}`, params);
  res.json({ ok: true, data: rows });
}));

router.get('/branches/:branchId/inventory/low-stock', asyncHandler(async (req, res) => {
  await requireBranchAccess(req.ctx, req.params.branchId);
  const rows = await db.query(
    'SELECT * FROM inventory_available WHERE branch_id = $1 AND quantity_on_hand <= low_stock_threshold',
    [req.params.branchId]
  );
  res.json({ ok: true, data: rows });
}));

/**
 * Điều chỉnh tồn kho thủ công: nhập hàng, kiểm kê, hư hỏng...
 * move_type: purchase_in | adjustment | transfer_in | transfer_out | return_in | damage_out
 * (sale_out được hệ thống tự ghi lúc tài xế lấy hàng, xem PATCH /deliveries/:id/status)
 */
router.post('/inventory/adjust', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['branch_id', 'variant_id', 'move_type', 'quantity']);
  if (req.body.move_type === 'sale_out') {
    throw new ApiError('BAD_REQUEST', 'sale_out chỉ được ghi tự động khi giao hàng, không gọi tay', 400);
  }
  await requireBranchAccess(req.ctx, req.body.branch_id);

  const result = await db.callRpc('apply_stock_movement', {
    p_branch_id: req.body.branch_id,
    p_variant_id: req.body.variant_id,
    p_move_type: req.body.move_type,
    p_quantity: req.body.quantity,
    p_ref_type: 'manual',
    p_ref_id: null,
    p_user_id: req.ctx.userId,
    p_note: req.body.note || null
  });
  res.json({ ok: true, data: { balance_after: result.apply_stock_movement } });
}));

router.get('/branches/:branchId/stock-movements', asyncHandler(async (req, res) => {
  await requireBranchAccess(req.ctx, req.params.branchId);
  const { limit, offset } = pagination(req.query);
  const clauses = ['branch_id = $1'];
  const params = [req.params.branchId];
  if (req.query.variant_id) { params.push(req.query.variant_id); clauses.push(`variant_id = $${params.length}`); }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM stock_movements WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

module.exports = router;
