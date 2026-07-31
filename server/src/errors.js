class ApiError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/**
 * Postgres báo lỗi qua SQLSTATE (err.code, 5 ký tự). Các hàm RPC trong
 * 04_api_functions.sql tự RAISE EXCEPTION với ERRCODE cụ thể (check_violation,
 * foreign_key_violation, no_data_found...) và message tiếng Việt sẵn sàng hiện
 * cho người dùng — chỉ cần dịch SQLSTATE sang HTTP status phù hợp.
 */
const SQLSTATE_MAP = {
  '23503': ['FOREIGN_KEY_VIOLATION', 400], // foreign_key_violation
  '23505': ['DUPLICATE', 409],             // unique_violation
  '23514': ['CHECK_VIOLATION', 400],       // check_violation — vd: không đủ tồn kho, sai state machine
  '22P02': ['BAD_INPUT', 400],             // invalid_text_representation — vd: uuid sai định dạng
  P0002: ['NOT_FOUND', 404]                // no_data_found
};

function fromPgError(err) {
  if (!err || !err.code) return null;
  const mapped = SQLSTATE_MAP[err.code];
  if (!mapped) return null;
  const [code, status] = mapped;
  return new ApiError(code, err.message, status);
}

module.exports = { ApiError, fromPgError };
