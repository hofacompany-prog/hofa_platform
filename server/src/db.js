const { Pool } = require('pg');
const config = require('./config');
const { fromPgError, ApiError } = require('./errors');

const pool = new Pool({
  connectionString: config.databaseUrl,
  ssl: { rejectUnauthorized: false }, // Supabase yêu cầu SSL; dùng CA hệ thống không kèm sẵn nên tắt strict-verify
  max: 10
});

pool.on('error', (err) => {
  // lỗi trên 1 connection đang rảnh trong pool — không crash cả server
  console.error('Lỗi không mong đợi trên Postgres pool:', err);
});

async function query(text, params) {
  try {
    const { rows } = await pool.query(text, params);
    return rows;
  } catch (err) {
    throw fromPgError(err) || err;
  }
}

async function queryOne(text, params) {
  const rows = await query(text, params);
  return rows[0] || null;
}

function quoteIdent(name) {
  return `"${name.replace(/"/g, '')}"`;
}

async function findById(table, id, columns = '*') {
  return queryOne(`SELECT ${columns} FROM ${quoteIdent(table)} WHERE id = $1`, [id]);
}

async function insertRow(table, data) {
  const keys = Object.keys(data);
  if (!keys.length) throw new ApiError('BAD_REQUEST', 'Không có dữ liệu để tạo mới', 400);
  const columns = keys.map(quoteIdent).join(', ');
  const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
  const values = keys.map((k) => serialize(k, data[k]));
  return queryOne(
    `INSERT INTO ${quoteIdent(table)} (${columns}) VALUES (${placeholders}) RETURNING *`,
    values
  );
}

async function insertRows(table, dataArray) {
  const out = [];
  for (const data of dataArray) out.push(await insertRow(table, data));
  return out;
}

async function updateById(table, id, data) {
  const keys = Object.keys(data);
  if (!keys.length) throw new ApiError('BAD_REQUEST', 'Không có gì để cập nhật', 400);
  const setClause = keys.map((k, i) => `${quoteIdent(k)} = $${i + 2}`).join(', ');
  const values = [id, ...keys.map((k) => serialize(k, data[k]))];
  return queryOne(
    `UPDATE ${quoteIdent(table)} SET ${setClause} WHERE id = $1 RETURNING *`,
    values
  );
}

async function deleteById(table, id) {
  return queryOne(`DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING *`, [id]);
}

/**
 * Cột/tham số kiểu mảng Postgres gốc (TEXT[]/VARCHAR[], không phải jsonb) — products.tags
 * và p_voucher_codes (tham số RPC create_order). node-postgres tự động format JS Array
 * thành cú pháp mảng Postgres {a,b,c} khi truyền thẳng (không JSON.stringify). Nếu lỡ
 * JSON.stringify thì Postgres nhận 1 chuỗi JSON, không khớp cú pháp mảng và sẽ báo lỗi.
 */
const NATIVE_ARRAY_COLUMNS = new Set(['tags', 'p_voucher_codes']);

/** jsonb/object cần JSON.stringify trước khi gửi qua pg; mảng TEXT[] gốc thì để nguyên. */
function serialize(key, value) {
  if (Array.isArray(value) && NATIVE_ARRAY_COLUMNS.has(key)) {
    return value;
  }
  if (value !== null && typeof value === 'object' && !(value instanceof Date)) {
    return JSON.stringify(value);
  }
  return value;
}

/**
 * Gọi 1 hàm RPC trong 04_api_functions.sql bằng cú pháp "named notation" của Postgres
 * (func(ten_tham_so => $1, ...)) — không cần truyền đủ và đúng thứ tự mọi tham số có default.
 */
async function callRpc(fnName, namedArgs) {
  const names = Object.keys(namedArgs);
  const placeholders = names.map((name, i) => `${name} => $${i + 1}`).join(', ');
  const values = names.map((name) => serialize(name, namedArgs[name]));
  return queryOne(`SELECT * FROM ${fnName}(${placeholders})`, values);
}

module.exports = { pool, query, queryOne, findById, insertRow, insertRows, updateById, deleteById, callRpc, quoteIdent };
