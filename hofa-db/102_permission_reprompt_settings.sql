-- Số ngày chờ trước khi app hiện lại banner nhắc bật quyền Thông báo/Vị trí (nếu người dùng đã
-- từ chối lúc hỏi lần đầu) — cấu hình được từ admin, mỗi app_scope 1 giá trị riêng. Banner này
-- KHÔNG tự động mở Cài đặt hay ép buộc gì — chỉ là lời nhắc có thể đóng tự do, người dùng chủ
-- động bấm mới mở Cài đặt. Bắt buộc phải như vậy vì Apple đã từ chối app do coi việc tự động
-- điều hướng sang Cài đặt/hiện popup chặn lặp lại là hành vi ép buộc (guideline 5.1.1(iv), 4.5.4).
-- NULL = không tự nhắc lại (mặc định, an toàn nhất).
alter table app_update_settings
  add column if not exists notif_reprompt_days integer,
  add column if not exists location_reprompt_days integer;

comment on column app_update_settings.notif_reprompt_days is
  'Số ngày chờ trước khi hiện lại banner nhắc bật quyền Thông báo (nếu trước đó đã từ chối). NULL = không tự nhắc lại.';
comment on column app_update_settings.location_reprompt_days is
  'Số ngày chờ trước khi hiện lại banner nhắc bật quyền Vị trí (nếu trước đó đã từ chối). NULL = không tự nhắc lại.';
