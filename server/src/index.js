const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const config = require('./config');
const { attachContext } = require('./middleware/auth');
const { ApiError } = require('./errors');
const dispatch = require('./dispatch');
const push = require('./push');
const orderOffer = require('./orderOffer');

const app = express();
app.use(helmet());
app.use(cors()); // API công khai cho app di động/web — không có cookie/session nên CORS mở là an toàn
app.use(morgan(config.isProd ? 'combined' : 'dev'));
app.use(express.json({ limit: '2mb' }));
app.use(attachContext);

app.get('/health', (req, res) => res.json({ ok: true, data: { status: 'up' } }));

app.use('/', require('./routes/auth'));
app.use('/', require('./routes/admin'));
app.use('/', require('./routes/users'));
app.use('/', require('./routes/merchants'));
app.use('/', require('./routes/merchant-classifications'));
app.use('/', require('./routes/merchant-wallet'));
app.use('/', require('./routes/products'));
app.use('/', require('./routes/inventory'));
app.use('/', require('./routes/wholesale'));
app.use('/', require('./routes/orders'));
app.use('/', require('./routes/drivers'));
app.use('/', require('./routes/driver-wallet'));
app.use('/', require('./routes/driver-finance-settings'));
app.use('/', require('./routes/deliveries'));
app.use('/', require('./routes/payments'));
app.use('/', require('./routes/reviews'));
app.use('/', require('./routes/favorites'));
app.use('/', require('./routes/vouchers'));
app.use('/', require('./routes/voucher-settings'));
app.use('/', require('./routes/shipping'));
app.use('/', require('./routes/delivery-radius-settings'));
app.use('/', require('./routes/platform-fee-settings'));
app.use('/', require('./routes/order-settings'));
app.use('/', require('./routes/auto-accept-settings'));
app.use('/', require('./routes/driver-accept-settings'));
app.use('/', require('./routes/driver-dispatch-settings'));
app.use('/', require('./routes/otp-settings'));
app.use('/', require('./routes/chat-settings'));
app.use('/', require('./routes/order-messages'));
app.use('/', require('./routes/bank-account-settings'));
app.use('/', require('./routes/admin-contact-settings'));
app.use('/', require('./routes/pwa-reminder-settings'));
app.use('/', require('./routes/banks'));
app.use('/', require('./routes/nav-icons'));
app.use('/', require('./routes/icon-libraries'));
app.use('/', require('./routes/admin-notifications'));
app.use('/', require('./routes/notifications'));
app.use('/', require('./routes/notification-settings'));
app.use('/', require('./routes/uploads'));
app.use('/', require('./routes/gasSync'));

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

// Tự dọn hộp thư thông báo theo notification_settings.ttl_hours (admin cấu hình ở web admin,
// mục Thông báo > Hộp thư theo cửa hàng) — không cấp bách như 2 sweep trên nên quét thưa hơn
// nhiều, mỗi giờ 1 lần là đủ.
setInterval(() => {
  push.sweepOldNotifications().catch((e) => console.error('[sweep-old-notifications]', e));
}, 60 * 60 * 1000);

// Tự kích hoạt đơn đặt trước (sales_model=scheduled) còn đang "ngủ" khi tới ngưỡng còn
// default_prep_minutes phút nữa là tới scheduled_for — xem hofa-db/49_preorder_gating.sql +
// orderOffer.sweepDuePreorders. 30s là đủ mịn vì ngưỡng tính theo phút.
setInterval(() => {
  orderOffer.sweepDuePreorders().catch((e) => console.error('[sweep-due-preorders]', e));
}, 30_000);

// Tự "nổ" cho cửa hàng các đơn GIAO NGAY đặt trước ở màn thanh toán (sales_model=instant,
// scheduled_for khác NULL) còn đang ngủ khi tới ngưỡng còn default_prep_minutes phút nữa là
// tới scheduled_for — xem hofa-db/84_instant_scheduled_order.sql + orderOffer.sweepDueScheduledInstant.
setInterval(() => {
  orderOffer.sweepDueScheduledInstant().catch((e) => console.error('[sweep-due-scheduled-instant]', e));
}, 30_000);

// Tự quét lại các đơn đang chờ tài xế mà lần gán gần nhất không tìm được ai (xem
// dispatch.sweepDriverSearch) — quét Node mỗi 15s nhưng chỉ thật sự thử gán lại 1 đơn khi đã
// đủ driver_dispatch_settings.rescan_interval_seconds, đủ mịn để đúng nhịp admin cấu hình
// (mặc định 60s) mà không cần khởi động lại interval mỗi lần đổi cấu hình.
setInterval(() => {
  dispatch.sweepDriverSearch().catch((e) => console.error('[sweep-driver-search]', e));
}, 15_000);
