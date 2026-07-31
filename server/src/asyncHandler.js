/** Bọc route handler async — bắt lỗi tự động chuyển cho errorHandler thay vì phải try/catch mỗi hàm. */
module.exports = function asyncHandler(fn) {
  return function (req, res, next) {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};
