require('dotenv').config();

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Thiếu biến môi trường ${name} — xem .env.example`);
  }
  return value;
}

module.exports = {
  port: process.env.PORT || 3000,
  isProd: process.env.NODE_ENV === 'production',
  databaseUrl: required('DATABASE_URL'),
  // Dùng để lấy JWKS (khoá công khai) của Supabase xác minh JWT — xem middleware/auth.js.
  // Từ khi Supabase chuyển sang "JWT Signing Keys" (ký bất đối xứng ES256), verify bằng
  // 1 secret dùng chung (SUPABASE_JWT_SECRET, kiểu HS256 cũ) không còn đúng cho token mới nữa.
  supabaseUrl: required('SUPABASE_URL').replace(/\/+$/, ''),
  // Service Role key (KHÔNG PHẢI anon key) — chỉ dùng ở supabaseAdmin.js để admin tạo thẳng
  // tài khoản chủ cửa hàng hoàn toàn mới (Admin API: auth.admin.createUser). Không dùng
  // required() — server vẫn phải chạy được khi chưa cấu hình, chỉ luồng đó báo lỗi rõ ràng.
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || null,
  paymentWebhookSecret: process.env.PAYMENT_WEBHOOK_SECRET || null,
  // Không dùng required() — server vẫn phải chạy được khi chưa cấu hình Cloudinary,
  // chỉ route /uploads/cloudinary-signature báo lỗi rõ ràng nếu thiếu.
  cloudinaryCloudName: process.env.CLOUDINARY_CLOUD_NAME || null,
  cloudinaryApiKey: process.env.CLOUDINARY_API_KEY || null,
  cloudinaryApiSecret: process.env.CLOUDINARY_API_SECRET || null,
  // Không dùng required() — server vẫn phải chạy được khi chưa cấu hình Firebase,
  // chỉ việc gửi push cho tài xế sẽ tự bỏ qua (xem push.js) tới khi được cấu hình.
  firebaseServiceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON || null,
  internalSweepSecret: process.env.INTERNAL_SWEEP_SECRET || null
};
