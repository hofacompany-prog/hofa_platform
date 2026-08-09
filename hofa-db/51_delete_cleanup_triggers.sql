-- Dọn số liệu liên quan khi 1 review/voucher_redemption/delivery bị xoá (hard delete) — dù xoá
-- trực tiếp hay bị kéo theo (CASCADE) từ việc admin xoá thẳng 1 đơn hàng/chuyến giao hàng ở
-- web admin. Đặt ở TRIGGER trên chính bảng con thay vì sửa tay từng route xoá (orders.js,
-- deliveries.js xoá 1/xoá hàng loạt) — vì CASCADE có thể kéo theo xoá những bảng này bất kể
-- xoá từ đâu, trigger đảm bảo số liệu luôn đúng dù sau này có thêm chỗ xoá mới cũng không phải
-- nhớ dọn tay lại.

-- 1) Rating cửa hàng/tài xế/sản phẩm bị lệch nếu review bị xoá — trước giờ refresh_rating() chỉ
-- chạy AFTER INSERT OR UPDATE, chưa từng chạy AFTER DELETE. Mở rộng đúng hàm này (không tạo hàm
-- mới) để giữ đúng chỗ duy nhất tính rating.
CREATE OR REPLACE FUNCTION refresh_rating() RETURNS TRIGGER AS $$
DECLARE
  v_target_type review_target;
  v_target_id   UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_target_type := OLD.target_type;
    v_target_id := OLD.target_id;
  ELSE
    v_target_type := NEW.target_type;
    v_target_id := NEW.target_id;
  END IF;

  IF v_target_type = 'merchant' THEN
    UPDATE merchants SET
      rating_avg   = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews
                      WHERE target_type='merchant' AND target_id=v_target_id AND NOT is_hidden),
      rating_count = (SELECT COUNT(*) FROM reviews
                      WHERE target_type='merchant' AND target_id=v_target_id AND NOT is_hidden)
    WHERE id = v_target_id;
  ELSIF v_target_type = 'driver' THEN
    UPDATE drivers SET
      rating_avg   = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews
                      WHERE target_type='driver' AND target_id=v_target_id AND NOT is_hidden),
      rating_count = (SELECT COUNT(*) FROM reviews
                      WHERE target_type='driver' AND target_id=v_target_id AND NOT is_hidden)
    WHERE id = v_target_id;
  ELSIF v_target_type = 'product' THEN
    UPDATE products SET
      rating_avg   = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews
                      WHERE target_type='product' AND target_id=v_target_id AND NOT is_hidden),
      rating_count = (SELECT COUNT(*) FROM reviews
                      WHERE target_type='product' AND target_id=v_target_id AND NOT is_hidden)
    WHERE id = v_target_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reviews_rating ON reviews;
CREATE TRIGGER trg_reviews_rating AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW EXECUTE FUNCTION refresh_rating();

-- 2) used_count của voucher không tự trừ lại khi voucher_redemptions bị xoá (vd đơn hàng đã
-- dùng voucher đó bị admin xoá thẳng — order_id ON DELETE CASCADE kéo theo xoá luôn dòng này).
CREATE OR REPLACE FUNCTION decrement_voucher_used_count() RETURNS TRIGGER AS $$
BEGIN
  UPDATE vouchers SET used_count = GREATEST(used_count - 1, 0) WHERE id = OLD.voucher_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_voucher_redemptions_decrement AFTER DELETE ON voucher_redemptions
FOR EACH ROW EXECUTE FUNCTION decrement_voucher_used_count();

-- 3) total_deliveries của tài xế không tự trừ lại khi 1 chuyến ĐÃ GIAO (status='delivered') bị
-- xoá thẳng (xoá 1 chuyến, xoá hàng loạt ở màn Chuyến giao hàng, hoặc CASCADE theo khi admin
-- xoá thẳng 1 đơn hàng — deliveries.order_id ON DELETE CASCADE) — khớp đúng điều kiện tăng ở
-- update_delivery_status() (hofa-db/43_buy_on_behalf_driver_dispatch.sql).
CREATE OR REPLACE FUNCTION decrement_driver_deliveries() RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = 'delivered' AND OLD.driver_id IS NOT NULL THEN
    UPDATE drivers SET total_deliveries = GREATEST(total_deliveries - 1, 0) WHERE id = OLD.driver_id;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_deliveries_decrement_on_delete AFTER DELETE ON deliveries
FOR EACH ROW EXECUTE FUNCTION decrement_driver_deliveries();

COMMENT ON FUNCTION decrement_voucher_used_count IS
  'Trừ lại vouchers.used_count khi 1 voucher_redemptions bị xoá (trực tiếp hoặc CASCADE theo khi đơn hàng gốc bị admin xoá thẳng) — tránh used_count lệch dần mỗi lần xoá đơn.';
COMMENT ON FUNCTION decrement_driver_deliveries IS
  'Trừ lại drivers.total_deliveries khi 1 chuyến đã ở trạng thái delivered bị xoá thẳng (xoá lẻ/hàng loạt ở màn Chuyến giao hàng, hoặc CASCADE theo khi đơn hàng gốc bị admin xoá thẳng) — tránh số liệu tài xế bị thổi phồng dần theo số lần xoá.';
