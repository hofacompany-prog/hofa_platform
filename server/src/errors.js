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

/**
 * err.constraint/err.table CHỈ có khi Postgres tự chặn 1 ràng buộc THẬT (UNIQUE/FK/CHECK) qua
 * libpq — khác hẳn RAISE EXCEPTION tay trong các hàm RPC (04_api_functions.sql...) đã viết sẵn
 * message tiếng Việt và KHÔNG bao giờ có 2 field này. message tự sinh của Postgres luôn là
 * tiếng Anh (vd "duplicate key value violates unique constraint..."), khó đọc với người không
 * rành SQL — dịch sẵn ra tiếng Việt, vẫn giữ tên constraint để còn tra ngược ra cột/bảng nào.
 */
function friendlyConstraintMessage(err) {
  switch (err.code) {
    case '23505':
      return `Dữ liệu bị trùng, đã tồn tại rồi${err.constraint ? ` (${err.constraint})` : ''}`;
    case '23503':
      return `Không thực hiện được — dữ liệu liên quan không tồn tại hoặc đang được dùng ở nơi khác${err.constraint ? ` (${err.constraint})` : ''}`;
    case '23514':
      return `Dữ liệu không hợp lệ, không đáp ứng điều kiện ràng buộc${err.constraint ? ` (${err.constraint})` : ''}`;
    case '22P02':
      return 'Định dạng dữ liệu không hợp lệ';
    default:
      return err.message;
  }
}

function fromPgError(err) {
  if (!err || !err.code) return null;
  const mapped = SQLSTATE_MAP[err.code];
  if (!mapped) return null;
  const [code, status] = mapped;
  const message = (err.constraint || err.table) ? friendlyConstraintMessage(err) : err.message;
  return new ApiError(code, message, status);
}

module.exports = { ApiError, fromPgError };
