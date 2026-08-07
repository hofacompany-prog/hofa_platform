-- Thuế suất GTGT/TNCN cho màn "Tài chính" (store app) — cùng cách tính với commission_rate đã
-- có sẵn (áp thẳng lên doanh thu ròng, không lồng thuế trong thuế). Mặc định 3%/1.5% đúng
-- mức thuế khoán hộ kinh doanh dịch vụ ăn uống theo Thông tư 40/2021/TT-BTC — admin chỉnh lại
-- ở web admin nếu cửa hàng đăng ký loại hình khác.
ALTER TABLE merchants ADD COLUMN vat_rate NUMERIC(5,2) NOT NULL DEFAULT 3.0 CHECK (vat_rate >= 0 AND vat_rate <= 100);
ALTER TABLE merchants ADD COLUMN pit_rate NUMERIC(5,2) NOT NULL DEFAULT 1.5 CHECK (pit_rate >= 0 AND pit_rate <= 100);
COMMENT ON COLUMN merchants.vat_rate IS 'Thuế suất GTGT (%) tính trên doanh thu ròng — mặc định theo hộ kinh doanh dịch vụ ăn uống (TT40/2021/TT-BTC)';
COMMENT ON COLUMN merchants.pit_rate IS 'Thuế suất TNCN (%) tính trên doanh thu ròng — mặc định theo hộ kinh doanh dịch vụ ăn uống (TT40/2021/TT-BTC)';
