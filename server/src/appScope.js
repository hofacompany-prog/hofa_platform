/** "Phạm vi app" gửi qua header X-App-Scope — mỗi app (Khách/Tài xế/Cửa hàng/Admin) chỉ được
 * thấy đúng (những) role tương ứng của chính nó trên cùng 1 SĐT, xem middleware/auth.js. */
const SCOPE_ROLES = {
  customer: ['customer'],
  driver: ['driver'],
  merchant: ['merchant_owner', 'merchant_staff'],
  admin: ['admin'],
};

/** Role mặc định khi tự đăng ký hồ sơ mới (POST /me/sync) cho từng scope — merchant luôn tạo
 * chủ mới (merchant_staff chỉ được tạo qua POST /merchants/:id/staff bởi chủ, không tự đăng ký). */
const SCOPE_DEFAULT_ROLE = {
  customer: 'customer',
  driver: 'driver',
  merchant: 'merchant_owner',
  admin: 'admin',
};

module.exports = { SCOPE_ROLES, SCOPE_DEFAULT_ROLE };
