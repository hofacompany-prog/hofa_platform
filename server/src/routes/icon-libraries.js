const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireRole, requireFields } = require('../utils');

/** Thư viện Iconify admin đã bật để tìm icon online ở màn Icon tabbar — chỉ admin dùng
 * (không liên quan tới 3 app khách/cửa hàng/tài xế), nên cả đọc lẫn ghi đều yêu cầu đăng
 * nhập admin, khác /nav-icons (GET công khai). */
router.get('/icon-libraries', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const rows = await db.query('SELECT prefix, name FROM icon_libraries ORDER BY name ASC');
  res.json({ ok: true, data: rows });
}));

router.post('/icon-libraries', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['prefix', 'name']);
  const existing = await db.queryOne('SELECT id FROM icon_libraries WHERE prefix = $1', [req.body.prefix]);
  if (existing) return res.json({ ok: true, data: existing });
  const created = await db.insertRow('icon_libraries', {
    prefix: String(req.body.prefix).trim(),
    name: String(req.body.name).trim()
  });
  res.status(201).json({ ok: true, data: created });
}));

router.delete('/icon-libraries/:prefix', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deleted = await db.query('DELETE FROM icon_libraries WHERE prefix = $1 RETURNING id', [req.params.prefix]);
  if (!deleted.length) throw new ApiError('NOT_FOUND', 'Không tìm thấy thư viện', 404);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
