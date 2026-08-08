const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, haversineKm } = require('../utils');
const push = require('../push');

const DRIVER_PROFILE_FIELDS = [
  'national_id', 'license_no', 'license_expiry', 'vehicle_type', 'vehicle_plate',
  'vehicle_capacity_kg', 'document_urls', 'bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder'
];

async function requireOwnDriverRow(ctx) {
  requireRole(ctx, ['driver']);
  const driver = await db.queryOne('SELECT * FROM drivers WHERE user_id = $1', [ctx.userId]);
  if (!driver) throw new ApiError('NOT_FOUND', 'Bạn chưa có hồ sơ tài xế', 404);
  return driver;
}

router.get('/drivers/me', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  const row = await db.queryOne('SELECT * FROM drivers WHERE user_id = $1', [req.ctx.userId]);
  res.json({ ok: true, data: row });
}));

router.post('/drivers/register', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, [
    'national_id', 'license_no', 'vehicle_type', 'vehicle_plate',
    'bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder'
  ]);

  const existing = await db.queryOne('SELECT id FROM drivers WHERE user_id = $1', [req.ctx.userId]);
  if (existing) throw new ApiError('CONFLICT', 'Bạn đã có hồ sơ tài xế', 409);

  const data = pickFields(req.body, DRIVER_PROFILE_FIELDS);
  data.user_id = req.ctx.userId;
  const driver = await db.insertRow('drivers', data);
  await db.query(`UPDATE users SET role = 'driver' WHERE id = $1 AND role = 'customer'`, [req.ctx.userId]);
  res.status(201).json({ ok: true, data: driver });
}));

/** Tài xế tự sửa hồ sơ (kể cả sau khi bị admin từ chối) — nếu hồ sơ đang ở trạng thái bị từ
 * chối, sửa/nộp lại coi như đã khắc phục nên tự xoá rejected_at/rejection_reason, đưa hồ sơ về
 * lại "đang chờ xét duyệt" mà không cần admin thao tác gì thêm. */
router.patch('/drivers/me', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  const driver = await db.queryOne('SELECT id, rejected_at FROM drivers WHERE user_id = $1', [req.ctx.userId]);
  if (!driver) throw new ApiError('NOT_FOUND', 'Bạn chưa có hồ sơ tài xế', 404);

  const data = pickFields(req.body, DRIVER_PROFILE_FIELDS);
  if (driver.rejected_at) {
    data.rejected_at = null;
    data.rejection_reason = null;
  }
  const updated = await db.updateById('drivers', driver.id, data);
  res.json({ ok: true, data: updated });
}));

router.patch('/drivers/me/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  requireFields(req.body, ['status']); // offline | online | busy | on_break
  const rows = await db.query(
    'UPDATE drivers SET status = $1 WHERE user_id = $2 RETURNING *',
    [req.body.status, req.ctx.userId]
  );
  res.json({ ok: true, data: rows[0] });
}));

router.patch('/drivers/me/auto-accept', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  requireFields(req.body, ['auto_accept']);
  const rows = await db.query(
    'UPDATE drivers SET auto_accept = $1 WHERE user_id = $2 RETURNING *',
    [!!req.body.auto_accept, req.ctx.userId]
  );
  res.json({ ok: true, data: rows[0] });
}));

router.patch('/drivers/me/location', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  requireFields(req.body, ['latitude', 'longitude']);
  await db.query(
    'UPDATE drivers SET current_latitude = $1, current_longitude = $2, location_updated_at = now() WHERE user_id = $3',
    [req.body.latitude, req.body.longitude, req.ctx.userId]
  );
  res.json({ ok: true, data: { updated: true } });
}));

/** Danh sách tài xế online, sắp theo khoảng cách gần nhất tới 1 toạ độ (vd: chi nhánh) — dùng
 * cho merchant/admin gán tay LẪN khách tự chọn tài xế ở đơn mua hộ (buy_on_behalf), nên chỉ
 * chọn đúng các cột hiển thị được công khai (tên, ảnh, đánh giá, loại xe) — không bao giờ trả
 * national_id/license_no/wallet_balance/document_urls dù ai gọi. exclude= loại bớt tài xế đã
 * từ chối đơn này (dùng lúc khách chọn lại sau khi tài xế trước từ chối/hết hạn). */
router.get('/drivers/available', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const excludeIds = typeof req.query.exclude === 'string' && req.query.exclude.trim()
    ? req.query.exclude.split(',').map((s) => s.trim()).filter(Boolean)
    : [];
  const drivers = await db.query(
    `SELECT d.id, d.status, d.current_latitude, d.current_longitude, d.vehicle_type, d.vehicle_plate,
            d.rating_avg, d.rating_count, u.full_name, u.avatar_url
       FROM drivers d
       JOIN users u ON u.id = d.user_id
      WHERE d.status = 'online' AND d.id <> ALL($1::uuid[])`,
    [excludeIds]
  );
  if (req.query.latitude !== undefined && req.query.longitude !== undefined) {
    const lat = parseFloat(req.query.latitude), lon = parseFloat(req.query.longitude);
    drivers.forEach((d) => {
      d.distance_km = d.current_latitude != null ? haversineKm(lat, lon, d.current_latitude, d.current_longitude) : null;
    });
    drivers.sort((a, b) => (a.distance_km ?? 1e9) - (b.distance_km ?? 1e9));
  }
  const { limit } = pagination(req.query);
  res.json({ ok: true, data: drivers.slice(0, limit) });
}));

router.get('/drivers/me/earnings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  const driver = await db.queryOne(
    'SELECT wallet_balance, total_deliveries, rating_avg, rating_count, id FROM drivers WHERE user_id = $1',
    [req.ctx.userId]
  );
  const { limit } = pagination(req.query);
  const recent = await db.query(
    `SELECT driver_fee, delivered_at FROM deliveries WHERE driver_id = $1 AND status = 'delivered' ORDER BY delivered_at DESC LIMIT $2`,
    [driver.id, limit]
  );
  res.json({ ok: true, data: { summary: driver, recent_deliveries: recent } });
}));

// ---- Ví tài xế: nạp/rút tiền ----

/** Yêu cầu nạp tiền — chỉ tạo dòng 'pending', KHÔNG cộng wallet_balance ngay (đợi admin xác
 * nhận đã nhận được chuyển khoản ở tab Thanh toán). App tài xế tự dựng QR chuyển khoản từ
 * GET /bank-account-settings (tài khoản của sàn) + amount trả về ở đây. */
router.post('/drivers/me/wallet/deposits', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  requireFields(req.body, ['amount']);
  const amount = Number(req.body.amount);
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new ApiError('BAD_REQUEST', 'Số tiền nạp không hợp lệ', 400);
  }
  const created = await db.insertRow('driver_wallet_deposits', { driver_id: driver.id, amount });
  res.status(201).json({ ok: true, data: created });
}));

/** Yêu cầu rút tiền — trừ wallet_balance NGAY (atomic, guard luôn trong cùng câu UPDATE để
 * chặn 2 yêu cầu chạy song song cùng vượt số dư thật) thay vì đợi admin duyệt, tránh tài xế
 * tạo nhiều yêu cầu rút vượt số dư trước khi admin kịp xử lý. Admin từ chối thì hoàn lại tiền
 * (xem POST /admin/wallet-withdrawals/:id/reject). Bắt buộc đã có thông tin ngân hàng vì admin
 * cần đó để chuyển khoản trả lại. */
router.post('/drivers/me/wallet/withdrawals', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  requireFields(req.body, ['amount']);
  const amount = Number(req.body.amount);
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new ApiError('BAD_REQUEST', 'Số tiền rút không hợp lệ', 400);
  }
  if (!driver.bank_bin || !driver.bank_account_number) {
    throw new ApiError('BANK_INFO_REQUIRED', 'Cần cập nhật thông tin ngân hàng trước khi rút tiền', 400);
  }
  const settings = await db.queryOne('SELECT min_withdrawal_balance FROM bank_account_settings ORDER BY updated_at DESC LIMIT 1');
  const minBalance = settings?.min_withdrawal_balance ?? 0;

  const debited = await db.queryOne(
    `UPDATE drivers SET wallet_balance = wallet_balance - $1
      WHERE id = $2 AND wallet_balance - $1 >= $3
      RETURNING wallet_balance`,
    [amount, driver.id, minBalance]
  );
  if (!debited) {
    throw new ApiError('INSUFFICIENT_BALANCE', 'Số dư không đủ để rút số tiền này', 409);
  }
  const created = await db.insertRow('driver_wallet_withdrawals', { driver_id: driver.id, amount });
  res.status(201).json({ ok: true, data: created });
}));

router.get('/admin/drivers', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM drivers ${where} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** Admin sửa trực tiếp hồ sơ tài xế (CCCD, GPLX, xe, ngân hàng) — không đụng verified_at/
 * rejected_at, dùng khi tài xế nhờ admin chỉnh hộ thay vì tự sửa/nộp lại qua PATCH /drivers/me. */
router.patch('/admin/drivers/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const data = pickFields(req.body, DRIVER_PROFILE_FIELDS);
  const updated = await db.updateById('drivers', req.params.id, data);
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài xế', 404);
  res.json({ ok: true, data: updated });
}));

router.post('/admin/drivers/:id/verify', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('drivers', req.params.id, {
    verified_at: new Date().toISOString(),
    rejected_at: null,
    rejection_reason: null
  });
  res.json({ ok: true, data: updated });
}));

/** Từ chối hồ sơ — kèm lý do (dropdown mẫu hoặc gõ tay ở web admin). Tài xế nhận push, sửa/nộp
 * lại hồ sơ ở PATCH /drivers/me sẽ tự xoá rejected_at, đưa hồ sơ về lại "đang chờ xét duyệt". */
router.post('/admin/drivers/:id/reject', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['reason']);
  const updated = await db.updateById('drivers', req.params.id, {
    rejected_at: new Date().toISOString(),
    rejection_reason: req.body.reason,
    verified_at: null
  });
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài xế', 404);
  push.notifyDriverRejected(req.params.id, req.body.reason).catch((err) => {
    console.error('[push] Không báo được cho tài xế về việc từ chối hồ sơ', req.params.id, err.message);
  });
  res.json({ ok: true, data: updated });
}));

// ---- Admin duyệt yêu cầu nạp/rút ví tài xế ----

router.get('/admin/wallet-deposits', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`wd.status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT wd.*, u.full_name AS driver_name, u.phone AS driver_phone
       FROM driver_wallet_deposits wd
       JOIN drivers d ON d.id = wd.driver_id
       JOIN users u ON u.id = d.user_id
      ${where}
      ORDER BY wd.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.post('/admin/wallet-deposits/:id/confirm', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deposit = await db.queryOne(`SELECT * FROM driver_wallet_deposits WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!deposit) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu nạp tiền đang chờ', 404);

  const updated = await db.updateById('driver_wallet_deposits', req.params.id, {
    status: 'confirmed',
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  await db.query('UPDATE drivers SET wallet_balance = wallet_balance + $1 WHERE id = $2', [deposit.amount, deposit.driver_id]);
  push.notifyDriverWallet(deposit.driver_id, 'deposit_confirmed', deposit.amount).catch(() => {});
  res.json({ ok: true, data: updated });
}));

router.get('/admin/wallet-withdrawals', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`ww.status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT ww.*, u.full_name AS driver_name, u.phone AS driver_phone,
            d.bank_name, d.bank_bin, d.bank_account_number, d.bank_account_holder
       FROM driver_wallet_withdrawals ww
       JOIN drivers d ON d.id = ww.driver_id
       JOIN users u ON u.id = d.user_id
      ${where}
      ORDER BY ww.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** Admin xác nhận ĐÃ chuyển khoản trả tài xế — tiền đã bị trừ khỏi ví từ lúc tài xế tạo yêu
 * cầu (xem POST /drivers/me/wallet/withdrawals), nên ở đây chỉ đánh dấu xong, không đụng
 * wallet_balance nữa. */
router.post('/admin/wallet-withdrawals/:id/confirm', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const withdrawal = await db.queryOne(`SELECT * FROM driver_wallet_withdrawals WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!withdrawal) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu rút tiền đang chờ', 404);

  const updated = await db.updateById('driver_wallet_withdrawals', req.params.id, {
    status: 'confirmed',
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  push.notifyDriverWallet(withdrawal.driver_id, 'withdrawal_confirmed', withdrawal.amount).catch(() => {});
  res.json({ ok: true, data: updated });
}));

/** Từ chối yêu cầu rút — hoàn lại đúng số tiền đã trừ tạm lúc tài xế tạo yêu cầu. */
router.post('/admin/wallet-withdrawals/:id/reject', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const withdrawal = await db.queryOne(`SELECT * FROM driver_wallet_withdrawals WHERE id = $1 AND status = 'pending'`, [req.params.id]);
  if (!withdrawal) throw new ApiError('NOT_FOUND', 'Không tìm thấy yêu cầu rút tiền đang chờ', 404);

  const updated = await db.updateById('driver_wallet_withdrawals', req.params.id, {
    status: 'rejected',
    reject_reason: req.body.reason || null,
    confirmed_at: new Date().toISOString(),
    confirmed_by: req.ctx.userId
  });
  await db.query('UPDATE drivers SET wallet_balance = wallet_balance + $1 WHERE id = $2', [withdrawal.amount, withdrawal.driver_id]);
  push.notifyDriverWallet(withdrawal.driver_id, 'withdrawal_rejected', withdrawal.amount, req.body.reason).catch(() => {});
  res.json({ ok: true, data: updated });
}));

/** Admin chỉnh tay trạng thái tài xế (offline/online/busy/on_break) — gỡ trường hợp tài xế bị
 * kẹt ở 'busy' (vd app tắt/mất mạng giữa chừng một chuyến, chuyến đã bị xoá/đổi trạng thái ở
 * màn "Chuyến giao hàng" nhưng vì lý do gì đó không tự trả tài xế về online) khiến không nhận
 * được chuyến mới — không đụng gì tới deliveries, chỉ đổi đúng cột status của drivers. */
router.patch('/admin/drivers/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const updated = await db.updateById('drivers', req.params.id, { status: req.body.status });
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài xế', 404);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
