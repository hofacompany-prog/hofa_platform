const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['name', 'sort_order'];

// Công khai (không cần đăng nhập) — app khách cần đọc để hiện viên nang lọc ở trang chủ, app
// cửa hàng/admin cần đọc để hiện danh sách chọn lúc tạo/sửa cửa hàng.
router.get('/merchant-classifications', asyncHandler(async (req, res) => {
  const rows = await db.query(
    'SELECT * FROM merchant_classifications ORDER BY sort_order ASC, name ASC'
  );
  res.json({ ok: true, data: rows });
}));

router.post('/merchant-classifications', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const data = pickFields(req.body, FIELDS);
  if (!data.name || !String(data.name).trim()) {
    throw new ApiError('BAD_REQUEST', 'Tên phân loại không được để trống', 400);
  }
  const created = await db.insertRow('merchant_classifications', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/merchant-classifications/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('merchant_classifications', req.params.id, pickFields(req.body, FIELDS));
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy phân loại', 404);
  res.json({ ok: true, data: updated });
}));

router.delete('/merchant-classifications/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deleted = await db.deleteById('merchant_classifications', req.params.id);
  if (!deleted) throw new ApiError('NOT_FOUND', 'Không tìm thấy phân loại', 404);
  res.json({ ok: true, data: deleted });
}));

module.exports = router;
