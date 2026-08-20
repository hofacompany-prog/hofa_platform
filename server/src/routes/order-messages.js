const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, requireOrderAccess } = require('../utils');
const push = require('../push');

const CHANNELS = ['customer_driver', 'customer_merchant'];

async function currentChatSettings() {
  return db.queryOne('SELECT * FROM chat_settings ORDER BY updated_at DESC LIMIT 1');
}

/** Đơn đang "vận hành" (mọi trạng thái trừ cancelled/refunded) luôn mở chat. Đã giao/hoàn tất
 * thì mở thêm hoursAfterDelivered giờ tính từ delivered_at rồi đóng hẳn. */
function isChatWindowOpen(order, hoursAfterDelivered) {
  if (order.status === 'cancelled' || order.status === 'refunded') return false;
  if (order.status === 'delivered' || order.status === 'completed') {
    if (!order.delivered_at) return false;
    const deadline = new Date(order.delivered_at).getTime() + hoursAfterDelivered * 3600 * 1000;
    return Date.now() <= deadline;
  }
  return true;
}

/** Kiểm quyền theo ĐÚNG kênh — customer_driver chỉ dành cho khách hàng + tài xế phụ trách đơn,
 * customer_merchant chỉ dành cho khách hàng + cửa hàng. requireOrderAccess đã xác nhận ctx là 1
 * trong customer/merchant/driver/admin của đơn này — ở đây chỉ cần loại bên KHÔNG thuộc kênh.
 * CHỈ chặn theo ctx.role khi ctx KHÔNG PHẢI chính khách hàng của đơn này — dùng thẳng ctx.role
 * (role tài khoản TOÀN HỆ THỐNG) từng chặn oan tài khoản có role merchant_owner/staff/driver
 * nhưng lại chính là người đặt đơn đó (role toàn hệ thống, không phải quan hệ với ĐÚNG đơn này —
 * order.customer_id mới là nguồn sự thật, giống cách orderCanView đã làm ở utils.js). */
async function requireChannelAccess(ctx, order, channel) {
  if (ctx.role === 'admin') return;
  const isOrderCustomer = ctx.userId === order.customer_id;
  if (channel === 'customer_driver') {
    if (!isOrderCustomer && (ctx.role === 'merchant_owner' || ctx.role === 'merchant_staff')) {
      throw new ApiError('FORBIDDEN', 'Kênh này chỉ dành cho khách hàng và tài xế', 403);
    }
    if (!isOrderCustomer && ctx.role === 'driver') {
      const delivery = await db.queryOne('SELECT driver_id FROM deliveries WHERE order_id = $1', [order.id]);
      if (!delivery || !delivery.driver_id) {
        throw new ApiError('BAD_REQUEST', 'Đơn chưa có tài xế phụ trách', 400);
      }
    }
  } else if (channel === 'customer_merchant') {
    if (!isOrderCustomer && ctx.role === 'driver') {
      throw new ApiError('FORBIDDEN', 'Kênh này chỉ dành cho khách hàng và cửa hàng', 403);
    }
  }
}

/** ID của (những) người "đầu bên kia" kênh này so với req.ctx — dùng tính other_party_last_read_at
 * để client hiện trạng thái "Đã gửi/Đã xem" cho tin của CHÍNH MÌNH. Kênh customer_merchant có
 * thể nhiều nhân viên cùng đọc — coi cửa hàng "đã xem" nếu BẤT KỲ ai trong đó đã xem
 * (MAX(last_read_at) trong danh sách). Trả về [] nếu ctx không phải 1 trong 2 đầu thường gặp
 * (vd admin xem hộ) — khi đó other_party_last_read_at trả về null, client không hiện "Đã xem".
 */
async function otherPartyUserIds(order, channel, ctx) {
  if (channel === 'customer_driver') {
    if (ctx.userId === order.customer_id) {
      const delivery = await db.queryOne('SELECT driver_id FROM deliveries WHERE order_id = $1', [order.id]);
      const driver = delivery?.driver_id
        ? await db.queryOne('SELECT user_id FROM drivers WHERE id = $1', [delivery.driver_id])
        : null;
      return driver?.user_id ? [driver.user_id] : [];
    }
    return [order.customer_id];
  }
  if (channel === 'customer_merchant') {
    if (ctx.userId === order.customer_id) {
      const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [order.merchant_id]);
      const staff = await db.query('SELECT user_id FROM merchant_staff WHERE merchant_id = $1', [order.merchant_id]);
      const ids = new Set(staff.map((s) => s.user_id));
      if (merchant?.owner_id) ids.add(merchant.owner_id);
      return [...ids];
    }
    return [order.customer_id];
  }
  return [];
}

router.get('/orders/:orderId/messages', asyncHandler(async (req, res) => {
  const order = await requireOrderAccess(req.ctx, req.params.orderId);
  const channel = req.query.channel;
  if (!CHANNELS.includes(channel)) throw new ApiError('BAD_REQUEST', 'Kênh không hợp lệ', 400);
  await requireChannelAccess(req.ctx, order, channel);

  const rows = await db.query(
    'SELECT * FROM order_messages WHERE order_id = $1 AND channel = $2 ORDER BY created_at ASC',
    [order.id, channel]
  );

  const otherIds = await otherPartyUserIds(order, channel, req.ctx);
  let otherPartyLastReadAt = null;
  if (otherIds.length) {
    const row = await db.queryOne(
      `SELECT MAX(last_read_at) AS t FROM order_message_reads
        WHERE order_id = $1 AND channel = $2 AND user_id = ANY($3::uuid[])`,
      [order.id, channel, otherIds]
    );
    otherPartyLastReadAt = row?.t ?? null;
  }

  // Mở màn chat (gọi API này) coi như đã đọc hết tới hiện tại — cập nhật mốc để
  // GET /orders/:orderId/messages/unread-counts tính đúng số CÒN chưa đọc lần sau.
  await db.query(
    `INSERT INTO order_message_reads (order_id, channel, user_id, last_read_at)
     VALUES ($1, $2, $3, now())
     ON CONFLICT (order_id, channel, user_id) DO UPDATE SET last_read_at = now()`,
    [order.id, channel, req.ctx.userId]
  );

  res.json({ ok: true, data: { messages: rows, other_party_last_read_at: otherPartyLastReadAt } });
}));

/** Số tin nhắn CHƯA ĐỌC theo từng kênh — dùng hiện badge nhỏ ở nút nhắn tin trong chi tiết đơn,
 * KHÔNG cần mở màn chat mới biết có tin mới. Kênh req.ctx không có quyền trả về 0 thay vì lỗi,
 * để client gọi 1 lần cho cả 2 kênh mà không cần biết trước vai trò của mình. */
router.get('/orders/:orderId/messages/unread-counts', asyncHandler(async (req, res) => {
  const order = await requireOrderAccess(req.ctx, req.params.orderId);
  const counts = {};
  for (const channel of CHANNELS) {
    try {
      await requireChannelAccess(req.ctx, order, channel);
    } catch (e) {
      counts[channel] = 0;
      continue;
    }
    const row = await db.queryOne(
      `SELECT COUNT(*)::int AS n FROM order_messages m
         LEFT JOIN order_message_reads r
           ON r.order_id = m.order_id AND r.channel = m.channel AND r.user_id = $3
        WHERE m.order_id = $1 AND m.channel = $2 AND m.sender_id != $3
          AND m.created_at > COALESCE(r.last_read_at, '-infinity'::timestamptz)`,
      [order.id, channel, req.ctx.userId]
    );
    counts[channel] = row.n;
  }
  res.json({ ok: true, data: counts });
}));

router.post('/orders/:orderId/messages', asyncHandler(async (req, res) => {
  const order = await requireOrderAccess(req.ctx, req.params.orderId);
  requireFields(req.body, ['channel']);
  const { channel } = req.body;
  if (!CHANNELS.includes(channel)) throw new ApiError('BAD_REQUEST', 'Kênh không hợp lệ', 400);
  await requireChannelAccess(req.ctx, order, channel);

  const body = req.body.body ? String(req.body.body).trim() : null;
  const imageUrl = req.body.image_url || null;
  if (!body && !imageUrl) throw new ApiError('BAD_REQUEST', 'Tin nhắn trống', 400);

  const settings = await currentChatSettings();
  const hoursAfterDelivered = settings ? settings.hours_after_delivered : 1;
  if (!isChatWindowOpen(order, hoursAfterDelivered)) {
    throw new ApiError('FORBIDDEN', 'Đơn đã đóng nhắn tin — quá thời gian cho phép', 403);
  }

  const message = await db.insertRow('order_messages', {
    order_id: order.id,
    channel,
    sender_id: req.ctx.userId,
    sender_role: req.ctx.role,
    body,
    image_url: imageUrl
  });

  // Báo cho ĐẦU BÊN KIA của đúng kênh này — không đụng gì tới bên còn lại (vd merchant không
  // biết cuộc trò chuyện customer_driver của đơn họ đang xử lý).
  const isFromCustomer = req.ctx.userId === order.customer_id;
  const previewBody = body || 'Đã gửi 1 hình ảnh';
  try {
    if (channel === 'customer_driver') {
      if (isFromCustomer) {
        const delivery = await db.queryOne('SELECT driver_id FROM deliveries WHERE order_id = $1', [order.id]);
        const driver = delivery?.driver_id
          ? await db.queryOne('SELECT user_id FROM drivers WHERE id = $1', [delivery.driver_id])
          : null;
        if (driver?.user_id) {
          await push.sendPushToUser(driver.user_id, {
            title: `Khách hàng · ${order.order_code}`,
            body: previewBody,
            data: { type: 'chat_message', order_id: order.id, channel }
          });
        }
      } else {
        await push.sendPushToUser(order.customer_id, {
          title: `Tài xế · ${order.order_code}`,
          body: previewBody,
          data: { type: 'chat_message', order_id: order.id, channel }
        });
      }
    } else if (channel === 'customer_merchant') {
      if (isFromCustomer) {
        const merchant = await db.queryOne('SELECT owner_id FROM merchants WHERE id = $1', [order.merchant_id]);
        const staff = await db.query('SELECT user_id FROM merchant_staff WHERE merchant_id = $1', [order.merchant_id]);
        const ids = new Set(staff.map((s) => s.user_id));
        if (merchant?.owner_id) ids.add(merchant.owner_id);
        await Promise.all([...ids].map((uid) => push.sendPushToUser(uid, {
          title: `Khách hàng · ${order.order_code}`,
          body: previewBody,
          data: { type: 'chat_message', order_id: order.id, channel }
        })));
      } else {
        await push.sendPushToUser(order.customer_id, {
          title: `Cửa hàng · ${order.order_code}`,
          body: previewBody,
          data: { type: 'chat_message', order_id: order.id, channel }
        });
      }
    }
  } catch (err) {
    console.error('[order-messages] Không báo được tin nhắn mới', order.id, err.message);
  }

  res.status(201).json({ ok: true, data: message });
}));

module.exports = router;
