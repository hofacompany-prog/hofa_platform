const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const config = require('./config');
const { attachContext } = require('./middleware/auth');
const { ApiError } = require('./errors');
const dispatch = require('./dispatch');
const orderOffer = require('./orderOffer');
const push = require('./push');

const app = express();
app.use(helmet());
app.use(cors()); // API công khai cho app di động/web — không có cookie/session nên CORS mở là an toàn
app.use(morgan(config.isProd ? 'combined' : 'dev'));
app.use(express.json({ limit: '2mb' }));
app.use(attachContext);

app.get('/health', (req, res) => res.json({ ok: true, data: { status: 'up' } }));

app.use('/', require('./routes/admin'));
app.use('/', require('./routes/users'));
app.use('/', require('./routes/merchants'));
app.use('/', require('./routes/products'));
app.use('/', require('./routes/inventory'));
app.use('/', require('./routes/wholesale'));
app.use('/', require('./routes/orders'));
app.use('/', require('./routes/drivers'));
app.use('/', require('./routes/deliveries'));
app.use('/', require('./routes/payments'));
app.use('/', require('./routes/reviews'));
app.use('/', require('./routes/vouchers'));
app.use('/', require('./routes/voucher-settings'));
app.use('/', require('./routes/shipping'));
app.use('/', require('./routes/order-settings'));
app.use('/', require('./routes/admin-notifications'));
app.use('/', require('./routes/notifications'));
app.use('/', require('./routes/notification-settings'));
app.use('/', require('./routes/uploads'));

app.use((req, res) => {
  res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Không có route này' } });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ ok: false, error: { code: err.code, message: err.message } });
  }
  console.error(err);
  res.status(500).json({ ok: false, error: { code: 'INTERNAL_ERROR', message: 'Lỗi hệ thống, thử lại sau' } });
});

app.listen(config.port, () => {
  console.log(`HOFA API đang chạy ở cổng ${config.port}`);
});

// Tự quét các chuyến giao hàng đã gán nhưng tài xế chưa xác nhận (bấm "Nhận đơn") sau
// accept_deadline (25s) và chuyển sang tài xế gần nhất kế tiếp — kể cả khi tài xế im
// lặng không bấm gì (không chỉ khi họ bấm "Từ chối"). Chạy ngay trong process này vì
// Render free plan không có cron job riêng; /internal/sweep-expired-offers vẫn giữ lại
// để gọi tay/debug khi cần.
setInterval(() => {
  dispatch.sweepExpiredOffers().catch((e) => console.error('[sweep-expired-offers]', e));
}, 10_000);

// Tương tự nhưng cho đơn hàng chờ cửa hàng xác nhận (accept_deadline 120s) — quá hạn
// mà không bấm "Nhận đơn" thì tự huỷ, vì không có "cửa hàng khác" để chuyển sang.
setInterval(() => {
  orderOffer.sweepExpiredOrderOffers().catch((e) => console.error('[sweep-expired-order-offers]', e));
}, 10_000);

// Tự dọn hộp thư thông báo theo notification_settings.ttl_hours (admin cấu hình ở web admin,
// mục Thông báo > Hộp thư theo cửa hàng) — không cấp bách như 2 sweep trên nên quét thưa hơn
// nhiều, mỗi giờ 1 lần là đủ.
setInterval(() => {
  push.sweepOldNotifications().catch((e) => console.error('[sweep-old-notifications]', e));
}, 60 * 60 * 1000);
