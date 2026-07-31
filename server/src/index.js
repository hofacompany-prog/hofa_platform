const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const config = require('./config');
const { attachContext } = require('./middleware/auth');
const { ApiError } = require('./errors');

const app = express();
app.use(helmet());
app.use(cors()); // API công khai cho app di động/web — không có cookie/session nên CORS mở là an toàn
app.use(morgan(config.isProd ? 'combined' : 'dev'));
app.use(express.json({ limit: '2mb' }));
app.use(attachContext);

app.get('/health', (req, res) => res.json({ ok: true, data: { status: 'up' } }));

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
