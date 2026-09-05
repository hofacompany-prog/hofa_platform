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
app.use('/', require('./routes/admin-devices'));
app.use('/', require('./routes/users'));
app.use('/', require('./routes/user-blocking-records'));
app.use('/', require('./routes/merchants'));
app.use('/', require('./routes/merchant-classifications'));
app.use('/', require('./routes/merchant-wallet'));
app.use('/', require('./routes/products'));
app.use('/', require('./routes/inventory'));
app.use('/', require('./routes/wholesale'));
app.use('/', require('./routes/orders'));
app.use('/', require('./routes/order-blocking-records'));
app.use('/', require('./routes/drivers'));
app.use('/', require('./routes/driver-blocking-records'));
app.use('/', require('./routes/driver-wallet'));
app.use('/', require('./routes/driver-finance-settings'));
app.use('/', require('./routes/deliveries'));
app.use('/', require('./routes/payments'));
app.use('/', require('./routes/reviews'));
app.use('/', require('./routes/favorites'));
app.use('/', require('./routes/vouchers'));
app.use('/', require('./routes/voucher-settings'));
app.use('/', require('./routes/shipping'));
app.use('/', require('./routes/small-order-fee-settings'));
app.use('/', require('./routes/delivery-radius-settings'));
app.use('/', require('./routes/platform-fee-settings'));
app.use('/', require('./routes/order-settings'));
app.use('/', require('./routes/auto-accept-settings'));
app.use('/', require('./routes/driver-accept-settings'));
app.use('/', require('./routes/driver-dispatch-settings'));
app.use('/', require('./routes/pickup-proximity-settings'));
app.use('/', require('./routes/otp-settings'));
app.use('/', require('./routes/chat-settings'));
app.use('/', require('./routes/order-messages'));
app.use('/', require('./routes/bank-account-settings'));
app.use('/', require('./routes/admin-contact-settings'));
app.use('/', require('./routes/pwa-reminder-settings'));
app.use('/', require('./routes/priceReports'));
app.use('/', require('./routes/issue-reports'));
app.use('/', require('./routes/routeDistance'));
app.use('/', require('./routes/banks'));
app.use('/', require('./routes/nav-icons'));
app.use('/', require('./routes/icon-libraries'));
app.use('/', require('./routes/admin-notifications'));
app.use('/', require('./routes/notifications'));
app.use('/', require('./routes/notification-settings'));
app.use('/', require('./routes/app-update-settings'));
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

// Tự tìm tài xế SỚM — trước khi cửa hàng bấm "Đã làm xong" — khi thời gian chuẩn bị còn lại
// chạm ngưỡng driver_dispatch_settings.search_before_ready_minutes (admin cấu hình), thay vì đợi
// tới ready_for_pickup mới bắt đầu tìm như sweepDriverSearch ở trên. Bỏ qua hẳn nếu admin bật
// search_on_confirm (tìm ngay lúc xác nhận, xem routes/orders.js). Cùng nhịp quét 15s cho đơn
// giản, chỉ thật sự thử gán khi đã đủ rescan_interval_seconds kể từ lần thử trước — xem
// dispatch.sweepEarlyDriverSearch.
setInterval(() => {
  dispatch.sweepEarlyDriverSearch().catch((e) => console.error('[sweep-early-driver-search]', e));
}, 15_000);

// Nhắc lại cửa hàng cho tới khi xác nhận đơn (status rời khỏi 'placed') — gửi LẠI push qua
// resendPushToUser, KHÔNG ghi thêm dòng notifications mới (không nhân bản hộp thư trong app),
// chỉ lặp lại chuông/rung nhắc. Quét Node mỗi 10s nhưng chỉ THẬT SỰ gửi lại cho 1 đơn khi đã đủ
// auto_accept_settings.order_reminder_interval_seconds (admin chỉnh ở "Thông số", mặc định
// 20s) kể từ lần gửi trước — cùng nhịp driver_dispatch_settings/sweepDriverSearch. Xem
// orderOffer.remindUnconfirmedOrders.
setInterval(() => {
  orderOffer.remindUnconfirmedOrders().catch((e) => console.error('[remind-unconfirmed-orders]', e));
}, 10_000);

// Nhắc lại tài xế cho tới khi nhận hoặc từ chối đơn mời (deliveries.status rời khỏi 'assigned')
// — cùng cơ chế remindUnconfirmedOrders ở trên nhưng phía tài xế, gửi LẠI qua resendPushToUser
// (không nhân bản hộp thư trong app). Quét Node mỗi 3s (accept_deadline mặc định chỉ 8-25s, cần
// mịn hơn hẳn phía cửa hàng) nhưng chỉ THẬT SỰ gửi lại khi đã đủ
// driver_accept_settings.offer_reminder_interval_seconds (admin chỉnh ở "Thông số tài xế", mặc
// định 5s) kể từ lần gửi trước. Tự dừng khi tài xế nhận/từ chối hoặc hết accept_deadline (
// sweepExpiredOffers tự chuyển tài xế khác) — xem dispatch.remindPendingDriverOffers.
setInterval(() => {
  dispatch.remindPendingDriverOffers().catch((e) => console.error('[remind-pending-driver-offers]', e));
}, 3_000);
