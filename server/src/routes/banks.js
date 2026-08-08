const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, requireRole } = require('../utils');

const BANK_FIELDS = ['name', 'bin', 'sort_order'];

/** Danh sách ngân hàng (tên + mã BIN chuẩn VietQR) — công khai, app tài xế dùng cho dropdown
 * chọn ngân hàng lúc đăng ký/sửa hồ sơ. Chỉ admin thêm/sửa/xoá. */
router.get('/banks', asyncHandler(async (req, res) => {
  const rows = await db.query('SELECT * FROM banks ORDER BY sort_order ASC, name ASC');
  res.json({ ok: true, data: rows });
}));

router.post('/banks', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['name', 'bin']);
  const created = await db.insertRow('banks', pickFields(req.body, BANK_FIELDS));
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/banks/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('banks', req.params.id, pickFields(req.body, BANK_FIELDS));
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy ngân hàng', 404);
  res.json({ ok: true, data: updated });
}));

router.delete('/banks/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deleted = await db.deleteById('banks', req.params.id);
  if (!deleted) throw new ApiError('NOT_FOUND', 'Không tìm thấy ngân hàng', 404);
  res.json({ ok: true, data: deleted });
}));

module.exports = router;
