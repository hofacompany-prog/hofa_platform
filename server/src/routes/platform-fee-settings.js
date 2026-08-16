const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { pickFields, requireFields, requireRole } = require('../utils');

const SETTINGS_FIELDS = ['fee_basis'];
const TIER_FIELDS = ['min_threshold', 'max_threshold', 'fee_type', 'fee_fixed_amount', 'fee_percent'];

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at, cùng pattern
 * delivery_radius_settings/voucher_settings. */
async function currentSettings() {
  return db.queryOne('SELECT * FROM platform_buy_on_behalf_fee_settings ORDER BY updated_at DESC LIMIT 1');
}

// Công khai (không cần đăng nhập) — không phải dữ liệu nhạy cảm, chỉ là cấu hình mặc định.
router.get('/platform-fee-settings', asyncHandler(async (req, res) => {
  const [settings, tiers] = await Promise.all([
    currentSettings(),
    db.query('SELECT * FROM platform_buy_on_behalf_fee_tiers ORDER BY min_threshold ASC')
  ]);
  res.json({ ok: true, data: { settings, tiers } });
}));

router.patch('/platform-fee-settings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await currentSettings();
  const data = { ...pickFields(req.body, SETTINGS_FIELDS), updated_at: new Date().toISOString(), updated_by: req.ctx.userId };
  const updated = existing
    ? await db.updateById('platform_buy_on_behalf_fee_settings', existing.id, data)
    : await db.insertRow('platform_buy_on_behalf_fee_settings', data);
  res.json({ ok: true, data: updated });
}));

router.post('/platform-fee-tiers', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['min_threshold', 'fee_type']);
  const created = await db.insertRow('platform_buy_on_behalf_fee_tiers', pickFields(req.body, TIER_FIELDS));
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/platform-fee-tiers/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('platform_buy_on_behalf_fee_tiers', req.params.id, pickFields(req.body, TIER_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/platform-fee-tiers/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  await db.deleteById('platform_buy_on_behalf_fee_tiers', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
