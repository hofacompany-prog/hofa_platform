const { ApiError } = require('./errors');
const db = require('./db');

function pickFields(obj, fields) {
  const out = {};
  fields.forEach((f) => {
    if (obj[f] !== undefined) out[f] = obj[f];
  });
  return out;
}

function requireFields(obj, fields) {
  const missing = fields.filter((f) => obj[f] === undefined || obj[f] === null || obj[f] === '');
  if (missing.length) {
    throw new ApiError('BAD_REQUEST', 'Thiếu tham số: ' + missing.join(', '), 400);
  }
}

function pagination(query) {
  const limit = Math.min(parseInt(query.limit, 10) || 20, 100);
  const offset = parseInt(query.offset, 10) || 0;
  return { limit, offset };
}

function requireAuth(ctx) {
  if (!ctx || !ctx.authenticated) {
    throw new ApiError('UNAUTHORIZED', 'Cần đăng nhập (thiếu hoặc sai access token)', 401);
  }
}

/** Từ migration 90 (hofa-db/90_multi_role_accounts.sql): đã đăng nhập (authenticated=true)
 * KHÔNG còn đồng nghĩa đã có hồ sơ (ctx.userId có thể null — SĐT có tài khoản Auth ở role khác
 * nhưng chưa /me/sync cho scope hiện tại, xem middleware/auth.js). Mọi route dùng ctx.userId
 * làm khoá ngoại (insert/update/query WHERE user_id = ...) PHẢI gọi hàm này thay vì requireAuth
 * trần — thiếu bước này từng gây lỗi 500 thô "null value in column violates not-null constraint"
 * (vd POST /devices) thay vì báo rõ "chưa có hồ sơ". CHỈ 2 route thật sự cần chấp nhận userId
 * null (GET /me, POST /me/sync) mới được giữ requireAuth trần. */
function requireProfile(ctx) {
  requireAuth(ctx);
  if (!ctx.userId) {
    throw new ApiError('PROFILE_NOT_FOUND', 'Đã đăng nhập nhưng chưa có hồ sơ — gọi POST /me/sync trước', 404);
  }
}

function requireRole(ctx, roles) {
  requireAuth(ctx);
  if (!roles.includes(ctx.role)) {
    throw new ApiError('FORBIDDEN', 'Chức năng này chỉ dành cho: ' + roles.join(', '), 403);
  }
}

async function requireOwnRow(table, id, userId, ownerField) {
  if (!id) throw new ApiError('BAD_REQUEST', 'Thiếu id', 400);
  const row = await db.findById(table, id);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy dữ liệu', 404);
  if (row[ownerField] !== userId) throw new ApiError('FORBIDDEN', 'Dữ liệu này không thuộc về bạn', 403);
  return row;
}

/** admin luôn qua; merchant_owner phải là chủ; merchant_staff phải có trong merchant_staff. */
async function requireMerchantAccess(ctx, merchantId) {
  requireAuth(ctx);
  if (ctx.role === 'admin') return true;

  if (ctx.role === 'merchant_owner') {
    const merchant = await db.queryOne('SELECT id, owner_id FROM merchants WHERE id = $1', [merchantId]);
    if (merchant && merchant.owner_id === ctx.userId) return true;
  }
  if (ctx.role === 'merchant_owner' || ctx.role === 'merchant_staff') {
    const staff = await db.queryOne(
      'SELECT id FROM merchant_staff WHERE merchant_id = $1 AND user_id = $2',
      [merchantId, ctx.userId]
    );
    if (staff) return true;
  }
  throw new ApiError('FORBIDDEN', 'Bạn không có quyền quản lý cửa hàng này', 403);
}

/** admin/merchant_owner (đúng chủ) luôn qua; merchant_staff phải có đúng [permission] trong
 * merchant_staff.permissions mới qua — dùng cho action nhạy cảm (sửa/xoá sản phẩm, đổi trạng
 * thái đơn, xem tài chính, điều chỉnh tồn kho...). requireMerchantAccess vẫn chạy trước để
 * xác nhận có thuộc cửa hàng này không, hàm này chỉ xiết thêm riêng cho merchant_staff. */
async function requirePermission(ctx, merchantId, permission) {
  await requireMerchantAccess(ctx, merchantId);
  if (ctx.role !== 'merchant_staff') return true;
  const staff = await db.queryOne(
    'SELECT permissions FROM merchant_staff WHERE merchant_id = $1 AND user_id = $2',
    [merchantId, ctx.userId]
  );
  const perms = staff?.permissions || [];
  if (!perms.includes(permission)) {
    throw new ApiError('FORBIDDEN', 'Bạn không có quyền thực hiện thao tác này', 403);
  }
  return true;
}

/** Chỉ chủ cửa hàng thật sự (owner_id đúng) hoặc admin — merchant_staff KHÔNG được quản lý
 * nhân viên khác dù có quyền gì đi nữa, đây là hành động chỉ chủ cửa hàng mới làm. */
async function requireOwnerAccess(ctx, merchantId) {
  requireAuth(ctx);
  if (ctx.role === 'admin') return true;
  const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [merchantId]);
  if (merchant && merchant.owner_id === ctx.userId) return true;
  throw new ApiError('FORBIDDEN', 'Chỉ chủ cửa hàng mới quản lý được nhân viên', 403);
}

async function orderCanView(ctx, order) {
  if (!ctx.authenticated) return false;
  if (ctx.role === 'admin') return true;
  if (order.customer_id === ctx.userId) return true;

  if (ctx.role === 'merchant_owner' || ctx.role === 'merchant_staff') {
    try {
      await requireMerchantAccess(ctx, order.merchant_id);
      return true;
    } catch (e) { /* không có quyền merchant, thử tiếp */ }
  }
  if (ctx.role === 'driver') {
    const delivery = await db.queryOne('SELECT driver_id FROM deliveries WHERE order_id = $1', [order.id]);
    const driver = await db.queryOne('SELECT id FROM drivers WHERE user_id = $1', [ctx.userId]);
    if (delivery && driver && delivery.driver_id === driver.id) return true;
  }
  return false;
}

async function requireOrderAccess(ctx, orderId) {
  requireAuth(ctx);
  const order = await db.findById('orders', orderId);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  if (!(await orderCanView(ctx, order))) throw new ApiError('FORBIDDEN', 'Bạn không có quyền xem đơn này', 403);
  return order;
}

/** Công thức haversine tính km bằng SQL — dùng chung cho GET /merchants, /merchants/:id,
 * /products (xem merchants.js, products.js). latParam/lngParam là vị trí tham số ($n) trong
 * mảng params truyền vào, branchAlias là alias bảng branches trong câu SQL đang viết (mặc định
 * 'b') — LEAST/GREATEST kẹp trong [-1,1] để tránh acos() lỗi domain vì sai số dấu phẩy động. */
function haversineKmSql(latParam, lngParam, branchAlias = 'b') {
  return `6371 * acos(LEAST(1, GREATEST(-1,
    cos(radians($${latParam})) * cos(radians(${branchAlias}.latitude)) * cos(radians(${branchAlias}.longitude) - radians($${lngParam}))
    + sin(radians($${latParam})) * sin(radians(${branchAlias}.latitude))
  )))`;
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** ?lat=&lng= tuỳ chọn — dùng ở GET /merchants, /merchants/:id, /products để tính khoảng cách
 * tới khách (toạ độ địa chỉ mặc định, xem hofa_customer_app/lib/providers/app_providers.dart#
 * customerCoordsProvider). Trả null nếu thiếu/không phải số — không phải lỗi, chỉ đơn giản là
 * bỏ qua phần khoảng cách. */
function parseLatLng(query) {
  const lat = query.lat !== undefined ? Number(query.lat) : null;
  const lng = query.lng !== undefined ? Number(query.lng) : null;
  if (lat == null || lng == null || Number.isNaN(lat) || Number.isNaN(lng)) return null;
  return { lat, lng };
}

module.exports = {
  pickFields, requireFields, pagination,
  requireAuth, requireProfile, requireRole, requireOwnRow, requireMerchantAccess,
  requirePermission, requireOwnerAccess,
  orderCanView, requireOrderAccess, haversineKm, haversineKmSql, parseLatLng
};
