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
  paymentWebhookSecret: process.env.PAYMENT_WEBHOOK_SECRET || null
};
