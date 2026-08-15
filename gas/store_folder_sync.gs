/** ============================================================================================
 *  CẤU HÌNH
 *  ============================================================================================ */

const ROOT_FOLDER_ID = '1Bn2kqF4Fa1ForhEUXkxjAiaX7ZtlMPti';

// ---- Đồng bộ lên hệ thống thật (tab "Đồng bộ CSDL", server/src/routes/gasSync.js) ----
// Điền đúng URL server thật (KHÔNG có dấu / cuối) và secret đã đặt ở biến môi trường
// GAS_SYNC_SECRET trên server — 2 giá trị này PHẢI khớp nhau, server từ chối nếu sai/thiếu.
const GAS_SYNC_API_BASE_URL = 'https://hofa-platform.onrender.com';
const GAS_SYNC_SECRET = '069cfbcbd0219c755f74a2fcd75d97c2';

// weekday 0=Chủ nhật..6=Thứ bảy — khớp đúng branch_hours.weekday thật (hofa-db/01_schema.sql) và
// đúng thứ tự app Cửa hàng đang dùng (hofa_store_app/lib/models/branch_hours.dart).
const WEEKDAY_LABELS_VN = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'];

/** {weekday: "HH:MM-HH:MM"} từ mảng [{weekday,open_time,close_time}] — cắt giây nếu có (Postgres
 *  trả TIME kèm giây, sheet/form chỉ dùng HH:MM). Dùng cả cho diff lẫn đổ dữ liệu vào form. */
function hoursByWeekday_(arr) {
  const map = {};
  (arr || []).forEach(function (h) {
    if (h.weekday === null || h.weekday === undefined) return;
    map[h.weekday] = String(h.open_time || '').slice(0, 5) + '-' + String(h.close_time || '').slice(0, 5);
  });
  return map;
}

// ---- Sheet MERCHANT ----
// Rút gọn tối đa — form CHỈ dành cho cửa hàng MUA HỘ (merchant_type='buy_on_behalf' luôn cố
// định, không phải cột chọn trong sheet — xem STORE_MERCHANT_TYPE_DEFAULT). Địa chỉ/Tỉnh thành
// phố bắt buộc có (branches.line1/province NOT NULL trong DB) dù không bị chặn cứng lúc lưu ở
// sheet — chỉ bị tab Đồng bộ CSDL từ chối nếu thiếu. Ảnh đại diện KHÔNG phải cột sheet — lấy
// trực tiếp từ thư mục con "Avatar" trên Drive (luôn đúng 1 ảnh, xem nút "Ảnh đại diện" trong
// form). Cột Link thư mục (Drive, tự quản lý) và ID hệ thống (server tự ghi sau khi đồng bộ,
// KHÔNG gõ tay) luôn ở CUỐI CÙNG. Sheet CHƯA đúng layout này thì chạy 1 LẦN DUY NHẤT menu
// "Quản lý HOFA → ⚠️ Sắp xếp lại cột MERCHANT (chạy 1 lần)" — tự viết lại dòng tiêu đề + dời
// đúng dữ liệu Vĩ độ/Kinh độ/Link thư mục đang có sang cột mới, hỏi xác nhận trước, không mất
// dữ liệu STT/Tên/Mô tả.
const STORE_SHEET_NAME = 'MERCHANT';
const STORE_HEADER_ROW = 1;
const STORE_START_ROW = 2;
const STORE_STT_COLUMN = 1;              // 1 - STT, tự điền, không cho gõ tay trong form
const STORE_NAME_COLUMN = 2;             // 2 - Tên cửa hàng → merchants.name (*)
const STORE_DESCRIPTION_COLUMN = 3;      // 3 - Mô tả → merchants.description
const STORE_ADDRESS_COLUMN = 4;          // 4 - Địa chỉ → branches.line1 (*, bắt buộc lúc đồng bộ)
const STORE_PROVINCE_COLUMN = 5;         // 5 - Tỉnh/Thành phố → branches.province (*, bắt buộc lúc đồng bộ)
const STORE_LATITUDE_COLUMN = 6;         // 6 - Vĩ độ → branches.latitude (*, input số)
const STORE_LONGITUDE_COLUMN = 7;        // 7 - Kinh độ → branches.longitude (*, input số)
const STORE_FOLDER_LINK_COLUMN = 8;      // 8 - Link thư mục (tự quản lý, không phải field API)
const STORE_SYSTEM_ID_COLUMN = 9;        // 9 - ID hệ thống (merchants.id, server tự ghi sau khi đồng bộ)
// Thêm CUỐI CÙNG (không chen giữa) để không phải dời lại Link thư mục/ID hệ thống — tránh lặp
// lại rắc rối lệch cột đã gặp. 1 cột DUY NHẤT lưu JSON — form vẽ UI 7 ngày (Chủ nhật..Thứ bảy,
// giống hệt màn "Giờ mở cửa" app Cửa hàng: mỗi ngày 1 công tắc bật/tắt + 2 ô chọn giờ, có nút áp
// dụng nhanh 1 khung giờ cho nhiều ngày cùng lúc) — KHÔNG sửa tay trực tiếp trong ô sheet.
// Dạng JSON: [{"weekday":1,"open_time":"08:00","close_time":"21:00"}, ...] — chỉ chứa NGÀY BẬT,
// weekday 0=Chủ nhật..6=Thứ bảy (khớp branch_hours.weekday thật). Để trống/[] = mở 24/7 (0 dòng
// branch_hours), xem hofa-db/78_branch_operating_hours_gate.sql.
const STORE_HOURS_COLUMN = 10;           // 10 - Giờ hoạt động (JSON) → branch_hours (weekday/open_time/close_time)
// Tự điền khi tải "Ảnh đại diện" lên rồi bấm "💾 Lưu" (xem uploadImageToCloudinary) — link
// Cloudinary công khai, KHÁC hẳn link Drive ở cột 8 (Drive không hotlink ổn định cho app hiển
// thị công khai). Không gõ tay trong sheet.
const STORE_LOGO_URL_COLUMN = 11;        // 11 - Ảnh đại diện (URL) → merchants.logo_url
// Chọn qua checkbox nhiều lựa chọn trong form (danh sách lấy từ GET /merchant-classifications,
// admin quản lý — xem hofa-db/71_merchant_classifications.sql), lưu dạng tên cách nhau bằng dấu
// phẩy. Tên không khớp phân loại nào đang có trong hệ thống sẽ bị bỏ qua lặng lẽ lúc đồng bộ.
const STORE_CLASSIFICATION_COLUMN = 12;  // 12 - Phân loại → merchant_classifications (nhiều-nhiều)
const STORE_LAST_COLUMN = STORE_CLASSIFICATION_COLUMN;

// Cả tool này chỉ tạo cửa hàng mua hộ — không có cột chọn trong sheet, cố định khi đẩy API sau
// này (chưa có code đẩy API trong bản này, chỉ đang quản lý dữ liệu qua Sheet/Drive).
const STORE_MERCHANT_TYPE_DEFAULT = 'buy_on_behalf';

// App Khách hiển thị mô tả tối đa 2 dòng bằng maxLines:2 (Flutter tự ngắt dòng theo font/độ
// rộng khung THẬT, không đếm ký tự — xem hofa_customer_app/lib/widgets/merchant_card.dart) nên
// không có giới hạn ký tự "đúng" nào cả, gõ dài mấy cũng không vỡ layout, chỉ tự hiện "...".
// Số dưới đây CHỈ là ước lượng thực tế để gõ trong Sheet có cữ (2 dòng ở cỡ chữ bodySmall trên
// đa số màn hình) — form hiện đếm ký tự sống + không chặn cứng (chỉ nhắc, không xoá chữ đã gõ).
const STORE_DESCRIPTION_MAX_CHARS = 120;

// Giới hạn dung lượng ảnh tải lên Drive (Avatar/Ảnh quán/Ảnh sản phẩm) — chặn ở cả 2 lớp: JS
// phía trình duyệt (báo ngay, không mất công tải lên) VÀ server (uploadImageToStoreSubfolder,
// phòng ai đó gọi thẳng hàm mà không qua form).
const PHOTO_MAX_BYTES = 200 * 1024;

// Toàn bộ header dòng 1 — dùng bởi migrateStoreColumnsToApiLayout_v1() và để đối chiếu khi bạn
// tự set up sheet mới từ đầu.
const STORE_HEADERS = [
  'STT',                // 1 — tự điền
  'Tên cửa hàng',        // 2 — merchants.name (*)
  'Mô tả',               // 3 — merchants.description
  'Địa chỉ',             // 4 — branches.line1 (*)
  'Tỉnh/Thành phố',      // 5 — branches.province (*)
  'Vĩ độ',               // 6 — branches.latitude (*)
  'Kinh độ',             // 7 — branches.longitude (*)
  'Link thư mục',        // 8 — tự quản lý, không gửi API
  'ID hệ thống',         // 9 — merchants.id, server tự ghi khi đồng bộ, không gõ tay
  'Giờ hoạt động',       // 10 — branch_hours (JSON), sửa qua form, không gõ tay trong sheet
  'Ảnh đại diện (URL)',  // 11 — merchants.logo_url, server (Cloudinary) tự ghi khi tải ảnh, không gõ tay
  'Phân loại'            // 12 — merchant_classifications, chọn qua checkbox trong form, không gõ tay
];

// 3 thư mục con tự tạo bên trong thư mục Drive của mỗi cửa hàng.
const SUBFOLDER_AVATAR = 'Avatar';               // chỉ chứa ĐÚNG 1 ảnh — tải ảnh mới sẽ xoá ảnh cũ
const SUBFOLDER_STORE_PHOTOS = 'Ảnh quán';
const SUBFOLDER_MENU_PHOTOS = 'Ảnh menu';        // cũng là nơi chọn ảnh khi CRUD sản phẩm

// ---- Sheet PRODUCT ----
// Layout khớp field thật của products (server/src/routes/products.js, PRODUCT_FIELDS). GIÁ
// KHÔNG còn nằm ở đây nữa — 1 sản phẩm thật ngoài DB có THỂ có NHIỀU biến thể (size/màu...),
// mỗi biến thể 1 giá riêng (bảng product_variants), nên chuyển hẳn sang sheet VARIANT riêng
// (xem bên dưới) — PRODUCT giờ chỉ còn thông tin sản phẩm CHA, không có giá. Mỗi sản phẩm cần
// ÍT NHẤT 1 dòng trong sheet VARIANT (tab "Biến thể") mới có giá/bán được. sales_model cố định
// 'instant' (giao ngay, khớp merchant mua hộ) — không phải cột chọn, xem PRODUCT_SALES_MODEL_
// DEFAULT. Tự tạo (kèm dòng tiêu đề) nếu sheet chưa có; sheet ĐÃ có theo layout cũ (9 cột, còn
// giá ở đây) thì chạy 1 LẦN DUY NHẤT menu "⚠️ Sắp xếp lại cột PRODUCT (chạy 1 lần)" — tự dời giá
// đang có sang 1 dòng biến thể "Mặc định" bên sheet VARIANT, không mất dữ liệu.
const PRODUCT_SHEET_NAME = 'PRODUCT';
const PRODUCT_START_ROW = 2;
const PRODUCT_STORE_COLUMN = 1;         // 1 - Tên quán → chỉ để lọc/liên kết, KHÔNG phải field API
const PRODUCT_NAME_COLUMN = 2;          // 2 - Tên sản phẩm → products.name (*)
const PRODUCT_DESCRIPTION_COLUMN = 3;   // 3 - Mô tả → products.description
const PRODUCT_UNIT_COLUMN = 4;          // 4 - Đơn vị → products.unit (để trống server mặc định "cái")
const PRODUCT_STATUS_COLUMN = 5;        // 5 - Trạng thái → products.status (dropdown)
const PRODUCT_IMAGE_COLUMN = 6;         // 6 - Ảnh sản phẩm → products.images (1 ảnh)
const PRODUCT_TOPPING_GROUPS_COLUMN = 7; // 7 - Nhóm topping áp dụng → product_topping_group_links (tên nhóm, cách nhau bằng dấu phẩy)
const PRODUCT_SYSTEM_ID_COLUMN = 8;     // 8 - ID hệ thống (products.id, server tự ghi khi đồng bộ, không gõ tay)

const PRODUCT_HEADERS = [
  'Tên quán',                // 1 — liên kết nội bộ, không gửi API
  'Tên sản phẩm',            // 2 — products.name (*)
  'Mô tả',                   // 3 — products.description
  'Đơn vị',                  // 4 — products.unit
  'Trạng thái',              // 5 — products.status: draft|active|out_of_stock|hidden|archived
  'Ảnh sản phẩm',            // 6 — products.images
  'Nhóm topping',            // 7 — product_topping_group_links, nhiều nhóm cách nhau bằng dấu phẩy (tên nhóm trong sheet TOPPING)
  'ID hệ thống'              // 8 — products.id, server tự ghi khi đồng bộ
];

// Giá trị enum product_status thật (hofa-db/01_schema.sql) kèm nhãn tiếng Việt cho dropdown.
const PRODUCT_STATUS_OPTIONS = [
  { value: 'draft', label: 'Nháp' },
  { value: 'active', label: 'Đang bán' },
  { value: 'out_of_stock', label: 'Hết hàng' },
  { value: 'hidden', label: 'Ẩn' },
  { value: 'archived', label: 'Đã lưu trữ' }
];

// Cả tool này chỉ tạo sản phẩm giao ngay — không có cột chọn trong sheet, cố định khi đẩy API
// sau này (chưa có code đẩy API trong bản này, chỉ đang quản lý dữ liệu qua Sheet/Drive).
const PRODUCT_SALES_MODEL_DEFAULT = 'instant';

// ---- Sheet VARIANT ----
// Khớp field thật của product_variants (PRODUCT_FIELDS trong products.js gọi là VARIANT_FIELDS)
// — 1 dòng = 1 biến thể (size/màu/gói...) của 1 sản phẩm, MỖI sản phẩm có ít nhất 1 dòng ở đây
// (đặt "Là mặc định" = BẬT) mới có giá/bán được thật.
const VARIANT_SHEET_NAME = 'VARIANT';
const VARIANT_START_ROW = 2;
const VARIANT_STORE_COLUMN = 1;          // 1 - Tên quán → liên kết nội bộ
const VARIANT_PRODUCT_COLUMN = 2;        // 2 - Tên sản phẩm → liên kết nội bộ (khớp PRODUCT.Tên sản phẩm)
const VARIANT_NAME_COLUMN = 3;           // 3 - Tên biến thể → product_variants.name (*), vd "Mặc định"/"Size L"
const VARIANT_PRICE_COLUMN = 4;          // 4 - Giá bán → product_variants.price (*)
const VARIANT_WEIGHT_COLUMN = 5;         // 5 - Trọng lượng (g) → product_variants.weight_gram
const VARIANT_IS_DEFAULT_COLUMN = 6;     // 6 - Là mặc định → product_variants.is_default (checkbox)
const VARIANT_IS_ACTIVE_COLUMN = 7;      // 7 - Đang bán → product_variants.is_active (checkbox, mặc định BẬT)
const VARIANT_SYSTEM_ID_COLUMN = 8;      // 8 - ID hệ thống (product_variants.id, server tự ghi khi đồng bộ, không gõ tay)

const VARIANT_HEADERS = [
  'Tên quán',                  // 1
  'Tên sản phẩm',              // 2
  'Tên biến thể',              // 3 — product_variants.name (*)
  'Giá bán',                   // 4 — product_variants.price (*)
  'Trọng lượng (g)',           // 5 — product_variants.weight_gram
  'Là mặc định',               // 6 — product_variants.is_default (checkbox)
  'Đang bán',                  // 7 — product_variants.is_active (checkbox)
  'ID hệ thống'                // 8 — product_variants.id, server tự ghi khi đồng bộ
];

// ---- Sheet TOPPING ----
// Gộp 2 bảng thật topping_groups + product_toppings (hofa-db/01_schema.sql,
// 17_topping_groups_merchant_level.sql) vào 1 sheet — MỖI DÒNG = 1 LỰA CHỌN TOPPING cụ thể, kèm
// theo thông tin NHÓM nó thuộc về (tên nhóm dùng để gộp — nhiều dòng cùng "Tên nhóm topping" +
// cùng "Tên quán" thì tự hiểu là CÙNG 1 NHÓM). "Bắt buộc chọn"/"Cho chọn nhiều" là thuộc tính
// của CẢ NHÓM (topping_groups.is_required/allow_multiple) — chỉ cần đúng ở dòng ĐẦU TIÊN tạo
// nhóm, các dòng topping sau cùng nhóm có thể để trống (sẽ không đổi lại thông tin nhóm đã có).
// 1 sản phẩm áp dụng nhóm nào thì gõ đúng "Tên nhóm topping" vào cột "Nhóm topping" của sheet
// PRODUCT (nhiều nhóm cách nhau bằng dấu phẩy).
const TOPPING_SHEET_NAME = 'TOPPING';
const TOPPING_START_ROW = 2;
const TOPPING_STORE_COLUMN = 1;              // 1 - Tên quán → liên kết nội bộ
const TOPPING_GROUP_NAME_COLUMN = 2;         // 2 - Tên nhóm topping → topping_groups.name (*)
const TOPPING_GROUP_REQUIRED_COLUMN = 3;     // 3 - Bắt buộc chọn → topping_groups.is_required (checkbox, cấp NHÓM)
const TOPPING_GROUP_ALLOW_MULTIPLE_COLUMN = 4; // 4 - Cho chọn nhiều → topping_groups.allow_multiple (checkbox, cấp NHÓM)
const TOPPING_NAME_COLUMN = 5;               // 5 - Tên topping → product_toppings.name (*)
const TOPPING_PRICE_COLUMN = 6;              // 6 - Giá cộng thêm (VNĐ) → product_toppings.price
const TOPPING_IS_ACTIVE_COLUMN = 7;          // 7 - Đang bán → product_toppings.is_active (checkbox, mặc định BẬT)
const TOPPING_GROUP_ID_COLUMN = 8;           // 8 - ID nhóm (topping_groups.id, server tự ghi khi đồng bộ, không gõ tay)
const TOPPING_ID_COLUMN = 9;                 // 9 - ID topping (product_toppings.id, server tự ghi khi đồng bộ, không gõ tay)

const TOPPING_HEADERS = [
  'Tên quán',              // 1
  'Tên nhóm topping',      // 2 — topping_groups.name (*)
  'Bắt buộc chọn',         // 3 — topping_groups.is_required (cấp nhóm)
  'Cho chọn nhiều',        // 4 — topping_groups.allow_multiple (cấp nhóm)
  'Tên topping',           // 5 — product_toppings.name (*)
  'Giá cộng thêm (VNĐ)',   // 6 — product_toppings.price
  'Đang bán',              // 7 — product_toppings.is_active
  'ID nhóm',               // 8 — topping_groups.id, server tự ghi khi đồng bộ
  'ID topping'             // 9 — product_toppings.id, server tự ghi khi đồng bộ
];


/** ============================================================================================
 *  MENU + TRIGGER MỞ FILE
 *  ============================================================================================ */

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Quản lý HOFA')
    .addItem('Quản lý cửa hàng', 'openStoreManager')
    .addItem('Quản lý sản phẩm', 'openProductManager')
    .addItem('Quản lý biến thể', 'openVariantManager')
    .addItem('Quản lý topping', 'openToppingManager')
    .addItem('Đồng bộ CSDL', 'openDbSyncManager')
    .addSeparator()
    .addItem('⚠️ Sắp xếp lại cột MERCHANT (chạy 1 lần)', 'migrateStoreColumnsToApiLayout_v1')
    .addItem('🔧 Chỉ sửa lại dòng tiêu đề MERCHANT (không đụng dữ liệu)', 'fixStoreHeaderRowOnly_v1')
    .addItem('⚠️ Sắp xếp lại cột PRODUCT (chạy 1 lần)', 'migrateProductColumnsToApiLayout_v1')
    .addToUi();
}

/** CHẠY 1 LẦN DUY NHẤT để ghi dòng tiêu đề (row 1) sheet MERCHANT theo đúng STORE_HEADERS hiện
 *  tại (10 cột — Địa chỉ/Tỉnh thành/ID hệ thống/Giờ hoạt động thêm dần qua các lần). AN TOÀN với 2
 *  layout cũ có thể gặp: layout NGAY TRƯỚC lần sắp xếp này (Vĩ độ cột 4, Link thư mục cột 6)
 *  hoặc layout RẤT CŨ (Vĩ độ cột 4, Link thư mục cột H=8, bản đầu tiên của tool) — tự đọc đúng
 *  dữ liệu Vĩ độ/Kinh độ/Link thư mục đang có TRƯỚC khi ghi đè, rồi dời sang đúng cột mới, không
 *  mất dữ liệu STT/Tên cửa hàng/Mô tả. Cột Địa chỉ/Tỉnh thành phố MỚI luôn để TRỐNG cho các dòng
 *  đã có sẵn (dữ liệu này chưa từng tồn tại trước đây) — bắt buộc điền tay trước khi đồng bộ lên
 *  hệ thống thật (branches.line1/province NOT NULL). Tự nhận biết nếu sheet ĐÃ đúng layout mới
 *  để không chạy nhầm lần 2 gây xáo trộn. */
/** Chỉ ghi lại ĐÚNG chữ dòng tiêu đề (row 1) theo STORE_HEADERS hiện tại — KHÔNG đụng dữ liệu
 *  bất kỳ dòng nào. Dùng khi migrateStoreColumnsToApiLayout_v1() đã từng chạy và dữ liệu Vĩ độ/
 *  Kinh độ/Link thư mục đã nằm đúng cột mới rồi, nhưng dòng tiêu đề vẫn còn chữ cũ/sai (vd do so
 *  khớp chữ tiêu đề bị lệch 1 ký tự ở lần chạy trước — an toàn tuyệt đối vì không viết gì vào
 *  dữ liệu, chỉ đúng 1 dòng đầu tiên). */
function fixStoreHeaderRowOnly_v1() {
  const ui = SpreadsheetApp.getUi();
  const sheet = getStoreSheet_();
  const confirm = ui.alert(
    'Ghi lại dòng tiêu đề MERCHANT?',
    'Chỉ viết lại ĐÚNG chữ dòng 1 (STT, Tên cửa hàng, Mô tả, Địa chỉ, Tỉnh/Thành phố, Vĩ độ, ' +
      'Kinh độ, Link thư mục, ID hệ thống, Giờ hoạt động, Ảnh đại diện (URL), Phân loại) — ' +
      'KHÔNG đụng bất kỳ dữ liệu dòng nào khác, chỉ thêm cột trống mới nếu sheet chưa đủ ' +
      STORE_HEADERS.length + ' cột. Dùng khi dữ liệu đã đúng cột nhưng tiêu đề vẫn sai/cũ/thiếu ' +
      'cột. Tiếp tục?',
    ui.ButtonSet.YES_NO
  );
  if (confirm !== ui.Button.YES) return;

  if (sheet.getMaxColumns() < STORE_HEADERS.length) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), STORE_HEADERS.length - sheet.getMaxColumns());
  }
  sheet.getRange(STORE_HEADER_ROW, 1, 1, STORE_HEADERS.length).setValues([STORE_HEADERS]);

  const extraCols = sheet.getLastColumn() - STORE_HEADERS.length;
  if (extraCols > 0) sheet.deleteColumns(STORE_HEADERS.length + 1, extraCols);

  ui.alert('Xong! Dòng tiêu đề MERCHANT đã đúng lại — mở lại form kiểm tra.');
}

function migrateStoreColumnsToApiLayout_v1() {
  const ui = SpreadsheetApp.getUi();
  const sheet = getStoreSheet_();

  const currentHeaders = sheet.getRange(STORE_HEADER_ROW, 1, 1, Math.max(sheet.getLastColumn(), STORE_HEADERS.length)).getValues()[0];
  if (currentHeaders[STORE_FOLDER_LINK_COLUMN - 1] === 'Link thư mục' &&
      currentHeaders[STORE_SYSTEM_ID_COLUMN - 1] === 'ID hệ thống' &&
      currentHeaders[STORE_HOURS_COLUMN - 1] === 'Giờ hoạt động') {
    ui.alert('Sheet MERCHANT đã ở layout mới rồi, không cần chạy lại.');
    return;
  }

  const confirm = ui.alert(
    'Sắp xếp lại cột MERCHANT?',
    'Sẽ viết lại toàn bộ dòng tiêu đề (row 1) theo layout mới — thêm 3 cột Địa chỉ, Tỉnh/Thành ' +
      'phố, ID hệ thống (dùng cho tab Đồng bộ CSDL) — dời đúng dữ liệu Vĩ độ/Kinh độ/Link thư mục ' +
      'đang có sang đúng cột mới, không mất dữ liệu. Cột Địa chỉ/Tỉnh thành phố sẽ để TRỐNG cho ' +
      'các dòng đã có sẵn — BẮT BUỘC điền tay trước khi đồng bộ lên hệ thống thật (địa chỉ chi ' +
      'nhánh không được để trống). Tiếp tục?',
    ui.ButtonSet.YES_NO
  );
  if (confirm !== ui.Button.YES) return;

  const lastDataRow = getStoreLastDataRow_(sheet);
  const numDataRows = Math.max(lastDataRow - STORE_START_ROW + 1, 0);

  // Đọc HẾT dữ liệu cũ ra biến TRƯỚC khi ghi đè bất kỳ cột nào — cột 6 vừa có thể là "Link thư
  // mục" của layout ngay trước, vừa sắp là "Vĩ độ" của layout mới, đọc trước tránh tự đè lên
  // chính dữ liệu nguồn.
  let oldLat = null;
  let oldLng = null;
  let oldLink = null;
  if (numDataRows > 0) {
    if (currentHeaders[3] === 'Vĩ độ') {
      oldLat = sheet.getRange(STORE_START_ROW, 4, numDataRows, 1).getValues();
      oldLng = sheet.getRange(STORE_START_ROW, 5, numDataRows, 1).getValues();
    }
    if (currentHeaders[5] === 'Link thư mục') {
      oldLink = sheet.getRange(STORE_START_ROW, 6, numDataRows, 1).getValues();
    } else if (currentHeaders[7] === 'Link thư mục') {
      oldLink = sheet.getRange(STORE_START_ROW, 8, numDataRows, 1).getValues();
    }
  }

  if (sheet.getMaxColumns() < STORE_HEADERS.length) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), STORE_HEADERS.length - sheet.getMaxColumns());
  }
  sheet.getRange(STORE_HEADER_ROW, 1, 1, STORE_HEADERS.length).setValues([STORE_HEADERS]);

  if (numDataRows > 0) {
    // Cột 4/5 giờ đổi nghĩa thành Địa chỉ/Tỉnh thành phố — xoá trắng trước khi ghi lại toạ độ ở
    // vị trí mới, tránh để sót số Vĩ độ/Kinh độ cũ nằm lộn dưới tiêu đề Địa chỉ/Tỉnh thành.
    sheet.getRange(STORE_START_ROW, 4, numDataRows, 2).clearContent();
    if (oldLat) {
      sheet.getRange(STORE_START_ROW, STORE_LATITUDE_COLUMN, numDataRows, 1).setValues(oldLat);
      sheet.getRange(STORE_START_ROW, STORE_LONGITUDE_COLUMN, numDataRows, 1).setValues(oldLng);
    }
    if (oldLink) {
      sheet.getRange(STORE_START_ROW, STORE_FOLDER_LINK_COLUMN, numDataRows, 1).setValues(oldLink);
    }
  }

  const extraCols = sheet.getLastColumn() - STORE_HEADERS.length;
  if (extraCols > 0) sheet.deleteColumns(STORE_HEADERS.length + 1, extraCols);

  // Ép cột Tên cửa hàng về định dạng "Văn bản thuần" — chặn Sheets tự ý chuyển ô thành kiểu
  // Ngày tháng nếu gõ nội dung trông giống ngày (nguyên nhân gây tên thư mục Drive kiểu
  // "Fri Jan 02 2026...", xem syncStoreFolderForRow_).
  sheet.getRange(STORE_START_ROW, STORE_NAME_COLUMN, Math.max(sheet.getMaxRows() - STORE_START_ROW + 1, 1), 1)
    .setNumberFormat('@');

  ui.alert(
    'Xong! Sheet MERCHANT đã theo layout mới. Nhớ điền Địa chỉ + Tỉnh/Thành phố cho các dòng đã ' +
    'có sẵn (bắt buộc, không thì tab Đồng bộ CSDL sẽ báo thiếu) trước khi đồng bộ.'
  );
}

/** CHẠY 1 LẦN DUY NHẤT để nâng cấp sheet PRODUCT — nhận diện + xử lý được CẢ 2 layout cũ:
 *  (a) layout rất cũ (6 cột: Tên quán/Tên sản phẩm/Giá/Mô tả/Trạng thái/Ảnh sản phẩm), hoặc
 *  (b) layout cũ hơn 1 chút (9 cột, còn Giá bán/Giá gốc/Giá nhập ngay trong PRODUCT).
 *  Cả 2 trường hợp đều tự DỜI GIÁ đang có sang 1 dòng biến thể "Mặc định" mới bên sheet VARIANT
 *  (is_default=BẬT), vì PRODUCT layout mới KHÔNG còn giữ giá nữa (1 sản phẩm thật có thể nhiều
 *  biến thể/giá khác nhau — xem VARIANT_HEADERS). Không mất dữ liệu Tên/Mô tả/Trạng thái/Ảnh.
 *  RIÊNG cột Trạng thái: dữ liệu rất cũ có thể là chữ tự do ("Đang bán"/"Ngừng bán") — không tự
 *  đoán quy đổi, giữ nguyên, tự chọn lại từ dropdown sau. Sheet chưa từng tồn tại thì
 *  getProductSheet_() tự tạo thẳng theo layout mới, hàm này chỉ nhận ra đã đúng và không làm gì. */
function migrateProductColumnsToApiLayout_v1() {
  const ui = SpreadsheetApp.getUi();
  const sheet = getProductSheet_();

  const currentHeaders = sheet.getRange(1, 1, 1, Math.max(sheet.getLastColumn(), PRODUCT_HEADERS.length)).getValues()[0];
  if (currentHeaders[PRODUCT_NAME_COLUMN - 1] === 'Tên sản phẩm' && currentHeaders[PRODUCT_TOPPING_GROUPS_COLUMN - 1] === 'Nhóm topping') {
    ui.alert('Sheet PRODUCT đã ở layout mới rồi, không cần chạy lại.');
    return;
  }

  const confirm = ui.alert(
    'Sắp xếp lại cột PRODUCT?',
    'Sẽ viết lại toàn bộ dòng tiêu đề theo layout mới (Tên quán, Tên sản phẩm, Mô tả, Đơn vị, ' +
      'Trạng thái, Ảnh sản phẩm, Nhóm topping) — cột Giá không còn ở đây nữa, sẽ TỰ DỜI sang 1 ' +
      'dòng biến thể "Mặc định" mới bên sheet VARIANT cho từng sản phẩm đang có giá. Cột "Trạng ' +
      'thái" giữ nguyên chữ cũ nếu có (không tự đoán quy đổi) — sau khi xong bạn nên chọn lại từ ' +
      'dropdown cho khớp giá trị chuẩn. Tiếp tục?',
    ui.ButtonSet.YES_NO
  );
  if (confirm !== ui.Button.YES) return;

  // Nhận diện layout cũ đang có theo SỐ CỘT thật (không đoán qua tên header, vì bản 9 cột cũ
  // dùng đúng chữ 'Giá bán' ở cột 6 — cứ ưu tiên coi ĐÃ CÓ ≥ 9 cột là bản 9 cột, còn lại (kể cả
  // sheet trống mới toanh mà getProductSheet_() lỡ tạo theo layout khác) coi là bản 6 cột cũ).
  const oldColCount = sheet.getLastColumn() >= 9 ? 9 : 6;
  const lastRow = sheet.getLastRow();
  const numDataRows = Math.max(lastRow - PRODUCT_START_ROW + 1, 0);
  const variantSheet = getVariantSheet_();
  const newVariantRows = [];

  if (numDataRows > 0) {
    const oldValues = sheet.getRange(PRODUCT_START_ROW, 1, numDataRows, oldColCount).getValues();
    const newValues = oldValues.map(function (r) {
      const row = new Array(PRODUCT_HEADERS.length).fill('');
      const storeName = r[0];
      const productName = r[1];
      row[PRODUCT_STORE_COLUMN - 1] = storeName;
      row[PRODUCT_NAME_COLUMN - 1] = productName;

      let price;
      if (oldColCount === 9) {
        // Bản 9 cột: Tên quán, Tên sản phẩm, Mô tả, Đơn vị, Trạng thái, Giá bán, Giá gốc, Giá nhập, Ảnh sản phẩm
        row[PRODUCT_DESCRIPTION_COLUMN - 1] = r[2];
        row[PRODUCT_UNIT_COLUMN - 1] = r[3];
        row[PRODUCT_STATUS_COLUMN - 1] = r[4];
        row[PRODUCT_IMAGE_COLUMN - 1] = r[8];
        price = r[5];
      } else {
        // Bản 6 cột (rất cũ): Tên quán, Tên sản phẩm, Giá, Mô tả, Trạng thái, Ảnh sản phẩm
        row[PRODUCT_DESCRIPTION_COLUMN - 1] = r[3];
        row[PRODUCT_STATUS_COLUMN - 1] = r[4];
        row[PRODUCT_IMAGE_COLUMN - 1] = r[5];
        price = r[2];
      }

      if (storeName && productName && price !== '' && price !== null && price !== undefined) {
        const variantRow = new Array(VARIANT_HEADERS.length).fill('');
        variantRow[VARIANT_STORE_COLUMN - 1] = storeName;
        variantRow[VARIANT_PRODUCT_COLUMN - 1] = productName;
        variantRow[VARIANT_NAME_COLUMN - 1] = 'Mặc định';
        variantRow[VARIANT_PRICE_COLUMN - 1] = price;
        variantRow[VARIANT_IS_DEFAULT_COLUMN - 1] = true;
        variantRow[VARIANT_IS_ACTIVE_COLUMN - 1] = true;
        newVariantRows.push(variantRow);
      }

      return row;
    });
    sheet.getRange(PRODUCT_START_ROW, 1, numDataRows, PRODUCT_HEADERS.length).setValues(newValues);
  }

  // Xoá hết cột thừa bên phải nếu bản cũ có nhiều cột hơn layout mới (9 cột cũ > 7 cột mới).
  const extraCols = sheet.getLastColumn() - PRODUCT_HEADERS.length;
  if (extraCols > 0) sheet.deleteColumns(PRODUCT_HEADERS.length + 1, extraCols);

  sheet.getRange(1, 1, 1, PRODUCT_HEADERS.length).setValues([PRODUCT_HEADERS]);

  if (newVariantRows.length > 0) {
    const variantLastRow = getSheetLastDataRow_(variantSheet, VARIANT_START_ROW, VARIANT_PRODUCT_COLUMN);
    variantSheet.getRange(variantLastRow + 1, 1, newVariantRows.length, VARIANT_HEADERS.length).setValues(newVariantRows);
    variantSheet.getRange(VARIANT_START_ROW, VARIANT_IS_DEFAULT_COLUMN, Math.max(variantSheet.getMaxRows() - VARIANT_START_ROW + 1, 1), 1).insertCheckboxes();
    variantSheet.getRange(VARIANT_START_ROW, VARIANT_IS_ACTIVE_COLUMN, Math.max(variantSheet.getMaxRows() - VARIANT_START_ROW + 1, 1), 1).insertCheckboxes();
  }

  // Dropdown cho cột Trạng thái — đúng enum product_status thật (hofa-db/01_schema.sql).
  const statusRule = SpreadsheetApp.newDataValidation()
    .requireValueInList(PRODUCT_STATUS_OPTIONS.map(function (o) { return o.value; }), true)
    .setAllowInvalid(true)
    .build();
  const fullRows = Math.max(sheet.getMaxRows() - PRODUCT_START_ROW + 1, 1);
  sheet.getRange(PRODUCT_START_ROW, PRODUCT_STATUS_COLUMN, fullRows, 1).setDataValidation(statusRule);

  ui.alert(
    'Xong! Sheet PRODUCT đã theo layout mới' +
    (newVariantRows.length > 0 ? ', đã tạo ' + newVariantRows.length + ' dòng biến thể "Mặc định" bên sheet VARIANT.' : '.') +
    ' Nhớ kiểm tra lại cột Trạng thái cho các dòng đã có sẵn.'
  );
}

/** Menu tuỳ chỉnh + showModalDialog CHỈ chạy được trên trình duyệt (máy tính hoặc trình duyệt
 *  điện thoại mở docs.google.com/spreadsheets) — app Google Sheets trên điện thoại KHÔNG hỗ trợ
 *  menu/dialog tuỳ chỉnh của Apps Script (giới hạn của Google, không sửa được bằng code). doGet
 *  bên dưới cho phép deploy thành 1 "Web app" — 1 trang web độc lập có link riêng, mở được bằng
 *  trình duyệt bất kỳ trên điện thoại (thêm vào Màn hình chính là dùng như app riêng), không cần
 *  mở qua app Sheets nữa. Cách deploy: Apps Script editor → Deploy → New deployment → chọn kiểu
 *  "Web app" → Execute as "Me", Who has access "Only myself" (hoặc "Anyone with Google Account"
 *  nếu muốn chia sẻ cho người khác trong nhóm) → Deploy → copy link, mở trên điện thoại. Sửa code
 *  xong nhớ vào Manage deployments → sửa deployment cũ (biểu tượng bút chì) → New version, không
 *  thì link cũ vẫn chạy bản trước đó.
 *
 *  Trả về ĐÚNG 1 trang gộp cả 2 form (chuyển tab bằng JS, không đổi URL/tải lại trang) — lúc đầu
 *  có thử tách riêng ?page=store / ?page=product thành 2 lượt gọi doGet khác nhau, nhưng trang
 *  Web app của Apps Script luôn chạy trong 1 iframe sandbox riêng (script.googleusercontent.com),
 *  link tương đối kiểu "?page=..." KHÔNG điều hướng đúng ra trang mới như web thường — bấm vào
 *  chỉ ra trang trắng. Gộp 1 trang + chuyển tab bằng JS tránh hẳn vấn đề này. */
function doGet(e) {
  return HtmlService.createHtmlOutput(buildAppHtml_())
    .setTitle('Quản lý HOFA')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

/** idPrefix='s_' cho form cửa hàng, 'p_' cho form sản phẩm — để 2 form gộp chung 1 trang không
 *  bị trùng id phần tử HTML. */
function buildAppHtml_() {
  return `
<style>
  body { font-family: Arial, sans-serif; margin: 0; }
  .tabbar { display: flex; position: sticky; top: 0; background: #fff; border-bottom: 1px solid #ddd; z-index: 10; }
  .tabbar button {
    flex: 1; padding: 14px 8px; border: none; background: #f4f4f4; font-weight: bold; font-size: 14px;
    cursor: pointer; margin: 0; border-radius: 0;
  }
  .tabbar button.active { background: #85C100; color: #fff; }
  .tabpanel { padding: 12px; display: none; }
  .tabpanel.active { display: block; }
</style>
<div class="tabbar">
  <button id="tabBtnStore" class="active">Cửa hàng</button>
  <button id="tabBtnProduct">Sản phẩm</button>
  <button id="tabBtnVariant">Biến thể</button>
  <button id="tabBtnTopping">Topping</button>
  <button id="tabBtnDbSync">Đồng bộ CSDL</button>
</div>
<div id="tabStore" class="tabpanel active">${buildStoreManagerHtml_('s_')}</div>
<div id="tabProduct" class="tabpanel">${buildProductManagerHtml_('p_')}</div>
<div id="tabVariant" class="tabpanel">${buildVariantManagerHtml_('v_')}</div>
<div id="tabTopping" class="tabpanel">${buildToppingManagerHtml_('t_')}</div>
<div id="tabDbSync" class="tabpanel">${buildDbSyncManagerHtml_('d_')}</div>
<script>
  var TABS = ['store', 'product', 'variant', 'topping', 'dbSync'];
  document.getElementById('tabBtnStore').addEventListener('click', function () { showTab('store'); });
  document.getElementById('tabBtnProduct').addEventListener('click', function () { showTab('product'); });
  document.getElementById('tabBtnVariant').addEventListener('click', function () { showTab('variant'); });
  document.getElementById('tabBtnTopping').addEventListener('click', function () { showTab('topping'); });
  document.getElementById('tabBtnDbSync').addEventListener('click', function () { showTab('dbSync'); });
  function showTab(name) {
    TABS.forEach(function (t) {
      var isActive = t === name;
      document.getElementById('tab' + t.charAt(0).toUpperCase() + t.slice(1)).classList.toggle('active', isActive);
      document.getElementById('tabBtn' + t.charAt(0).toUpperCase() + t.slice(1)).classList.toggle('active', isActive);
    });
  }
</script>
`;
}

function openStoreManager() {
  const html = HtmlService.createHtmlOutput(buildStoreManagerHtml_(''))
    .setWidth(760)
    .setHeight(700);
  SpreadsheetApp.getUi().showModalDialog(html, 'Quản lý cửa hàng');
}

function openProductManager() {
  const html = HtmlService.createHtmlOutput(buildProductManagerHtml_(''))
    .setWidth(760)
    .setHeight(700);
  SpreadsheetApp.getUi().showModalDialog(html, 'Quản lý sản phẩm');
}

function openVariantManager() {
  const html = HtmlService.createHtmlOutput(buildVariantManagerHtml_(''))
    .setWidth(760)
    .setHeight(700);
  SpreadsheetApp.getUi().showModalDialog(html, 'Quản lý biến thể');
}

function openToppingManager() {
  const html = HtmlService.createHtmlOutput(buildToppingManagerHtml_(''))
    .setWidth(760)
    .setHeight(700);
  SpreadsheetApp.getUi().showModalDialog(html, 'Quản lý topping');
}

function openDbSyncManager() {
  const html = HtmlService.createHtmlOutput(buildDbSyncManagerHtml_(''))
    .setWidth(760)
    .setHeight(700);
  SpreadsheetApp.getUi().showModalDialog(html, 'Đồng bộ CSDL');
}


/** ============================================================================================
 *  onEdit — tự động tạo/đồng bộ thư mục Drive khi gõ tay tên quán ở cột B (giữ nguyên hành vi
 *  cũ), giờ dùng chung syncStoreFolderForRow_() với form CRUD để không lặp logic.
 *  ============================================================================================ */

function onEdit(e) {
  if (!e || !e.range) return;

  const range = e.range;
  const sheet = range.getSheet();

  if (sheet.getName() !== STORE_SHEET_NAME) return;
  if (range.getRow() < STORE_START_ROW) return;
  if (range.getColumn() !== STORE_NAME_COLUMN) return;

  const numRows = range.getNumRows();
  for (let i = 0; i < numRows; i++) {
    syncStoreFolderForRow_(sheet, range.getRow() + i);
  }
}

/** Đồng bộ thư mục Drive cho đúng 1 dòng cửa hàng: xoá tên → xoá link; có Folder ID cũ (lấy từ
 *  link ở cột H) mà folder còn tồn tại → đổi tên nếu cần + đảm bảo đủ 3 thư mục con; ngược lại
 *  (chưa có link, hoặc folder cũ đã bị xoá) → tìm/tạo lại theo đúng tên quán dưới thư mục gốc. */
function syncStoreFolderForRow_(sheet, row) {
  const nameCell = sheet.getRange(row, STORE_NAME_COLUMN);
  const folderLinkCell = sheet.getRange(row, STORE_FOLDER_LINK_COLUMN);
  const rawName = nameCell.getValue();

  if (!rawName) {
    folderLinkCell.clearContent();
    return;
  }

  // Sheets tự chuyển ô thành kiểu Ngày tháng nếu nội dung gõ vào "giống ngày" (kể cả vô tình,
  // hoặc do định dạng cột còn sót từ trước) — String(Date) ra dạng
  // "Fri Jan 02 2026 00:00:00 GMT+0700 (...)" rất xấu nếu lỡ dùng làm tên thư mục Drive. Chặn
  // sớm + báo rõ, thay vì âm thầm tạo/đổi tên thư mục thành ngày tháng.
  if (rawName instanceof Date) {
    throw new Error(
      'Ô Tên cửa hàng ở dòng ' + row + ' đang là kiểu Ngày tháng (' +
      Utilities.formatDate(rawName, Session.getScriptTimeZone(), 'dd/MM/yyyy') +
      '), không phải chữ — bôi đen ô đó, vào Format > Number > Plain text rồi gõ lại tên cửa hàng.'
    );
  }

  const restaurantName = String(rawName).trim();

  if (!restaurantName) {
    folderLinkCell.clearContent();
    return;
  }

  const oldFolderId = folderIdFromLink_(folderLinkCell.getValue());
  if (oldFolderId) {
    const folder = getFolderByIdSafe_(oldFolderId);
    if (folder) {
      if (folder.getName() !== restaurantName) folder.setName(restaurantName);
      getOrCreateSubfolder_(folder, SUBFOLDER_AVATAR);
      getOrCreateSubfolder_(folder, SUBFOLDER_STORE_PHOTOS);
      getOrCreateSubfolder_(folder, SUBFOLDER_MENU_PHOTOS);
      folderLinkCell.setValue(folderUrl_(folder.getId()));
      return;
    }
    // Folder cũ không còn tồn tại (đã bị xoá tay trên Drive) → tìm/tạo lại theo tên bên dưới.
  }

  const structure = ensureStoreFolderStructure_(restaurantName);
  folderLinkCell.setValue(folderUrl_(structure.storeFolder.getId()));
}


/** ============================================================================================
 *  DRIVE — HÀM DÙNG CHUNG
 *  ============================================================================================ */

function folderUrl_(folderId) {
  return 'https://drive.google.com/drive/folders/' + folderId;
}

function folderIdFromLink_(link) {
  if (!link) return '';
  const match = String(link).match(/\/folders\/([a-zA-Z0-9_-]+)/);
  return match ? match[1] : '';
}

function getFolderByIdSafe_(folderId) {
  try {
    return DriveApp.getFolderById(folderId);
  } catch (e) {
    return null;
  }
}

function getOrCreateSubfolder_(parentFolder, name) {
  const it = parentFolder.getFoldersByName(name);
  return it.hasNext() ? it.next() : parentFolder.createFolder(name);
}

/** Đảm bảo đủ thư mục quán (tìm theo tên dưới thư mục gốc, tạo mới nếu chưa có) + 3 thư mục
 *  con Avatar/Ảnh quán/Ảnh menu — dùng chung cho onEdit, form CRUD cửa hàng, và mọi hàm ảnh. */
function ensureStoreFolderStructure_(storeName) {
  const root = DriveApp.getFolderById(ROOT_FOLDER_ID);
  const it = root.getFoldersByName(storeName);
  const storeFolder = it.hasNext() ? it.next() : root.createFolder(storeName);
  return {
    storeFolder: storeFolder,
    avatarFolder: getOrCreateSubfolder_(storeFolder, SUBFOLDER_AVATAR),
    storePhotoFolder: getOrCreateSubfolder_(storeFolder, SUBFOLDER_STORE_PHOTOS),
    menuPhotoFolder: getOrCreateSubfolder_(storeFolder, SUBFOLDER_MENU_PHOTOS)
  };
}


/** ============================================================================================
 *  API — CRUD CỬA HÀNG (sheet MERCHANT)
 *  Form CRUD tự vẽ theo ĐÚNG các cột đang có ở dòng tiêu đề (row 1) của sheet MERCHANT — không
 *  hard-code tên cột nào ngoài Tên cửa hàng/Link thư mục, phòng khi bạn thêm cột khác sau này.
 *  ============================================================================================ */

function getStoreSheet_() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(STORE_SHEET_NAME);
  if (!sheet) throw new Error('Không tìm thấy sheet ' + STORE_SHEET_NAME);
  return sheet;
}

/** Tên các cột thật của sheet MERCHANT (đọc từ dòng tiêu đề) — form CRUD tự vẽ 1 ô nhập cho mỗi
 *  cột trả về ở đây, theo đúng thứ tự. */
function getStoreHeaders() {
  const sheet = getStoreSheet_();
  const lastCol = Math.max(sheet.getLastColumn(), STORE_LAST_COLUMN);
  return sheet.getRange(STORE_HEADER_ROW, 1, 1, lastCol).getValues()[0];
}

/** Danh sách cửa hàng cho dropdown chọn — {row, name}. */
function listStores() {
  const sheet = getStoreSheet_();
  const lastRow = sheet.getLastRow();
  if (lastRow < STORE_START_ROW) return [];
  const names = sheet
    .getRange(STORE_START_ROW, STORE_NAME_COLUMN, lastRow - STORE_START_ROW + 1, 1)
    .getValues();
  const result = [];
  names.forEach(function (r, i) {
    const name = String(r[0]).trim();
    if (name) result.push({ row: STORE_START_ROW + i, name: name });
  });
  return result;
}

/** Toàn bộ giá trị 1 dòng cửa hàng, theo đúng thứ tự cột trả về từ getStoreHeaders(). */
function getStoreRow(row) {
  const sheet = getStoreSheet_();
  const lastCol = Math.max(sheet.getLastColumn(), STORE_LAST_COLUMN);
  return sheet.getRange(row, 1, 1, lastCol).getValues()[0];
}

/** Dòng dữ liệu THẬT sự cuối cùng theo 1 cột "khoá" (dòng cuối còn có giá trị ở cột đó) —
 *  KHÔNG dùng sheet.getLastRow() để tìm dòng trống tiếp theo, vì getLastRow() tính theo toàn bộ
 *  vùng có định dạng/viền kẻ..., có thể lớn hơn nhiều dòng dữ liệu thật (kẻ bảng sẵn xuống hàng
 *  trăm dòng trống là nguyên nhân phổ biến khiến "Thêm mới" tưởng như không thêm được — dòng
 *  mới bị ghi tít xuống dưới, ngoài tầm nhìn). Trả về startRow - 1 nếu sheet trống. Dùng chung
 *  cho STORE/VARIANT/TOPPING — mỗi sheet 1 cột khoá khác nhau. */
function getSheetLastDataRow_(sheet, startRow, keyColumn) {
  const maxRows = sheet.getMaxRows();
  if (maxRows < startRow) return startRow - 1;
  const values = sheet.getRange(startRow, keyColumn, maxRows - startRow + 1, 1).getValues();
  for (let i = values.length - 1; i >= 0; i--) {
    if (String(values[i][0]).trim()) return startRow + i;
  }
  return startRow - 1;
}

function getStoreLastDataRow_(sheet) {
  return getSheetLastDataRow_(sheet, STORE_START_ROW, STORE_NAME_COLUMN);
}

/** STT kế tiếp — đánh số liên tục theo dòng dữ liệu thật cuối cùng (getStoreLastDataRow_),
 *  KHÔNG đọc cột A hiện có (phòng trường hợp cột A từng bị xoá/sửa tay lệch số). */
function getNextStoreStt_(sheet) {
  return getStoreLastDataRow_(sheet) - STORE_START_ROW + 2;
}

/** Cho form xem trước STT sẽ được gán khi thêm cửa hàng mới. */
function getNextStoreStt() {
  return getNextStoreStt_(getStoreSheet_());
}

/** Tạo mới (row falsy) hoặc cập nhật (row có giá trị) 1 dòng cửa hàng — values là mảng giá trị
 *  đúng theo thứ tự cột của getStoreHeaders(). Ghi xong tự đồng bộ thư mục Drive + 3 thư mục
 *  con ngay (syncStoreFolderForRow_), y hệt lúc gõ tay tên quán ở cột B — cột Link thư mục
 *  trong values bị bỏ qua, luôn do server tự tính lại; cột STT cũng bị bỏ qua khi TẠO MỚI, tự
 *  điền theo getNextStoreStt_ (xem getStoreLastDataRow_ vì sao không dùng getLastRow()). */
function upsertStore(row, values) {
  const sheet = getStoreSheet_();
  const isNew = !row;
  const targetRow = row || getStoreLastDataRow_(sheet) + 1;
  const newName = String(values[STORE_NAME_COLUMN - 1] || '').trim();
  const duplicate = listStores().find(function (s) {
    return s.row !== targetRow && s.name.toLowerCase() === newName.toLowerCase();
  });
  if (duplicate) {
    throw new Error(
      'Đã có cửa hàng khác tên "' + duplicate.name + '" ở dòng ' + duplicate.row +
      ' rồi — 2 cửa hàng trùng tên sẽ dùng chung 1 thư mục Drive và không phân biệt được sản ' +
      'phẩm/biến thể/topping thuộc quán nào. Đổi sang 1 tên khác (vd thêm quận/chi nhánh vào tên).'
    );
  }
  if (isNew) values[STORE_STT_COLUMN - 1] = getNextStoreStt_(sheet);
  sheet.getRange(targetRow, 1, 1, values.length).setValues([values]);
  syncStoreFolderForRow_(sheet, targetRow);
  return { row: targetRow };
}

/** Xoá 1 dòng cửa hàng — thư mục Drive tương ứng chỉ CHUYỂN VÀO THÙNG RÁC (không xoá vĩnh
 *  viễn), phòng lỡ tay xoá nhầm còn khôi phục lại được. */
function deleteStore(row) {
  const sheet = getStoreSheet_();
  const folderId = folderIdFromLink_(sheet.getRange(row, STORE_FOLDER_LINK_COLUMN).getValue());
  if (folderId) {
    const folder = getFolderByIdSafe_(folderId);
    if (folder) folder.setTrashed(true);
  }
  sheet.deleteRow(row);
}


/** ============================================================================================
 *  API — ẢNH (Avatar / Ảnh quán / Ảnh menu) — dùng chung cho form Cửa hàng LẪN ô chọn ảnh sản
 *  phẩm (luôn mở đúng thư mục "Ảnh menu" của quán đang chọn).
 *  ============================================================================================ */

function toImageInfo_(file) {
  return {
    id: file.getId(),
    name: file.getName(),
    url: 'https://drive.google.com/uc?export=view&id=' + file.getId(),
    thumbnailUrl: 'https://drive.google.com/thumbnail?id=' + file.getId() + '&sz=w300'
  };
}

/** Danh sách ảnh trong 1 thư mục con (Avatar/Ảnh quán/Ảnh menu) của 1 quán — dùng vẽ lưới chọn
 *  ảnh. Tự tạo quán/thư mục nếu vì lý do gì đó chưa có (an toàn khi gọi sớm). */
function listImagesInStoreSubfolder(storeName, subfolderName) {
  const structure = ensureStoreFolderStructure_(storeName);
  const sub = getOrCreateSubfolder_(structure.storeFolder, subfolderName);
  const files = sub.getFiles();
  const result = [];
  while (files.hasNext()) result.push(toImageInfo_(files.next()));
  return result;
}

/** Tải 1 ảnh (base64 lấy từ thẻ input file phía trình duyệt) lên đúng thư mục con của quán.
 *  replaceExisting = true (dùng cho Avatar) sẽ chuyển hết ảnh cũ trong thư mục vào Thùng rác
 *  trước khi thêm ảnh mới — đảm bảo thư mục Avatar LUÔN CHỈ CÓ ĐÚNG 1 ẢNH. Chặn ảnh quá
 *  PHOTO_MAX_BYTES — form đã chặn từ phía trình duyệt rồi, đây là lớp phòng thủ thứ 2. */
function uploadImageToStoreSubfolder(storeName, subfolderName, fileName, mimeType, base64Data, replaceExisting) {
  const bytes = Utilities.base64Decode(base64Data);
  if (bytes.length > PHOTO_MAX_BYTES) {
    throw new Error(
      'Ảnh "' + fileName + '" nặng ' + Math.round(bytes.length / 1024) +
      'KB, vượt quá ' + (PHOTO_MAX_BYTES / 1024) + 'KB cho phép.'
    );
  }

  const structure = ensureStoreFolderStructure_(storeName);
  const sub = getOrCreateSubfolder_(structure.storeFolder, subfolderName);

  if (replaceExisting) {
    const files = sub.getFiles();
    while (files.hasNext()) files.next().setTrashed(true);
  }

  const blob = Utilities.newBlob(bytes, mimeType, fileName);
  return toImageInfo_(sub.createFile(blob));
}

/** Xoá (chuyển vào Thùng rác) 1 ảnh theo File ID — dùng chung cho mọi thư mục con. */
function deleteImage(fileId) {
  DriveApp.getFileById(fileId).setTrashed(true);
}


/** ============================================================================================
 *  API — CRUD SẢN PHẨM (sheet PRODUCT, tự tạo nếu chưa có)
 *  ============================================================================================ */

function getProductSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(PRODUCT_SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(PRODUCT_SHEET_NAME);
    sheet.getRange(1, 1, 1, PRODUCT_HEADERS.length).setValues([PRODUCT_HEADERS]);
    sheet.setFrozenRows(1);
  }
  return sheet;
}

/** Sản phẩm thuộc 1 quán (khớp đúng tên quán ở cột A) — {row, values}. */
function listProductsByStore(storeName) {
  const sheet = getProductSheet_();
  const lastRow = sheet.getLastRow();
  if (lastRow < PRODUCT_START_ROW) return [];
  const values = sheet
    .getRange(PRODUCT_START_ROW, 1, lastRow - PRODUCT_START_ROW + 1, PRODUCT_HEADERS.length)
    .getValues();
  const result = [];
  values.forEach(function (r, i) {
    if (String(r[0]).trim() === storeName) {
      result.push({ row: PRODUCT_START_ROW + i, values: r });
    }
  });
  return result;
}

/** Tạo mới (row falsy) hoặc cập nhật (row có giá trị) 1 dòng sản phẩm — values theo đúng thứ
 *  tự PRODUCT_HEADERS. */
function upsertProduct(row, values) {
  const sheet = getProductSheet_();
  const targetRow = row || getSheetLastDataRow_(sheet, PRODUCT_START_ROW, PRODUCT_NAME_COLUMN) + 1;
  sheet.getRange(targetRow, 1, 1, values.length).setValues([values]);
  return { row: targetRow };
}

function deleteProduct(row) {
  getProductSheet_().deleteRow(row);
}


/** ============================================================================================
 *  API — CRUD BIẾN THỂ (sheet VARIANT, tự tạo nếu chưa có) — 1 sản phẩm có thể nhiều biến thể.
 *  ============================================================================================ */

function getVariantSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(VARIANT_SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(VARIANT_SHEET_NAME);
    sheet.getRange(1, 1, 1, VARIANT_HEADERS.length).setValues([VARIANT_HEADERS]);
    sheet.setFrozenRows(1);
    sheet.getRange(VARIANT_START_ROW, VARIANT_IS_DEFAULT_COLUMN, 200, 1).insertCheckboxes();
    sheet.getRange(VARIANT_START_ROW, VARIANT_IS_ACTIVE_COLUMN, 200, 1).insertCheckboxes();
  }
  return sheet;
}

/** Biến thể thuộc đúng 1 sản phẩm (khớp Tên quán + Tên sản phẩm) — {row, values}. */
function listVariantsByProduct(storeName, productName) {
  const sheet = getVariantSheet_();
  const lastRow = sheet.getLastRow();
  if (lastRow < VARIANT_START_ROW) return [];
  const values = sheet
    .getRange(VARIANT_START_ROW, 1, lastRow - VARIANT_START_ROW + 1, VARIANT_HEADERS.length)
    .getValues();
  const result = [];
  values.forEach(function (r, i) {
    if (String(r[VARIANT_STORE_COLUMN - 1]).trim() === storeName &&
        String(r[VARIANT_PRODUCT_COLUMN - 1]).trim() === productName) {
      result.push({ row: VARIANT_START_ROW + i, values: r });
    }
  });
  return result;
}

/** Tạo mới (row falsy) hoặc cập nhật (row có giá trị) 1 dòng biến thể. */
function upsertVariant(row, values) {
  const sheet = getVariantSheet_();
  const targetRow = row || getSheetLastDataRow_(sheet, VARIANT_START_ROW, VARIANT_PRODUCT_COLUMN) + 1;
  sheet.getRange(targetRow, 1, 1, values.length).setValues([values]);
  return { row: targetRow };
}

function deleteVariant(row) {
  getVariantSheet_().deleteRow(row);
}


/** ============================================================================================
 *  API — CRUD TOPPING (sheet TOPPING, tự tạo nếu chưa có) — gộp topping_groups + product_toppings,
 *  mỗi dòng là 1 lựa chọn topping cụ thể kèm thông tin nhóm nó thuộc về (xem comment ở CONFIG).
 *  ============================================================================================ */

function getToppingSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(TOPPING_SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(TOPPING_SHEET_NAME);
    sheet.getRange(1, 1, 1, TOPPING_HEADERS.length).setValues([TOPPING_HEADERS]);
    sheet.setFrozenRows(1);
    sheet.getRange(TOPPING_START_ROW, TOPPING_GROUP_REQUIRED_COLUMN, 200, 1).insertCheckboxes();
    sheet.getRange(TOPPING_START_ROW, TOPPING_GROUP_ALLOW_MULTIPLE_COLUMN, 200, 1).insertCheckboxes();
    sheet.getRange(TOPPING_START_ROW, TOPPING_IS_ACTIVE_COLUMN, 200, 1).insertCheckboxes();
  }
  return sheet;
}

/** Toàn bộ topping (mọi nhóm) của 1 quán — {row, values}. */
function listToppingsByStore(storeName) {
  const sheet = getToppingSheet_();
  const lastRow = sheet.getLastRow();
  if (lastRow < TOPPING_START_ROW) return [];
  const values = sheet
    .getRange(TOPPING_START_ROW, 1, lastRow - TOPPING_START_ROW + 1, TOPPING_HEADERS.length)
    .getValues();
  const result = [];
  values.forEach(function (r, i) {
    if (String(r[TOPPING_STORE_COLUMN - 1]).trim() === storeName) {
      result.push({ row: TOPPING_START_ROW + i, values: r });
    }
  });
  return result;
}

/** Tên các nhóm topping ĐÃ CÓ của 1 quán (không trùng lặp) — cho ô "Nhóm topping" bên form Sản
 *  phẩm biết những nhóm nào chọn được, và cho form Topping gợi ý khi thêm topping vào nhóm cũ. */
function listToppingGroupNames(storeName) {
  const names = listToppingsByStore(storeName)
    .map(function (r) { return String(r.values[TOPPING_GROUP_NAME_COLUMN - 1]).trim(); });
  return names.filter(function (n, i) { return n && names.indexOf(n) === i; });
}

/** Tạo mới (row falsy) hoặc cập nhật (row có giá trị) 1 dòng topping. */
function upsertTopping(row, values) {
  const sheet = getToppingSheet_();
  const targetRow = row || getSheetLastDataRow_(sheet, TOPPING_START_ROW, TOPPING_NAME_COLUMN) + 1;
  sheet.getRange(targetRow, 1, 1, values.length).setValues([values]);
  return { row: targetRow };
}

function deleteTopping(row) {
  getToppingSheet_().deleteRow(row);
}


/** ============================================================================================
 *  ĐỒNG BỘ LÊN HỆ THỐNG THẬT (server/src/routes/gasSync.js) — tab "Đồng bộ CSDL"
 *  ============================================================================================ */

function setStoreSystemId_(row, id) {
  getStoreSheet_().getRange(row, STORE_SYSTEM_ID_COLUMN).setValue(id);
}
function setProductSystemId_(row, id) {
  getProductSheet_().getRange(row, PRODUCT_SYSTEM_ID_COLUMN).setValue(id);
}
function setVariantSystemId_(row, id) {
  getVariantSheet_().getRange(row, VARIANT_SYSTEM_ID_COLUMN).setValue(id);
}
function setToppingGroupId_(row, id) {
  getToppingSheet_().getRange(row, TOPPING_GROUP_ID_COLUMN).setValue(id);
}
function setToppingId_(row, id) {
  getToppingSheet_().getRange(row, TOPPING_ID_COLUMN).setValue(id);
}

/** Gọi API thật (server/src/routes/gasSync.js) qua UrlFetchApp — xác thực bằng GAS_SYNC_SECRET
 *  (không phải JWT, Apps Script không có session Supabase), throw Error rõ ràng nếu HTTP lỗi
 *  hoặc chưa cấu hình URL/secret ở đầu file. */
function gasApiRequest_(method, path, payload) {
  if (!GAS_SYNC_API_BASE_URL || GAS_SYNC_API_BASE_URL.indexOf('your-api') !== -1) {
    throw new Error('Chưa cấu hình GAS_SYNC_API_BASE_URL ở đầu file — điền đúng URL server thật rồi thử lại.');
  }
  const options = {
    method: method,
    contentType: 'application/json',
    headers: { 'x-gas-sync-secret': GAS_SYNC_SECRET },
    muteHttpExceptions: true
  };
  if (payload) options.payload = JSON.stringify(payload);
  const resp = UrlFetchApp.fetch(GAS_SYNC_API_BASE_URL + path, options);
  const code = resp.getResponseCode();
  let body = null;
  try { body = JSON.parse(resp.getContentText()); } catch (e) { /* body vẫn null, xử lý ở dưới */ }
  if (code >= 400 || !body || !body.ok) {
    const msg = body && body.error ? body.error.message : ('Lỗi HTTP ' + code);
    throw new Error(msg);
  }
  return body.data;
}

/** Danh sách phân loại cửa hàng admin đang quản lý (GET /merchant-classifications, endpoint
 *  công khai, không cần secret nhưng vẫn gọi qua gasApiRequest_ cho gọn — server không kiểm tra
 *  header này ở route đó) — cho form vẽ checkbox chọn nhiều. Trả về [] nếu lỗi (không throw,
 *  form vẫn mở được, chỉ là chưa chọn được phân loại). */
function getMerchantClassificationOptions() {
  try {
    return gasApiRequest_('get', '/merchant-classifications', null) || [];
  } catch (e) {
    return [];
  }
}

/** Upload 1 ảnh lên Cloudinary — để hiển thị được trên app Khách/Cửa hàng (khác Drive: Drive
 *  không hotlink ổn định cho ảnh hiển thị công khai trong app, chỉ hợp quản lý ảnh nội bộ).
 *  Ký request qua POST /gas-sync/cloudinary-signature (bảo vệ bằng GAS_SYNC_SECRET, không phải
 *  JWT), rồi tự POST file thẳng lên Cloudinary bằng UrlFetchApp dạng multipart — server không
 *  proxy file nhị phân qua, chỉ ký. Trả về secure_url (string), throw Error nếu lỗi.
 *  cloudinaryFolder: 'merchants' (ảnh đại diện) hoặc 'products' (ảnh sản phẩm) — khớp
 *  ALLOWED_FOLDERS phía server (server/src/routes/gasSync.js). */
function uploadImageToCloudinary(base64Data, mimeType, fileName, cloudinaryFolder) {
  const sig = gasApiRequest_('post', '/gas-sync/cloudinary-signature', { folder: cloudinaryFolder });
  const bytes = Utilities.base64Decode(base64Data);
  const blob = Utilities.newBlob(bytes, mimeType, fileName);
  const resp = UrlFetchApp.fetch('https://api.cloudinary.com/v1_1/' + sig.cloud_name + '/image/upload', {
    method: 'post',
    payload: {
      file: blob,
      api_key: sig.api_key,
      timestamp: String(sig.timestamp),
      signature: sig.signature,
      folder: sig.folder
    },
    muteHttpExceptions: true
  });
  const code = resp.getResponseCode();
  let data = null;
  try { data = JSON.parse(resp.getContentText()); } catch (e) { /* data vẫn null, xử lý ở dưới */ }
  if (code >= 400 || !data || !data.secure_url) {
    const msg = data && data.error ? data.error.message : ('Lỗi HTTP ' + code);
    throw new Error('Tải ảnh lên Cloudinary thất bại: ' + msg);
  }
  return data.secure_url;
}

/** Gom dữ liệu 1 cửa hàng từ 4 sheet MERCHANT/TOPPING/PRODUCT/VARIANT thành đúng cấu trúc
 *  POST /gas-sync/apply cần — CHƯA gửi đi, chỉ đọc từ sheet. Mỗi mục kèm "row" (vị trí dòng
 *  thật trong sheet) để gasSyncApply() biết ghi ID hệ thống trả về vào đúng chỗ. */
/** Đọc JSON giờ hoạt động từ cột "Giờ hoạt động" — [] nếu trống/không parse được (không throw,
 *  coi như mở 24/7, giống hành vi 0 dòng branch_hours). */
function parseStoreHoursJson_(raw) {
  const text = String(raw || '').trim();
  if (!text) return [];
  try {
    const arr = JSON.parse(text);
    return Array.isArray(arr) ? arr : [];
  } catch (e) {
    return [];
  }
}

function gasSyncBuildPayloadForStore_(storeName) {
  const storeEntry = listStores().filter(function (s) { return s.name === storeName; })[0];
  if (!storeEntry) throw new Error('Không tìm thấy cửa hàng "' + storeName + '" trong sheet MERCHANT');
  const sv = getStoreRow(storeEntry.row);

  const merchant = {
    row: storeEntry.row,
    id: sv[STORE_SYSTEM_ID_COLUMN - 1] || null,
    name: String(sv[STORE_NAME_COLUMN - 1] || '').trim(),
    description: sv[STORE_DESCRIPTION_COLUMN - 1] || '',
    address_line1: sv[STORE_ADDRESS_COLUMN - 1] || '',
    province: sv[STORE_PROVINCE_COLUMN - 1] || '',
    latitude: sv[STORE_LATITUDE_COLUMN - 1] === '' ? null : Number(sv[STORE_LATITUDE_COLUMN - 1]),
    longitude: sv[STORE_LONGITUDE_COLUMN - 1] === '' ? null : Number(sv[STORE_LONGITUDE_COLUMN - 1]),
    hours: parseStoreHoursJson_(sv[STORE_HOURS_COLUMN - 1]),
    logo_url: sv[STORE_LOGO_URL_COLUMN - 1] || '',
    classification_names: String(sv[STORE_CLASSIFICATION_COLUMN - 1] || '')
      .split(',').map(function (s) { return s.trim(); }).filter(Boolean)
  };

  // Nhóm topping — sheet TOPPING phẳng (1 dòng = 1 topping), gộp lại theo Tên nhóm.
  const toppingRows = listToppingsByStore(storeName);
  const groupsByName = {};
  const groupOrder = [];
  toppingRows.forEach(function (r) {
    const v = r.values;
    const groupName = String(v[TOPPING_GROUP_NAME_COLUMN - 1] || '').trim();
    if (!groupName) return;
    if (!groupsByName[groupName]) {
      groupsByName[groupName] = {
        row: r.row,
        id: v[TOPPING_GROUP_ID_COLUMN - 1] || null,
        name: groupName,
        is_required: !!v[TOPPING_GROUP_REQUIRED_COLUMN - 1],
        allow_multiple: !!v[TOPPING_GROUP_ALLOW_MULTIPLE_COLUMN - 1],
        toppings: []
      };
      groupOrder.push(groupName);
    }
    groupsByName[groupName].toppings.push({
      row: r.row,
      id: v[TOPPING_ID_COLUMN - 1] || null,
      name: String(v[TOPPING_NAME_COLUMN - 1] || '').trim(),
      price: v[TOPPING_PRICE_COLUMN - 1] === '' ? 0 : Number(v[TOPPING_PRICE_COLUMN - 1]),
      is_active: !!v[TOPPING_IS_ACTIVE_COLUMN - 1]
    });
  });
  const toppingGroups = groupOrder.map(function (n) { return groupsByName[n]; });

  // Sản phẩm + biến thể.
  const productRows = listProductsByStore(storeName);
  const products = productRows.map(function (r) {
    const v = r.values;
    const name = String(v[PRODUCT_NAME_COLUMN - 1] || '').trim();
    const variantRows = listVariantsByProduct(storeName, name);
    return {
      row: r.row,
      id: v[PRODUCT_SYSTEM_ID_COLUMN - 1] || null,
      name: name,
      description: v[PRODUCT_DESCRIPTION_COLUMN - 1] || '',
      unit: v[PRODUCT_UNIT_COLUMN - 1] || '',
      status: v[PRODUCT_STATUS_COLUMN - 1] || 'active',
      image_url: v[PRODUCT_IMAGE_COLUMN - 1] || '',
      topping_group_names: String(v[PRODUCT_TOPPING_GROUPS_COLUMN - 1] || '')
        .split(',').map(function (s) { return s.trim(); }).filter(Boolean),
      variants: variantRows.map(function (vr) {
        const vv = vr.values;
        return {
          row: vr.row,
          id: vv[VARIANT_SYSTEM_ID_COLUMN - 1] || null,
          name: vv[VARIANT_NAME_COLUMN - 1] || '',
          price: vv[VARIANT_PRICE_COLUMN - 1] === '' ? null : Number(vv[VARIANT_PRICE_COLUMN - 1]),
          weight_gram: vv[VARIANT_WEIGHT_COLUMN - 1] === '' ? null : Number(vv[VARIANT_WEIGHT_COLUMN - 1]),
          is_default: !!vv[VARIANT_IS_DEFAULT_COLUMN - 1],
          is_active: !!vv[VARIANT_IS_ACTIVE_COLUMN - 1]
        };
      })
    };
  });

  return { merchant: merchant, topping_groups: toppingGroups, products: products };
}

/** 1 dòng "Nhãn: "cũ" → "mới"", hoặc null nếu không đổi (so sánh dạng chuỗi, đủ dùng cho cả số/
 *  boolean/text — number vs number lệch kiểu JS thật thì đã lệch giá trị thật, không phải lệch
 *  do so sánh chuỗi). */
/** 1 dòng so sánh "Sheet vs Database" cho 1 field — LUÔN trả về dòng (kể cả không đổi, đánh dấu
 *  "="), để người dùng nhìn thấy đủ cả 2 phía trước khi quyết định đồng bộ, không chỉ mỗi phần
 *  đã đổi (yêu cầu "so sánh cả sheet lẫn database cho dễ"). */
function fieldCompareRow_(label, oldVal, newVal) {
  const o = (oldVal === null || oldVal === undefined || oldVal === '') ? '(trống)' : String(oldVal);
  const n = (newVal === null || newVal === undefined || newVal === '') ? '(trống)' : String(newVal);
  const same = o === n;
  return '   ' + (same ? '=' : '≠') + ' ' + label + ' — Sheet: ' + n + ' | Database: ' + o;
}

function diffMerchant_(lines, snapshot, payload) {
  const oldM = snapshot.merchant;
  const oldB = snapshot.branch;
  if (snapshot.name_conflict) {
    lines.push(
      '⚠️ CẢNH BÁO: đã có cửa hàng khác tên "' + payload.merchant.name + '" trong hệ thống (id ' +
      snapshot.name_conflict.id + ', ' +
      (snapshot.name_conflict.is_gas_synced ? 'cũng do GAS quản lý' : 'KHÔNG phải do GAS quản lý') +
      ') — đồng bộ sẽ tạo THÊM 1 cửa hàng MỚI, không phải cửa hàng đó. Nếu là cùng 1 cửa hàng, dán ' +
      'đúng ID hệ thống vào cột "ID hệ thống" của MERCHANT trước khi đồng bộ.'
    );
  }
  if (!oldM) {
    lines.push('🆕 CỬA HÀNG MỚI: "' + payload.merchant.name + '" (chưa có trên Database)');
    lines.push(fieldCompareRow_('Tên', '', payload.merchant.name));
    lines.push(fieldCompareRow_('Mô tả', '', payload.merchant.description));
    lines.push(fieldCompareRow_('Ảnh đại diện', '', payload.merchant.logo_url));
    lines.push(fieldCompareRow_('Phân loại', '', payload.merchant.classification_names.join(', ')));
    lines.push(fieldCompareRow_('Địa chỉ', '', payload.merchant.address_line1));
    lines.push(fieldCompareRow_('Tỉnh/Thành phố', '', payload.merchant.province));
    lines.push(fieldCompareRow_('Vĩ độ', '', payload.merchant.latitude));
    lines.push(fieldCompareRow_('Kinh độ', '', payload.merchant.longitude));
    const newHoursMap = hoursByWeekday_(payload.merchant.hours);
    WEEKDAY_LABELS_VN.forEach(function (label, wd) {
      lines.push(fieldCompareRow_(label, '', newHoursMap[wd] || 'Đóng cửa'));
    });
    return;
  }
  lines.push('📋 CỬA HÀNG "' + oldM.name + '" (id ' + oldM.id + '):');
  lines.push(fieldCompareRow_('Tên', oldM.name, payload.merchant.name));
  lines.push(fieldCompareRow_('Mô tả', oldM.description, payload.merchant.description));
  lines.push(fieldCompareRow_('Ảnh đại diện', oldM.logo_url, payload.merchant.logo_url));
  lines.push(fieldCompareRow_(
    'Phân loại',
    (oldM.classifications || []).slice().sort().join(', '),
    payload.merchant.classification_names.slice().sort().join(', ')
  ));
  if (oldB) {
    lines.push(fieldCompareRow_('Địa chỉ', oldB.line1, payload.merchant.address_line1));
    lines.push(fieldCompareRow_('Tỉnh/Thành phố', oldB.province, payload.merchant.province));
    lines.push(fieldCompareRow_('Vĩ độ', oldB.latitude, payload.merchant.latitude));
    lines.push(fieldCompareRow_('Kinh độ', oldB.longitude, payload.merchant.longitude));
    const oldHoursMap = hoursByWeekday_(oldB.hours);
    const newHoursMap = hoursByWeekday_(payload.merchant.hours);
    WEEKDAY_LABELS_VN.forEach(function (label, wd) {
      lines.push(fieldCompareRow_(label, oldHoursMap[wd] || 'Đóng cửa', newHoursMap[wd] || 'Đóng cửa'));
    });
  } else {
    lines.push('   ≠ Chi nhánh chính — Sheet: ' + payload.merchant.address_line1 + ', ' + payload.merchant.province + ' | Database: (chưa có)');
  }
}

function diffToppingGroups_(lines, snapshot, payload) {
  const oldById = {};
  (snapshot.topping_groups || []).forEach(function (g) { oldById[g.id] = g; });
  const seenOldIds = {};

  (payload.topping_groups || []).forEach(function (g) {
    if (!g.id) {
      lines.push('🆕 NHÓM TOPPING MỚI: "' + g.name + '" (' +
        (g.is_required ? 'bắt buộc chọn' : 'không bắt buộc') + ', ' +
        (g.allow_multiple ? 'cho chọn nhiều' : 'chỉ chọn 1') + ')');
      (g.toppings || []).forEach(function (t) {
        lines.push('   + Topping mới: "' + t.name + '" (+' + (t.price || 0) + 'đ)');
      });
      return;
    }
    seenOldIds[g.id] = true;
    const oldG = oldById[g.id];
    if (!oldG) {
      lines.push('⚠️ Nhóm topping "' + g.name + '" có ID hệ thống (' + g.id + ') nhưng không tìm thấy trên hệ thống — có thể đã bị xoá, kiểm tra lại.');
      return;
    }
    lines.push('📋 NHÓM TOPPING "' + oldG.name + '" (id ' + oldG.id + '):');
    lines.push(fieldCompareRow_('Tên nhóm', oldG.name, g.name));
    lines.push(fieldCompareRow_('Bắt buộc chọn', oldG.is_required, !!g.is_required));
    lines.push(fieldCompareRow_('Cho chọn nhiều', oldG.allow_multiple, !!g.allow_multiple));

    const oldToppingsById = {};
    (oldG.toppings || []).forEach(function (t) { oldToppingsById[t.id] = t; });
    const seenOldToppingIds = {};
    (g.toppings || []).forEach(function (t) {
      if (!t.id) {
        lines.push('   🆕 Topping mới: "' + t.name + '" (+' + (t.price || 0) + 'đ)');
        return;
      }
      seenOldToppingIds[t.id] = true;
      const oldT = oldToppingsById[t.id];
      if (!oldT) { lines.push('   ⚠️ Topping "' + t.name + '" có ID nhưng không tìm thấy trên hệ thống'); return; }
      lines.push('   -- Topping "' + oldT.name + '":');
      lines.push('   ' + fieldCompareRow_('Tên', oldT.name, t.name));
      lines.push('   ' + fieldCompareRow_('Giá cộng thêm', oldT.price, t.price || 0));
      lines.push('   ' + fieldCompareRow_('Đang bán', oldT.is_active, t.is_active !== false));
    });
    (oldG.toppings || []).forEach(function (ot) {
      if (!seenOldToppingIds[ot.id]) {
        lines.push('   🗑️ SẼ XOÁ topping: "' + ot.name + '" (đã bị xoá khỏi sheet TOPPING)');
      }
    });
  });

  (snapshot.topping_groups || []).forEach(function (og) {
    if (!seenOldIds[og.id]) {
      lines.push('🗑️ SẼ XOÁ NHÓM TOPPING: "' + og.name + '" (và toàn bộ topping trong nhóm — đã bị xoá khỏi sheet TOPPING)');
    }
  });
}

function diffProducts_(lines, snapshot, payload) {
  const oldById = {};
  (snapshot.products || []).forEach(function (p) { oldById[p.id] = p; });
  const seenOldIds = {};

  (payload.products || []).forEach(function (p) {
    if (!p.id) {
      lines.push('🆕 SẢN PHẨM MỚI: "' + p.name + '" (' + (p.status || 'active') + ')');
      (p.variants || []).forEach(function (v) {
        lines.push('   + Biến thể mới: "' + v.name + '" — ' + (v.price || 0) + 'đ');
      });
      if ((p.topping_group_names || []).length) {
        lines.push('   Nhóm topping: ' + p.topping_group_names.join(', '));
      }
      return;
    }
    seenOldIds[p.id] = true;
    const oldP = oldById[p.id];
    if (!oldP) {
      lines.push('⚠️ Sản phẩm "' + p.name + '" có ID hệ thống (' + p.id + ') nhưng không tìm thấy trên hệ thống — có thể đã bị xoá, kiểm tra lại.');
      return;
    }
    lines.push('📋 SẢN PHẨM "' + oldP.name + '" (id ' + oldP.id + '):');
    lines.push(fieldCompareRow_('Tên', oldP.name, p.name));
    lines.push(fieldCompareRow_('Mô tả', oldP.description, p.description));
    lines.push(fieldCompareRow_('Đơn vị', oldP.unit, p.unit));
    lines.push(fieldCompareRow_('Trạng thái', oldP.status, p.status));
    lines.push(fieldCompareRow_('Ảnh', (oldP.images && oldP.images[0]) || '', p.image_url));
    const oldGroupNames = (oldP.topping_group_names || []).slice().sort().join(', ');
    const newGroupNames = (p.topping_group_names || []).slice().sort().join(', ');
    lines.push(fieldCompareRow_('Nhóm topping', oldGroupNames, newGroupNames));

    const oldVariantsById = {};
    (oldP.variants || []).forEach(function (v) { oldVariantsById[v.id] = v; });
    const seenOldVariantIds = {};
    (p.variants || []).forEach(function (v) {
      if (!v.id) { lines.push('   🆕 Biến thể mới: "' + v.name + '" — ' + (v.price || 0) + 'đ'); return; }
      seenOldVariantIds[v.id] = true;
      const oldV = oldVariantsById[v.id];
      if (!oldV) { lines.push('   ⚠️ Biến thể "' + v.name + '" có ID nhưng không tìm thấy trên hệ thống'); return; }
      lines.push('   -- Biến thể "' + oldV.name + '":');
      lines.push('   ' + fieldCompareRow_('Tên', oldV.name, v.name));
      lines.push('   ' + fieldCompareRow_('Giá bán', oldV.price, v.price));
      lines.push('   ' + fieldCompareRow_('Trọng lượng', oldV.weight_gram, v.weight_gram));
      lines.push('   ' + fieldCompareRow_('Là mặc định', oldV.is_default, !!v.is_default));
      lines.push('   ' + fieldCompareRow_('Đang bán', oldV.is_active, v.is_active !== false));
    });
    (oldP.variants || []).forEach(function (ov) {
      if (!seenOldVariantIds[ov.id]) {
        lines.push('   🗑️ SẼ XOÁ biến thể: "' + ov.name + '" (đã bị xoá khỏi sheet VARIANT)');
      }
    });
  });

  (snapshot.products || []).forEach(function (op) {
    if (!seenOldIds[op.id]) {
      lines.push('🗑️ SẼ XOÁ SẢN PHẨM: "' + op.name + '" (đã bị xoá khỏi sheet PRODUCT)');
    }
  });
}

/** Gọi bởi tab "Đồng bộ CSDL" — GET snapshot hiện có trên server rồi so với sheet, trả về danh
 *  sách thay đổi dạng text để người dùng đọc + xác nhận TRƯỚC khi bấm nút đồng bộ thật sự
 *  (gasSyncApply). KHÔNG ghi gì lên server ở bước này. */
function gasSyncCheckDiff(storeName) {
  const payload = gasSyncBuildPayloadForStore_(storeName);
  const qs = payload.merchant.id
    ? ('merchant_id=' + encodeURIComponent(payload.merchant.id))
    : ('name=' + encodeURIComponent(payload.merchant.name));
  const snapshot = gasApiRequest_('get', '/gas-sync/snapshot?' + qs, null);

  const lines = [];
  diffMerchant_(lines, snapshot, payload);
  diffToppingGroups_(lines, snapshot, payload);
  diffProducts_(lines, snapshot, payload);
  if (!lines.length) lines.push('Không có gì thay đổi so với hệ thống thật.');

  const deleteCount = lines.filter(function (l) { return l.indexOf('🗑️') !== -1; }).length;

  return {
    lines: lines,
    blockingConflict: !payload.merchant.id && !!snapshot.name_conflict,
    deleteCount: deleteCount
  };
}

/** Gọi bởi tab "Đồng bộ CSDL" SAU KHI người dùng đã xem gasSyncCheckDiff và bấm xác nhận — gửi
 *  toàn bộ dữ liệu cửa hàng lên POST /gas-sync/apply, rồi ghi lại "ID hệ thống" server trả về
 *  vào đúng dòng sheet cho từng mục THÀNH CÔNG (mục nào lỗi thì giữ nguyên ID cũ, không mất dấu,
 *  để lần đồng bộ sau còn khớp lại đúng dòng đó). */
function gasSyncApply(storeName) {
  const payload = gasSyncBuildPayloadForStore_(storeName);

  const applyBody = {
    merchant: {
      id: payload.merchant.id || undefined,
      name: payload.merchant.name,
      description: payload.merchant.description,
      address_line1: payload.merchant.address_line1,
      province: payload.merchant.province,
      latitude: payload.merchant.latitude,
      longitude: payload.merchant.longitude,
      hours: payload.merchant.hours,
      logo_url: payload.merchant.logo_url,
      classification_names: payload.merchant.classification_names
    },
    topping_groups: payload.topping_groups.map(function (g) {
      return {
        id: g.id || undefined,
        name: g.name,
        is_required: g.is_required,
        allow_multiple: g.allow_multiple,
        toppings: g.toppings.map(function (t) {
          return { id: t.id || undefined, name: t.name, price: t.price, is_active: t.is_active };
        })
      };
    }),
    products: payload.products.map(function (p) {
      return {
        id: p.id || undefined,
        name: p.name,
        description: p.description,
        unit: p.unit,
        status: p.status,
        image_url: p.image_url,
        topping_group_names: p.topping_group_names,
        variants: p.variants.map(function (v) {
          return {
            id: v.id || undefined,
            name: v.name,
            price: v.price,
            weight_gram: v.weight_gram,
            is_default: v.is_default,
            is_active: v.is_active
          };
        })
      };
    })
  };

  const result = gasApiRequest_('post', '/gas-sync/apply', applyBody);

  setStoreSystemId_(payload.merchant.row, result.merchant.id);

  const summary = { merchantId: result.merchant.id, errors: [], deleted: result.deleted || {} };

  result.topping_groups.forEach(function (g, i) {
    const srcGroup = payload.topping_groups[i];
    if (g.error) { summary.errors.push('Nhóm topping "' + g.name + '": ' + g.error); return; }
    setToppingGroupId_(srcGroup.row, g.id);
    (g.toppings || []).forEach(function (t, j) {
      const srcTopping = srcGroup.toppings[j];
      if (t.error) { summary.errors.push('Topping "' + t.name + '": ' + t.error); return; }
      setToppingId_(srcTopping.row, t.id);
    });
  });

  result.products.forEach(function (p, i) {
    const srcProduct = payload.products[i];
    if (p.error) { summary.errors.push('Sản phẩm "' + p.name + '": ' + p.error); return; }
    setProductSystemId_(srcProduct.row, p.id);
    (p.variants || []).forEach(function (v, j) {
      const srcVariant = srcProduct.variants[j];
      if (v.error) { summary.errors.push('Biến thể "' + v.name + '": ' + v.error); return; }
      setVariantSystemId_(srcVariant.row, v.id);
    });
  });

  return summary;
}

/** Cửa hàng do GAS quản lý mà dòng tương ứng đã bị XOÁ HẲN khỏi sheet MERCHANT (không phải chỉ
 *  xoá tên — dòng biến mất hoàn toàn nên "ID hệ thống" không còn nơi nào lưu lại nữa). So toàn
 *  bộ cửa hàng is_gas_synced=true trên hệ thống thật với danh sách ID hệ thống còn lại trong
 *  sheet — cửa hàng nào không còn dòng nào khớp thì coi là cần dọn. */
function gasSyncFindOrphanedMerchants() {
  const synced = gasApiRequest_('get', '/gas-sync/merchants', null);
  const sheetIds = {};
  listStores().forEach(function (s) {
    const v = getStoreRow(s.row);
    const id = v[STORE_SYSTEM_ID_COLUMN - 1];
    if (id) sheetIds[id] = true;
  });
  return synced.filter(function (m) { return !sheetIds[m.id]; });
}

/** Xoá CỨNG từng cửa hàng trong danh sách (đã được gasSyncFindOrphanedMerchants xác nhận là mồ
 *  côi + người dùng đã xác nhận trên UI) — lỗi ở 1 cửa hàng không chặn các cửa hàng còn lại. */
function gasSyncDeleteOrphanedMerchants(list) {
  return list.map(function (m) {
    try {
      gasApiRequest_('delete', '/gas-sync/merchants/' + encodeURIComponent(m.id), null);
      return { id: m.id, name: m.name };
    } catch (e) {
      return { id: m.id, name: m.name, error: e.message };
    }
  });
}


/** ============================================================================================
 *  ĐỊA CHỈ ↔ TOẠ ĐỘ (Nominatim/OpenStreetMap) — nút "📍 Chọn vị trí ngay đây" + "🗺️ Tìm trên bản đồ"
 *  ============================================================================================ */

/** Dò địa chỉ/tỉnh thành từ Vĩ độ+Kinh độ qua Nominatim (OpenStreetMap, MIỄN PHÍ, không cần API
 *  key — cùng lựa chọn đã dùng cho app Khách vì Google Maps tính phí, xem ghi chú dự án). Gọi từ
 *  server (UrlFetchApp) chứ không gọi thẳng từ trình duyệt vì trang HTML của dialog/web app chạy
 *  trong iframe sandbox (script.googleusercontent.com), fetch() thẳng dễ bị chặn CORS. Trả về
 *  {address, province} hoặc {address:'', province:''} nếu không dò được (không throw — nút bấm
 *  vị trí vẫn phải điền được Vĩ độ/Kinh độ dù phần địa chỉ dò lỗi). */
function reverseGeocodeLatLng(lat, lng) {
  try {
    const url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=' + encodeURIComponent(lat) +
      '&lon=' + encodeURIComponent(lng) + '&accept-language=vi&zoom=18&addressdetails=1';
    const resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { 'User-Agent': 'HOFA-GAS-StoreTool/1.0 (noreply@hofa.com.vn)' },
      muteHttpExceptions: true
    });
    if (resp.getResponseCode() >= 400) return { address: '', province: '' };
    const data = JSON.parse(resp.getContentText());
    const a = data.address || {};

    const streetPart = [a.house_number, a.road].filter(Boolean).join(' ');
    const wardPart = a.suburb || a.quarter || a.neighbourhood || a.village || a.town || '';
    const address = [streetPart, wardPart].filter(Boolean).join(', ') || (data.display_name || '');

    const province = a.state || a.city || a.county || '';

    return { address: address, province: province };
  } catch (e) {
    return { address: '', province: '' };
  }
}

/** ============================================================================================
 *  GIAO DIỆN — FORM QUẢN LÝ CỬA HÀNG
 *  ============================================================================================ */

function buildStoreManagerHtml_(idPrefix) {
  idPrefix = idPrefix || '';
  return `
<style>
  #${idPrefix}root { font-family: Arial, sans-serif; font-size: 13px; }
  #${idPrefix}root label { font-weight: bold; display: block; margin-top: 8px; }
  #${idPrefix}root input[type=text], #${idPrefix}root textarea { width: 100%; padding: 6px; margin-top: 3px; box-sizing: border-box; }
  #${idPrefix}root textarea { resize: vertical; min-height: 60px; font-family: inherit; }
  #${idPrefix}root select { width: 100%; padding: 6px; margin-top: 3px; box-sizing: border-box; }
  #${idPrefix}root .row { display: flex; gap: 10px; align-items: flex-end; }
  #${idPrefix}root .row > div { flex: 1; }
  #${idPrefix}root button { padding: 7px 14px; margin: 10px 6px 0 0; cursor: pointer; }
  #${idPrefix}root .photo-tabbar { display: flex; gap: 6px; margin-top: 10px; }
  #${idPrefix}root .photo-tabbar button { flex: 1; margin: 0; background: #eef; }
  #${idPrefix}root .photo-tabbar button.photo-tab-active { background: #85C100; color: #fff; }
  #${idPrefix}root .photo-panel { display: none; border: 1px solid #ccc; border-radius: 6px; padding: 10px; margin-top: 10px; background: #fafafa; }
  #${idPrefix}root .photo-panel.photo-panel-active { display: block; }
  #${idPrefix}root .grid { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
  #${idPrefix}root .thumb { position: relative; width: 88px; height: 88px; }
  #${idPrefix}root .thumb img { width: 100%; height: 100%; object-fit: cover; border-radius: 4px; border: 1px solid #ddd; cursor: pointer; }
  #${idPrefix}root .thumb .del { position: absolute; top: -6px; right: -6px; background: #d33; color: #fff; border-radius: 50%; width: 18px; height: 18px; font-size: 11px; line-height: 18px; text-align: center; cursor: pointer; }
  #${idPrefix}msg { color: #0a7d1f; font-weight: bold; margin-top: 8px; min-height: 18px; }
  #${idPrefix}err { color: #c0392b; font-weight: bold; }
  #${idPrefix}linkArea a { display: inline-block; margin-top: 3px; }
  #${idPrefix}hoursArea { margin-top: 3px; border: 1px solid #ddd; border-radius: 6px; padding: 8px 10px; }
  #${idPrefix}hoursArea .hoursRow { display: flex; align-items: center; gap: 8px; padding: 4px 0; }
  #${idPrefix}hoursArea .hoursRow input[type=checkbox] { width: auto; margin: 0; }
  #${idPrefix}hoursArea .hoursLabel { width: 82px; flex: 0 0 auto; font-weight: normal; }
  #${idPrefix}hoursArea input[type=time] { width: auto; padding: 4px; margin: 0; box-sizing: border-box; }
  #${idPrefix}hoursArea .hoursBulkRow { display: flex; align-items: center; gap: 8px; margin-top: 8px; padding-top: 8px; border-top: 1px dashed #ccc; flex-wrap: wrap; }
  #${idPrefix}hoursArea .hoursBulkRow button { margin: 0; padding: 5px 10px; }
  #${idPrefix}hoursArea .hoursHint { font-size: 11px; color: #888; margin-top: 6px; }
  #${idPrefix}mapPasteRow { display: flex; gap: 8px; margin-top: 8px; }
  #${idPrefix}mapPasteRow input[type=text] { flex: 1; margin-top: 0; }
  #${idPrefix}mapPasteRow button { margin: 0; }
</style>

<div id="${idPrefix}root">
  <div class="row">
    <div>
      <label>Chọn cửa hàng</label>
      <select id="${idPrefix}storeSelect"></select>
    </div>
    <div style="flex: 0 0 auto;">
      <button id="${idPrefix}btnNew">+ Thêm cửa hàng mới</button>
    </div>
  </div>

  <div id="${idPrefix}formArea"></div>

  <div class="photo-buttons">
    <button id="${idPrefix}btnHereLoc">📍 Chọn vị trí ngay đây</button>
    <button id="${idPrefix}btnMaps">Tìm vị trí trên Google Maps</button>
  </div>

  <div id="${idPrefix}mapPasteRow">
    <input type="text" id="${idPrefix}mapPasteInput" placeholder="Dán toạ độ vừa sao chép từ Google Maps vào đây...">
    <button id="${idPrefix}btnMapPasteConfirm">✅ Xác nhận</button>
  </div>

  <div class="photo-tabbar">
    <button id="${idPrefix}photoTabBtnAvatar" class="photo-tab-active">Ảnh đại diện</button>
    <button id="${idPrefix}photoTabBtnStore">Ảnh quán</button>
    <button id="${idPrefix}photoTabBtnProduct">Ảnh sản phẩm</button>
  </div>

  <div id="${idPrefix}photoPanelAvatar" class="photo-panel photo-panel-active">
    <div style="color:#888; font-size:12px;">Chỉ 1 ảnh — tải ảnh mới sẽ tự thay ảnh cũ.</div>
    <div style="margin-top: 8px;">
      <input type="file" id="${idPrefix}avatarFile" accept="image/*">
      <button id="${idPrefix}btnUploadAvatar">Tải ảnh lên</button>
    </div>
    <div id="${idPrefix}avatarGrid" class="grid"></div>
  </div>

  <div id="${idPrefix}photoPanelStore" class="photo-panel">
    <div style="margin-top: 8px;">
      <input type="file" id="${idPrefix}storePhotoFile" accept="image/*" multiple>
      <button id="${idPrefix}btnUploadStorePhoto">Tải ảnh lên</button>
    </div>
    <div id="${idPrefix}storePhotoGrid" class="grid"></div>
  </div>

  <div id="${idPrefix}photoPanelProduct" class="photo-panel">
    <div style="margin-top: 8px;">
      <input type="file" id="${idPrefix}productPhotoFile" accept="image/*" multiple>
      <button id="${idPrefix}btnUploadProductPhoto">Tải ảnh lên</button>
    </div>
    <div id="${idPrefix}productPhotoGrid" class="grid"></div>
  </div>

  <div>
    <button id="${idPrefix}btnSave">💾 Lưu</button>
    <button id="${idPrefix}btnDelete">🗑 Xoá cửa hàng</button>
    <button onclick="google.script.host.close()">Đóng</button>
  </div>
  <div id="${idPrefix}msg"></div>
  <div id="${idPrefix}err"></div>
</div>

<script>
(function () {
  var PFX = '${idPrefix}';
  var $ = function (id) { return document.getElementById(PFX + id); };
  var headers = [];
  var stores = [];
  var currentRow = null;
  var PHOTO_TABS = [
    { subfolder: '${SUBFOLDER_AVATAR}', replace: true, cloudinaryFolder: 'merchants', tabBtn: 'photoTabBtnAvatar', panel: 'photoPanelAvatar', fileInput: 'avatarFile', uploadBtn: 'btnUploadAvatar', grid: 'avatarGrid' },
    { subfolder: '${SUBFOLDER_STORE_PHOTOS}', replace: false, cloudinaryFolder: null, tabBtn: 'photoTabBtnStore', panel: 'photoPanelStore', fileInput: 'storePhotoFile', uploadBtn: 'btnUploadStorePhoto', grid: 'storePhotoGrid' },
    { subfolder: '${SUBFOLDER_MENU_PHOTOS}', replace: false, cloudinaryFolder: null, tabBtn: 'photoTabBtnProduct', panel: 'photoPanelProduct', fileInput: 'productPhotoFile', uploadBtn: 'btnUploadProductPhoto', grid: 'productPhotoGrid' }
  ];
  var activePhotoTab = PHOTO_TABS[0];
  var currentStt = '';
  var currentSystemId = '';
  var currentLogoUrl = '';
  var STT_IDX = ${STORE_STT_COLUMN - 1};
  var NAME_IDX = ${STORE_NAME_COLUMN - 1};
  var ADDRESS_IDX = ${STORE_ADDRESS_COLUMN - 1};
  var PROVINCE_IDX = ${STORE_PROVINCE_COLUMN - 1};
  var LAT_IDX = ${STORE_LATITUDE_COLUMN - 1};
  var LNG_IDX = ${STORE_LONGITUDE_COLUMN - 1};
  var LINK_IDX = ${STORE_FOLDER_LINK_COLUMN - 1};
  var SYSTEM_ID_IDX = ${STORE_SYSTEM_ID_COLUMN - 1};
  var HOURS_IDX = ${STORE_HOURS_COLUMN - 1};
  var LOGO_URL_IDX = ${STORE_LOGO_URL_COLUMN - 1};
  var CLASSIFICATION_IDX = ${STORE_CLASSIFICATION_COLUMN - 1};
  var classificationOptions = [];
  var currentClassificationNames = [];
  var WEEKDAY_LABELS = ${JSON.stringify(WEEKDAY_LABELS_VN)};
  var EXPECTED_HEADERS = ${JSON.stringify(STORE_HEADERS)};
  var DESC_MAX_CHARS = ${STORE_DESCRIPTION_MAX_CHARS};
  var MAX_PHOTO_BYTES = ${PHOTO_MAX_BYTES};
  var NUMBER_IDX = [LAT_IDX, LNG_IDX];

  function showMsg(t) { $('msg').innerText = t; $('err').innerText = ''; }
  function showErr(e) { $('err').innerText = 'Lỗi: ' + (e && e.message ? e.message : e); $('msg').innerText = ''; }

  /** Sheet MERCHANT chưa chạy migration lần nào thì dòng tiêu đề (row 1) còn trống — form sẽ hiện
   *  toàn nhãn rỗng, không biết điền gì. So cột Tên cửa hàng (luôn có ở vị trí NAME_IDX theo
   *  EXPECTED_HEADERS) để phát hiện sớm, báo rõ thay vì vẽ 1 form câm. */
  function headersReady(h) {
    return h[NAME_IDX] === EXPECTED_HEADERS[NAME_IDX];
  }

  function init() {
    google.script.run.withSuccessHandler(function (h) {
      headers = h;
      if (!headersReady(h)) {
        $('formArea').innerHTML = '';
        showErr(
          'Sheet MERCHANT chưa có tiêu đề cột. Vào menu Google Sheet: Quản lý HOFA → ' +
          '⚠️ Sắp xếp lại cột MERCHANT (chạy 1 lần) — xong rồi mở lại form này.'
        );
        return;
      }
      renderForm(new Array(headers.length).fill(''));
      loadStores();
    }).withFailureHandler(showErr).getStoreHeaders();

    // Danh sách phân loại (GET /merchant-classifications, admin quản lý) tải song song, có thể
    // về sau renderForm lần đầu — vẽ lại đúng khung phân loại khi có, giữ nguyên lựa chọn đang
    // hiện (currentClassificationNames) để không mất tick đã chọn.
    google.script.run.withSuccessHandler(function (opts) {
      classificationOptions = opts || [];
      renderClassificationEditor(currentClassificationNames);
    }).withFailureHandler(function () {}).getMerchantClassificationOptions();
  }

  function loadStores() {
    google.script.run.withSuccessHandler(function (list) {
      stores = list;
      var sel = $('storeSelect');
      sel.innerHTML = '';
      var opt0 = document.createElement('option');
      opt0.value = '';
      opt0.text = '-- Chọn cửa hàng --';
      sel.appendChild(opt0);
      list.forEach(function (s) {
        var opt = document.createElement('option');
        opt.value = s.row;
        opt.text = s.name;
        sel.appendChild(opt);
      });
    }).withFailureHandler(showErr).listStores();
  }

  $('storeSelect').addEventListener('change', onSelectStore);
  $('btnNew').addEventListener('click', newStore);
  $('btnSave').addEventListener('click', saveStore);
  $('btnDelete').addEventListener('click', removeStore);
  $('btnHereLoc').addEventListener('click', useCurrentLocation);
  $('btnMaps').addEventListener('click', openMaps);
  $('btnMapPasteConfirm').addEventListener('click', mapPasteConfirm);
  PHOTO_TABS.forEach(function (t) {
    $(t.tabBtn).addEventListener('click', function () { switchPhotoTab(t); });
    $(t.uploadBtn).addEventListener('click', function () { uploadPhotoFor(t); });
  });
  init();

  function onSelectStore() {
    var row = $('storeSelect').value;
    if (!row) { newStore(); return; }
    currentRow = parseInt(row, 10);
    resetPhotoTabs();
    google.script.run.withSuccessHandler(renderForm).withFailureHandler(showErr).getStoreRow(currentRow);
  }

  function newStore() {
    currentRow = null;
    currentStt = '';
    $('storeSelect').value = '';
    resetPhotoTabs();
    renderForm(new Array(headers.length).fill(''));
    google.script.run.withSuccessHandler(function (stt) {
      currentStt = ''; // vẫn để trống — CHỈ hiện xem trước, số thật chốt lúc bấm Lưu để
                        // không bị lệch nếu có người khác thêm quán trong lúc đang mở form
      var sttEl = $('sttArea');
      if (sttEl) sttEl.textContent = 'Sẽ tự điền: ' + stt;
    }).withFailureHandler(function () {}).getNextStoreStt();
  }

  function renderForm(values) {
    var area = $('formArea');
    area.innerHTML = '';
    currentStt = values[STT_IDX] || '';
    currentSystemId = values[SYSTEM_ID_IDX] || '';
    currentLogoUrl = values[LOGO_URL_IDX] || '';
    var REQUIRED_IDX = [NAME_IDX, ADDRESS_IDX, PROVINCE_IDX, LAT_IDX, LNG_IDX];
    headers.forEach(function (h, i) {
      var label = document.createElement('label');
      label.textContent = h + (REQUIRED_IDX.indexOf(i) !== -1 ? ' *' : '');
      area.appendChild(label);

      if (i === STT_IDX) {
        var sttDiv = document.createElement('div');
        sttDiv.id = PFX + 'sttArea';
        sttDiv.style.color = '#888';
        sttDiv.textContent = currentStt || 'Sẽ tự điền khi lưu';
        area.appendChild(sttDiv);
      } else if (i === LINK_IDX) {
        var div = document.createElement('div');
        div.id = PFX + 'linkArea';
        var v = values[i] || '';
        if (v) {
          var a = document.createElement('a');
          a.href = v; a.target = '_blank'; a.textContent = 'Mở thư mục Drive';
          div.appendChild(a);
        } else {
          div.textContent = 'Chưa có — tự tạo khi lưu';
          div.style.color = '#888';
        }
        area.appendChild(div);
      } else if (i === SYSTEM_ID_IDX) {
        var idDiv = document.createElement('div');
        idDiv.style.color = '#888';
        idDiv.textContent = currentSystemId
          ? 'Đã đồng bộ — ID: ' + currentSystemId
          : 'Chưa đồng bộ lên hệ thống thật — sang tab "Đồng bộ CSDL" để đẩy lên';
        area.appendChild(idDiv);
      } else if (i === HOURS_IDX) {
        var hoursDiv = document.createElement('div');
        hoursDiv.id = PFX + 'hoursArea';
        area.appendChild(hoursDiv);
        renderHoursEditor(parseHoursJson(values[i]));
      } else if (i === LOGO_URL_IDX) {
        var logoDiv = document.createElement('div');
        logoDiv.id = PFX + 'logoUrlArea';
        if (currentLogoUrl) {
          var logoImg = document.createElement('img');
          logoImg.src = currentLogoUrl;
          logoImg.style.cssText = 'width:56px;height:56px;object-fit:cover;border-radius:4px;border:1px solid #ccc;vertical-align:middle;margin-right:8px;';
          logoDiv.appendChild(logoImg);
          var logoLink = document.createElement('a');
          logoLink.href = currentLogoUrl; logoLink.target = '_blank'; logoLink.textContent = 'Xem ảnh gốc';
          logoDiv.appendChild(logoLink);
        } else {
          logoDiv.textContent = 'Chưa có — tự điền khi tải ảnh ở tab "Ảnh đại diện" bên dưới';
          logoDiv.style.color = '#888';
        }
        area.appendChild(logoDiv);
      } else if (i === CLASSIFICATION_IDX) {
        var classDiv = document.createElement('div');
        classDiv.id = PFX + 'classificationArea';
        area.appendChild(classDiv);
        currentClassificationNames = String(values[i] || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean);
        renderClassificationEditor(currentClassificationNames);
      } else if (h === 'Mô tả') {
        var textarea = document.createElement('textarea');
        textarea.id = PFX + 'f' + i;
        textarea.value = values[i] || '';
        area.appendChild(textarea);
        var counter = document.createElement('div');
        counter.id = PFX + 'descCounter';
        counter.style.cssText = 'font-size:11px;margin-top:2px;color:#888;';
        var updateCounter = function () {
          var len = textarea.value.length;
          counter.textContent = len + '/' + DESC_MAX_CHARS + ' ký tự (ước lượng ~2 dòng — ' +
            'app vẫn tự hiện "..." nếu dài hơn, không mất giao diện)';
          counter.style.color = len > DESC_MAX_CHARS ? '#c0392b' : '#888';
        };
        textarea.addEventListener('input', updateCounter);
        updateCounter();
        area.appendChild(counter);
      } else if (NUMBER_IDX.indexOf(i) !== -1) {
        var numInput = document.createElement('input');
        numInput.id = PFX + 'f' + i;
        numInput.type = 'number';
        numInput.step = '0.0000001';
        numInput.value = values[i] || '';
        area.appendChild(numInput);
      } else {
        var input = document.createElement('input');
        input.id = PFX + 'f' + i;
        input.type = 'text';
        input.value = values[i] || '';
        area.appendChild(input);
      }
    });
    loadPhotoGridFor(activePhotoTab);
  }

  function parseHoursJson(raw) {
    if (!raw) return [];
    try {
      var arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr : [];
    } catch (e) {
      return [];
    }
  }

  function renderHoursEditor(hoursArr) {
    var container = $('hoursArea');
    if (!container) return;
    container.innerHTML = '';
    var byWeekday = {};
    hoursArr.forEach(function (h) { byWeekday[h.weekday] = h; });

    WEEKDAY_LABELS.forEach(function (label, wd) {
      var row = document.createElement('div');
      row.className = 'hoursRow';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.id = PFX + 'hoursEnable' + wd;
      cb.checked = !!byWeekday[wd];
      var lbl = document.createElement('span');
      lbl.className = 'hoursLabel';
      lbl.textContent = label;
      var openInput = document.createElement('input');
      openInput.type = 'time';
      openInput.id = PFX + 'hoursOpen' + wd;
      openInput.value = byWeekday[wd] ? String(byWeekday[wd].open_time).slice(0, 5) : '08:00';
      openInput.disabled = !cb.checked;
      var dash = document.createElement('span');
      dash.textContent = '—';
      var closeInput = document.createElement('input');
      closeInput.type = 'time';
      closeInput.id = PFX + 'hoursClose' + wd;
      closeInput.value = byWeekday[wd] ? String(byWeekday[wd].close_time).slice(0, 5) : '21:00';
      closeInput.disabled = !cb.checked;
      cb.addEventListener('change', function () {
        openInput.disabled = !cb.checked;
        closeInput.disabled = !cb.checked;
      });
      row.appendChild(cb);
      row.appendChild(lbl);
      row.appendChild(openInput);
      row.appendChild(dash);
      row.appendChild(closeInput);
      container.appendChild(row);
    });

    var bulkRow = document.createElement('div');
    bulkRow.className = 'hoursBulkRow';
    var bulkLabel = document.createElement('span');
    bulkLabel.textContent = 'Áp dụng nhanh cho các ngày đã tick:';
    var bulkOpen = document.createElement('input');
    bulkOpen.type = 'time'; bulkOpen.id = PFX + 'hoursBulkOpen'; bulkOpen.value = '08:00';
    var bulkDash = document.createElement('span'); bulkDash.textContent = '—';
    var bulkClose = document.createElement('input');
    bulkClose.type = 'time'; bulkClose.id = PFX + 'hoursBulkClose'; bulkClose.value = '21:00';
    var bulkBtn = document.createElement('button');
    bulkBtn.type = 'button';
    bulkBtn.textContent = 'Áp dụng';
    bulkBtn.addEventListener('click', function () {
      var open = $('hoursBulkOpen').value;
      var close = $('hoursBulkClose').value;
      if (!open || !close) { showErr('Chọn đủ giờ mở/đóng ở khung "Áp dụng nhanh" trước'); return; }
      WEEKDAY_LABELS.forEach(function (label, wd) {
        var cbEl = $('hoursEnable' + wd);
        if (cbEl && cbEl.checked) {
          $('hoursOpen' + wd).value = open;
          $('hoursClose' + wd).value = close;
        }
      });
      showMsg('Đã áp dụng ' + open + '—' + close + ' cho các ngày đã tick — nhớ bấm Lưu.');
    });
    bulkRow.appendChild(bulkLabel);
    bulkRow.appendChild(bulkOpen);
    bulkRow.appendChild(bulkDash);
    bulkRow.appendChild(bulkClose);
    bulkRow.appendChild(bulkBtn);
    container.appendChild(bulkRow);

    var hint = document.createElement('div');
    hint.className = 'hoursHint';
    hint.textContent = 'Tick ngày đang mở cửa rồi chọn giờ riêng cho ngày đó, hoặc điền khung "Áp dụng nhanh" ở dưới rồi bấm Áp dụng để copy cùng 1 giờ cho các ngày đã tick. Không tick ngày nào = mở 24/7 tất cả các ngày.';
    container.appendChild(hint);
  }

  function collectHoursFromEditor() {
    var result = [];
    WEEKDAY_LABELS.forEach(function (label, wd) {
      var cbEl = $('hoursEnable' + wd);
      if (cbEl && cbEl.checked) {
        var openEl = $('hoursOpen' + wd);
        var closeEl = $('hoursClose' + wd);
        if (openEl.value && closeEl.value) {
          result.push({ weekday: wd, open_time: openEl.value, close_time: closeEl.value });
        }
      }
    });
    return result;
  }

  /** Danh sách phân loại đang có (từ classificationOptions, GET /merchant-classifications) —
   *  vẽ 1 checkbox mỗi phân loại, tick sẵn theo selectedNames đang lưu ở cột Phân loại. Chưa
   *  tải xong danh sách (classificationOptions rỗng lúc mới mở form) thì hiện gợi ý chờ, tự vẽ
   *  lại khi tải xong (xem init()). */
  function renderClassificationEditor(selectedNames) {
    var container = $('classificationArea');
    if (!container) return;
    container.innerHTML = '';
    if (!classificationOptions.length) {
      var waiting = document.createElement('div');
      waiting.style.color = '#888';
      waiting.textContent = 'Đang tải danh sách phân loại…';
      container.appendChild(waiting);
      return;
    }
    classificationOptions.forEach(function (opt) {
      var label = document.createElement('label');
      label.style.cssText = 'display:flex; align-items:center; gap:6px; font-weight:normal; margin:4px 0;';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.style.width = 'auto';
      cb.value = opt.name;
      cb.checked = selectedNames.indexOf(opt.name) !== -1;
      label.appendChild(cb);
      label.appendChild(document.createTextNode(opt.name));
      container.appendChild(label);
    });
  }

  function collectClassificationsFromEditor() {
    var container = $('classificationArea');
    if (!container) return [];
    var checkboxes = container.querySelectorAll('input[type=checkbox]:checked');
    var names = [];
    for (var i = 0; i < checkboxes.length; i++) names.push(checkboxes[i].value);
    return names;
  }

  function collectValues() {
    return headers.map(function (h, i) {
      if (i === STT_IDX) return currentStt;
      if (i === LINK_IDX) return '';
      if (i === SYSTEM_ID_IDX) return currentSystemId;
      if (i === LOGO_URL_IDX) return currentLogoUrl;
      if (i === HOURS_IDX) {
        var hours = collectHoursFromEditor();
        return hours.length ? JSON.stringify(hours) : '';
      }
      if (i === CLASSIFICATION_IDX) {
        return collectClassificationsFromEditor().join(', ');
      }
      var el = $('f' + i);
      if (!el) return '';
      if (NUMBER_IDX.indexOf(i) !== -1) {
        return el.value === '' ? '' : Number(el.value);
      }
      return el.value;
    });
  }

  function saveStore() {
    var values = collectValues();
    if (!values[NAME_IDX] || !values[NAME_IDX].trim()) { showErr('Chưa nhập Tên cửa hàng'); return; }
    google.script.run.withSuccessHandler(function (res) {
      currentRow = res.row;
      showMsg('Đã lưu cửa hàng');
      loadStores();
    }).withFailureHandler(showErr).upsertStore(currentRow, values);
  }

  function removeStore() {
    if (!currentRow) { showErr('Chưa chọn cửa hàng để xoá'); return; }
    if (!confirm('Xoá cửa hàng này? Thư mục Drive sẽ chuyển vào Thùng rác.')) return;
    google.script.run.withSuccessHandler(function () {
      showMsg('Đã xoá cửa hàng');
      newStore();
      loadStores();
    }).withFailureHandler(showErr).deleteStore(currentRow);
  }

  /** Lấy vị trí GPS/mạng của chính thiết bị đang mở form (navigator.geolocation — API chuẩn của
   *  trình duyệt, không cần API key) — hỏi xác nhận rồi mới điền vào Vĩ độ/Kinh độ, không tự ý
   *  ghi đè. Trình duyệt sẽ tự hỏi quyền truy cập vị trí lần đầu bấm nút này. */
  function useCurrentLocation() {
    if (!navigator.geolocation) {
      showErr('Trình duyệt này không hỗ trợ lấy vị trí — dùng nút "Tìm trên Google Maps" rồi gõ tay.');
      return;
    }
    showMsg('Đang lấy vị trí…');
    navigator.geolocation.getCurrentPosition(
      function (pos) {
        var lat = pos.coords.latitude;
        var lng = pos.coords.longitude;
        if (!confirm('Đã lấy được vị trí:\\nVĩ độ: ' + lat + '\\nKinh độ: ' + lng + '\\n\\nDùng vị trí này cho cửa hàng?')) {
          showMsg('');
          return;
        }
        if ($('f' + LAT_IDX)) $('f' + LAT_IDX).value = lat;
        if ($('f' + LNG_IDX)) $('f' + LNG_IDX).value = lng;
        showMsg('Đã điền Vĩ độ/Kinh độ — đang dò Địa chỉ/Tỉnh thành phố…');
        google.script.run.withSuccessHandler(function (r) {
          if (r && r.address && $('f' + ADDRESS_IDX)) $('f' + ADDRESS_IDX).value = r.address;
          if (r && r.province && $('f' + PROVINCE_IDX)) $('f' + PROVINCE_IDX).value = r.province;
          showMsg(
            r && (r.address || r.province)
              ? 'Đã điền Vĩ độ/Kinh độ/Địa chỉ/Tỉnh thành phố — kiểm tra lại rồi bấm Lưu.'
              : 'Đã điền Vĩ độ/Kinh độ — không dò được Địa chỉ/Tỉnh thành phố tự động, tự gõ tay giúp mình.'
          );
        }).withFailureHandler(function () {
          showMsg('Đã điền Vĩ độ/Kinh độ — không dò được Địa chỉ/Tỉnh thành phố tự động, tự gõ tay giúp mình.');
        }).reverseGeocodeLatLng(lat, lng);
      },
      function (err) {
        var msg = err && err.code === 1
          ? 'Bạn chưa cho phép truy cập vị trí — vào cài đặt trình duyệt bật lại quyền vị trí cho trang này.'
          : 'Không lấy được vị trí (' + (err && err.message ? err.message : 'không rõ lý do') + ') — dùng nút "Tìm trên Google Maps" rồi gõ tay.';
        showErr(msg);
      },
      { enableHighAccuracy: true, timeout: 15000 }
    );
  }

  /** Mở Google Maps tìm theo tên cửa hàng (nếu đã có toạ độ thì tìm thẳng theo toạ độ, chính
   *  xác hơn) — dùng để xem đúng vị trí rồi chuột phải chọn "Sao chép toạ độ" bên đó, quay lại
   *  dán vào ô bên dưới + bấm "✅ Xác nhận" để tự điền. */
  function openMaps() {
    var lat = $('f' + LAT_IDX) ? $('f' + LAT_IDX).value : '';
    var lng = $('f' + LNG_IDX) ? $('f' + LNG_IDX).value : '';
    var query = (lat && lng) ? (lat + ',' + lng) : ($('f' + NAME_IDX) ? $('f' + NAME_IDX).value : '');
    if (!query) { showErr('Nhập Tên cửa hàng hoặc Vĩ độ/Kinh độ trước'); return; }
    window.open('https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(query), '_blank');
  }

  /** Tách toạ độ (lat,lng) từ nội dung dán vào — LỌC SẠCH mọi ký tự thừa trước (ngoặc, độ °,
   *  chữ N/E, khoảng trắng lạ...), chỉ giữ số/dấu chấm/dấu phẩy/dấu trừ, rồi CẮT THẲNG theo dấu
   *  phẩy đầu tiên (dạng Google Maps "Sao chép toạ độ" luôn là "vĩ độ, kinh độ", vd
   *  "10.781024482796337, 106.94970051971518", kể cả khi dán kèm ngoặc/ký tự lạ như
   *  "(10.78, 106.94)" hay "10.78°N, 106.94°E") rồi ép 2 nửa thành số — không dùng regex kiểm
   *  tra định dạng (từng lỗi khó hiểu ở môi trường thật dù test Node.js luôn đúng, lọc + cắt
   *  bằng indexOf()/slice() đơn giản hơn nhiều nên chắc chắn hơn). Trả về {lat,lng} hoặc null
   *  nếu không tách được 2 số. */
  function extractLatLngFromPastedText_(text) {
    var clean = String(text || '')
      .replace(/[\uFF0C]/g, ',')
      .replace(/[^0-9.,\-]/g, '')
      .trim();
    var idx = clean.indexOf(',');
    if (idx === -1) return null;
    var lat = Number(clean.slice(0, idx));
    var lng = Number(clean.slice(idx + 1));
    if (isNaN(lat) || isNaN(lng)) return null;
    return { lat: lat, lng: lng };
  }

  /** Bấm "✅ Xác nhận" cạnh ô dán — tách toạ độ (lat,lng) từ nội dung vừa dán (đã sao chép trực
   *  tiếp bên Google Maps), điền vào Vĩ độ/Kinh độ, rồi tự dò ngược Địa chỉ/Tỉnh thành phố (dùng
   *  chung reverseGeocodeLatLng với nút "📍 Chọn vị trí ngay đây"). */
  function mapPasteConfirm() {
    var raw = $('mapPasteInput').value.trim();
    if (!raw) { showErr('Dán toạ độ vừa sao chép từ Google Maps vào ô trước'); return; }
    var pos = extractLatLngFromPastedText_(raw);
    if (!pos) {
      showErr(
        'Không tìm thấy toạ độ trong nội dung đã dán — bên Google Maps, chuột phải đúng vị trí ' +
        'chọn "Sao chép toạ độ" rồi dán lại vào đây.'
      );
      return;
    }

    if ($('f' + LAT_IDX)) $('f' + LAT_IDX).value = pos.lat;
    if ($('f' + LNG_IDX)) $('f' + LNG_IDX).value = pos.lng;
    showMsg('Đã điền Vĩ độ/Kinh độ — đang dò Địa chỉ/Tỉnh thành phố…');
    google.script.run.withSuccessHandler(function (r) {
      if (r && r.address && $('f' + ADDRESS_IDX)) $('f' + ADDRESS_IDX).value = r.address;
      if (r && r.province && $('f' + PROVINCE_IDX)) $('f' + PROVINCE_IDX).value = r.province;
      $('mapPasteInput').value = '';
      showMsg(
        r && (r.address || r.province)
          ? 'Đã điền Vĩ độ/Kinh độ/Địa chỉ/Tỉnh thành phố — kiểm tra lại rồi bấm Lưu.'
          : 'Đã điền Vĩ độ/Kinh độ — không dò được Địa chỉ/Tỉnh thành phố tự động, tự gõ tay giúp mình.'
      );
    }).withFailureHandler(function () {
      $('mapPasteInput').value = '';
      showMsg('Đã điền Vĩ độ/Kinh độ — không dò được Địa chỉ/Tỉnh thành phố tự động, tự gõ tay giúp mình.');
    }).reverseGeocodeLatLng(pos.lat, pos.lng);
  }

  /** Chuyển tab ảnh (Ảnh đại diện/Ảnh quán/Ảnh sản phẩm) — mỗi tab giữ input file + grid
   *  riêng, không dùng chung 1 panel nữa nên chuyển qua lại không mất trạng thái đang chọn ở
   *  tab kia. */
  function switchPhotoTab(tab) {
    activePhotoTab = tab;
    PHOTO_TABS.forEach(function (t) {
      var active = t === tab;
      $(t.panel).classList.toggle('photo-panel-active', active);
      $(t.tabBtn).classList.toggle('photo-tab-active', active);
    });
    loadPhotoGridFor(tab);
  }

  function resetPhotoTabs() {
    PHOTO_TABS.forEach(function (t) { $(t.grid).innerHTML = ''; });
    switchPhotoTab(PHOTO_TABS[0]);
  }

  function loadPhotoGridFor(tab) {
    var nameEl = $('f' + NAME_IDX);
    var storeName = nameEl ? nameEl.value.trim() : '';
    if (!storeName) { $(tab.grid).innerHTML = ''; return; }
    google.script.run.withSuccessHandler(function (images) {
      var grid = $(tab.grid);
      grid.innerHTML = '';
      images.forEach(function (img) {
        var thumb = document.createElement('div');
        thumb.className = 'thumb';
        var im = document.createElement('img');
        im.src = img.thumbnailUrl;
        im.title = img.name;
        thumb.appendChild(im);
        var del = document.createElement('div');
        del.className = 'del';
        del.textContent = '×';
        del.title = 'Xoá ảnh';
        del.onclick = function () { removePhoto(tab, img.id); };
        thumb.appendChild(del);
        grid.appendChild(thumb);
      });
    }).withFailureHandler(showErr).listImagesInStoreSubfolder(storeName, tab.subfolder);
  }

  /** Ảnh quán/Ảnh sản phẩm cho chọn NHIỀU ảnh cùng lúc (input file có "multiple") — tải TUẦN TỰ
   *  từng ảnh một (không tải song song, tránh vượt giới hạn gọi đồng thời của Apps Script), báo
   *  tiến độ theo từng ảnh, chỉ làm mới lưới ảnh 1 lần sau khi xong hết. Ảnh đại diện vẫn chỉ
   *  chọn được 1 ảnh (input không có "multiple") nên vòng lặp này chỉ chạy đúng 1 vòng. */
  function uploadPhotoFor(tab) {
    var fileInput = $(tab.fileInput);
    var nameEl = $('f' + NAME_IDX);
    var storeName = nameEl ? nameEl.value.trim() : '';
    if (!storeName) { showErr('Nhập Tên cửa hàng (và Lưu, nếu là quán mới) trước khi quản lý ảnh'); return; }
    if (!fileInput.files.length) { showErr('Chọn ít nhất 1 ảnh trước'); return; }
    var files = Array.prototype.slice.call(fileInput.files);
    var oversized = files.filter(function (f) { return f.size > MAX_PHOTO_BYTES; });
    if (oversized.length) {
      showErr('Ảnh "' + oversized[0].name + '" nặng ' + (oversized[0].size / 1024).toFixed(0) +
        'KB, vượt quá ' + (MAX_PHOTO_BYTES / 1024) + 'KB cho phép — chọn ảnh nhẹ hơn hoặc nén lại trước khi tải lên.');
      return;
    }
    uploadFilesSequentially_(tab, storeName, files, 0, [], fileInput);
  }

  function uploadFilesSequentially_(tab, storeName, files, index, errors, fileInput) {
    if (index >= files.length) {
      fileInput.value = '';
      loadPhotoGridFor(tab);
      if (errors.length) {
        showErr('Đã tải ' + (files.length - errors.length) + '/' + files.length + ' ảnh — lỗi: ' + errors.join('; '));
      } else {
        showMsg('Đã tải xong ' + files.length + ' ảnh.');
      }
      return;
    }
    var file = files[index];
    showMsg('Đang tải ảnh ' + (index + 1) + '/' + files.length + ' ("' + file.name + '")…');
    var reader = new FileReader();
    reader.onload = function () {
      var base64 = reader.result.split(',')[1];
      google.script.run.withSuccessHandler(function () {
        if (tab.cloudinaryFolder) {
          uploadToCloudinaryAndContinue_(tab, storeName, files, index, errors, fileInput, file, base64);
        } else {
          uploadFilesSequentially_(tab, storeName, files, index + 1, errors, fileInput);
        }
      }).withFailureHandler(function (e) {
        errors.push(file.name + ': ' + (e && e.message ? e.message : e));
        uploadFilesSequentially_(tab, storeName, files, index + 1, errors, fileInput);
      }).uploadImageToStoreSubfolder(storeName, tab.subfolder, file.name, file.type, base64, tab.replace);
    };
    reader.readAsDataURL(file);
  }

  /** Sau khi ảnh đã tải xong lên Drive (thư mục nội bộ), với tab có cloudinaryFolder (hiện chỉ
   *  Ảnh đại diện) tải THÊM 1 lần nữa lên Cloudinary để có link công khai hiển thị được trên app
   *  (merchants.logo_url) — điền vào form (currentLogoUrl, ghi thật vào sheet khi bấm "💾 Lưu"
   *  như mọi trường khác, xem collectValues()). Lỗi ở bước Cloudinary không chặn các ảnh còn lại
   *  (ảnh vẫn đã lưu được trên Drive, chỉ là chưa có link công khai). */
  function uploadToCloudinaryAndContinue_(tab, storeName, files, index, errors, fileInput, file, base64) {
    google.script.run.withSuccessHandler(function (url) {
      currentLogoUrl = url;
      showMsg('Đã tải ảnh lên Cloudinary — nhớ bấm "💾 Lưu" để ghi lại link ảnh đại diện.');
      var logoArea = $('logoUrlArea');
      if (logoArea) {
        logoArea.innerHTML = '';
        var logoImg = document.createElement('img');
        logoImg.src = url;
        logoImg.style.cssText = 'width:56px;height:56px;object-fit:cover;border-radius:4px;border:1px solid #ccc;vertical-align:middle;margin-right:8px;';
        logoArea.appendChild(logoImg);
        var logoLink = document.createElement('a');
        logoLink.href = url; logoLink.target = '_blank'; logoLink.textContent = 'Xem ảnh gốc';
        logoArea.appendChild(logoLink);
      }
      uploadFilesSequentially_(tab, storeName, files, index + 1, errors, fileInput);
    }).withFailureHandler(function (e) {
      errors.push(file.name + ' (Cloudinary): ' + (e && e.message ? e.message : e));
      uploadFilesSequentially_(tab, storeName, files, index + 1, errors, fileInput);
    }).uploadImageToCloudinary(base64, file.type, file.name, tab.cloudinaryFolder);
  }

  function removePhoto(tab, fileId) {
    if (!confirm('Xoá ảnh này?')) return;
    google.script.run.withSuccessHandler(function () { loadPhotoGridFor(tab); }).withFailureHandler(showErr).deleteImage(fileId);
  }
})();
</script>
`;
}


/** ============================================================================================
 *  GIAO DIỆN — FORM QUẢN LÝ SẢN PHẨM
 *  ============================================================================================ */

function buildProductManagerHtml_(idPrefix) {
  idPrefix = idPrefix || '';
  return `
<style>
  #${idPrefix}root { font-family: Arial, sans-serif; font-size: 13px; }
  #${idPrefix}root label { font-weight: bold; display: block; margin-top: 8px; }
  #${idPrefix}root input[type=text], #${idPrefix}root textarea, #${idPrefix}root select { width: 100%; padding: 6px; margin-top: 3px; box-sizing: border-box; }
  #${idPrefix}root textarea { resize: vertical; min-height: 50px; font-family: inherit; }
  #${idPrefix}root button { padding: 7px 14px; margin: 10px 6px 0 0; cursor: pointer; }
  #${idPrefix}productList { max-height: 150px; overflow: auto; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px; }
  #${idPrefix}productList div { padding: 6px; cursor: pointer; border-bottom: 1px solid #eee; }
  #${idPrefix}productList div:hover { background: #f0f4ff; }
  #${idPrefix}root .imgRow { display: flex; gap: 8px; align-items: center; margin-top: 3px; }
  #${idPrefix}pImgPreview { width: 56px; height: 56px; object-fit: cover; border: 1px solid #ccc; border-radius: 4px; display: none; }
  #${idPrefix}root .photo-panel { display: none; border: 1px solid #ccc; border-radius: 6px; padding: 10px; margin-top: 10px; background: #fafafa; }
  #${idPrefix}root .grid { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
  #${idPrefix}root .thumb { width: 88px; height: 88px; }
  #${idPrefix}root .thumb img { width: 100%; height: 100%; object-fit: cover; border-radius: 4px; border: 1px solid #ddd; cursor: pointer; }
  #${idPrefix}toppingGroupBox { max-height: 130px; overflow: auto; border: 1px solid #ccc; border-radius: 4px; margin-top: 3px; padding: 6px; }
  #${idPrefix}toppingGroupBox label { display: flex; align-items: center; gap: 6px; font-weight: normal; margin: 4px 0; }
  #${idPrefix}toppingGroupBox label input { width: auto; margin: 0; }
  #${idPrefix}msg { color: #0a7d1f; font-weight: bold; margin-top: 8px; min-height: 18px; }
  #${idPrefix}err { color: #c0392b; font-weight: bold; }
</style>

<div id="${idPrefix}root">
  <label>Chọn cửa hàng</label>
  <select id="${idPrefix}storeSelect"></select>

  <label>Sản phẩm của quán</label>
  <div id="${idPrefix}productList"><i>Chọn cửa hàng để xem sản phẩm</i></div>
  <button id="${idPrefix}btnNewProduct">+ Thêm sản phẩm mới</button>
  <div style="color:#888; font-size:12px; margin-top:4px;">Sau khi lưu sản phẩm, sang tab <b>Biến thể</b> thêm ít nhất 1 biến thể (giá) thì sản phẩm mới bán được.</div>

  <label>Tên sản phẩm *</label>
  <input type="text" id="${idPrefix}pName">

  <label>Mô tả</label>
  <textarea id="${idPrefix}pDesc"></textarea>

  <label>Đơn vị</label>
  <input type="text" id="${idPrefix}pUnit" placeholder="cái">

  <label>Trạng thái</label>
  <select id="${idPrefix}pStatus"></select>

  <label>Nhóm topping áp dụng</label>
  <div id="${idPrefix}toppingGroupBox"><i>Chọn cửa hàng để xem các nhóm topping đã tạo</i></div>

  <label>Ảnh sản phẩm</label>
  <div class="imgRow">
    <img id="${idPrefix}pImgPreview" src="">
    <input type="text" id="${idPrefix}pImgUrl" placeholder="Chưa chọn ảnh" readonly>
    <button id="${idPrefix}btnPickImage">Chọn ảnh từ Ảnh menu</button>
  </div>
  <div class="imgRow" style="margin-top:6px;">
    <input type="file" id="${idPrefix}pImgUploadFile" accept="image/*">
    <button id="${idPrefix}btnUploadProductImage">📤 Tải ảnh mới lên</button>
  </div>
  <div style="color:#888; font-size:12px; margin-top:2px;">
    Tải ảnh mới lên Cloudinary để hiển thị trên app (khuyên dùng) — hoặc "Chọn ảnh từ Ảnh menu"
    nếu ảnh đã tải sẵn bên tab Cửa hàng &gt; Ảnh sản phẩm trước đó.
  </div>

  <div id="${idPrefix}imagePickerPanel" class="photo-panel">
    <div>Bấm vào 1 ảnh để chọn — ảnh lấy từ đúng thư mục "${SUBFOLDER_MENU_PHOTOS}" của quán đang chọn.</div>
    <div class="grid" id="${idPrefix}pImageGrid"></div>
  </div>

  <div id="${idPrefix}pSystemIdArea" style="color:#888; font-size:12px; margin-top:8px;"></div>

  <div>
    <button id="${idPrefix}btnSaveProduct">💾 Lưu sản phẩm</button>
    <button id="${idPrefix}btnDeleteProduct">🗑 Xoá sản phẩm</button>
    <button onclick="google.script.host.close()">Đóng</button>
  </div>
  <div id="${idPrefix}msg"></div>
  <div id="${idPrefix}err"></div>
</div>

<script>
(function () {
  var PFX = '${idPrefix}';
  var $ = function (id) { return document.getElementById(PFX + id); };
  var currentStore = '';
  var currentRow = null;
  var products = [];
  var currentImages = [];
  var currentToppingGroupsValue = '';
  var NAME_IDX = ${PRODUCT_NAME_COLUMN - 1};
  var DESC_IDX = ${PRODUCT_DESCRIPTION_COLUMN - 1};
  var UNIT_IDX = ${PRODUCT_UNIT_COLUMN - 1};
  var STATUS_IDX = ${PRODUCT_STATUS_COLUMN - 1};
  var IMAGE_IDX = ${PRODUCT_IMAGE_COLUMN - 1};
  var TOPPING_GROUPS_IDX = ${PRODUCT_TOPPING_GROUPS_COLUMN - 1};
  var SYSTEM_ID_IDX = ${PRODUCT_SYSTEM_ID_COLUMN - 1};
  var EDITABLE_COLUMN_COUNT = ${PRODUCT_SYSTEM_ID_COLUMN - 1};
  var STATUS_OPTIONS = ${JSON.stringify(PRODUCT_STATUS_OPTIONS)};
  var MAX_PHOTO_BYTES = ${PHOTO_MAX_BYTES};

  function showMsg(t) { $('msg').innerText = t; $('err').innerText = ''; }
  function showErr(e) { $('err').innerText = 'Lỗi: ' + (e && e.message ? e.message : e); $('msg').innerText = ''; }

  function init() {
    STATUS_OPTIONS.forEach(function (o) {
      var opt = document.createElement('option');
      opt.value = o.value; opt.text = o.label;
      $('pStatus').appendChild(opt);
    });
    google.script.run.withSuccessHandler(function (list) {
      var sel = $('storeSelect');
      sel.innerHTML = '';
      var opt0 = document.createElement('option');
      opt0.value = ''; opt0.text = '-- Chọn cửa hàng --';
      sel.appendChild(opt0);
      list.forEach(function (s) {
        var opt = document.createElement('option');
        opt.value = s.name; opt.text = s.name;
        sel.appendChild(opt);
      });
    }).withFailureHandler(showErr).listStores();
  }

  $('storeSelect').addEventListener('change', onSelectStore);
  $('btnNewProduct').addEventListener('click', newProduct);
  $('btnSaveProduct').addEventListener('click', saveProduct);
  $('btnDeleteProduct').addEventListener('click', removeProduct);
  $('btnPickImage').addEventListener('click', openImagePicker);
  $('btnUploadProductImage').addEventListener('click', uploadProductImageToCloudinary);
  init();

  function onSelectStore() {
    currentStore = $('storeSelect').value;
    $('imagePickerPanel').style.display = 'none';
    newProduct();
    loadProducts();
    loadToppingGroupNames();
  }

  function loadToppingGroupNames() {
    var box = $('toppingGroupBox');
    if (!currentStore) { box.innerHTML = '<i>Chọn cửa hàng để xem các nhóm topping đã tạo</i>'; return; }
    google.script.run.withSuccessHandler(function (names) {
      box.innerHTML = '';
      if (!names.length) {
        box.innerHTML = '<i>Quán này chưa có nhóm topping nào — sang tab Topping để tạo.</i>';
        return;
      }
      names.forEach(function (n) {
        var label = document.createElement('label');
        var cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.value = n;
        label.appendChild(cb);
        label.appendChild(document.createTextNode(n));
        box.appendChild(label);
      });
      applyToppingGroupSelection();
    }).withFailureHandler(function () {}).listToppingGroupNames(currentStore);
  }

  function applyToppingGroupSelection() {
    var selected = currentToppingGroupsValue.split(',').map(function (s) { return s.trim(); }).filter(Boolean);
    var box = $('toppingGroupBox');
    var checkboxes = box.querySelectorAll('input[type=checkbox]');
    for (var i = 0; i < checkboxes.length; i++) {
      checkboxes[i].checked = selected.indexOf(checkboxes[i].value) !== -1;
    }
  }

  function getSelectedToppingGroups() {
    var box = $('toppingGroupBox');
    var checkboxes = box.querySelectorAll('input[type=checkbox]:checked');
    var names = [];
    for (var i = 0; i < checkboxes.length; i++) names.push(checkboxes[i].value);
    return names.join(', ');
  }

  function loadProducts() {
    var el = $('productList');
    if (!currentStore) { el.innerHTML = '<i>Chọn cửa hàng để xem sản phẩm</i>'; return; }
    google.script.run.withSuccessHandler(function (list) {
      products = list;
      el.innerHTML = '';
      if (!list.length) { el.innerHTML = '<i>Chưa có sản phẩm</i>'; return; }
      list.forEach(function (p) {
        var div = document.createElement('div');
        div.textContent = p.values[NAME_IDX] || '(chưa đặt tên)';
        div.onclick = function () { selectProduct(p.row); };
        el.appendChild(div);
      });
    }).withFailureHandler(showErr).listProductsByStore(currentStore);
  }

  function selectProduct(row) {
    currentRow = row;
    var p = products.filter(function (x) { return x.row === row; })[0];
    if (p) fillForm(p.values);
  }

  function newProduct() {
    currentRow = null;
    var blank = new Array(${PRODUCT_HEADERS.length}).fill('');
    blank[STATUS_IDX] = 'active';
    fillForm(blank);
  }

  function fillForm(v) {
    $('pName').value = v[NAME_IDX] || '';
    $('pDesc').value = v[DESC_IDX] || '';
    $('pUnit').value = v[UNIT_IDX] || '';
    $('pStatus').value = v[STATUS_IDX] || 'active';
    $('pImgUrl').value = v[IMAGE_IDX] || '';
    currentToppingGroupsValue = v[TOPPING_GROUPS_IDX] || '';
    applyToppingGroupSelection();
    updateImgPreview(v[IMAGE_IDX] || '');
    $('pSystemIdArea').textContent = v[SYSTEM_ID_IDX]
      ? 'Đã đồng bộ — ID: ' + v[SYSTEM_ID_IDX]
      : 'Chưa đồng bộ lên hệ thống thật — sang tab "Đồng bộ CSDL" để đẩy lên';
  }

  function updateImgPreview(url) {
    var img = $('pImgPreview');
    if (url) { img.src = url; img.style.display = 'inline-block'; } else { img.style.display = 'none'; }
  }

  function saveProduct() {
    if (!currentStore) { showErr('Chọn cửa hàng trước'); return; }
    var name = $('pName').value.trim();
    if (!name) { showErr('Chưa nhập Tên sản phẩm'); return; }
    var values = new Array(EDITABLE_COLUMN_COUNT).fill('');
    values[${PRODUCT_STORE_COLUMN - 1}] = currentStore;
    values[NAME_IDX] = name;
    values[DESC_IDX] = $('pDesc').value;
    values[UNIT_IDX] = $('pUnit').value;
    values[STATUS_IDX] = $('pStatus').value;
    values[IMAGE_IDX] = $('pImgUrl').value;
    values[TOPPING_GROUPS_IDX] = getSelectedToppingGroups();
    google.script.run.withSuccessHandler(function (res) {
      currentRow = res.row;
      showMsg('Đã lưu sản phẩm');
      loadProducts();
    }).withFailureHandler(showErr).upsertProduct(currentRow, values);
  }

  function removeProduct() {
    if (!currentRow) { showErr('Chưa chọn sản phẩm để xoá'); return; }
    if (!confirm('Xoá sản phẩm này?')) return;
    google.script.run.withSuccessHandler(function () {
      showMsg('Đã xoá sản phẩm');
      newProduct();
      loadProducts();
    }).withFailureHandler(showErr).deleteProduct(currentRow);
  }

  function openImagePicker() {
    if (!currentStore) { showErr('Chọn cửa hàng trước'); return; }
    $('imagePickerPanel').style.display = 'block';
    google.script.run.withSuccessHandler(function (images) {
      currentImages = images;
      var grid = $('pImageGrid');
      grid.innerHTML = '';
      images.forEach(function (img, idx) {
        var thumb = document.createElement('div');
        thumb.className = 'thumb';
        var im = document.createElement('img');
        im.src = img.thumbnailUrl;
        im.title = img.name;
        im.onclick = function () { pickImage(idx); };
        thumb.appendChild(im);
        grid.appendChild(thumb);
      });
    }).withFailureHandler(showErr).listImagesInStoreSubfolder(currentStore, '${SUBFOLDER_MENU_PHOTOS}');
  }

  function pickImage(idx) {
    var img = currentImages[idx];
    $('pImgUrl').value = img.url;
    updateImgPreview(img.url);
    $('imagePickerPanel').style.display = 'none';
  }

  /** Tải ảnh sản phẩm mới thẳng lên Cloudinary (folder 'products') — điền luôn vào pImgUrl, KHÔNG
   *  qua Drive như "Chọn ảnh từ Ảnh menu" (đó là ảnh đã có sẵn trong thư mục nội bộ của quán,
   *  không phải link công khai — Drive không hotlink ổn định cho ảnh hiển thị công khai). */
  function uploadProductImageToCloudinary() {
    var fileInput = $('pImgUploadFile');
    if (!fileInput.files.length) { showErr('Chọn 1 ảnh trước'); return; }
    var file = fileInput.files[0];
    if (file.size > MAX_PHOTO_BYTES) {
      showErr('Ảnh "' + file.name + '" nặng ' + (file.size / 1024).toFixed(0) +
        'KB, vượt quá ' + (MAX_PHOTO_BYTES / 1024) + 'KB cho phép — chọn ảnh nhẹ hơn hoặc nén lại trước khi tải lên.');
      fileInput.value = '';
      return;
    }
    showMsg('Đang tải ảnh lên Cloudinary…');
    var reader = new FileReader();
    reader.onload = function () {
      var base64 = reader.result.split(',')[1];
      google.script.run.withSuccessHandler(function (url) {
        $('pImgUrl').value = url;
        updateImgPreview(url);
        fileInput.value = '';
        showMsg('Đã tải ảnh lên — nhớ bấm "💾 Lưu sản phẩm" để ghi lại.');
      }).withFailureHandler(showErr).uploadImageToCloudinary(base64, file.type, file.name, 'products');
    };
    reader.readAsDataURL(file);
  }
})();
</script>
`;
}

function buildVariantManagerHtml_(idPrefix) {
  idPrefix = idPrefix || '';
  return `
<style>
  #${idPrefix}root { font-family: Arial, sans-serif; font-size: 13px; }
  #${idPrefix}root label { font-weight: bold; display: block; margin-top: 8px; }
  #${idPrefix}root input[type=text], #${idPrefix}root input[type=number], #${idPrefix}root select { width: 100%; padding: 6px; margin-top: 3px; box-sizing: border-box; }
  #${idPrefix}root button { padding: 7px 14px; margin: 10px 6px 0 0; cursor: pointer; }
  #${idPrefix}variantList { max-height: 150px; overflow: auto; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px; }
  #${idPrefix}variantList div { padding: 6px; cursor: pointer; border-bottom: 1px solid #eee; }
  #${idPrefix}variantList div:hover { background: #f0f4ff; }
  #${idPrefix}root .checkRow { display: flex; align-items: center; gap: 6px; margin-top: 10px; }
  #${idPrefix}root .checkRow label { margin: 0; font-weight: normal; }
  #${idPrefix}root .checkRow input { width: auto; margin: 0; }
  #${idPrefix}msg { color: #0a7d1f; font-weight: bold; margin-top: 8px; min-height: 18px; }
  #${idPrefix}err { color: #c0392b; font-weight: bold; }
</style>

<div id="${idPrefix}root">
  <label>Chọn cửa hàng</label>
  <select id="${idPrefix}storeSelect"></select>

  <label>Chọn sản phẩm</label>
  <select id="${idPrefix}productSelect"></select>

  <label>Biến thể của sản phẩm</label>
  <div id="${idPrefix}variantList"><i>Chọn sản phẩm để xem biến thể</i></div>
  <button id="${idPrefix}btnNewVariant">+ Thêm biến thể mới</button>

  <label>Tên biến thể *</label>
  <input type="text" id="${idPrefix}vName" placeholder="Mặc định, Size L, ...">

  <label>Giá bán *</label>
  <input type="number" id="${idPrefix}vPrice" step="1" min="0">

  <label>Trọng lượng (g)</label>
  <input type="number" id="${idPrefix}vWeight" step="1" min="0">

  <div class="checkRow">
    <input type="checkbox" id="${idPrefix}vIsDefault">
    <label for="${idPrefix}vIsDefault">Là biến thể mặc định</label>
  </div>
  <div class="checkRow">
    <input type="checkbox" id="${idPrefix}vIsActive" checked>
    <label for="${idPrefix}vIsActive">Đang bán</label>
  </div>

  <div id="${idPrefix}vSystemIdArea" style="color:#888; font-size:12px; margin-top:8px;"></div>

  <div>
    <button id="${idPrefix}btnSaveVariant">💾 Lưu biến thể</button>
    <button id="${idPrefix}btnDeleteVariant">🗑 Xoá biến thể</button>
    <button onclick="google.script.host.close()">Đóng</button>
  </div>
  <div id="${idPrefix}msg"></div>
  <div id="${idPrefix}err"></div>
</div>

<script>
(function () {
  var PFX = '${idPrefix}';
  var $ = function (id) { return document.getElementById(PFX + id); };
  var currentStore = '';
  var currentProduct = '';
  var currentRow = null;
  var variants = [];
  var NAME_IDX = ${VARIANT_NAME_COLUMN - 1};
  var PRICE_IDX = ${VARIANT_PRICE_COLUMN - 1};
  var WEIGHT_IDX = ${VARIANT_WEIGHT_COLUMN - 1};
  var IS_DEFAULT_IDX = ${VARIANT_IS_DEFAULT_COLUMN - 1};
  var IS_ACTIVE_IDX = ${VARIANT_IS_ACTIVE_COLUMN - 1};
  var SYSTEM_ID_IDX = ${VARIANT_SYSTEM_ID_COLUMN - 1};
  var EDITABLE_COLUMN_COUNT = ${VARIANT_SYSTEM_ID_COLUMN - 1};

  function showMsg(t) { $('msg').innerText = t; $('err').innerText = ''; }
  function showErr(e) { $('err').innerText = 'Lỗi: ' + (e && e.message ? e.message : e); $('msg').innerText = ''; }

  function init() {
    google.script.run.withSuccessHandler(function (list) {
      var sel = $('storeSelect');
      sel.innerHTML = '';
      var opt0 = document.createElement('option');
      opt0.value = ''; opt0.text = '-- Chọn cửa hàng --';
      sel.appendChild(opt0);
      list.forEach(function (s) {
        var opt = document.createElement('option');
        opt.value = s.name; opt.text = s.name;
        sel.appendChild(opt);
      });
    }).withFailureHandler(showErr).listStores();
  }

  $('storeSelect').addEventListener('change', onSelectStore);
  $('productSelect').addEventListener('change', onSelectProduct);
  $('btnNewVariant').addEventListener('click', newVariant);
  $('btnSaveVariant').addEventListener('click', saveVariant);
  $('btnDeleteVariant').addEventListener('click', removeVariant);
  init();

  function onSelectStore() {
    currentStore = $('storeSelect').value;
    currentProduct = '';
    $('productSelect').innerHTML = '';
    $('variantList').innerHTML = '<i>Chọn sản phẩm để xem biến thể</i>';
    newVariant();
    if (!currentStore) return;
    google.script.run.withSuccessHandler(function (list) {
      var sel = $('productSelect');
      sel.innerHTML = '';
      var opt0 = document.createElement('option');
      opt0.value = ''; opt0.text = '-- Chọn sản phẩm --';
      sel.appendChild(opt0);
      list.forEach(function (p) {
        var opt = document.createElement('option');
        opt.value = p.values[${PRODUCT_NAME_COLUMN - 1}]; opt.text = p.values[${PRODUCT_NAME_COLUMN - 1}];
        sel.appendChild(opt);
      });
    }).withFailureHandler(showErr).listProductsByStore(currentStore);
  }

  function onSelectProduct() {
    currentProduct = $('productSelect').value;
    newVariant();
    loadVariants();
  }

  function loadVariants() {
    var el = $('variantList');
    if (!currentStore || !currentProduct) { el.innerHTML = '<i>Chọn sản phẩm để xem biến thể</i>'; return; }
    google.script.run.withSuccessHandler(function (list) {
      variants = list;
      el.innerHTML = '';
      if (!list.length) { el.innerHTML = '<i>Chưa có biến thể — sản phẩm này chưa bán được, cần thêm ít nhất 1 biến thể</i>'; return; }
      list.forEach(function (v) {
        var div = document.createElement('div');
        div.textContent = (v.values[NAME_IDX] || '(chưa đặt tên)') + ' — ' + (v.values[PRICE_IDX] || '') + ' đ';
        div.onclick = function () { selectVariant(v.row); };
        el.appendChild(div);
      });
    }).withFailureHandler(showErr).listVariantsByProduct(currentStore, currentProduct);
  }

  function selectVariant(row) {
    currentRow = row;
    var v = variants.filter(function (x) { return x.row === row; })[0];
    if (v) fillForm(v.values);
  }

  function newVariant() {
    currentRow = null;
    $('vName').value = '';
    $('vPrice').value = '';
    $('vWeight').value = '';
    $('vIsDefault').checked = false;
    $('vIsActive').checked = true;
    $('vSystemIdArea').textContent = '';
  }

  function fillForm(v) {
    $('vName').value = v[NAME_IDX] || '';
    $('vPrice').value = v[PRICE_IDX] || '';
    $('vWeight').value = v[WEIGHT_IDX] || '';
    $('vIsDefault').checked = !!v[IS_DEFAULT_IDX];
    $('vIsActive').checked = v[IS_ACTIVE_IDX] === '' || v[IS_ACTIVE_IDX] === undefined ? true : !!v[IS_ACTIVE_IDX];
    $('vSystemIdArea').textContent = v[SYSTEM_ID_IDX]
      ? 'Đã đồng bộ — ID: ' + v[SYSTEM_ID_IDX]
      : 'Chưa đồng bộ lên hệ thống thật — sang tab "Đồng bộ CSDL" để đẩy lên';
  }

  function saveVariant() {
    if (!currentStore || !currentProduct) { showErr('Chọn cửa hàng và sản phẩm trước'); return; }
    var name = $('vName').value.trim();
    if (!name) { showErr('Chưa nhập Tên biến thể'); return; }
    if ($('vPrice').value === '') { showErr('Chưa nhập Giá bán'); return; }
    var values = new Array(EDITABLE_COLUMN_COUNT).fill('');
    values[${VARIANT_STORE_COLUMN - 1}] = currentStore;
    values[${VARIANT_PRODUCT_COLUMN - 1}] = currentProduct;
    values[NAME_IDX] = name;
    values[PRICE_IDX] = Number($('vPrice').value);
    values[WEIGHT_IDX] = $('vWeight').value === '' ? '' : Number($('vWeight').value);
    values[IS_DEFAULT_IDX] = $('vIsDefault').checked;
    values[IS_ACTIVE_IDX] = $('vIsActive').checked;
    google.script.run.withSuccessHandler(function (res) {
      currentRow = res.row;
      showMsg('Đã lưu biến thể');
      loadVariants();
    }).withFailureHandler(showErr).upsertVariant(currentRow, values);
  }

  function removeVariant() {
    if (!currentRow) { showErr('Chưa chọn biến thể để xoá'); return; }
    if (!confirm('Xoá biến thể này?')) return;
    google.script.run.withSuccessHandler(function () {
      showMsg('Đã xoá biến thể');
      newVariant();
      loadVariants();
    }).withFailureHandler(showErr).deleteVariant(currentRow);
  }
})();
</script>
`;
}

function buildToppingManagerHtml_(idPrefix) {
  idPrefix = idPrefix || '';
  return `
<style>
  #${idPrefix}root { font-family: Arial, sans-serif; font-size: 13px; }
  #${idPrefix}root label { font-weight: bold; display: block; margin-top: 8px; }
  #${idPrefix}root input[type=text], #${idPrefix}root input[type=number], #${idPrefix}root select { width: 100%; padding: 6px; margin-top: 3px; box-sizing: border-box; }
  #${idPrefix}root button { padding: 7px 14px; margin: 10px 6px 0 0; cursor: pointer; }
  #${idPrefix}toppingList { max-height: 150px; overflow: auto; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px; }
  #${idPrefix}toppingList div { padding: 6px; cursor: pointer; border-bottom: 1px solid #eee; }
  #${idPrefix}toppingList div:hover { background: #f0f4ff; }
  #${idPrefix}toppingList div.groupHeader { font-weight: bold; background: #f5f5f5; cursor: default; }
  #${idPrefix}toppingList div.groupHeader:hover { background: #f5f5f5; }
  #${idPrefix}root .checkRow { display: flex; align-items: center; gap: 6px; margin-top: 10px; }
  #${idPrefix}root .checkRow label { margin: 0; font-weight: normal; }
  #${idPrefix}root .checkRow input { width: auto; margin: 0; }
  #${idPrefix}msg { color: #0a7d1f; font-weight: bold; margin-top: 8px; min-height: 18px; }
  #${idPrefix}err { color: #c0392b; font-weight: bold; }
</style>

<div id="${idPrefix}root">
  <label>Chọn cửa hàng</label>
  <select id="${idPrefix}storeSelect"></select>

  <label>Topping của cửa hàng</label>
  <div id="${idPrefix}toppingList"><i>Chọn cửa hàng để xem topping</i></div>
  <button id="${idPrefix}btnNewTopping">+ Thêm topping mới</button>
  <div style="color:#888; font-size:12px; margin-top:4px;">Sang tab <b>Sản phẩm</b>, điền đúng <b>Tên nhóm topping</b> vào ô "Nhóm topping áp dụng" để gắn topping cho sản phẩm.</div>

  <label>Tên nhóm topping *</label>
  <input type="text" id="${idPrefix}tGroupName" placeholder="Vd: Chọn topping, Chọn size đá..." list="${idPrefix}groupNameList">
  <datalist id="${idPrefix}groupNameList"></datalist>

  <div class="checkRow">
    <input type="checkbox" id="${idPrefix}tRequired">
    <label for="${idPrefix}tRequired">Bắt buộc chọn</label>
  </div>
  <div class="checkRow">
    <input type="checkbox" id="${idPrefix}tAllowMultiple">
    <label for="${idPrefix}tAllowMultiple">Cho chọn nhiều</label>
  </div>

  <label>Tên topping *</label>
  <input type="text" id="${idPrefix}tName" placeholder="Vd: Trân châu, Thạch...">

  <label>Giá cộng thêm (VNĐ)</label>
  <input type="number" id="${idPrefix}tPrice" step="1" min="0">

  <div class="checkRow">
    <input type="checkbox" id="${idPrefix}tIsActive" checked>
    <label for="${idPrefix}tIsActive">Đang bán</label>
  </div>

  <div id="${idPrefix}tSystemIdArea" style="color:#888; font-size:12px; margin-top:8px;"></div>

  <div>
    <button id="${idPrefix}btnSaveTopping">💾 Lưu topping</button>
    <button id="${idPrefix}btnDeleteTopping">🗑 Xoá topping</button>
    <button onclick="google.script.host.close()">Đóng</button>
  </div>
  <div id="${idPrefix}msg"></div>
  <div id="${idPrefix}err"></div>
</div>

<script>
(function () {
  var PFX = '${idPrefix}';
  var $ = function (id) { return document.getElementById(PFX + id); };
  var currentStore = '';
  var currentRow = null;
  var toppings = [];
  var GROUP_NAME_IDX = ${TOPPING_GROUP_NAME_COLUMN - 1};
  var REQUIRED_IDX = ${TOPPING_GROUP_REQUIRED_COLUMN - 1};
  var ALLOW_MULTIPLE_IDX = ${TOPPING_GROUP_ALLOW_MULTIPLE_COLUMN - 1};
  var NAME_IDX = ${TOPPING_NAME_COLUMN - 1};
  var PRICE_IDX = ${TOPPING_PRICE_COLUMN - 1};
  var IS_ACTIVE_IDX = ${TOPPING_IS_ACTIVE_COLUMN - 1};
  var GROUP_ID_IDX = ${TOPPING_GROUP_ID_COLUMN - 1};
  var TOPPING_ID_IDX = ${TOPPING_ID_COLUMN - 1};
  var EDITABLE_COLUMN_COUNT = ${TOPPING_GROUP_ID_COLUMN - 1};

  function showMsg(t) { $('msg').innerText = t; $('err').innerText = ''; }
  function showErr(e) { $('err').innerText = 'Lỗi: ' + (e && e.message ? e.message : e); $('msg').innerText = ''; }

  function init() {
    google.script.run.withSuccessHandler(function (list) {
      var sel = $('storeSelect');
      sel.innerHTML = '';
      var opt0 = document.createElement('option');
      opt0.value = ''; opt0.text = '-- Chọn cửa hàng --';
      sel.appendChild(opt0);
      list.forEach(function (s) {
        var opt = document.createElement('option');
        opt.value = s.name; opt.text = s.name;
        sel.appendChild(opt);
      });
    }).withFailureHandler(showErr).listStores();
  }

  $('storeSelect').addEventListener('change', onSelectStore);
  $('btnNewTopping').addEventListener('click', newTopping);
  $('btnSaveTopping').addEventListener('click', saveTopping);
  $('btnDeleteTopping').addEventListener('click', removeTopping);
  init();

  function onSelectStore() {
    currentStore = $('storeSelect').value;
    newTopping();
    loadToppings();
    loadGroupNames();
  }

  function loadGroupNames() {
    var list = $('groupNameList');
    list.innerHTML = '';
    if (!currentStore) return;
    google.script.run.withSuccessHandler(function (names) {
      names.forEach(function (n) {
        var opt = document.createElement('option');
        opt.value = n;
        list.appendChild(opt);
      });
    }).withFailureHandler(function () {}).listToppingGroupNames(currentStore);
  }

  function loadToppings() {
    var el = $('toppingList');
    if (!currentStore) { el.innerHTML = '<i>Chọn cửa hàng để xem topping</i>'; return; }
    google.script.run.withSuccessHandler(function (list) {
      toppings = list;
      el.innerHTML = '';
      if (!list.length) { el.innerHTML = '<i>Chưa có topping</i>'; return; }
      var lastGroup = null;
      list.forEach(function (t) {
        var groupName = t.values[GROUP_NAME_IDX] || '(chưa đặt tên nhóm)';
        if (groupName !== lastGroup) {
          var header = document.createElement('div');
          header.className = 'groupHeader';
          header.textContent = groupName;
          el.appendChild(header);
          lastGroup = groupName;
        }
        var div = document.createElement('div');
        div.textContent = '— ' + (t.values[NAME_IDX] || '(chưa đặt tên)') + ' (+' + (t.values[PRICE_IDX] || 0) + ' đ)';
        div.onclick = function () { selectTopping(t.row); };
        el.appendChild(div);
      });
    }).withFailureHandler(showErr).listToppingsByStore(currentStore);
  }

  function selectTopping(row) {
    currentRow = row;
    var t = toppings.filter(function (x) { return x.row === row; })[0];
    if (t) fillForm(t.values);
  }

  function newTopping() {
    currentRow = null;
    $('tGroupName').value = '';
    $('tRequired').checked = false;
    $('tAllowMultiple').checked = false;
    $('tName').value = '';
    $('tPrice').value = '';
    $('tIsActive').checked = true;
    $('tSystemIdArea').textContent = '';
  }

  function fillForm(v) {
    $('tGroupName').value = v[GROUP_NAME_IDX] || '';
    $('tRequired').checked = !!v[REQUIRED_IDX];
    $('tAllowMultiple').checked = !!v[ALLOW_MULTIPLE_IDX];
    $('tName').value = v[NAME_IDX] || '';
    $('tPrice').value = v[PRICE_IDX] || '';
    $('tIsActive').checked = v[IS_ACTIVE_IDX] === '' || v[IS_ACTIVE_IDX] === undefined ? true : !!v[IS_ACTIVE_IDX];
    $('tSystemIdArea').textContent = v[TOPPING_ID_IDX]
      ? 'Đã đồng bộ — ID nhóm: ' + (v[GROUP_ID_IDX] || '(chưa có)') + ', ID topping: ' + v[TOPPING_ID_IDX]
      : 'Chưa đồng bộ lên hệ thống thật — sang tab "Đồng bộ CSDL" để đẩy lên';
  }

  function saveTopping() {
    if (!currentStore) { showErr('Chọn cửa hàng trước'); return; }
    var groupName = $('tGroupName').value.trim();
    if (!groupName) { showErr('Chưa nhập Tên nhóm topping'); return; }
    var name = $('tName').value.trim();
    if (!name) { showErr('Chưa nhập Tên topping'); return; }
    var values = new Array(EDITABLE_COLUMN_COUNT).fill('');
    values[${TOPPING_STORE_COLUMN - 1}] = currentStore;
    values[GROUP_NAME_IDX] = groupName;
    values[REQUIRED_IDX] = $('tRequired').checked;
    values[ALLOW_MULTIPLE_IDX] = $('tAllowMultiple').checked;
    values[NAME_IDX] = name;
    values[PRICE_IDX] = $('tPrice').value === '' ? 0 : Number($('tPrice').value);
    values[IS_ACTIVE_IDX] = $('tIsActive').checked;
    google.script.run.withSuccessHandler(function (res) {
      currentRow = res.row;
      showMsg('Đã lưu topping');
      loadToppings();
      loadGroupNames();
    }).withFailureHandler(showErr).upsertTopping(currentRow, values);
  }

  function removeTopping() {
    if (!currentRow) { showErr('Chưa chọn topping để xoá'); return; }
    if (!confirm('Xoá topping này?')) return;
    google.script.run.withSuccessHandler(function () {
      showMsg('Đã xoá topping');
      newTopping();
      loadToppings();
      loadGroupNames();
    }).withFailureHandler(showErr).deleteTopping(currentRow);
  }
})();
</script>
`;
}

function buildDbSyncManagerHtml_(idPrefix) {
  idPrefix = idPrefix || '';
  return `
<style>
  #${idPrefix}root { font-family: Arial, sans-serif; font-size: 13px; }
  #${idPrefix}root label { font-weight: bold; display: block; margin-top: 8px; }
  #${idPrefix}root select { width: 100%; padding: 6px; margin-top: 3px; box-sizing: border-box; }
  #${idPrefix}root button { padding: 7px 14px; margin: 10px 6px 0 0; cursor: pointer; }
  #${idPrefix}root button:disabled { opacity: 0.5; cursor: not-allowed; }
  #${idPrefix}diffBox { white-space: pre-wrap; font-family: 'Courier New', monospace; font-size: 12px; max-height: 320px; overflow: auto; border: 1px solid #ccc; border-radius: 4px; padding: 10px; margin-top: 8px; background: #fafafa; }
  #${idPrefix}msg { color: #0a7d1f; font-weight: bold; margin-top: 8px; min-height: 18px; }
  #${idPrefix}err { color: #c0392b; font-weight: bold; }
</style>

<div id="${idPrefix}root">
  <div style="color:#888; font-size:12px;">
    Đẩy dữ liệu cửa hàng (MERCHANT/TOPPING/PRODUCT/VARIANT) từ sheet lên hệ thống thật.
    Luôn kiểm tra danh sách thay đổi trước, xác nhận đúng rồi mới bấm đồng bộ — chỉ đụng vào
    cửa hàng do chính công cụ này quản lý, không ảnh hưởng cửa hàng khác trong hệ thống.
  </div>

  <label>Chọn cửa hàng</label>
  <select id="${idPrefix}storeSelect"></select>

  <div>
    <button id="${idPrefix}btnCheck">🔍 Kiểm tra thay đổi</button>
    <button id="${idPrefix}btnApply" disabled>✅ Xác nhận và đồng bộ</button>
  </div>

  <div id="${idPrefix}diffBox">Chọn cửa hàng rồi bấm "Kiểm tra thay đổi" để xem trước.</div>

  <div id="${idPrefix}msg"></div>
  <div id="${idPrefix}err"></div>

  <hr style="margin-top:20px; border:none; border-top:1px solid #ddd;">

  <label>Cửa hàng đã bị xoá hẳn khỏi sheet MERCHANT</label>
  <div style="color:#888; font-size:12px;">
    Xoá nguyên 1 dòng cửa hàng trong sheet MERCHANT (không phải xoá tên) không tự động xoá được
    trên hệ thống thật — bấm kiểm tra bên dưới để tìm những cửa hàng do GAS quản lý đã hết dấu
    vết trong sheet, rồi xoá CỨNG hẳn (kèm mọi chi nhánh/sản phẩm/biến thể/topping/đơn hàng liên
    quan — KHÔNG hoàn tác được).
  </div>
  <div>
    <button id="${idPrefix}btnCheckOrphans">🔍 Kiểm tra cửa hàng cần xoá</button>
    <button id="${idPrefix}btnDeleteOrphans" disabled>🗑️ Xoá cứng các cửa hàng này</button>
  </div>
  <div id="${idPrefix}orphanBox" style="white-space:pre-wrap; font-family:'Courier New',monospace; font-size:12px; max-height:200px; overflow:auto; border:1px solid #ccc; border-radius:4px; padding:10px; margin-top:8px; background:#fff5f5;">Bấm "Kiểm tra cửa hàng cần xoá" để xem.</div>
  <div id="${idPrefix}orphanMsg" style="color:#0a7d1f; font-weight:bold; margin-top:8px; min-height:18px;"></div>
  <div id="${idPrefix}orphanErr" style="color:#c0392b; font-weight:bold;"></div>
</div>

<script>
(function () {
  var PFX = '${idPrefix}';
  var $ = function (id) { return document.getElementById(PFX + id); };
  var currentStore = '';
  var diffChecked = false;
  var lastDeleteCount = 0;
  var orphanMerchants = [];

  function showMsg(t) { $('msg').innerText = t; $('err').innerText = ''; }
  function showErr(e) { $('err').innerText = 'Lỗi: ' + (e && e.message ? e.message : e); $('msg').innerText = ''; }

  function init() {
    google.script.run.withSuccessHandler(function (list) {
      var sel = $('storeSelect');
      sel.innerHTML = '';
      var opt0 = document.createElement('option');
      opt0.value = ''; opt0.text = '-- Chọn cửa hàng --';
      sel.appendChild(opt0);
      list.forEach(function (s) {
        var opt = document.createElement('option');
        opt.value = s.name; opt.text = s.name;
        sel.appendChild(opt);
      });
    }).withFailureHandler(showErr).listStores();
  }

  $('storeSelect').addEventListener('change', onSelectStore);
  $('btnCheck').addEventListener('click', checkDiff);
  $('btnApply').addEventListener('click', applySync);
  $('btnCheckOrphans').addEventListener('click', checkOrphans);
  $('btnDeleteOrphans').addEventListener('click', deleteOrphans);
  init();

  function showOrphanMsg(t) { $('orphanMsg').innerText = t; $('orphanErr').innerText = ''; }
  function showOrphanErr(e) { $('orphanErr').innerText = 'Lỗi: ' + (e && e.message ? e.message : e); $('orphanMsg').innerText = ''; }

  function checkOrphans() {
    $('btnDeleteOrphans').disabled = true;
    orphanMerchants = [];
    $('orphanBox').textContent = 'Đang kiểm tra...';
    showOrphanMsg('');
    google.script.run.withSuccessHandler(function (list) {
      orphanMerchants = list;
      if (!list.length) {
        $('orphanBox').textContent = 'Không có cửa hàng nào cần dọn — mọi cửa hàng do GAS quản lý đều còn dòng tương ứng trong sheet MERCHANT.';
        return;
      }
      $('orphanBox').textContent = list.map(function (m) {
        return '🗑️ "' + m.name + '" (id ' + m.id + ')';
      }).join('\\n');
      $('btnDeleteOrphans').disabled = false;
      showOrphanMsg('Tìm thấy ' + list.length + ' cửa hàng cần xoá — kiểm tra kỹ tên rồi mới bấm xoá.');
    }).withFailureHandler(function (e) {
      $('orphanBox').textContent = '(không kiểm tra được)';
      showOrphanErr(e);
    }).gasSyncFindOrphanedMerchants();
  }

  function deleteOrphans() {
    if (!orphanMerchants.length) return;
    var names = orphanMerchants.map(function (m) { return m.name; }).join(', ');
    if (!confirm('⚠️ XOÁ CỨNG ' + orphanMerchants.length + ' cửa hàng (' + names + ') cùng toàn bộ chi ' +
      'nhánh/sản phẩm/biến thể/topping/đơn hàng liên quan — KHÔNG hoàn tác được. Chắc chắn tiếp tục?')) return;
    $('btnDeleteOrphans').disabled = true;
    $('orphanBox').textContent = 'Đang xoá...';
    google.script.run.withSuccessHandler(function (res) {
      var lines = [];
      res.forEach(function (r) {
        lines.push(r.error ? ('❌ "' + r.name + '": ' + r.error) : ('✅ Đã xoá "' + r.name + '"'));
      });
      $('orphanBox').textContent = lines.join('\\n');
      var failCount = res.filter(function (r) { return r.error; }).length;
      if (failCount) {
        showOrphanErr(failCount + ' cửa hàng xoá không thành công, xem chi tiết ở trên.');
      } else {
        showOrphanMsg('Đã xoá xong ' + res.length + ' cửa hàng.');
      }
      orphanMerchants = [];
    }).withFailureHandler(function (e) {
      $('btnDeleteOrphans').disabled = false;
      showOrphanErr(e);
    }).gasSyncDeleteOrphanedMerchants(orphanMerchants.map(function (m) { return { id: m.id, name: m.name }; }));
  }

  function onSelectStore() {
    currentStore = $('storeSelect').value;
    diffChecked = false;
    lastDeleteCount = 0;
    $('btnApply').disabled = true;
    $('btnApply').textContent = '✅ Xác nhận và đồng bộ';
    $('diffBox').textContent = currentStore
      ? 'Bấm "Kiểm tra thay đổi" để xem trước.'
      : 'Chọn cửa hàng rồi bấm "Kiểm tra thay đổi" để xem trước.';
    showMsg('');
  }

  function checkDiff() {
    if (!currentStore) { showErr('Chọn cửa hàng trước'); return; }
    diffChecked = false;
    lastDeleteCount = 0;
    $('btnApply').disabled = true;
    $('diffBox').textContent = 'Đang kiểm tra...';
    google.script.run.withSuccessHandler(function (res) {
      $('diffBox').textContent = res.lines.join('\\n');
      if (res.blockingConflict) {
        showErr('Có trùng tên với cửa hàng khác trong hệ thống — sửa lại trước khi đồng bộ (xem chi tiết ở trên).');
        return;
      }
      diffChecked = true;
      lastDeleteCount = res.deleteCount || 0;
      $('btnApply').disabled = false;
      $('btnApply').textContent = lastDeleteCount > 0
        ? '✅ Xác nhận và đồng bộ (có ' + lastDeleteCount + ' mục sẽ bị XOÁ)'
        : '✅ Xác nhận và đồng bộ';
      showMsg('Đã kiểm tra xong (mỗi dòng: = không đổi, ≠ khác nhau) — xem kỹ rồi mới bấm đồng bộ.' +
        (lastDeleteCount > 0 ? ' ⚠️ Có ' + lastDeleteCount + ' mục sẽ bị XOÁ THẬT trên hệ thống.' : ''));
    }).withFailureHandler(function (e) {
      $('diffBox').textContent = '(không kiểm tra được)';
      showErr(e);
    }).gasSyncCheckDiff(currentStore);
  }

  function applySync() {
    if (!currentStore || !diffChecked) { showErr('Bấm "Kiểm tra thay đổi" trước'); return; }
    var confirmMsg = 'Đồng bộ cửa hàng "' + currentStore + '" lên hệ thống thật theo đúng danh sách thay đổi ở trên?';
    if (lastDeleteCount > 0) {
      confirmMsg = '⚠️ Có ' + lastDeleteCount + ' MỤC SẼ BỊ XOÁ THẬT trên hệ thống (sản phẩm/biến thể/topping đã ' +
        'xoá khỏi sheet) — KHÔNG hoàn tác được. ' + confirmMsg;
    }
    if (!confirm(confirmMsg)) return;
    $('btnApply').disabled = true;
    google.script.run.withSuccessHandler(function (res) {
      diffChecked = false;
      $('btnApply').textContent = '✅ Xác nhận và đồng bộ';
      var deleted = res.deleted || {};
      var deletedTotal = (deleted.products || []).length + (deleted.variants || []).length +
        (deleted.topping_groups || []).length + (deleted.toppings || []).length;
      var summary = 'Đồng bộ thành công! ID cửa hàng: ' + res.merchantId;
      if (deletedTotal > 0) {
        summary += ' — đã xoá ' + deletedTotal + ' mục (sản phẩm [xoá mềm]: ' + (deleted.products || []).length +
          ', biến thể [xoá cứng]: ' + (deleted.variants || []).length + ', nhóm topping [xoá cứng]: ' + (deleted.topping_groups || []).length +
          ', topping [xoá cứng]: ' + (deleted.toppings || []).length + ')';
      }
      if (res.errors && res.errors.length) {
        showErr('Đồng bộ xong nhưng có ' + res.errors.length + ' lỗi:\\n' + res.errors.join('\\n'));
      } else {
        showMsg(summary);
      }
      $('diffBox').textContent = 'Đã đồng bộ — bấm "Kiểm tra thay đổi" lại nếu muốn xem trạng thái mới nhất.';
    }).withFailureHandler(function (e) {
      $('btnApply').disabled = false;
      showErr(e);
    }).gasSyncApply(currentStore);
  }
})();
</script>
`;
}
