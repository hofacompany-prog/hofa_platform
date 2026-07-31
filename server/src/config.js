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
  jwtSecret: required('SUPABASE_JWT_SECRET'),
  paymentWebhookSecret: process.env.PAYMENT_WEBHOOK_SECRET || null
};
