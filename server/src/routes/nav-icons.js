const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireRole } = require('../utils');

const APPS = ['admin', 'customer', 'store', 'driver'];

/** Icon tabbar tuỳ chỉnh của 4 app — công khai, mỗi app tự gọi lúc khởi động (kể cả chưa đăng
 * nhập) để biết tab nào đang có icon tuỳ chỉnh. ?app= lọc đúng 1 app cho gọn payload. */
router.get('/nav-icons', asyncHandler(async (req, res) => {
  const app = req.query.app;
  const rows = app
    ? await db.query('SELECT app, tab_key, icon_url FROM nav_tab_icons WHERE app = $1', [app])
    : await db.query('SELECT app, tab_key, icon_url FROM nav_tab_icons');
  res.json({ ok: true, data: rows });
}));

/** Đặt/xoá icon cho 1 tab — chỉ admin. icon_url = null (hoặc rỗng) thì xoá dòng, tab đó quay
 * lại dùng icon Material mặc định trong code của app. */
router.put('/nav-icons/:app/:tabKey', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { app, tabKey } = req.params;
  if (!APPS.includes(app)) throw new ApiError('BAD_REQUEST', 'app không hợp lệ', 400);

  const iconUrl = typeof req.body.icon_url === 'string' && req.body.icon_url.trim()
    ? req.body.icon_url.trim() : null;

  if (iconUrl === null) {
    await db.query('DELETE FROM nav_tab_icons WHERE app = $1 AND tab_key = $2', [app, tabKey]);
    return res.json({ ok: true, data: null });
  }

  const existing = await db.queryOne(
    'SELECT id FROM nav_tab_icons WHERE app = $1 AND tab_key = $2',
    [app, tabKey]
  );
  const row = existing
    ? await db.updateById('nav_tab_icons', existing.id, { icon_url: iconUrl, updated_by: req.ctx.userId })
    : await db.insertRow('nav_tab_icons', { app, tab_key: tabKey, icon_url: iconUrl, updated_by: req.ctx.userId });
  res.json({ ok: true, data: row });
}));

module.exports = router;
