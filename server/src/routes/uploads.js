const router = require('express').Router();
const crypto = require('crypto');
const config = require('../config');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireAuth } = require('../utils');

// Nơi lưu ảnh hợp lệ — chặn client tự đặt folder tuỳ ý trên Cloudinary.
const ALLOWED_FOLDERS = ['merchants', 'products'];

/**
 * Ký request upload ảnh lên Cloudinary — client (hofa_store_app) gọi API này trước,
 * lấy chữ ký rồi tự POST file thẳng lên Cloudinary bằng chữ ký đó (server không phải
 * proxy nhị phân file, chỉ ký). API_SECRET không bao giờ rời khỏi server.
 * Xem: https://cloudinary.com/documentation/signatures
 */
router.post('/uploads/cloudinary-signature', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);

  if (!config.cloudinaryCloudName || !config.cloudinaryApiKey || !config.cloudinaryApiSecret) {
    throw new ApiError('NOT_CONFIGURED', 'Cloudinary chưa được cấu hình trên server', 500);
  }

  const folder = ALLOWED_FOLDERS.includes(req.body.folder) ? req.body.folder : 'products';
  const timestamp = Math.round(Date.now() / 1000);

  // Chuỗi ký PHẢI đúng thứ tự alphabet theo tên tham số, khớp với các tham số client
  // sẽ gửi kèm lên Cloudinary (ngoài file/api_key/cloud_name không cần ký).
  const paramsToSign = `folder=hofa/${folder}&timestamp=${timestamp}`;
  const signature = crypto
    .createHash('sha1')
    .update(paramsToSign + config.cloudinaryApiSecret)
    .digest('hex');

  res.json({
    ok: true,
    data: {
      signature,
      timestamp,
      folder: `hofa/${folder}`,
      api_key: config.cloudinaryApiKey,
      cloud_name: config.cloudinaryCloudName
    }
  });
}));

module.exports = router;
