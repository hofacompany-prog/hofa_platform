-- ============================================================================
-- FIX: cảnh báo "SECURITY DEFINER view" của Supabase linter
--
-- Vấn đề: từ PostgreSQL 15, view mặc định chạy bằng quyền của người TẠO view.
-- Nghĩa là view inventory_available đi xuyên qua Row Level Security của bảng
-- inventory — ai gọi API cũng đọc được tồn kho của mọi cửa hàng.
--
-- Cách sửa: bật security_invoker để view tuân theo quyền của người truy vấn.
--
-- Chạy file này trong SQL Editor. Chỉ mất một giây.
-- ============================================================================

ALTER VIEW public.inventory_available SET (security_invoker = on);

-- Kiểm tra lại: cột security_invoker phải là 'on'
SELECT c.relname AS view_name,
       COALESCE(
         (SELECT o FROM unnest(c.reloptions) AS o WHERE o LIKE 'security_invoker%'),
         'CHUA BAT — con lo hong'
       ) AS trang_thai
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v' AND n.nspname = 'public';
