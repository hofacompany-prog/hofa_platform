const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireRole } = require('../utils');

const FIELDS = ['min_build_number', 'ios_store_url', 'android_store_url'];
const VALID_SCOPES = ['customer', 'driver', 'merchant'];

/** App native gọi lúc mở app (kể cả chưa đăng nhập) để biết có cần ép cập nhật không — đọc
 * THẲNG header, không dùng req.ctx.appScope vì middleware/auth.js chỉ gán giá trị đó khi request
 * có kèm Access Token; request chưa đăng nhập vẫn phải kiểm tra được (chặn ngay từ màn đăng nhập
 * nếu app quá cũ), header X-App-Scope vẫn luôn được ApiClient gửi bất kể đã đăng nhập hay chưa. */
router.get('/app-update-settings', asyncHandler(async (req, res) => {
  const appScope = req.headers['x-app-scope'];
  if (!VALID_SCOPES.includes(appScope)) {
    throw new ApiError('BAD_REQUEST', 'Thiếu hoặc sai định danh ứng dụng (X-App-Scope)', 400);
  }
  const row = await db.queryOne('SELECT * FROM app_update_settings WHERE app_scope = $1', [appScope]);
  res.json({ ok: true, data: row });
}));

router.get('/admin/app-update-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const rows = await db.query('SELECT * FROM app_update_settings ORDER BY app_scope');
  res.json({ ok: true, data: rows });
}));

router.patch('/admin/app-update-settings/:appScope', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  if (!VALID_SCOPES.includes(req.params.appScope)) {
    throw new ApiError('BAD_REQUEST', 'app_scope không hợp lệ', 400);
  }
  const existing = await db.queryOne(
    'SELECT id FROM app_update_settings WHERE app_scope = $1',
    [req.params.appScope]
  );
  const data = {
    ...pickFields(req.body, FIELDS),
    updated_at: new Date().toISOString(),
    updated_by: req.ctx.userId
  };
  const updated = existing
    ? await db.updateById('app_update_settings', existing.id, data)
    : await db.insertRow('app_update_settings', { app_scope: req.params.appScope, ...data });
  res.json({ ok: true, data: updated });
}));

module.exports = router;
