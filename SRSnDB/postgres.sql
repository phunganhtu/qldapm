-- ============================================================================
-- SIÊU THỊ ĐIỆN MÁY — DDL ĐẦY ĐỦ 117 BẢNG (ERD v1.1)
-- Hệ quản trị: PostgreSQL 15 trở lên. Encoding UTF-8.
-- Nguồn: Dac_Ta_ERD_Chi_Tiet_117_Bang_v1_1.docx (117 bảng / 813 cột / 282 FK).
-- Lựa chọn vật lý: UUID; mã varchar; JSONB; thời gian timestamptz;
-- tiền VND numeric(19,0); giá vốn/số đo numeric(24,6); tỷ lệ numeric(9,6).
-- Các lựa chọn độ dài/precision là đề xuất từ đặc tả, cần khớp API và hạn mức.
-- Không dùng kiểu money hoặc float cho tiền. Không mặc định thuế/giá bằng 0.
-- UUID tự sinh chỉ ở PK độc lập; PK subtype dùng chung ID của header/line cha.
-- Mặc định currency VND không thay thế kiểm tra tương thích tiền tệ liên bảng.
--
-- CHẠY: psql -X -v ON_ERROR_STOP=1 -d ten_database -f Sieu_Thi_Dien_May_PostgreSQL_Full.sql
-- Tạo mới schema dien_may trong database đã tồn tại. Không DROP dữ liệu.
-- Script chạy một lần; cố ý không IF NOT EXISTS để phát hiện schema sai/đã có.
-- Toàn bộ DDL nằm trong một transaction; FK thêm sau khi tạo đủ bảng.
-- ON DELETE/UPDATE NO ACTION: giữ lịch sử, không cascade xóa chứng từ.
-- FK DEFERRABLE INITIALLY IMMEDIATE: giao dịch đặc biệt có thể SET CONSTRAINTS.
-- Enum dùng CHECK để có thể sửa tập giá trị bằng migration có kiểm soát.
-- NULL trong unique mặc định được phép lặp; NULLS NOT DISTINCT chỉ áp dụng
-- các khóa cần chuẩn hóa NULL (vị trí tồn, phạm vi quyền, mốc lô nhập).
--
-- PHẠM VI THỰC THI:
-- DDL thực thi PK, FK, NOT NULL, UNIQUE, CHECK trong dòng và một số unique partial.
-- COMMENT ON TABLE/COLUMN giữ mô tả, luật và cấu trúc JSON từ đặc tả.
-- Luật tổng hợp/chuyển trạng thái/quyền/đồng thời phải được thực hiện trong
-- dịch vụ giao dịch hoặc stored procedure riêng; DDL này không giả lập chúng.
-- Cụ thể: giữ tồn/công suất; tổng slice và hoàn tiền; nguồn tín dụng đang hiệu lực;
-- phê duyệt; cùng đơn/SKU/kho giữa các FK; một subtype đúng loại chứng từ;
-- chống chu trình; giá không chồng khoảng; bất biến ledger và JSON schema.
-- exchange_credit_line.source_slice_id KHÔNG UNIQUE suốt đời: hiệu lực phụ thuộc
-- exchange_credit.state ở bảng cha; khóa source slice và kiểm tra credit hiện hành
-- trong cùng transaction khi tạo/áp dụng/đảo tín dụng để giữ lịch sử tái sử dụng.
-- Không có trigger, procedure nghiệp vụ, seed, tài khoản, GRANT hoặc dữ liệu mẫu.
-- Không dùng tài khoản sở hữu schema làm tài khoản ứng dụng vận hành.
-- Tham khảo cú pháp: https://www.postgresql.org/docs/15/ddl-constraints.html
-- ============================================================================

BEGIN;
SET LOCAL client_encoding = 'UTF8';
SET LOCAL timezone = 'UTC';
CREATE SCHEMA dien_may;
COMMENT ON SCHEMA dien_may IS 'Quản lý siêu thị điện máy — ERD v1.1, 117 bảng';


-- ============================================================================
-- M01 Tổ chức tài khoản và phân quyền
-- ============================================================================

-- T001 store: Cửa hàng hoặc điểm điều hành bán hàng
CREATE TABLE dien_may."store" (
    "store_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "address_snapshot" jsonb NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_store" PRIMARY KEY ("store_id"),
    CONSTRAINT "uq_store_code" UNIQUE ("code"),
    CONSTRAINT "ck_store_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."store" IS 'Cửa hàng hoặc điểm điều hành bán hàng.
Cấu trúc address_snapshot: recipient_name, phone, address_line, area_code, delivery_note; chụp đúng lúc giao dịch.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."store"."store_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."store"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."store"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."store"."address_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."store"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T002 warehouse: Kho thực hoặc kho ảo hàng đang chuyển
CREATE TABLE dien_may."warehouse" (
    "warehouse_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "kind" varchar(40) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_warehouse" PRIMARY KEY ("warehouse_id"),
    CONSTRAINT "uq_warehouse_code" UNIQUE ("code"),
    CONSTRAINT "ck_warehouse_kind_domain" CHECK ("kind" IN ('PHYSICAL', 'TRANSIT')),
    CONSTRAINT "ck_warehouse_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."warehouse" IS 'Kho thực hoặc kho ảo hàng đang chuyển.
Ràng buộc nghiệp vụ: Kho TRANSIT không được bán. Không ngừng kho còn tồn hoặc công việc mở.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."warehouse"."warehouse_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."warehouse"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."warehouse"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."warehouse"."kind" IS 'Phân loại đối tượng, quyết định các trường và quy tắc bắt buộc tương ứng.';
COMMENT ON COLUMN dien_may."warehouse"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T003 store_warehouse: Cấu hình cửa hàng được sử dụng kho nào
CREATE TABLE dien_may."store_warehouse" (
    "store_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "can_sell" boolean NOT NULL,
    "can_dispatch" boolean NOT NULL,
    "can_receive" boolean NOT NULL,
    "priority" integer NOT NULL,
    CONSTRAINT "pk_store_warehouse" PRIMARY KEY ("store_id", "warehouse_id")
);
COMMENT ON TABLE dien_may."store_warehouse" IS 'Cấu hình cửa hàng được sử dụng kho nào.
Ràng buộc nghiệp vụ: PK ghép; đơn R1 phải chọn một cặp cửa hàng và kho được phép xuất.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."store_warehouse"."store_id" IS 'Liên kết cửa hàng hoặc điểm điều hành bán hàng.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."store_warehouse"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."store_warehouse"."can_sell" IS 'Cho phép cửa hàng dùng kho này làm nguồn tồn có thể bán.';
COMMENT ON COLUMN dien_may."store_warehouse"."can_dispatch" IS 'Cho phép xuất đơn bán của cửa hàng từ kho được liên kết.';
COMMENT ON COLUMN dien_may."store_warehouse"."can_receive" IS 'Cho phép nghiệp vụ nhập nhận dùng cặp cửa hàng và kho này.';
COMMENT ON COLUMN dien_may."store_warehouse"."priority" IS 'Độ ưu tiên lựa chọn; số lớn được ưu tiên hơn khi các tiêu chí phạm vi tương đương.';

-- T004 warehouse_location: Vị trí vật lý bên trong kho
CREATE TABLE dien_may."warehouse_location" (
    "location_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "warehouse_id" uuid NOT NULL,
    "code" varchar(100) NOT NULL,
    "kind" varchar(40) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_warehouse_location" PRIMARY KEY ("location_id"),
    CONSTRAINT "uq_warehouse_location_warehouse_id_code" UNIQUE ("warehouse_id", "code"),
    CONSTRAINT "ck_warehouse_location_kind_domain" CHECK ("kind" IN ('STORAGE', 'QUARANTINE', 'DISPLAY', 'TRANSIT')),
    CONSTRAINT "ck_warehouse_location_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."warehouse_location" IS 'Vị trí vật lý bên trong kho.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."warehouse_location"."location_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."warehouse_location"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."warehouse_location"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."warehouse_location"."kind" IS 'Phân loại đối tượng, quyết định các trường và quy tắc bắt buộc tương ứng.';
COMMENT ON COLUMN dien_may."warehouse_location"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T005 user_account: Danh tính đăng nhập, khác hồ sơ khách hàng và nhân viên
CREATE TABLE dien_may."user_account" (
    "user_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "login_key" varchar(255) NOT NULL,
    "password_hash" text NOT NULL,
    "account_kind" varchar(40) NOT NULL,
    "status" varchar(40) NOT NULL,
    "mfa_secret_ref" text,
    CONSTRAINT "pk_user_account" PRIMARY KEY ("user_id"),
    CONSTRAINT "uq_user_account_login_key" UNIQUE ("login_key"),
    CONSTRAINT "ck_user_account_account_kind_domain" CHECK ("account_kind" IN ('STAFF', 'CUSTOMER')),
    CONSTRAINT "ck_user_account_status_domain" CHECK ("status" IN ('ACTIVE', 'LOCKED', 'DISABLED'))
);
COMMENT ON TABLE dien_may."user_account" IS 'Danh tính đăng nhập, khác hồ sơ khách hàng và nhân viên.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."user_account"."user_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."user_account"."login_key" IS 'Tên hoặc liên hệ đăng nhập đã chuẩn hóa theo chính sách tài khoản.';
COMMENT ON COLUMN dien_may."user_account"."password_hash" IS 'Mật khẩu đã băm có salt theo cơ chế được chọn, không thể dùng để gửi lại mật khẩu cũ.';
COMMENT ON COLUMN dien_may."user_account"."account_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."user_account"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."user_account"."mfa_secret_ref" IS 'Chỉ tham chiếu kho bí mật; không lưu secret rõ';

-- T006 employee: Nhân sự vận hành và phạm vi cửa hàng chính
CREATE TABLE dien_may."employee" (
    "employee_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "user_id" uuid NOT NULL,
    "home_store_id" uuid,
    "employee_code" varchar(100) NOT NULL,
    "display_name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_employee" PRIMARY KEY ("employee_id"),
    CONSTRAINT "uq_employee_user_id" UNIQUE ("user_id"),
    CONSTRAINT "uq_employee_employee_code" UNIQUE ("employee_code"),
    CONSTRAINT "ck_employee_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."employee" IS 'Nhân sự vận hành và phạm vi cửa hàng chính.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."employee"."employee_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."employee"."user_id" IS 'Liên kết danh tính đăng nhập, khác hồ sơ khách hàng và nhân viên.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."employee"."home_store_id" IS 'Cửa hàng chính của nhân viên; không tự thay thế các quyền đã cấp theo phạm vi.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."employee"."employee_code" IS 'Mã nhân sự ổn định để phân công, tra cứu và đối chiếu thao tác.';
COMMENT ON COLUMN dien_may."employee"."display_name" IS 'Tên người được hiển thị; không dùng tên để xác định duy nhất một người.';
COMMENT ON COLUMN dien_may."employee"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T007 role: Nhóm quyền được cấp theo phạm vi
CREATE TABLE dien_may."role" (
    "role_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_role" PRIMARY KEY ("role_id"),
    CONSTRAINT "uq_role_code" UNIQUE ("code"),
    CONSTRAINT "ck_role_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."role" IS 'Nhóm quyền được cấp theo phạm vi.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."role"."role_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."role"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."role"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."role"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T008 permission: Hành động trên một loại tài nguyên nghiệp vụ
CREATE TABLE dien_may."permission" (
    "permission_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "resource_type" varchar(100) NOT NULL,
    "action" varchar(100) NOT NULL,
    CONSTRAINT "pk_permission" PRIMARY KEY ("permission_id"),
    CONSTRAINT "uq_permission_code" UNIQUE ("code")
);
COMMENT ON TABLE dien_may."permission" IS 'Hành động trên một loại tài nguyên nghiệp vụ.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."permission"."permission_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."permission"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."permission"."resource_type" IS 'Mã loại tài nguyên được kiểm quyền, ví dụ đơn bán, kho hoặc khoản hoàn.';
COMMENT ON COLUMN dien_may."permission"."action" IS 'Mã hành động cụ thể, ví dụ xem, tạo, xác nhận, ghi sổ hoặc duyệt.';

-- T009 role_permission: Quan hệ nhiều nhiều vai trò và quyền kèm hạn mức
CREATE TABLE dien_may."role_permission" (
    "role_id" uuid NOT NULL,
    "permission_id" uuid NOT NULL,
    "amount_limit" numeric(19,0),
    "currency" varchar(100) NOT NULL DEFAULT 'VND',
    CONSTRAINT "pk_role_permission" PRIMARY KEY ("role_id", "permission_id"),
    CONSTRAINT "ck_role_permission_amount_limit_nonnegative" CHECK ("amount_limit" >= 0)
);
COMMENT ON TABLE dien_may."role_permission" IS 'Quan hệ nhiều nhiều vai trò và quyền kèm hạn mức.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."role_permission"."role_id" IS 'Liên kết nhóm quyền được cấp theo phạm vi.
FK → role.role_id.';
COMMENT ON COLUMN dien_may."role_permission"."permission_id" IS 'Liên kết hành động trên một loại tài nguyên nghiệp vụ.
FK → permission.permission_id.';
COMMENT ON COLUMN dien_may."role_permission"."amount_limit" IS 'Hạn mức tiền của quyền trong vai trò; NULL là không áp ngưỡng theo cấu hình, không mặc định vô hạn.';
COMMENT ON COLUMN dien_may."role_permission"."currency" IS 'Mã tiền tệ của khoản tiền; R1 chỉ dùng VND và phải khớp toàn giao dịch.
Mặc định: VND cho R1.';

-- T010 access_scope: Phạm vi toàn doanh nghiệp cửa hàng hoặc kho
CREATE TABLE dien_may."access_scope" (
    "scope_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "scope_kind" varchar(40) NOT NULL,
    "store_id" uuid,
    "warehouse_id" uuid,
    CONSTRAINT "pk_access_scope" PRIMARY KEY ("scope_id"),
    CONSTRAINT "uq_access_scope_scope_kind_store_id_warehouse_id" UNIQUE NULLS NOT DISTINCT ("scope_kind", "store_id", "warehouse_id"),
    CONSTRAINT "ck_access_scope_scope_kind_domain" CHECK ("scope_kind" IN ('GLOBAL', 'STORE', 'WAREHOUSE')),
    CONSTRAINT "ck_access_scope_scope_target" CHECK ((scope_kind = 'GLOBAL' AND store_id IS NULL AND warehouse_id IS NULL) OR (scope_kind = 'STORE' AND store_id IS NOT NULL AND warehouse_id IS NULL) OR (scope_kind = 'WAREHOUSE' AND warehouse_id IS NOT NULL AND store_id IS NULL))
);
COMMENT ON TABLE dien_may."access_scope" IS 'Phạm vi toàn doanh nghiệp cửa hàng hoặc kho.
Ràng buộc nghiệp vụ: GLOBAL: cả hai FK NULL; STORE: chỉ store_id có giá trị; WAREHOUSE: chỉ warehouse_id có giá trị. Duy nhất mỗi phạm vi theo giá trị chuẩn hóa.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."access_scope"."scope_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."access_scope"."scope_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."access_scope"."store_id" IS 'Liên kết cửa hàng hoặc điểm điều hành bán hàng.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."access_scope"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';

-- T011 user_role_assignment: Cấp vai trò cho người dùng trong thời gian và phạm vi
CREATE TABLE dien_may."user_role_assignment" (
    "assignment_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "user_id" uuid NOT NULL,
    "role_id" uuid NOT NULL,
    "scope_id" uuid NOT NULL,
    "granted_by" uuid NOT NULL,
    "valid_from" timestamptz NOT NULL,
    "valid_to" timestamptz,
    "delegation_source_id" uuid,
    CONSTRAINT "pk_user_role_assignment" PRIMARY KEY ("assignment_id"),
    CONSTRAINT "ck_user_role_assignment_valid_range" CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT "ck_user_role_assignment_not_self_delegation" CHECK (delegation_source_id IS NULL OR delegation_source_id <> assignment_id)
);
COMMENT ON TABLE dien_may."user_role_assignment" IS 'Cấp vai trò cho người dùng trong thời gian và phạm vi.
Ràng buộc nghiệp vụ: Không cho ủy quyền vượt quyền/hạn mức của nguồn. Cấp quyền khách không làm thành nhân viên.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."user_role_assignment"."assignment_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."user_role_assignment"."user_id" IS 'Liên kết danh tính đăng nhập, khác hồ sơ khách hàng và nhân viên.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."user_role_assignment"."role_id" IS 'Liên kết nhóm quyền được cấp theo phạm vi.
FK → role.role_id.';
COMMENT ON COLUMN dien_may."user_role_assignment"."scope_id" IS 'Phạm vi kiểm quyền của lần cấp vai trò, gồm GLOBAL, STORE hoặc WAREHOUSE.
FK → access_scope.scope_id.';
COMMENT ON COLUMN dien_may."user_role_assignment"."granted_by" IS 'Người thực tế cấp hoặc ủy quyền vai trò.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."user_role_assignment"."valid_from" IS 'Thời điểm bắt đầu hiệu lực, được tính vào khoảng áp dụng.';
COMMENT ON COLUMN dien_may."user_role_assignment"."valid_to" IS 'Thời điểm kết thúc hiệu lực, không được tính vào khoảng; NULL là chưa ấn định kết thúc.';
COMMENT ON COLUMN dien_may."user_role_assignment"."delegation_source_id" IS 'Bản cấp quyền nguồn của việc ủy quyền; không được vượt quyền hoặc hiệu lực nguồn.
FK → user_role_assignment.assignment_id.';

-- T012 auth_session: Phiên truy cập có khả năng thu hồi
CREATE TABLE dien_may."auth_session" (
    "session_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "user_id" uuid NOT NULL,
    "token_hash" text NOT NULL,
    "expires_at" timestamptz NOT NULL,
    "revoked_at" timestamptz,
    "last_seen_at" timestamptz NOT NULL,
    CONSTRAINT "pk_auth_session" PRIMARY KEY ("session_id"),
    CONSTRAINT "uq_auth_session_token_hash" UNIQUE ("token_hash")
);
COMMENT ON TABLE dien_may."auth_session" IS 'Phiên truy cập có khả năng thu hồi.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."auth_session"."session_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."auth_session"."user_id" IS 'Liên kết danh tính đăng nhập, khác hồ sơ khách hàng và nhân viên.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."auth_session"."token_hash" IS 'Dấu băm token phiên; không lưu token truy cập rõ trong bảng.';
COMMENT ON COLUMN dien_may."auth_session"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';
COMMENT ON COLUMN dien_may."auth_session"."revoked_at" IS 'Thời điểm thu hồi phiên; có giá trị thì phải từ chối truy cập tiếp theo.';
COMMENT ON COLUMN dien_may."auth_session"."last_seen_at" IS 'Thời điểm phiên được sử dụng gần nhất, dùng kiểm thời hạn không hoạt động.';

-- T013 verification_challenge: Xác minh liên hệ hoặc tra cứu đơn bằng OTP
CREATE TABLE dien_may."verification_challenge" (
    "challenge_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "user_id" uuid,
    "order_id" uuid,
    "purpose" varchar(40) NOT NULL,
    "destination_hash" text NOT NULL,
    "secret_hash" text NOT NULL,
    "expires_at" timestamptz NOT NULL,
    "attempt_count" integer NOT NULL DEFAULT 0,
    "consumed_at" timestamptz,
    CONSTRAINT "pk_verification_challenge" PRIMARY KEY ("challenge_id"),
    CONSTRAINT "ck_verification_challenge_purpose_domain" CHECK ("purpose" IN ('REGISTER', 'LOGIN', 'RESET', 'ORDER_LOOKUP', 'PICKUP')),
    CONSTRAINT "ck_verification_challenge_attempt_count_nonnegative" CHECK ("attempt_count" >= 0)
);
COMMENT ON TABLE dien_may."verification_challenge" IS 'Xác minh liên hệ hoặc tra cứu đơn bằng OTP.
Ràng buộc nghiệp vụ: OTP dùng một lần, ràng buộc đúng mục đích và đơn; destination rõ chỉ lưu mã hóa khi cần gửi.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."verification_challenge"."challenge_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."verification_challenge"."user_id" IS 'Liên kết danh tính đăng nhập, khác hồ sơ khách hàng và nhân viên.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."verification_challenge"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."verification_challenge"."purpose" IS 'Mục đích sử dụng; không được dùng bản ghi cho một mục đích xác minh khác.';
COMMENT ON COLUMN dien_may."verification_challenge"."destination_hash" IS 'Dấu băm địa chỉ nhận OTP để đối chiếu và hạn chế lạm dụng.';
COMMENT ON COLUMN dien_may."verification_challenge"."secret_hash" IS 'Dấu băm mã xác minh dùng một lần; không lưu OTP rõ.';
COMMENT ON COLUMN dien_may."verification_challenge"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';
COMMENT ON COLUMN dien_may."verification_challenge"."attempt_count" IS 'Số lần đã thử mã xác minh; dùng giới hạn dò OTP.
Mặc định: 0 khi tạo challenge.';
COMMENT ON COLUMN dien_may."verification_challenge"."consumed_at" IS 'Thời điểm mã xác minh đã dùng thành công; có giá trị thì không dùng lại.';

-- ============================================================================
-- M02 Danh mục sản phẩm và biến thể
-- ============================================================================

-- T014 category: Nhóm hàng có cấu trúc phân cấp
CREATE TABLE dien_may."category" (
    "category_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "parent_id" uuid,
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_category" PRIMARY KEY ("category_id"),
    CONSTRAINT "uq_category_code" UNIQUE ("code"),
    CONSTRAINT "ck_category_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT "ck_category_not_self_parent" CHECK (parent_id IS NULL OR parent_id <> category_id)
);
COMMENT ON TABLE dien_may."category" IS 'Nhóm hàng có cấu trúc phân cấp.
Ràng buộc nghiệp vụ: Cấm chu trình cha con.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."category"."category_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."category"."parent_id" IS 'Nhóm hàng cha; NULL tại gốc, không được tạo chu trình.
FK → category.category_id.';
COMMENT ON COLUMN dien_may."category"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."category"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."category"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T015 brand: Thương hiệu sản phẩm
CREATE TABLE dien_may."brand" (
    "brand_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_brand" PRIMARY KEY ("brand_id"),
    CONSTRAINT "uq_brand_code" UNIQUE ("code"),
    CONSTRAINT "ck_brand_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."brand" IS 'Thương hiệu sản phẩm.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."brand"."brand_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."brand"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."brand"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."brand"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T016 product: Mẫu hoặc dòng sản phẩm, chưa phải đơn vị quản lý tồn
CREATE TABLE dien_may."product" (
    "product_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "category_id" uuid NOT NULL,
    "brand_id" uuid NOT NULL,
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "description" text,
    "publication_status" varchar(40) NOT NULL,
    CONSTRAINT "pk_product" PRIMARY KEY ("product_id"),
    CONSTRAINT "uq_product_code" UNIQUE ("code"),
    CONSTRAINT "ck_product_publication_status_domain" CHECK ("publication_status" IN ('DRAFT', 'PUBLISHED', 'HIDDEN', 'DISCONTINUED'))
);
COMMENT ON TABLE dien_may."product" IS 'Mẫu hoặc dòng sản phẩm, chưa phải đơn vị quản lý tồn.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."product"."product_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."product"."category_id" IS 'Liên kết nhóm hàng có cấu trúc phân cấp.
FK → category.category_id.';
COMMENT ON COLUMN dien_may."product"."brand_id" IS 'Liên kết thương hiệu sản phẩm.
FK → brand.brand_id.';
COMMENT ON COLUMN dien_may."product"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."product"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."product"."description" IS 'Nội dung mô tả nghiệp vụ hoặc giới thiệu sản phẩm.';
COMMENT ON COLUMN dien_may."product"."publication_status" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';

-- T017 sku: Biến thể bán được theo màu dung lượng hoặc cấu hình
CREATE TABLE dien_may."sku" (
    "sku_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "product_id" uuid NOT NULL,
    "code" varchar(50) NOT NULL,
    "barcode" varchar(100),
    "variant_name" varchar(255) NOT NULL,
    "unit_code" varchar(100) NOT NULL,
    "requires_serial" boolean NOT NULL,
    "requires_installation" boolean NOT NULL,
    "weight" numeric(24,6) NOT NULL,
    "dimensions_snapshot" jsonb NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_sku" PRIMARY KEY ("sku_id"),
    CONSTRAINT "uq_sku_code" UNIQUE ("code"),
    CONSTRAINT "uq_sku_barcode" UNIQUE ("barcode"),
    CONSTRAINT "ck_sku_weight_nonnegative" CHECK ("weight" >= 0),
    CONSTRAINT "ck_sku_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."sku" IS 'Biến thể bán được theo màu dung lượng hoặc cấu hình.
Ràng buộc nghiệp vụ: Không có trường quantity hoặc current_price làm nguồn chuẩn tại đây. Tồn theo sổ kho, giá theo price_entry.
Cấu trúc dimensions_snapshot: length, width, height, unit; số đo không âm và dùng cùng hệ đơn vị.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."sku"."sku_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."sku"."product_id" IS 'Liên kết mẫu hoặc dòng sản phẩm, chưa phải đơn vị quản lý tồn.
FK → product.product_id.';
COMMENT ON COLUMN dien_may."sku"."code" IS 'Mã hàng nội bộ duy nhất, tối đa 50 ký tự theo SRS; không tái dùng cho SKU khác.';
COMMENT ON COLUMN dien_may."sku"."barcode" IS 'Mã vạch của SKU nếu có; giữ dạng chuỗi để không mất số 0 đầu.';
COMMENT ON COLUMN dien_may."sku"."variant_name" IS 'Tên biến thể phân biệt màu, dung lượng hoặc cấu hình trong cùng mẫu sản phẩm.';
COMMENT ON COLUMN dien_may."sku"."unit_code" IS 'Mã đơn vị tính; thiết bị R1 quản lý theo đơn vị nguyên, không bán số lẻ.';
COMMENT ON COLUMN dien_may."sku"."requires_serial" IS 'Cho biết SKU cần theo dõi từng máy bằng serial trong nhập, xuất và hậu mãi.';
COMMENT ON COLUMN dien_may."sku"."requires_installation" IS 'Cho biết SKU có nghĩa vụ lắp đặt bắt buộc trước khi đơn hoàn tất.';
COMMENT ON COLUMN dien_may."sku"."weight" IS 'Khối lượng một đơn vị hàng, dùng tính năng lực vận chuyển; đơn vị đo phải thống nhất.';
COMMENT ON COLUMN dien_may."sku"."dimensions_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."sku"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T018 attribute_definition: Thuộc tính có kiểu dữ liệu áp dụng theo nhóm hàng
CREATE TABLE dien_may."attribute_definition" (
    "attribute_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "category_id" uuid NOT NULL,
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "data_type" varchar(40) NOT NULL,
    "unit_code" varchar(100),
    "is_required" boolean NOT NULL,
    "is_variant" boolean NOT NULL,
    "allowed_values" jsonb,
    CONSTRAINT "pk_attribute_definition" PRIMARY KEY ("attribute_id"),
    CONSTRAINT "uq_attribute_definition_category_id_code" UNIQUE ("category_id", "code"),
    CONSTRAINT "ck_attribute_definition_data_type_domain" CHECK ("data_type" IN ('TEXT', 'NUMBER', 'BOOL', 'OPTION'))
);
COMMENT ON TABLE dien_may."attribute_definition" IS 'Thuộc tính có kiểu dữ liệu áp dụng theo nhóm hàng.
Cấu trúc allowed_values: Danh sách {code, label} của lựa chọn hợp lệ; chỉ dùng khi data_type tương ứng.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."attribute_definition"."attribute_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."attribute_definition"."category_id" IS 'Liên kết nhóm hàng có cấu trúc phân cấp.
FK → category.category_id.';
COMMENT ON COLUMN dien_may."attribute_definition"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."attribute_definition"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."attribute_definition"."data_type" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."attribute_definition"."unit_code" IS 'Đơn vị đo của thuộc tính số, ví dụ lít, inch hoặc watt; NULL khi không cần đơn vị.';
COMMENT ON COLUMN dien_may."attribute_definition"."is_required" IS 'Thuộc tính bắt buộc phải có giá trị trước khi sản phẩm được công bố.';
COMMENT ON COLUMN dien_may."attribute_definition"."is_variant" IS 'Thuộc tính được dùng để phân biệt các SKU của một mẫu.';
COMMENT ON COLUMN dien_may."attribute_definition"."allowed_values" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';

-- T019 sku_attribute_value: Giá trị thuộc tính của biến thể
CREATE TABLE dien_may."sku_attribute_value" (
    "sku_id" uuid NOT NULL,
    "attribute_id" uuid NOT NULL,
    "text_value" text,
    "number_value" numeric(24,6),
    "bool_value" boolean,
    CONSTRAINT "pk_sku_attribute_value" PRIMARY KEY ("sku_id", "attribute_id"),
    CONSTRAINT "ck_sku_attribute_value_one_value" CHECK (num_nonnulls(text_value, number_value, bool_value) = 1)
);
COMMENT ON TABLE dien_may."sku_attribute_value" IS 'Giá trị thuộc tính của biến thể.
Ràng buộc nghiệp vụ: Đúng một trường giá trị theo data_type; kiểm nhóm sản phẩm tương thích. Thuộc tính chung có thể được sao chép từ mẫu khi tạo SKU, không dùng JSON không kiểm kiểu để lọc.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."sku_attribute_value"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."sku_attribute_value"."attribute_id" IS 'Liên kết thuộc tính có kiểu dữ liệu áp dụng theo nhóm hàng.
FK → attribute_definition.attribute_id.';
COMMENT ON COLUMN dien_may."sku_attribute_value"."text_value" IS 'Giá trị dạng chuỗi hoặc mã lựa chọn của thuộc tính.';
COMMENT ON COLUMN dien_may."sku_attribute_value"."number_value" IS 'Giá trị số thập phân của thuộc tính, diễn giải cùng unit_code.';
COMMENT ON COLUMN dien_may."sku_attribute_value"."bool_value" IS 'Giá trị đúng/sai của thuộc tính; NULL khác với FALSE.';

-- T020 product_media: Ảnh tài liệu sản phẩm hoặc riêng một biến thể
CREATE TABLE dien_may."product_media" (
    "media_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "product_id" uuid NOT NULL,
    "sku_id" uuid,
    "file_id" uuid NOT NULL,
    "sort_order" integer NOT NULL,
    "alt_text" text,
    CONSTRAINT "pk_product_media" PRIMARY KEY ("media_id"),
    CONSTRAINT "ck_product_media_sort_order_nonnegative" CHECK ("sort_order" >= 0)
);
COMMENT ON TABLE dien_may."product_media" IS 'Ảnh tài liệu sản phẩm hoặc riêng một biến thể.
Ràng buộc nghiệp vụ: Nếu có sku_id thì SKU phải thuộc product_id này.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."product_media"."media_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."product_media"."product_id" IS 'Liên kết mẫu hoặc dòng sản phẩm, chưa phải đơn vị quản lý tồn.
FK → product.product_id.';
COMMENT ON COLUMN dien_may."product_media"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."product_media"."file_id" IS 'Liên kết tệp được kiểm loại quyền truy cập và thời hạn.
FK → file_asset.file_id.';
COMMENT ON COLUMN dien_may."product_media"."sort_order" IS 'Thứ tự sắp xếp hiển thị, không phải khóa định danh đối tượng.';
COMMENT ON COLUMN dien_may."product_media"."alt_text" IS 'Mô tả nội dung ảnh để hỗ trợ hiển thị và khả năng tiếp cận.';

-- T021 service_definition: Dịch vụ thu phí giao lắp hoặc phát sinh được bán thành dòng đơn
CREATE TABLE dien_may."service_definition" (
    "service_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "service_kind" varchar(40) NOT NULL,
    "required_skill" varchar(100),
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_service_definition" PRIMARY KEY ("service_id"),
    CONSTRAINT "uq_service_definition_code" UNIQUE ("code"),
    CONSTRAINT "ck_service_definition_service_kind_domain" CHECK ("service_kind" IN ('DELIVERY', 'INSTALLATION', 'EXTRA')),
    CONSTRAINT "ck_service_definition_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."service_definition" IS 'Dịch vụ thu phí giao lắp hoặc phát sinh được bán thành dòng đơn.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."service_definition"."service_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."service_definition"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."service_definition"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."service_definition"."service_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."service_definition"."required_skill" IS 'Mã kỹ năng cần có để thực hiện công việc hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."service_definition"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- ============================================================================
-- M03 Mua hàng nhập hàng và nhà cung cấp
-- ============================================================================

-- T022 supplier: Nhà cung cấp hàng hoặc trung tâm sửa chữa đối tác
CREATE TABLE dien_may."supplier" (
    "supplier_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "tax_code" text,
    "contact_snapshot" jsonb NOT NULL,
    "supplier_kind" varchar(40) NOT NULL,
    "terms_snapshot" jsonb NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_supplier" PRIMARY KEY ("supplier_id"),
    CONSTRAINT "uq_supplier_code" UNIQUE ("code"),
    CONSTRAINT "ck_supplier_supplier_kind_domain" CHECK ("supplier_kind" IN ('GOODS', 'SERVICE', 'BOTH')),
    CONSTRAINT "ck_supplier_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."supplier" IS 'Nhà cung cấp hàng hoặc trung tâm sửa chữa đối tác.
Cấu trúc contact_snapshot: name, phone, email và thông tin liên hệ tại mốc ghi nhận; không tự cập nhật từ hồ sơ hiện hành.
Cấu trúc terms_snapshot: payment_terms, lead_time, delivery_terms, return_terms theo thỏa thuận được ghi nhận.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."supplier"."supplier_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."supplier"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."supplier"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."supplier"."tax_code" IS 'Mã số thuế của tổ chức nếu có; kiểm theo dữ liệu người cung cấp và hợp đồng tích hợp.';
COMMENT ON COLUMN dien_may."supplier"."contact_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."supplier"."supplier_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."supplier"."terms_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."supplier"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T023 purchase_order: Đơn mua hàng theo nhà cung cấp và kho nhận
CREATE TABLE dien_may."purchase_order" (
    "document_id" uuid NOT NULL,
    "supplier_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "status" varchar(40) NOT NULL,
    "expected_at" timestamptz,
    "currency" varchar(100) NOT NULL DEFAULT 'VND',
    "approved_version" integer,
    CONSTRAINT "pk_purchase_order" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_purchase_order_status_domain" CHECK ("status" IN ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'PART_RECEIVED', 'CLOSED', 'CANCELLED')),
    CONSTRAINT "ck_purchase_order_approved_version_positive" CHECK ("approved_version" > 0)
);
COMMENT ON TABLE dien_may."purchase_order" IS 'Đơn mua hàng theo nhà cung cấp và kho nhận.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."purchase_order"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."purchase_order"."supplier_id" IS 'Liên kết nhà cung cấp hàng hoặc trung tâm sửa chữa đối tác.
FK → supplier.supplier_id.';
COMMENT ON COLUMN dien_may."purchase_order"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."purchase_order"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."purchase_order"."expected_at" IS 'Thời điểm hàng được kỳ vọng về kho, chưa phải bằng chứng đã nhận.';
COMMENT ON COLUMN dien_may."purchase_order"."currency" IS 'Mã tiền tệ của khoản tiền; R1 chỉ dùng VND và phải khớp toàn giao dịch.
Mặc định: VND cho R1.';
COMMENT ON COLUMN dien_may."purchase_order"."approved_version" IS 'Phiên bản nội dung PO đã được duyệt, dùng phát hiện sửa sau duyệt.';

-- T024 purchase_order_line: Dòng mua và lượng được phép nhận
CREATE TABLE dien_may."purchase_order_line" (
    "line_id" uuid NOT NULL,
    "purchase_order_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "ordered_qty" integer NOT NULL,
    "unit_cost" numeric(24,6) NOT NULL,
    "discount_amount" numeric(19,0) NOT NULL,
    "tax_snapshot" jsonb NOT NULL,
    CONSTRAINT "pk_purchase_order_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_purchase_order_line_ordered_qty_positive" CHECK ("ordered_qty" > 0),
    CONSTRAINT "ck_purchase_order_line_unit_cost_nonnegative" CHECK ("unit_cost" >= 0),
    CONSTRAINT "ck_purchase_order_line_discount_amount_nonnegative" CHECK ("discount_amount" >= 0)
);
COMMENT ON TABLE dien_may."purchase_order_line" IS 'Dòng mua và lượng được phép nhận.
Ràng buộc nghiệp vụ: Số nhận hiệu lực lấy từ phiếu nhập đã chốt trừ đảo; cấm vượt số duyệt nếu chưa có phiên bản mua bổ sung.
Cấu trúc tax_snapshot: tax_code, tax_rate, tax_amount, price_includes_tax tại thời điểm dòng mua.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."purchase_order_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."purchase_order_line"."purchase_order_id" IS 'Liên kết đơn mua hàng theo nhà cung cấp và kho nhận.
FK → purchase_order.document_id.';
COMMENT ON COLUMN dien_may."purchase_order_line"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."purchase_order_line"."ordered_qty" IS 'Lượng đặt mua đã được đề nghị hoặc duyệt theo phiên bản PO hiện tại.';
COMMENT ON COLUMN dien_may."purchase_order_line"."unit_cost" IS 'Giá nhập một đơn vị trước khi phân bổ chi phí bổ sung theo chính sách tài chính.';
COMMENT ON COLUMN dien_may."purchase_order_line"."discount_amount" IS 'Khoản giảm được ghi cho dòng mua hoặc chứng từ tương ứng.';
COMMENT ON COLUMN dien_may."purchase_order_line"."tax_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';

-- T025 goods_receipt: Phiếu nhận từng phần theo PO
CREATE TABLE dien_may."goods_receipt" (
    "document_id" uuid NOT NULL,
    "purchase_order_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "supplier_reference" text,
    "status" varchar(40) NOT NULL,
    "received_at" timestamptz NOT NULL,
    CONSTRAINT "pk_goods_receipt" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_goods_receipt_status_domain" CHECK ("status" IN ('DRAFT', 'POSTED', 'REVERSED'))
);
COMMENT ON TABLE dien_may."goods_receipt" IS 'Phiếu nhận từng phần theo PO.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."goods_receipt"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."goods_receipt"."purchase_order_id" IS 'Liên kết đơn mua hàng theo nhà cung cấp và kho nhận.
FK → purchase_order.document_id.';
COMMENT ON COLUMN dien_may."goods_receipt"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."goods_receipt"."supplier_reference" IS 'Số chứng từ hoặc tham chiếu giao hàng của nhà cung cấp.';
COMMENT ON COLUMN dien_may."goods_receipt"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."goods_receipt"."received_at" IS 'Thời điểm hệ thống hoặc bộ phận tiếp nhận ghi nhận đã nhận thực tế.';

-- T026 goods_receipt_line: Chi tiết hàng đạt hoặc cách ly trong lần nhận
CREATE TABLE dien_may."goods_receipt_line" (
    "line_id" uuid NOT NULL,
    "receipt_id" uuid NOT NULL,
    "purchase_order_line_id" uuid NOT NULL,
    "accepted_qty" integer NOT NULL,
    "quarantine_qty" integer NOT NULL,
    "unit_cost_snapshot" numeric(24,6) NOT NULL,
    "allocated_landed_cost" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_goods_receipt_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_goods_receipt_line_accepted_qty_nonnegative" CHECK ("accepted_qty" >= 0),
    CONSTRAINT "ck_goods_receipt_line_quarantine_qty_nonnegative" CHECK ("quarantine_qty" >= 0),
    CONSTRAINT "ck_goods_receipt_line_unit_cost_snapshot_nonnegative" CHECK ("unit_cost_snapshot" >= 0),
    CONSTRAINT "ck_goods_receipt_line_allocated_landed_cost_nonnegative" CHECK ("allocated_landed_cost" >= 0),
    CONSTRAINT "ck_goods_receipt_line_received_qty" CHECK (accepted_qty + quarantine_qty > 0)
);
COMMENT ON TABLE dien_may."goods_receipt_line" IS 'Chi tiết hàng đạt hoặc cách ly trong lần nhận.
Ràng buộc nghiệp vụ: Tổng lượng dương; kho, SKU và nguồn PO phải khớp chuỗi header-line. Serial được ghi qua device và stock_movement_device khi chốt.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."receipt_id" IS 'Liên kết phiếu nhận từng phần theo po.
FK → goods_receipt.document_id.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."purchase_order_line_id" IS 'Liên kết dòng mua và lượng được phép nhận.
FK → purchase_order_line.line_id.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."accepted_qty" IS 'Lượng được nhận đạt chất lượng; với phiếu chuyển là số chiếu từ lần nhận thực.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."quarantine_qty" IS 'Lượng nhận vào cách ly, chưa đủ điều kiện bán.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."unit_cost_snapshot" IS 'Giá vốn hoặc đơn giá nhập chụp ở lần giao dịch, không lấy giá hiện hành để thay.';
COMMENT ON COLUMN dien_may."goods_receipt_line"."allocated_landed_cost" IS 'Phần chi phí nhập bổ sung được phân bổ vào dòng theo chính sách đã duyệt.';

-- T027 supplier_return: Phiếu hoàn nhà cung cấp
CREATE TABLE dien_may."supplier_return" (
    "document_id" uuid NOT NULL,
    "supplier_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "status" varchar(40) NOT NULL,
    "reason" varchar(500) NOT NULL,
    CONSTRAINT "pk_supplier_return" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_supplier_return_status_domain" CHECK ("status" IN ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'POSTED', 'CANCELLED'))
);
COMMENT ON TABLE dien_may."supplier_return" IS 'Phiếu hoàn nhà cung cấp.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."supplier_return"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."supplier_return"."supplier_id" IS 'Liên kết nhà cung cấp hàng hoặc trung tâm sửa chữa đối tác.
FK → supplier.supplier_id.';
COMMENT ON COLUMN dien_may."supplier_return"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."supplier_return"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."supplier_return"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';

-- T028 supplier_return_line: Dòng hàng thực hoàn về nhà cung cấp
CREATE TABLE dien_may."supplier_return_line" (
    "line_id" uuid NOT NULL,
    "supplier_return_id" uuid NOT NULL,
    "receipt_line_id" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "unit_cost_snapshot" numeric(24,6) NOT NULL,
    CONSTRAINT "pk_supplier_return_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_supplier_return_line_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_supplier_return_line_unit_cost_snapshot_nonnegative" CHECK ("unit_cost_snapshot" >= 0)
);
COMMENT ON TABLE dien_may."supplier_return_line" IS 'Dòng hàng thực hoàn về nhà cung cấp.
Ràng buộc nghiệp vụ: Phải còn tồn thuộc sở hữu doanh nghiệp và chưa bị giữ; thiết bị cụ thể theo movement_device.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."supplier_return_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."supplier_return_line"."supplier_return_id" IS 'Liên kết phiếu hoàn nhà cung cấp.
FK → supplier_return.document_id.';
COMMENT ON COLUMN dien_may."supplier_return_line"."receipt_line_id" IS 'Liên kết chi tiết hàng đạt hoặc cách ly trong lần nhận.
FK → goods_receipt_line.line_id.';
COMMENT ON COLUMN dien_may."supplier_return_line"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."supplier_return_line"."unit_cost_snapshot" IS 'Giá vốn hoặc đơn giá nhập chụp ở lần giao dịch, không lấy giá hiện hành để thay.';

-- T029 stock_lot: Lô gốc để truy nguồn và tính tuổi tồn, không phải giá vốn hiện hành
CREATE TABLE dien_may."stock_lot" (
    "lot_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "sku_id" uuid NOT NULL,
    "receipt_line_id" uuid,
    "opening_line_id" uuid,
    "import_batch_id" uuid,
    "origin_kind" varchar(40) NOT NULL,
    "received_at" timestamptz NOT NULL,
    "supplier_lot_code" text,
    CONSTRAINT "pk_stock_lot" PRIMARY KEY ("lot_id"),
    CONSTRAINT "ck_stock_lot_origin_kind_domain" CHECK ("origin_kind" IN ('PURCHASE', 'OPENING', 'EXTERNAL_CUSTODY')),
    CONSTRAINT "ck_stock_lot_source" CHECK ((origin_kind <> 'PURCHASE' OR (receipt_line_id IS NOT NULL AND opening_line_id IS NULL)) AND (origin_kind <> 'OPENING' OR (opening_line_id IS NOT NULL AND import_batch_id IS NOT NULL AND receipt_line_id IS NULL)) AND num_nonnulls(receipt_line_id, opening_line_id) <= 1)
);
COMMENT ON TABLE dien_may."stock_lot" IS 'Lô gốc để truy nguồn và tính tuổi tồn, không phải giá vốn hiện hành.
Ràng buộc nghiệp vụ: PURCHASE cần receipt_line; OPENING cần opening_line và import_batch khớp header tồn đầu; hai FK nguồn dòng không đồng thời có giá trị. EXTERNAL_CUSTODY không làm tăng giá trị tồn sở hữu. SKU nguồn phải khớp.
Kiểm soát ghi: Lô đã phát sinh ghi sổ giữ bất biến nguồn gốc và SKU. Điều chỉnh số lượng qua movement; không sửa lô để chuyển lịch sử hàng sang nguồn nhập khác.';
COMMENT ON COLUMN dien_may."stock_lot"."lot_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."stock_lot"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."stock_lot"."receipt_line_id" IS 'Liên kết chi tiết hàng đạt hoặc cách ly trong lần nhận.
FK → goods_receipt_line.line_id.';
COMMENT ON COLUMN dien_may."stock_lot"."opening_line_id" IS 'Liên kết dòng tồn đầu có vị trí tình trạng và giá trị nguồn.
FK → opening_balance_line.line_id.';
COMMENT ON COLUMN dien_may."stock_lot"."import_batch_id" IS 'Liên kết một lô nhập có kiểm và chốt nguyên tử trong phạm vi công bố.
FK → import_batch.batch_id.';
COMMENT ON COLUMN dien_may."stock_lot"."origin_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."stock_lot"."received_at" IS 'Thời điểm hệ thống hoặc bộ phận tiếp nhận ghi nhận đã nhận thực tế.';
COMMENT ON COLUMN dien_may."stock_lot"."supplier_lot_code" IS 'Mã lô phía nhà cung cấp nếu có, không thay lot_id nội bộ.';

-- T030 opening_balance: Chứng từ tồn đầu được kiểm và duyệt trước ghi sổ
CREATE TABLE dien_may."opening_balance" (
    "document_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "import_batch_id" uuid NOT NULL,
    "cutoff_at" timestamptz NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_opening_balance" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_opening_balance_warehouse_id_import_batch_id" UNIQUE ("warehouse_id", "import_batch_id"),
    CONSTRAINT "ck_opening_balance_status_domain" CHECK ("status" IN ('DRAFT', 'VALIDATED', 'APPROVED', 'POSTED'))
);
COMMENT ON TABLE dien_may."opening_balance" IS 'Chứng từ tồn đầu được kiểm và duyệt trước ghi sổ.
Ràng buộc nghiệp vụ: Chỉ dùng cho tồn đầu tại mốc cutover được duyệt; không nhận lại cùng lượng qua goods_receipt. Sau chốt điều chỉnh bằng chứng từ riêng.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."opening_balance"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."opening_balance"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."opening_balance"."import_batch_id" IS 'Liên kết một lô nhập có kiểm và chốt nguyên tử trong phạm vi công bố.
FK → import_batch.batch_id.';
COMMENT ON COLUMN dien_may."opening_balance"."cutoff_at" IS 'Mốc chốt dữ liệu tồn đầu hoặc lô chuyển đổi, tách khỏi ngày tải tệp.';
COMMENT ON COLUMN dien_may."opening_balance"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T031 opening_balance_line: Dòng tồn đầu có vị trí tình trạng và giá trị nguồn
CREATE TABLE dien_may."opening_balance_line" (
    "line_id" uuid NOT NULL,
    "opening_balance_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "location_id" uuid NOT NULL,
    "condition_code" varchar(40) NOT NULL,
    "quantity" integer NOT NULL,
    "carrying_amount" numeric(24,6) NOT NULL,
    CONSTRAINT "pk_opening_balance_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_opening_balance_line_condition_code_domain" CHECK ("condition_code" IN ('SALEABLE', 'QUARANTINE', 'DISPLAY', 'DAMAGED')),
    CONSTRAINT "ck_opening_balance_line_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_opening_balance_line_carrying_amount_nonnegative" CHECK ("carrying_amount" >= 0)
);
COMMENT ON TABLE dien_may."opening_balance_line" IS 'Dòng tồn đầu có vị trí tình trạng và giá trị nguồn.
Ràng buộc nghiệp vụ: Kho vị trí khớp header; quantity > 0 và carrying_amount >= 0. Tạo lot, device nếu cần và posting OPENING; không ghi thẳng stock_balance. Đây là tồn thuộc COMPANY, máy giữ hộ chuyển bằng hồ sơ custody riêng.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."opening_balance_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."opening_balance_line"."opening_balance_id" IS 'Liên kết chứng từ tồn đầu được kiểm và duyệt trước ghi sổ.
FK → opening_balance.document_id.';
COMMENT ON COLUMN dien_may."opening_balance_line"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."opening_balance_line"."location_id" IS 'Liên kết vị trí vật lý bên trong kho.
FK → warehouse_location.location_id.';
COMMENT ON COLUMN dien_may."opening_balance_line"."condition_code" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."opening_balance_line"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."opening_balance_line"."carrying_amount" IS 'Giá trị giá vốn được mang theo lượng hàng của bản ghi.';

-- ============================================================================
-- M04 Sổ kho vị trí tồn và thiết bị
-- ============================================================================

-- T032 inventory_position: Ngăn tồn theo lô vị trí tình trạng và chủ sở hữu
CREATE TABLE dien_may."inventory_position" (
    "position_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "location_id" uuid NOT NULL,
    "lot_id" uuid NOT NULL,
    "condition_code" varchar(40) NOT NULL,
    "ownership" varchar(40) NOT NULL,
    "owner_customer_id" uuid,
    CONSTRAINT "pk_inventory_position" PRIMARY KEY ("position_id"),
    CONSTRAINT "uq_inventory_position_location_id_lot_id_conditio_29b16ff4a1" UNIQUE NULLS NOT DISTINCT ("location_id", "lot_id", "condition_code", "ownership", "owner_customer_id"),
    CONSTRAINT "ck_inventory_position_condition_code_domain" CHECK ("condition_code" IN ('SALEABLE', 'QUARANTINE', 'DISPLAY', 'DAMAGED')),
    CONSTRAINT "ck_inventory_position_ownership_domain" CHECK ("ownership" IN ('COMPANY', 'CUSTOMER', 'SUPPLIER')),
    CONSTRAINT "ck_inventory_position_customer_owner" CHECK ((ownership = 'CUSTOMER') = (owner_customer_id IS NOT NULL))
);
COMMENT ON TABLE dien_may."inventory_position" IS 'Ngăn tồn theo lô vị trí tình trạng và chủ sở hữu.
Ràng buộc nghiệp vụ: CUSTOMER cần owner_customer_id; loại khác không được có FK này. Hàng giữ hộ không thuộc tồn bán và giá trị tồn sở hữu.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."inventory_position"."position_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."inventory_position"."location_id" IS 'Liên kết vị trí vật lý bên trong kho.
FK → warehouse_location.location_id.';
COMMENT ON COLUMN dien_may."inventory_position"."lot_id" IS 'Liên kết lô gốc để truy nguồn và tính tuổi tồn, không phải giá vốn hiện hành.
FK → stock_lot.lot_id.';
COMMENT ON COLUMN dien_may."inventory_position"."condition_code" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."inventory_position"."ownership" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."inventory_position"."owner_customer_id" IS 'Khách sở hữu hàng giữ hộ; bắt buộc với CUSTOMER và NULL với loại sở hữu khác.
FK → customer.customer_id.';

-- T033 stock_balance: Số dư lượng chiếu từ sổ kho theo ngăn tồn
CREATE TABLE dien_may."stock_balance" (
    "position_id" uuid NOT NULL,
    "on_hand_qty" integer NOT NULL,
    "row_version" integer NOT NULL DEFAULT 1,
    "last_posting_id" uuid,
    CONSTRAINT "pk_stock_balance" PRIMARY KEY ("position_id"),
    CONSTRAINT "ck_stock_balance_on_hand_qty_nonnegative" CHECK ("on_hand_qty" >= 0),
    CONSTRAINT "ck_stock_balance_row_version_positive" CHECK ("row_version" > 0)
);
COMMENT ON TABLE dien_may."stock_balance" IS 'Số dư lượng chiếu từ sổ kho theo ngăn tồn.
Ràng buộc nghiệp vụ: on_hand_qty >= 0. Là projection có thể tái tạo; không cho chỉnh trực tiếp hoặc cộng thêm lượng giữ vào on_hand.
Kiểm soát ghi: Chỉ tiến trình ghi sổ cập nhật trong transaction; tái tạo từ sổ được khi đối chiếu. Không có chức năng người dùng tự sửa số dư.';
COMMENT ON COLUMN dien_may."stock_balance"."position_id" IS 'Liên kết ngăn tồn theo lô vị trí tình trạng và chủ sở hữu.
FK → inventory_position.position_id.';
COMMENT ON COLUMN dien_may."stock_balance"."on_hand_qty" IS 'Lượng đang có tại ngăn tồn; chưa trừ giữ hàng, không bao gồm lượng giữ như phần cộng thêm.';
COMMENT ON COLUMN dien_may."stock_balance"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';
COMMENT ON COLUMN dien_may."stock_balance"."last_posting_id" IS 'Posting gần nhất đã cập nhật số dư này, phục vụ truy vết và đối chiếu.
FK → stock_posting.document_id.';

-- T034 stock_cost_balance: Số dư giá vốn bình quân di động theo kho và SKU
CREATE TABLE dien_may."stock_cost_balance" (
    "warehouse_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "owned_qty" integer NOT NULL,
    "carrying_value" numeric(24,6) NOT NULL,
    "average_unit_cost" numeric(24,6) NOT NULL,
    "row_version" integer NOT NULL DEFAULT 1,
    CONSTRAINT "pk_stock_cost_balance" PRIMARY KEY ("warehouse_id", "sku_id"),
    CONSTRAINT "ck_stock_cost_balance_owned_qty_nonnegative" CHECK ("owned_qty" >= 0),
    CONSTRAINT "ck_stock_cost_balance_carrying_value_nonnegative" CHECK ("carrying_value" >= 0),
    CONSTRAINT "ck_stock_cost_balance_average_unit_cost_nonnegative" CHECK ("average_unit_cost" >= 0),
    CONSTRAINT "ck_stock_cost_balance_row_version_positive" CHECK ("row_version" > 0)
);
COMMENT ON TABLE dien_may."stock_cost_balance" IS 'Số dư giá vốn bình quân di động theo kho và SKU.
Ràng buộc nghiệp vụ: Chỉ gồm hàng COMPANY; cập nhật cùng posting. Giá vốn phát sinh giữ độ chính xác cao, tổng tiền chứng từ VND làm tròn theo chính sách.
Kiểm soát ghi: Chỉ tiến trình ghi sổ cập nhật trong transaction; tái tạo từ sổ được khi đối chiếu. Không có chức năng người dùng tự sửa số dư.';
COMMENT ON COLUMN dien_may."stock_cost_balance"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."stock_cost_balance"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."stock_cost_balance"."owned_qty" IS 'Tổng lượng thuộc sở hữu doanh nghiệp trong phạm vi tính giá vốn.';
COMMENT ON COLUMN dien_may."stock_cost_balance"."carrying_value" IS 'Tổng giá trị tồn thuộc sở hữu doanh nghiệp trong phạm vi kho và SKU.';
COMMENT ON COLUMN dien_may."stock_cost_balance"."average_unit_cost" IS 'Giá vốn bình quân di động hiện hành, là projection từ phát sinh đã ghi sổ.';
COMMENT ON COLUMN dien_may."stock_cost_balance"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';

-- T035 stock_posting: Lần ghi sổ bất biến có chứng từ nguồn xác định
CREATE TABLE dien_may."stock_posting" (
    "document_id" uuid NOT NULL,
    "source_document_id" uuid NOT NULL,
    "operation_kind" varchar(40) NOT NULL,
    "operation_key" varchar(255) NOT NULL,
    "reversal_of_id" uuid,
    "posted_at" timestamptz NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_stock_posting" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_stock_posting_source_document_id_operation_kin_d4a7b2f9cc" UNIQUE ("source_document_id", "operation_kind", "operation_key"),
    CONSTRAINT "ck_stock_posting_operation_kind_domain" CHECK ("operation_kind" IN ('OPENING', 'RECEIVE', 'DISPATCH', 'TRANSFER_OUT', 'TRANSFER_IN', 'RETURN_IN', 'COUNT_ADJUST', 'CUSTODY', 'REVERSE')),
    CONSTRAINT "ck_stock_posting_status_domain" CHECK ("status" IN ('POSTED', 'REVERSED')),
    CONSTRAINT "ck_stock_posting_reversal" CHECK ((operation_kind = 'REVERSE') = (reversal_of_id IS NOT NULL)),
    CONSTRAINT "ck_stock_posting_not_self_reversal" CHECK (reversal_of_id IS NULL OR reversal_of_id <> document_id)
);
COMMENT ON TABLE dien_may."stock_posting" IS 'Lần ghi sổ bất biến có chứng từ nguồn xác định.
Ràng buộc nghiệp vụ: Ghi sổ đúng một lần cho mỗi thao tác. Đảo là posting mới với movement đối ứng liên kết gốc. REVERSED chỉ nhãn đã có đối ứng; vẫn cộng movement gốc và movement đảo, không loại gốc làm đếm đảo hai lần. Nội dung và dòng cũ không sửa.
Kiểm soát ghi: Chỉ tạo khi ghi sổ, không có bản nháp trong bảng này. Nội dung và movement gốc bất biến; REVERSED chỉ đánh dấu đã có đối ứng, không loại phát sinh gốc khỏi phép cộng sổ.';
COMMENT ON COLUMN dien_may."stock_posting"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."stock_posting"."source_document_id" IS 'Chứng từ nguồn giải thích vì sao phát sinh sổ hoặc sự kiện.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."stock_posting"."operation_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."stock_posting"."operation_key" IS 'Khóa nghiệp vụ của thao tác để chống ghi nhận cùng hiệu ứng nhiều lần.';
COMMENT ON COLUMN dien_may."stock_posting"."reversal_of_id" IS 'Liên kết lần ghi sổ bất biến có chứng từ nguồn xác định.
FK → stock_posting.document_id.';
COMMENT ON COLUMN dien_may."stock_posting"."posted_at" IS 'Thời điểm ghi sổ chính thức, bắt buộc ở bảng chỉ lưu phát sinh đã chốt.';
COMMENT ON COLUMN dien_may."stock_posting"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T036 stock_movement: Dịch chuyển có nguồn đích, hỗ trợ nhập xuất và chuyển nội bộ
CREATE TABLE dien_may."stock_movement" (
    "movement_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "posting_id" uuid NOT NULL,
    "source_line_id" uuid NOT NULL,
    "from_position_id" uuid,
    "to_position_id" uuid,
    "quantity" integer NOT NULL,
    "unit_cost_snapshot" numeric(24,6) NOT NULL,
    "carrying_amount" numeric(24,6) NOT NULL,
    "reversal_of_id" uuid,
    CONSTRAINT "pk_stock_movement" PRIMARY KEY ("movement_id"),
    CONSTRAINT "ck_stock_movement_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_stock_movement_unit_cost_snapshot_nonnegative" CHECK ("unit_cost_snapshot" >= 0),
    CONSTRAINT "ck_stock_movement_carrying_amount_nonnegative" CHECK ("carrying_amount" >= 0),
    CONSTRAINT "ck_stock_movement_positions" CHECK (num_nonnulls(from_position_id, to_position_id) >= 1 AND from_position_id IS DISTINCT FROM to_position_id),
    CONSTRAINT "ck_stock_movement_not_self_reversal" CHECK (reversal_of_id IS NULL OR reversal_of_id <> movement_id)
);
COMMENT ON TABLE dien_may."stock_movement" IS 'Dịch chuyển có nguồn đích, hỗ trợ nhập xuất và chuyển nội bộ.
Ràng buộc nghiệp vụ: Lượng > 0; ít nhất một vị trí; from khác to. Hai vị trí nếu có phải cùng SKU/lô. Nguồn NULL chỉ cho nhập/nhận từ ngoài; đích NULL chỉ cho xuất/hoàn ngoài hợp lệ. source_line thuộc source_document của posting.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."stock_movement"."movement_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."stock_movement"."posting_id" IS 'Liên kết lần ghi sổ bất biến có chứng từ nguồn xác định.
FK → stock_posting.document_id.';
COMMENT ON COLUMN dien_may."stock_movement"."source_line_id" IS 'Dòng nguồn thuộc đúng source_document của posting.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."stock_movement"."from_position_id" IS 'Ngăn tồn bị giảm; NULL chỉ khi nghiệp vụ cho phép nhận hàng từ bên ngoài.
FK → inventory_position.position_id.';
COMMENT ON COLUMN dien_may."stock_movement"."to_position_id" IS 'Ngăn tồn được tăng; NULL chỉ khi nghiệp vụ cho phép xuất hàng ra ngoài.
FK → inventory_position.position_id.';
COMMENT ON COLUMN dien_may."stock_movement"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."stock_movement"."unit_cost_snapshot" IS 'Giá vốn hoặc đơn giá nhập chụp ở lần giao dịch, không lấy giá hiện hành để thay.';
COMMENT ON COLUMN dien_may."stock_movement"."carrying_amount" IS 'Giá trị giá vốn được mang theo lượng hàng của bản ghi.';
COMMENT ON COLUMN dien_may."stock_movement"."reversal_of_id" IS 'Movement gốc bị đối ứng; không xóa hoặc loại movement gốc khỏi sổ cộng dồn.
FK → stock_movement.movement_id.';

-- T037 device: Một máy cụ thể, không gộp với SKU hoặc dòng đơn
CREATE TABLE dien_may."device" (
    "device_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "sku_id" uuid NOT NULL,
    "origin_lot_id" uuid,
    "serial_raw" text NOT NULL,
    "serial_key" varchar(255) NOT NULL,
    "current_position_id" uuid,
    "ownership" varchar(40) NOT NULL,
    "owner_customer_id" uuid,
    "condition_code" varchar(40) NOT NULL,
    "row_version" integer NOT NULL DEFAULT 1,
    CONSTRAINT "pk_device" PRIMARY KEY ("device_id"),
    CONSTRAINT "uq_device_serial_key" UNIQUE ("serial_key"),
    CONSTRAINT "ck_device_ownership_domain" CHECK ("ownership" IN ('COMPANY', 'CUSTOMER', 'SUPPLIER')),
    CONSTRAINT "ck_device_condition_code_domain" CHECK ("condition_code" IN ('SALEABLE', 'QUARANTINE', 'DISPLAY', 'DAMAGED')),
    CONSTRAINT "ck_device_row_version_positive" CHECK ("row_version" > 0),
    CONSTRAINT "ck_device_customer_owner" CHECK ((ownership = 'CUSTOMER') = (owner_customer_id IS NOT NULL))
);
COMMENT ON TABLE dien_may."device" IS 'Một máy cụ thể, không gộp với SKU hoặc dòng đơn.
Ràng buộc nghiệp vụ: Mã key duy nhất toàn hệ thống theo SRS. Nếu không có mã hãng dùng định danh nội bộ được phép. Vị trí NULL khi ngoài kho; mọi thay đổi vị trí/chủ sở hữu có event. SKU và sở hữu phải khớp position khi có vị trí.
Kiểm soát ghi: Vị trí, chủ sở hữu và tình trạng hiện tại chỉ cập nhật từ movement hoặc device_event trong transaction. Hiệu chỉnh serial cần chứng cứ và phê duyệt, không sửa mất lịch sử máy.';
COMMENT ON COLUMN dien_may."device"."device_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."device"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."device"."origin_lot_id" IS 'Lô gốc đã tiếp nhận máy; có thể NULL với hồ sơ máy ngoài hệ thống được phép nhận.
FK → stock_lot.lot_id.';
COMMENT ON COLUMN dien_may."device"."serial_raw" IS 'Serial gốc, tối đa 100 ký tự theo SRS; giữ nguyên chuỗi số 0 đầu.';
COMMENT ON COLUMN dien_may."device"."serial_key" IS 'Serial sau chuẩn hóa dùng kiểm duy nhất toàn hệ thống; không đổi mất lịch sử.';
COMMENT ON COLUMN dien_may."device"."current_position_id" IS 'Ngăn tồn hiện tại của máy; NULL khi máy đang ở ngoài các kho được theo dõi.
FK → inventory_position.position_id.';
COMMENT ON COLUMN dien_may."device"."ownership" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."device"."owner_customer_id" IS 'Khách sở hữu thiết bị khi ownership = CUSTOMER; không dùng để xác định vị trí máy.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."device"."condition_code" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."device"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';

-- T038 device_identifier: IMEI hoặc mã bổ sung của thiết bị, tránh trùng chéo cột IMEI1 IMEI2
CREATE TABLE dien_may."device_identifier" (
    "identifier_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "device_id" uuid NOT NULL,
    "identifier_kind" varchar(40) NOT NULL,
    "ordinal" integer NOT NULL,
    "raw_value" text NOT NULL,
    "normalized_value" varchar(255) NOT NULL,
    CONSTRAINT "pk_device_identifier" PRIMARY KEY ("identifier_id"),
    CONSTRAINT "uq_device_identifier_identifier_kind_normalized_value" UNIQUE ("identifier_kind", "normalized_value"),
    CONSTRAINT "uq_device_identifier_device_id_identifier_kind_ordinal" UNIQUE ("device_id", "identifier_kind", "ordinal"),
    CONSTRAINT "ck_device_identifier_identifier_kind_domain" CHECK ("identifier_kind" IN ('IMEI', 'MANUFACTURER_ALIAS')),
    CONSTRAINT "ck_device_identifier_ordinal_positive" CHECK ("ordinal" > 0)
);
COMMENT ON TABLE dien_may."device_identifier" IS 'IMEI hoặc mã bổ sung của thiết bị, tránh trùng chéo cột IMEI1 IMEI2.
Ràng buộc nghiệp vụ: Một IMEI không gắn hai máy dù ở vị trí thứ nhất hay thứ hai. Serial chính vẫn ở device.serial_key. Không chuyển chuỗi mã sang số.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."device_identifier"."identifier_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."device_identifier"."device_id" IS 'Liên kết một máy cụ thể, không gộp với sku hoặc dòng đơn.
FK → device.device_id.';
COMMENT ON COLUMN dien_may."device_identifier"."identifier_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."device_identifier"."ordinal" IS 'Số thứ tự mã định danh cùng loại trên một thiết bị, ví dụ IMEI thứ nhất hoặc thứ hai.';
COMMENT ON COLUMN dien_may."device_identifier"."raw_value" IS 'Giá trị gốc đã tiếp nhận trước chuẩn hóa; không chuyển mã dạng chuỗi thành số.';
COMMENT ON COLUMN dien_may."device_identifier"."normalized_value" IS 'IMEI hoặc mã phụ đã chuẩn hóa; duy nhất theo identifier_kind để chặn trùng chéo vị trí IMEI.';

-- T039 stock_movement_device: Máy nào tham gia một dịch chuyển tồn
CREATE TABLE dien_may."stock_movement_device" (
    "movement_id" uuid NOT NULL,
    "device_id" uuid NOT NULL,
    "device_allocation_id" uuid,
    CONSTRAINT "pk_stock_movement_device" PRIMARY KEY ("movement_id", "device_id")
);
COMMENT ON TABLE dien_may."stock_movement_device" IS 'Máy nào tham gia một dịch chuyển tồn.
Ràng buộc nghiệp vụ: Với SKU serial, số máy bằng movement.quantity; máy phải ở đúng nguồn ngay trước ghi. Cùng thiết bị được phép đi qua nhiều movement lịch sử, không chỉ một giao dịch suốt đời.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."stock_movement_device"."movement_id" IS 'Liên kết dịch chuyển có nguồn đích, hỗ trợ nhập xuất và chuyển nội bộ.
FK → stock_movement.movement_id.';
COMMENT ON COLUMN dien_may."stock_movement_device"."device_id" IS 'Liên kết một máy cụ thể, không gộp với sku hoặc dòng đơn.
FK → device.device_id.';
COMMENT ON COLUMN dien_may."stock_movement_device"."device_allocation_id" IS 'Liên kết cấp độc quyền serial cho một giữ hàng đang hiệu lực.
FK → device_allocation.allocation_id.';

-- T040 device_event: Lịch sử vị trí quyền sở hữu và tình trạng máy
CREATE TABLE dien_may."device_event" (
    "device_event_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "device_id" uuid NOT NULL,
    "source_document_id" uuid NOT NULL,
    "movement_id" uuid,
    "event_type" varchar(100) NOT NULL,
    "before_snapshot" jsonb NOT NULL,
    "after_snapshot" jsonb NOT NULL,
    "occurred_at" timestamptz NOT NULL,
    CONSTRAINT "pk_device_event" PRIMARY KEY ("device_event_id")
);
COMMENT ON TABLE dien_may."device_event" IS 'Lịch sử vị trí quyền sở hữu và tình trạng máy.
Ràng buộc nghiệp vụ: Ghi bất biến; bao gồm nhận bảo hành, chuyển hãng, trả khách và thay chủ. current_* ở device là projection của chuỗi này.
Cấu trúc before_snapshot: Các trường nghiệp vụ được phép ghi trước thay đổi; không chứa bí mật hoặc dữ liệu máy khách.
Cấu trúc after_snapshot: Các trường nghiệp vụ tương ứng sau thay đổi; phải cùng schema với sự kiện.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."device_event"."device_event_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."device_event"."device_id" IS 'Liên kết một máy cụ thể, không gộp với sku hoặc dòng đơn.
FK → device.device_id.';
COMMENT ON COLUMN dien_may."device_event"."source_document_id" IS 'Chứng từ nguồn giải thích vì sao phát sinh sổ hoặc sự kiện.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."device_event"."movement_id" IS 'Liên kết dịch chuyển có nguồn đích, hỗ trợ nhập xuất và chuyển nội bộ.
FK → stock_movement.movement_id.';
COMMENT ON COLUMN dien_may."device_event"."event_type" IS 'Mã loại sự kiện, dùng để chọn đúng cách xử lý và cấu trúc payload.';
COMMENT ON COLUMN dien_may."device_event"."before_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."device_event"."after_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."device_event"."occurred_at" IS 'Thời điểm sự kiện nghiệp vụ xảy ra, giữ để dựng đúng thứ tự xử lý.';

-- ============================================================================
-- M05 Giữ hàng chuyển kho và kiểm kê
-- ============================================================================

-- T041 stock_reservation: Giữ lượng bán hoặc phân bổ chuyển, chưa phải xuất kho
CREATE TABLE dien_may."stock_reservation" (
    "reservation_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "warehouse_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "order_line_id" uuid,
    "transfer_line_id" uuid,
    "quantity" integer NOT NULL,
    "state" varchar(40) NOT NULL,
    "expires_at" timestamptz,
    "extension_count" integer NOT NULL DEFAULT 0,
    "row_version" integer NOT NULL DEFAULT 1,
    CONSTRAINT "pk_stock_reservation" PRIMARY KEY ("reservation_id"),
    CONSTRAINT "ck_stock_reservation_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_stock_reservation_state_domain" CHECK ("state" IN ('HELD', 'COMMITTED', 'CONSUMED', 'RELEASED', 'EXPIRED')),
    CONSTRAINT "ck_stock_reservation_extension_count_nonnegative" CHECK ("extension_count" >= 0),
    CONSTRAINT "ck_stock_reservation_row_version_positive" CHECK ("row_version" > 0),
    CONSTRAINT "ck_stock_reservation_source" CHECK (num_nonnulls(order_line_id, transfer_line_id) = 1),
    CONSTRAINT "ck_stock_reservation_held_expiry" CHECK (state <> 'HELD' OR expires_at IS NOT NULL)
);
COMMENT ON TABLE dien_may."stock_reservation" IS 'Giữ lượng bán hoặc phân bổ chuyển, chưa phải xuất kho.
Ràng buộc nghiệp vụ: XOR hai FK nguồn. HELD có hạn; COMMITTED không bị tác vụ hết hạn giải phóng. Giữ theo SKU-kho trước khi chọn lô/serial. Lượng dương; tổng giữ hoạt động không vượt tồn đạt COMPANY của SKU-kho.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."stock_reservation"."reservation_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."stock_reservation"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."stock_reservation"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."stock_reservation"."order_line_id" IS 'Dòng hàng bán được giữ; có giá trị thì transfer_line_id phải NULL.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."stock_reservation"."transfer_line_id" IS 'Dòng chuyển kho được phân bổ; có giá trị thì order_line_id phải NULL.
FK → transfer_order_line.line_id.';
COMMENT ON COLUMN dien_may."stock_reservation"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."stock_reservation"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."stock_reservation"."expires_at" IS 'Mốc hết giữ tạm HELD; COMMITTED không bị tác vụ hết hạn tự giải phóng.';
COMMENT ON COLUMN dien_may."stock_reservation"."extension_count" IS 'Số lần đã gia hạn giữ tạm, phải nằm trong giới hạn cấu hình.
Mặc định: 0 khi bắt đầu giữ.';
COMMENT ON COLUMN dien_may."stock_reservation"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';

-- T042 device_allocation: Cấp độc quyền serial cho một giữ hàng đang hiệu lực
CREATE TABLE dien_may."device_allocation" (
    "allocation_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "reservation_id" uuid NOT NULL,
    "device_id" uuid NOT NULL,
    "state" varchar(40) NOT NULL,
    "allocated_at" timestamptz NOT NULL,
    CONSTRAINT "pk_device_allocation" PRIMARY KEY ("allocation_id"),
    CONSTRAINT "ck_device_allocation_state_domain" CHECK ("state" IN ('ACTIVE', 'CONSUMED', 'RELEASED'))
);
COMMENT ON TABLE dien_may."device_allocation" IS 'Cấp độc quyền serial cho một giữ hàng đang hiệu lực.
Ràng buộc nghiệp vụ: Chỉ cấp khi máy đúng SKU/kho, tình trạng đạt COMPANY. Tổng serial ACTIVE/CONSUMED không vượt lượng giữ; xuất thực tham chiếu bản cấp phát.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."device_allocation"."allocation_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."device_allocation"."reservation_id" IS 'Liên kết giữ lượng bán hoặc phân bổ chuyển, chưa phải xuất kho.
FK → stock_reservation.reservation_id.';
COMMENT ON COLUMN dien_may."device_allocation"."device_id" IS 'Liên kết một máy cụ thể, không gộp với sku hoặc dòng đơn.
FK → device.device_id.';
COMMENT ON COLUMN dien_may."device_allocation"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."device_allocation"."allocated_at" IS 'Thời điểm serial được cấp độc quyền cho giữ hàng.';

-- T043 transfer_order: Chuyển hàng giữa hai kho có theo dõi đang vận chuyển
CREATE TABLE dien_may."transfer_order" (
    "document_id" uuid NOT NULL,
    "from_warehouse_id" uuid NOT NULL,
    "to_warehouse_id" uuid NOT NULL,
    "transit_warehouse_id" uuid NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_transfer_order" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_transfer_order_status_domain" CHECK ("status" IN ('DRAFT', 'APPROVED', 'IN_TRANSIT', 'PART_RECEIVED', 'CLOSED', 'CANCELLED')),
    CONSTRAINT "ck_transfer_order_warehouses" CHECK (from_warehouse_id <> to_warehouse_id AND transit_warehouse_id <> from_warehouse_id AND transit_warehouse_id <> to_warehouse_id)
);
COMMENT ON TABLE dien_may."transfer_order" IS 'Chuyển hàng giữa hai kho có theo dõi đang vận chuyển.
Ràng buộc nghiệp vụ: Ba kho có vai trò đúng; nguồn khác đích; transit có kind TRANSIT.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."transfer_order"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."transfer_order"."from_warehouse_id" IS 'Kho nguồn của phiếu chuyển, khác kho đích.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."transfer_order"."to_warehouse_id" IS 'Kho đích nhận hàng chuyển; chỉ tăng tồn bán sau nhận đạt.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."transfer_order"."transit_warehouse_id" IS 'Kho ảo TRANSIT giữ lượng đang đi và phần chênh lệch chưa xử lý.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."transfer_order"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T044 transfer_order_line: Lượng và giá vốn mang theo của một dòng chuyển
CREATE TABLE dien_may."transfer_order_line" (
    "line_id" uuid NOT NULL,
    "transfer_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "requested_qty" integer NOT NULL,
    "issued_qty" integer NOT NULL,
    "accepted_qty" integer NOT NULL,
    "damaged_qty" integer NOT NULL,
    "carrying_amount_snapshot" numeric(24,6) NOT NULL,
    CONSTRAINT "pk_transfer_order_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_transfer_order_line_requested_qty_positive" CHECK ("requested_qty" > 0),
    CONSTRAINT "ck_transfer_order_line_issued_qty_nonnegative" CHECK ("issued_qty" >= 0),
    CONSTRAINT "ck_transfer_order_line_accepted_qty_nonnegative" CHECK ("accepted_qty" >= 0),
    CONSTRAINT "ck_transfer_order_line_damaged_qty_nonnegative" CHECK ("damaged_qty" >= 0),
    CONSTRAINT "ck_transfer_order_line_carrying_amount_snapshot_nonnegative" CHECK ("carrying_amount_snapshot" >= 0)
);
COMMENT ON TABLE dien_may."transfer_order_line" IS 'Lượng và giá vốn mang theo của một dòng chuyển.
Ràng buộc nghiệp vụ: Các số đã xuất/nhận là projection từ movement; thiếu còn tại transit. Nhận từng phần được phép; tổng nhận/hoàn/mất được duyệt không vượt số xuất.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."transfer_order_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."transfer_order_line"."transfer_id" IS 'Liên kết chuyển hàng giữa hai kho có theo dõi đang vận chuyển.
FK → transfer_order.document_id.';
COMMENT ON COLUMN dien_may."transfer_order_line"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."transfer_order_line"."requested_qty" IS 'Lượng được đề nghị chuyển giữa hai kho.';
COMMENT ON COLUMN dien_may."transfer_order_line"."issued_qty" IS 'Lượng đã xuất chuyển thực tế, được dựng từ movement đã ghi sổ.';
COMMENT ON COLUMN dien_may."transfer_order_line"."accepted_qty" IS 'Lượng được nhận đạt chất lượng; với phiếu chuyển là số chiếu từ lần nhận thực.';
COMMENT ON COLUMN dien_may."transfer_order_line"."damaged_qty" IS 'Lượng nhận hỏng hoặc không đạt khi nhận chuyển, phải vào cách ly.';
COMMENT ON COLUMN dien_may."transfer_order_line"."carrying_amount_snapshot" IS 'Giá vốn chụp của phần hàng chuyển, dùng khi nhận tại đích và xử lý chênh lệch.';

-- T045 stocktake: Phiên kiểm kê có phạm vi khóa ghi sổ rõ ràng
CREATE TABLE dien_may."stocktake" (
    "document_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "scope_location_id" uuid,
    "scope_sku_id" uuid,
    "locked_at" timestamptz,
    "unlocked_at" timestamptz,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_stocktake" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_stocktake_status_domain" CHECK ("status" IN ('DRAFT', 'LOCKED', 'COUNTED', 'APPROVED', 'POSTED', 'CANCELLED')),
    CONSTRAINT "ck_stocktake_unlock_time" CHECK (unlocked_at IS NULL OR (locked_at IS NOT NULL AND unlocked_at >= locked_at))
);
COMMENT ON TABLE dien_may."stocktake" IS 'Phiên kiểm kê có phạm vi khóa ghi sổ rõ ràng.
Ràng buộc nghiệp vụ: NULL trong bộ lọc nghĩa toàn kho, không phải chưa xác định. Cấm hai phiên LOCKED chồng phạm vi; giữ khóa tới chốt/hủy có quyền.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."stocktake"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."stocktake"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."stocktake"."scope_location_id" IS 'Vị trí thuộc phạm vi kiểm; NULL áp dụng mọi vị trí trong kho đã chọn.
FK → warehouse_location.location_id.';
COMMENT ON COLUMN dien_may."stocktake"."scope_sku_id" IS 'SKU thuộc phạm vi kiểm; NULL áp dụng mọi SKU trong các vị trí được chọn.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."stocktake"."locked_at" IS 'Thời điểm bắt đầu khóa phạm vi kiểm kê và chụp số liệu.';
COMMENT ON COLUMN dien_may."stocktake"."unlocked_at" IS 'Thời điểm mở khóa sau khi phiên kiểm kê chốt hoặc hủy hợp lệ.';
COMMENT ON COLUMN dien_may."stocktake"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T046 stocktake_line: Số hệ thống và số thực theo ngăn tồn tại mốc kiểm
CREATE TABLE dien_may."stocktake_line" (
    "line_id" uuid NOT NULL,
    "stocktake_id" uuid NOT NULL,
    "position_id" uuid NOT NULL,
    "system_qty" integer NOT NULL,
    "counted_qty" integer,
    "variance_reason" varchar(500),
    CONSTRAINT "pk_stocktake_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "uq_stocktake_line_stocktake_id_position_id" UNIQUE ("stocktake_id", "position_id"),
    CONSTRAINT "ck_stocktake_line_system_qty_nonnegative" CHECK ("system_qty" >= 0),
    CONSTRAINT "ck_stocktake_line_counted_qty_nonnegative" CHECK ("counted_qty" >= 0)
);
COMMENT ON TABLE dien_may."stocktake_line" IS 'Số hệ thống và số thực theo ngăn tồn tại mốc kiểm.
Ràng buộc nghiệp vụ: Chênh được ghi bằng stock_posting có nguồn là phiên kiểm; không sửa projection trực tiếp.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."stocktake_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."stocktake_line"."stocktake_id" IS 'Liên kết phiên kiểm kê có phạm vi khóa ghi sổ rõ ràng.
FK → stocktake.document_id.';
COMMENT ON COLUMN dien_may."stocktake_line"."position_id" IS 'Liên kết ngăn tồn theo lô vị trí tình trạng và chủ sở hữu.
FK → inventory_position.position_id.';
COMMENT ON COLUMN dien_may."stocktake_line"."system_qty" IS 'Số lượng hệ thống tại mốc khóa kiểm kê, không thay theo phát sinh sau mốc này.';
COMMENT ON COLUMN dien_may."stocktake_line"."counted_qty" IS 'Số lượng thực đếm; NULL là chưa kiểm đếm, 0 là đã đếm và không có hàng.';
COMMENT ON COLUMN dien_may."stocktake_line"."variance_reason" IS 'Nguyên nhân chênh lệch kiểm kê được ghi để trình duyệt điều chỉnh.';

-- T047 stocktake_observation: Lần quét hoặc phát hiện serial trong kiểm kê
CREATE TABLE dien_may."stocktake_observation" (
    "observation_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "stocktake_id" uuid NOT NULL,
    "device_id" uuid,
    "observed_serial" text NOT NULL,
    "observed_location_id" uuid NOT NULL,
    "result" varchar(40) NOT NULL,
    CONSTRAINT "pk_stocktake_observation" PRIMARY KEY ("observation_id"),
    CONSTRAINT "ck_stocktake_observation_result_domain" CHECK ("result" IN ('MATCH', 'MISSING', 'EXTRA', 'WRONG_LOCATION', 'UNKNOWN'))
);
COMMENT ON TABLE dien_may."stocktake_observation" IS 'Lần quét hoặc phát hiện serial trong kiểm kê.
Ràng buộc nghiệp vụ: Serial lạ không tự tạo tồn; cần kiểm định nguồn và phê duyệt trước posting.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."stocktake_observation"."observation_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."stocktake_observation"."stocktake_id" IS 'Liên kết phiên kiểm kê có phạm vi khóa ghi sổ rõ ràng.
FK → stocktake.document_id.';
COMMENT ON COLUMN dien_may."stocktake_observation"."device_id" IS 'Liên kết một máy cụ thể, không gộp với sku hoặc dòng đơn.
FK → device.device_id.';
COMMENT ON COLUMN dien_may."stocktake_observation"."observed_serial" IS 'Chuỗi serial thực tế được quét trong kiểm kê, kể cả mã chưa được nhận diện.';
COMMENT ON COLUMN dien_may."stocktake_observation"."observed_location_id" IS 'Liên kết vị trí vật lý bên trong kho.
FK → warehouse_location.location_id.';
COMMENT ON COLUMN dien_may."stocktake_observation"."result" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';

-- ============================================================================
-- M06 Giá khuyến mại và voucher
-- ============================================================================

-- T048 price_list: Phạm vi chọn bảng giá
CREATE TABLE dien_may."price_list" (
    "price_list_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "store_id" uuid,
    "channel" varchar(40),
    "priority" integer NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_price_list" PRIMARY KEY ("price_list_id"),
    CONSTRAINT "uq_price_list_code" UNIQUE ("code"),
    CONSTRAINT "ck_price_list_channel_domain" CHECK ("channel" IN ('ONLINE', 'COUNTER')),
    CONSTRAINT "ck_price_list_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."price_list" IS 'Phạm vi chọn bảng giá.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."price_list"."price_list_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."price_list"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."price_list"."store_id" IS 'Liên kết cửa hàng hoặc điểm điều hành bán hàng.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."price_list"."channel" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."price_list"."priority" IS 'Độ ưu tiên lựa chọn; số lớn được ưu tiên hơn khi các tiêu chí phạm vi tương đương.';
COMMENT ON COLUMN dien_may."price_list"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T049 price_entry: Giá SKU có khoảng hiệu lực và phiên bản
CREATE TABLE dien_may."price_entry" (
    "price_entry_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "price_list_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "unit_price" numeric(19,0) NOT NULL,
    "tax_rate" numeric(9,6) NOT NULL,
    "valid_from" timestamptz NOT NULL,
    "valid_to" timestamptz,
    "revision" integer NOT NULL,
    CONSTRAINT "pk_price_entry" PRIMARY KEY ("price_entry_id"),
    CONSTRAINT "ck_price_entry_unit_price_nonnegative" CHECK ("unit_price" >= 0),
    CONSTRAINT "ck_price_entry_revision_positive" CHECK ("revision" > 0),
    CONSTRAINT "ck_price_entry_valid_range" CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE dien_may."price_entry" IS 'Giá SKU có khoảng hiệu lực và phiên bản.
Ràng buộc nghiệp vụ: Khoảng [from,to) không chồng ở cùng list/SKU/priority; ngày kết thúc nếu có lớn hơn bắt đầu. Chọn theo store-specific, channel-specific rồi priority giảm dần; cấm hai ứng viên thắng ngang nhau kể cả khác list ở lúc công bố/sửa cấu hình. Không sửa bản đã được đơn tham chiếu; tạo bản mới.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."price_entry"."price_entry_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."price_entry"."price_list_id" IS 'Liên kết phạm vi chọn bảng giá.
FK → price_list.price_list_id.';
COMMENT ON COLUMN dien_may."price_entry"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."price_entry"."unit_price" IS 'Đơn giá niêm yết đã gồm thuế theo quy ước giá R1.';
COMMENT ON COLUMN dien_may."price_entry"."tax_rate" IS 'Tỷ lệ thuế được cấu hình theo nhóm hàng và thời điểm; không gán cứng trong mã.';
COMMENT ON COLUMN dien_may."price_entry"."valid_from" IS 'Thời điểm bắt đầu hiệu lực, được tính vào khoảng áp dụng.';
COMMENT ON COLUMN dien_may."price_entry"."valid_to" IS 'Thời điểm kết thúc hiệu lực, không được tính vào khoảng; NULL là chưa ấn định kết thúc.';
COMMENT ON COLUMN dien_may."price_entry"."revision" IS 'Phiên bản giá được công bố; bản đã tham chiếu bởi đơn không được sửa hồi tố.';

-- T050 promotion: Định danh chương trình khuyến mại
CREATE TABLE dien_may."promotion" (
    "promotion_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_promotion" PRIMARY KEY ("promotion_id"),
    CONSTRAINT "uq_promotion_code" UNIQUE ("code"),
    CONSTRAINT "ck_promotion_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."promotion" IS 'Định danh chương trình khuyến mại.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."promotion"."promotion_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."promotion"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."promotion"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."promotion"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T051 promotion_version: Luật khuyến mại bất biến theo phiên bản
CREATE TABLE dien_may."promotion_version" (
    "promotion_version_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "promotion_id" uuid NOT NULL,
    "version_no" integer NOT NULL,
    "valid_from" timestamptz NOT NULL,
    "valid_to" timestamptz NOT NULL,
    "rules_snapshot" jsonb NOT NULL,
    "usage_limit" integer,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_promotion_version" PRIMARY KEY ("promotion_version_id"),
    CONSTRAINT "uq_promotion_version_promotion_id_version_no" UNIQUE ("promotion_id", "version_no"),
    CONSTRAINT "ck_promotion_version_version_no_positive" CHECK ("version_no" > 0),
    CONSTRAINT "ck_promotion_version_usage_limit_nonnegative" CHECK ("usage_limit" >= 0),
    CONSTRAINT "ck_promotion_version_status_domain" CHECK ("status" IN ('DRAFT', 'APPROVED', 'ACTIVE', 'ENDED', 'CANCELLED')),
    CONSTRAINT "ck_promotion_version_valid_range" CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE dien_may."promotion_version" IS 'Luật khuyến mại bất biến theo phiên bản.
Ràng buộc nghiệp vụ: JSON là luật có schema được kiểm, không chứa SQL tự do; nhóm SKU đích dùng bảng nối để đảm bảo FK.
Cấu trúc rules_snapshot: schema_version, channel, scope, minimum_order, discount_type, rate_or_amount, cap, can_combine_line_discount, usage_rule; phiên bản đã dùng không sửa.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."promotion_version"."promotion_version_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."promotion_version"."promotion_id" IS 'Liên kết định danh chương trình khuyến mại.
FK → promotion.promotion_id.';
COMMENT ON COLUMN dien_may."promotion_version"."version_no" IS 'Số thứ tự phiên bản trong cùng đối tượng cha, không dùng lại phiên bản đã công bố.';
COMMENT ON COLUMN dien_may."promotion_version"."valid_from" IS 'Thời điểm bắt đầu hiệu lực, được tính vào khoảng áp dụng.';
COMMENT ON COLUMN dien_may."promotion_version"."valid_to" IS 'Thời điểm kết thúc chương trình, bắt buộc sau valid_from và không thuộc khoảng được áp dụng.';
COMMENT ON COLUMN dien_may."promotion_version"."rules_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."promotion_version"."usage_limit" IS 'Số lượt tối đa được phép; phải tính cả các lượt đang giữ theo quy tắc chương trình.';
COMMENT ON COLUMN dien_may."promotion_version"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T052 promotion_sku: SKU thuộc phạm vi một phiên bản khuyến mại
CREATE TABLE dien_may."promotion_sku" (
    "promotion_version_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    CONSTRAINT "pk_promotion_sku" PRIMARY KEY ("promotion_version_id", "sku_id")
);
COMMENT ON TABLE dien_may."promotion_sku" IS 'SKU thuộc phạm vi một phiên bản khuyến mại.
Ràng buộc nghiệp vụ: Nếu chương trình áp toàn nhóm phải ghi quy tắc phạm vi rõ trong rules; kiểm SKU hiệu lực tại lúc đặt.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."promotion_sku"."promotion_version_id" IS 'Liên kết luật khuyến mại bất biến theo phiên bản.
FK → promotion_version.promotion_version_id.';
COMMENT ON COLUMN dien_may."promotion_sku"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';

-- T053 voucher: Mã sử dụng cho khuyến mại cấp đơn
CREATE TABLE dien_may."voucher" (
    "voucher_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "promotion_version_id" uuid NOT NULL,
    "code" varchar(100) NOT NULL,
    "usage_limit" integer NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_voucher" PRIMARY KEY ("voucher_id"),
    CONSTRAINT "uq_voucher_code" UNIQUE ("code"),
    CONSTRAINT "ck_voucher_usage_limit_nonnegative" CHECK ("usage_limit" >= 0),
    CONSTRAINT "ck_voucher_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."voucher" IS 'Mã sử dụng cho khuyến mại cấp đơn.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."voucher"."voucher_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."voucher"."promotion_version_id" IS 'Liên kết luật khuyến mại bất biến theo phiên bản.
FK → promotion_version.promotion_version_id.';
COMMENT ON COLUMN dien_may."voucher"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."voucher"."usage_limit" IS 'Số lượt tối đa được phép; phải tính cả các lượt đang giữ theo quy tắc chương trình.';
COMMENT ON COLUMN dien_may."voucher"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T054 voucher_claim: Một lượt giữ hoặc sử dụng voucher gắn đúng đơn
CREATE TABLE dien_may."voucher_claim" (
    "claim_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "voucher_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "state" varchar(40) NOT NULL,
    "held_at" timestamptz NOT NULL,
    "expires_at" timestamptz,
    "used_at" timestamptz,
    CONSTRAINT "pk_voucher_claim" PRIMARY KEY ("claim_id"),
    CONSTRAINT "uq_voucher_claim_order_id" UNIQUE ("order_id"),
    CONSTRAINT "ck_voucher_claim_state_domain" CHECK ("state" IN ('HELD', 'USED', 'RELEASED'))
);
COMMENT ON TABLE dien_may."voucher_claim" IS 'Một lượt giữ hoặc sử dụng voucher gắn đúng đơn.
Ràng buộc nghiệp vụ: Một voucher cấp đơn R1. Lượt HELD và USED đều chiếm hạn mức; USED không tự phục hồi sau hủy/trả. Đơn đã thu giữ nguyên lượt và quyền lợi.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."voucher_claim"."claim_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."voucher_claim"."voucher_id" IS 'Liên kết mã sử dụng cho khuyến mại cấp đơn.
FK → voucher.voucher_id.';
COMMENT ON COLUMN dien_may."voucher_claim"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."voucher_claim"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."voucher_claim"."held_at" IS 'Thời điểm bắt đầu giữ lượt sử dụng.';
COMMENT ON COLUMN dien_may."voucher_claim"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';
COMMENT ON COLUMN dien_may."voucher_claim"."used_at" IS 'Thời điểm lượt giữ được chuyển thành đã dùng.';

-- ============================================================================
-- M07 Khách hàng giỏ hàng và đơn bán
-- ============================================================================

-- T055 customer: Hồ sơ người mua gồm khách vãng lai không có tài khoản
CREATE TABLE dien_may."customer" (
    "customer_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "user_id" uuid,
    "display_name" varchar(255) NOT NULL,
    "is_guest" boolean NOT NULL,
    "merged_into_id" uuid,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_customer" PRIMARY KEY ("customer_id"),
    CONSTRAINT "uq_customer_user_id" UNIQUE ("user_id"),
    CONSTRAINT "ck_customer_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE', 'MERGED', 'ANONYMIZED')),
    CONSTRAINT "ck_customer_merge_target" CHECK (merged_into_id IS NULL OR merged_into_id <> customer_id)
);
COMMENT ON TABLE dien_may."customer" IS 'Hồ sơ người mua gồm khách vãng lai không có tài khoản.
Ràng buộc nghiệp vụ: RDA chọn tạo hồ sơ guest cho mọi giao dịch để truy sở hữu máy. Không tự gộp vì trùng tên/điện thoại; gộp cần duyệt và giữ liên kết lịch sử.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."customer"."customer_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."customer"."user_id" IS 'Tài khoản nếu khách có đăng nhập; NULL cho hồ sơ guest, không ngăn đặt hàng.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."customer"."display_name" IS 'Tên người được hiển thị; không dùng tên để xác định duy nhất một người.';
COMMENT ON COLUMN dien_may."customer"."is_guest" IS 'TRUE khi hồ sơ mua hàng không yêu cầu tài khoản đăng nhập.';
COMMENT ON COLUMN dien_may."customer"."merged_into_id" IS 'Hồ sơ khách đích sau khi gộp có phê duyệt; không xóa mất giao dịch của hồ sơ nguồn.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."customer"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T056 customer_contact: Thông tin liên hệ có bằng chứng xác minh
CREATE TABLE dien_may."customer_contact" (
    "contact_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "customer_id" uuid NOT NULL,
    "kind" varchar(40) NOT NULL,
    "normalized_value" text NOT NULL,
    "verified_at" timestamptz,
    "is_primary" boolean NOT NULL,
    CONSTRAINT "pk_customer_contact" PRIMARY KEY ("contact_id"),
    CONSTRAINT "ck_customer_contact_kind_domain" CHECK ("kind" IN ('PHONE', 'EMAIL'))
);
COMMENT ON TABLE dien_may."customer_contact" IS 'Thông tin liên hệ có bằng chứng xác minh.
Ràng buộc nghiệp vụ: Không UNIQUE điện thoại toàn bộ khách để tránh gộp sai người; tài khoản và liên hệ đăng nhập có quy tắc duy nhất riêng tại user_account.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."customer_contact"."contact_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."customer_contact"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."customer_contact"."kind" IS 'Phân loại đối tượng, quyết định các trường và quy tắc bắt buộc tương ứng.';
COMMENT ON COLUMN dien_may."customer_contact"."normalized_value" IS 'Điện thoại hoặc email đã chuẩn hóa; không UNIQUE toàn bộ khách để tránh tự gộp sai người.';
COMMENT ON COLUMN dien_may."customer_contact"."verified_at" IS 'Thời điểm thông tin hoặc kết quả được xác minh; NULL nghĩa chưa được xác minh.';
COMMENT ON COLUMN dien_may."customer_contact"."is_primary" IS 'Đánh dấu liên hệ ưu tiên; chỉ một liên hệ ưu tiên hiệu lực trong phạm vi được cấu hình.';

-- T057 customer_address: Sổ địa chỉ hiện hành của khách
CREATE TABLE dien_may."customer_address" (
    "address_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "customer_id" uuid NOT NULL,
    "recipient_name" varchar(255) NOT NULL,
    "phone" text NOT NULL,
    "address_value" jsonb NOT NULL,
    "is_default" boolean NOT NULL,
    CONSTRAINT "pk_customer_address" PRIMARY KEY ("address_id")
);
COMMENT ON TABLE dien_may."customer_address" IS 'Sổ địa chỉ hiện hành của khách.
Ràng buộc nghiệp vụ: Đơn giữ bản chụp; sửa địa chỉ này không sửa đơn cũ.
Cấu trúc address_value: recipient_name, phone, address_line, area_code, delivery_note của địa chỉ hiện hành; đơn bán giữ snapshot độc lập.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."customer_address"."address_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."customer_address"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."customer_address"."recipient_name" IS 'Tên người được phép nhận hàng hoặc nhận liên hệ tại địa chỉ.';
COMMENT ON COLUMN dien_may."customer_address"."phone" IS 'Điện thoại liên hệ đã chuẩn hóa; không dùng riêng trường này để nhận sở hữu đơn.';
COMMENT ON COLUMN dien_may."customer_address"."address_value" IS 'Địa chỉ hiện hành của khách, gồm vùng, dòng địa chỉ và chỉ dẫn giao nếu có.';
COMMENT ON COLUMN dien_may."customer_address"."is_default" IS 'Đánh dấu địa chỉ ưu tiên; không tự sửa địa chỉ đã chụp trên đơn.';

-- T058 customer_consent: Lịch sử đồng ý hoặc rút đồng ý theo mục đích
CREATE TABLE dien_may."customer_consent" (
    "consent_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "customer_id" uuid NOT NULL,
    "policy_version_id" uuid NOT NULL,
    "purpose" varchar(100) NOT NULL,
    "decision" varchar(40) NOT NULL,
    "recorded_at" timestamptz NOT NULL,
    "evidence_file_id" uuid,
    CONSTRAINT "pk_customer_consent" PRIMARY KEY ("consent_id"),
    CONSTRAINT "ck_customer_consent_decision_domain" CHECK ("decision" IN ('GRANT', 'WITHDRAW'))
);
COMMENT ON TABLE dien_may."customer_consent" IS 'Lịch sử đồng ý hoặc rút đồng ý theo mục đích.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."customer_consent"."consent_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."customer_consent"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."customer_consent"."policy_version_id" IS 'Liên kết nội dung chính sách đã duyệt có phiên bản.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."customer_consent"."purpose" IS 'Mục đích xử lý dữ liệu hoặc tiếp thị mà khách đồng ý hoặc rút đồng ý; ghi riêng từng mục đích.';
COMMENT ON COLUMN dien_may."customer_consent"."decision" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."customer_consent"."recorded_at" IS 'Thời điểm hệ thống ghi nhận quyết định đồng ý hoặc rút đồng ý của khách.';
COMMENT ON COLUMN dien_may."customer_consent"."evidence_file_id" IS 'Tệp chứng cứ được kiểm quyền và thời hạn lưu giữ.
FK → file_asset.file_id.';

-- T059 cart: Giỏ của tài khoản hoặc phiên vãng lai, không giữ tồn
CREATE TABLE dien_may."cart" (
    "cart_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "customer_id" uuid,
    "guest_session_hash" text,
    "version" integer NOT NULL,
    "expires_at" timestamptz NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_cart" PRIMARY KEY ("cart_id"),
    CONSTRAINT "ck_cart_version_positive" CHECK ("version" > 0),
    CONSTRAINT "ck_cart_status_domain" CHECK ("status" IN ('ACTIVE', 'CONVERTED', 'EXPIRED')),
    CONSTRAINT "ck_cart_owner" CHECK (num_nonnulls(customer_id, guest_session_hash) >= 1)
);
COMMENT ON TABLE dien_may."cart" IS 'Giỏ của tài khoản hoặc phiên vãng lai, không giữ tồn.
Ràng buộc nghiệp vụ: Có customer hoặc session đã xác định; hợp nhất giỏ cần kiểm giá/tồn lại.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."cart"."cart_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."cart"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."cart"."guest_session_hash" IS 'Dấu băm định danh phiên vãng lai để truy cập đúng giỏ.';
COMMENT ON COLUMN dien_may."cart"."version" IS 'Phiên bản nội dung hiện thời dùng để đối chiếu khi gửi thay đổi.';
COMMENT ON COLUMN dien_may."cart"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';
COMMENT ON COLUMN dien_may."cart"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T060 cart_item: SKU và lượng mong muốn trong giỏ
CREATE TABLE dien_may."cart_item" (
    "cart_id" uuid NOT NULL,
    "sku_id" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "last_quote_snapshot" jsonb,
    CONSTRAINT "pk_cart_item" PRIMARY KEY ("cart_id", "sku_id"),
    CONSTRAINT "ck_cart_item_quantity_positive" CHECK ("quantity" > 0)
);
COMMENT ON TABLE dien_may."cart_item" IS 'SKU và lượng mong muốn trong giỏ.
Ràng buộc nghiệp vụ: Lượng > 0. Báo giá giỏ không là giá cam kết hoặc nguồn tồn.
Cấu trúc last_quote_snapshot: quoted_at, sku, quantity, unit_price, discounts, fees, total; chỉ là báo giá giỏ, chưa cam kết.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."cart_item"."cart_id" IS 'Liên kết giỏ của tài khoản hoặc phiên vãng lai, không giữ tồn.
FK → cart.cart_id.';
COMMENT ON COLUMN dien_may."cart_item"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."cart_item"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."cart_item"."last_quote_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';

-- T061 sales_order: Đơn thương mại, khác trạng thái tiền giao và lắp
CREATE TABLE dien_may."sales_order" (
    "document_id" uuid NOT NULL,
    "customer_id" uuid NOT NULL,
    "store_id" uuid NOT NULL,
    "fulfillment_warehouse_id" uuid NOT NULL,
    "replacement_for_order_id" uuid,
    "channel" varchar(40) NOT NULL,
    "delivery_mode" varchar(40) NOT NULL,
    "status" varchar(40) NOT NULL,
    "contact_snapshot" jsonb NOT NULL,
    "address_snapshot" jsonb,
    "terms_policy_version_id" uuid NOT NULL,
    "total_payable_snapshot" numeric(19,0) NOT NULL,
    "currency" varchar(100) NOT NULL DEFAULT 'VND',
    "confirmed_at" timestamptz,
    "completed_at" timestamptz,
    CONSTRAINT "pk_sales_order" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_sales_order_channel_domain" CHECK ("channel" IN ('ONLINE', 'COUNTER')),
    CONSTRAINT "ck_sales_order_delivery_mode_domain" CHECK ("delivery_mode" IN ('SHIP', 'PICKUP')),
    CONSTRAINT "ck_sales_order_status_domain" CHECK ("status" IN ('PENDING_CONFIRMATION', 'CONFIRMED', 'FULFILLING', 'COMPLETED', 'CANCELLED', 'EXPIRED', 'CLOSED_UNFULFILLED')),
    CONSTRAINT "ck_sales_order_total_payable_snapshot_nonnegative" CHECK ("total_payable_snapshot" >= 0),
    CONSTRAINT "ck_sales_order_not_self_replacement" CHECK (replacement_for_order_id IS NULL OR replacement_for_order_id <> document_id)
);
COMMENT ON TABLE dien_may."sales_order" IS 'Đơn thương mại, khác trạng thái tiền giao và lắp.
Ràng buộc nghiệp vụ: Kho được phép của cửa hàng; R1 một kho thực hiện. Giá/chính sách chụp bất biến sau xác nhận. Thay hàng khi trả đang mở hoặc đã trả tiền dùng đơn thay thế liên kết.
Cấu trúc contact_snapshot: name, phone, email và thông tin liên hệ tại mốc ghi nhận; không tự cập nhật từ hồ sơ hiện hành.
Cấu trúc address_snapshot: recipient_name, phone, address_line, area_code, delivery_note; chụp đúng lúc giao dịch.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."sales_order"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."sales_order"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."sales_order"."store_id" IS 'Liên kết cửa hàng hoặc điểm điều hành bán hàng.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."sales_order"."fulfillment_warehouse_id" IS 'Một kho thực hiện toàn đơn R1, phải được phép xuất cho store_id của đơn.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."sales_order"."replacement_for_order_id" IS 'Đơn cũ mà đơn hiện tại thay thế; không dùng để sửa hồi tố giá hoặc lượng của đơn cũ.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."sales_order"."channel" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."sales_order"."delivery_mode" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."sales_order"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."sales_order"."contact_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."sales_order"."address_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."sales_order"."terms_policy_version_id" IS 'Liên kết nội dung chính sách đã duyệt có phiên bản.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."sales_order"."total_payable_snapshot" IS 'Tổng tiền phải trả đã chụp trước điều chỉnh hậu mãi; bằng tổng giá trị thuần các dòng.';
COMMENT ON COLUMN dien_may."sales_order"."currency" IS 'Mã tiền tệ của khoản tiền; R1 chỉ dùng VND và phải khớp toàn giao dịch.
Mặc định: VND cho R1.';
COMMENT ON COLUMN dien_may."sales_order"."confirmed_at" IS 'Thời điểm xác nhận hợp lệ theo loại đối tượng.';
COMMENT ON COLUMN dien_may."sales_order"."completed_at" IS 'Thời điểm hoàn thành công việc hoặc đơn; NULL khi chưa đạt điều kiện hoàn thành.';

-- T062 sales_order_line: Dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng
CREATE TABLE dien_may."sales_order_line" (
    "line_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "sku_id" uuid,
    "service_id" uuid,
    "price_entry_id" uuid,
    "return_policy_version_id" uuid,
    "warranty_policy_version_id" uuid,
    "item_snapshot" jsonb NOT NULL,
    "quantity" integer NOT NULL,
    "unit_price_snapshot" numeric(19,0) NOT NULL,
    "tax_rate_snapshot" numeric(9,6) NOT NULL,
    "net_amount_snapshot" numeric(19,0) NOT NULL,
    "discount_total_snapshot" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_sales_order_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_sales_order_line_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_sales_order_line_unit_price_snapshot_nonnegative" CHECK ("unit_price_snapshot" >= 0),
    CONSTRAINT "ck_sales_order_line_net_amount_snapshot_nonnegative" CHECK ("net_amount_snapshot" >= 0),
    CONSTRAINT "ck_sales_order_line_discount_total_snapshot_nonnegative" CHECK ("discount_total_snapshot" >= 0),
    CONSTRAINT "ck_sales_order_line_item" CHECK (num_nonnulls(sku_id, service_id) = 1)
);
COMMENT ON TABLE dien_may."sales_order_line" IS 'Dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
Ràng buộc nghiệp vụ: Đúng một trong sku_id/service_id. Dòng dịch vụ cho phí giao/lắp/phát sinh; không sinh tồn. net_amount là giá trị sau giảm đã gồm thuế theo SRS; tổng các dòng phải bằng tổng đơn.
Cấu trúc item_snapshot: item_code, item_name, unit, variant_attributes và các thông số cần hiển thị trên chứng từ.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."sales_order_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."sku_id" IS 'SKU của dòng hàng; có giá trị thì service_id phải NULL.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."service_id" IS 'Dịch vụ hoặc phí của dòng; có giá trị thì sku_id phải NULL và không phát sinh tồn.
FK → service_definition.service_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."price_entry_id" IS 'Nguồn giá đã chọn nếu dùng bảng giá; tiền đã chụp trên dòng vẫn là căn cứ lịch sử.
FK → price_entry.price_entry_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."return_policy_version_id" IS 'Phiên bản chính sách đổi trả được chụp khi bán, đúng loại RETURN.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."warranty_policy_version_id" IS 'Phiên bản chính sách bảo hành được chụp khi bán, đúng loại WARRANTY.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."sales_order_line"."item_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."sales_order_line"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."sales_order_line"."unit_price_snapshot" IS 'Đơn giá được chấp nhận tại giao dịch, giữ nguyên sau khi khóa đơn.';
COMMENT ON COLUMN dien_may."sales_order_line"."tax_rate_snapshot" IS 'Tỷ lệ thuế chụp tại lúc bán, dùng cho chứng từ và đối chiếu lịch sử.';
COMMENT ON COLUMN dien_may."sales_order_line"."net_amount_snapshot" IS 'Giá trị dòng sau giảm đã gồm thuế; không cộng thuế lần hai.';
COMMENT ON COLUMN dien_may."sales_order_line"."discount_total_snapshot" IS 'Tổng giảm đã phân bổ đến dòng đơn; phải khớp tổng discount_allocation.';

-- T063 order_discount: Khoản giảm có nguồn luật hoặc phê duyệt xác định
CREATE TABLE dien_may."order_discount" (
    "discount_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "order_id" uuid NOT NULL,
    "promotion_version_id" uuid,
    "voucher_claim_id" uuid,
    "approval_request_id" uuid,
    "kind" varchar(40) NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    "calculation_snapshot" jsonb NOT NULL,
    CONSTRAINT "pk_order_discount" PRIMARY KEY ("discount_id"),
    CONSTRAINT "uq_order_discount_voucher_claim_id" UNIQUE ("voucher_claim_id"),
    CONSTRAINT "ck_order_discount_kind_domain" CHECK ("kind" IN ('LINE_PROMOTION', 'ORDER_VOUCHER', 'MANUAL')),
    CONSTRAINT "ck_order_discount_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_order_discount_source" CHECK ((kind = 'LINE_PROMOTION' AND promotion_version_id IS NOT NULL AND voucher_claim_id IS NULL) OR (kind = 'ORDER_VOUCHER' AND voucher_claim_id IS NOT NULL) OR (kind = 'MANUAL' AND approval_request_id IS NOT NULL AND voucher_claim_id IS NULL AND promotion_version_id IS NULL))
);
COMMENT ON TABLE dien_may."order_discount" IS 'Khoản giảm có nguồn luật hoặc phê duyệt xác định.
Ràng buộc nghiệp vụ: Nguồn bắt buộc theo kind; MANUAL không cộng voucher R1. Không ghi trùng khoản giảm vào tổng đơn và dòng.
Cấu trúc calculation_snapshot: basis_amount, rule_version, rate_or_amount, cap, rounding và kết quả tính giảm.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."order_discount"."discount_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."order_discount"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."order_discount"."promotion_version_id" IS 'Liên kết luật khuyến mại bất biến theo phiên bản.
FK → promotion_version.promotion_version_id.';
COMMENT ON COLUMN dien_may."order_discount"."voucher_claim_id" IS 'Liên kết một lượt giữ hoặc sử dụng voucher gắn đúng đơn.
FK → voucher_claim.claim_id.';
COMMENT ON COLUMN dien_may."order_discount"."approval_request_id" IS 'Liên kết đề nghị duyệt gắn phiên bản nội dung chứng từ cụ thể.
FK → approval_request.request_id.';
COMMENT ON COLUMN dien_may."order_discount"."kind" IS 'Phân loại đối tượng, quyết định các trường và quy tắc bắt buộc tương ứng.';
COMMENT ON COLUMN dien_may."order_discount"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';
COMMENT ON COLUMN dien_may."order_discount"."calculation_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';

-- T064 discount_allocation: Phân bổ giảm đến dòng để trả đúng giá lúc mua
CREATE TABLE dien_may."discount_allocation" (
    "discount_id" uuid NOT NULL,
    "order_line_id" uuid NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_discount_allocation" PRIMARY KEY ("discount_id", "order_line_id"),
    CONSTRAINT "ck_discount_allocation_amount_nonnegative" CHECK ("amount" >= 0)
);
COMMENT ON TABLE dien_may."discount_allocation" IS 'Phân bổ giảm đến dòng để trả đúng giá lúc mua.
Ràng buộc nghiệp vụ: Dòng phải cùng đơn; tổng phân bổ bằng amount khoản giảm và không vượt tiền dòng. Là nguồn chuẩn phần giảm phân bổ; trường discount_total ở dòng là snapshot đối chiếu.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."discount_allocation"."discount_id" IS 'Liên kết khoản giảm có nguồn luật hoặc phê duyệt xác định.
FK → order_discount.discount_id.';
COMMENT ON COLUMN dien_may."discount_allocation"."order_line_id" IS 'Liên kết dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."discount_allocation"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';

-- T065 order_status_history: Lịch sử trạng thái thương mại và nguyên nhân
CREATE TABLE dien_may."order_status_history" (
    "history_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "order_id" uuid NOT NULL,
    "actor_id" uuid,
    "from_status" varchar(40),
    "to_status" varchar(40) NOT NULL,
    "reason" varchar(500),
    "occurred_at" timestamptz NOT NULL,
    CONSTRAINT "pk_order_status_history" PRIMARY KEY ("history_id"),
    CONSTRAINT "ck_order_status_history_from_status_domain" CHECK ("from_status" IN ('PENDING_CONFIRMATION', 'CONFIRMED', 'FULFILLING', 'COMPLETED', 'CANCELLED', 'EXPIRED', 'CLOSED_UNFULFILLED')),
    CONSTRAINT "ck_order_status_history_to_status_domain" CHECK ("to_status" IN ('PENDING_CONFIRMATION', 'CONFIRMED', 'FULFILLING', 'COMPLETED', 'CANCELLED', 'EXPIRED', 'CLOSED_UNFULFILLED'))
);
COMMENT ON TABLE dien_may."order_status_history" IS 'Lịch sử trạng thái thương mại và nguyên nhân.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."order_status_history"."history_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."order_status_history"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."order_status_history"."actor_id" IS 'Tài khoản thực hiện thao tác; NULL cho sự kiện hệ thống được nhận diện trong audit.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."order_status_history"."from_status" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."order_status_history"."to_status" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."order_status_history"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';
COMMENT ON COLUMN dien_may."order_status_history"."occurred_at" IS 'Thời điểm sự kiện nghiệp vụ xảy ra, giữ để dựng đúng thứ tự xử lý.';

-- ============================================================================
-- M08 Xuất hàng giao nhận và lắp đặt
-- ============================================================================

-- T066 service_zone: Vùng phục vụ theo địa chỉ cấu hình
CREATE TABLE dien_may."service_zone" (
    "zone_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "coverage_snapshot" jsonb NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_service_zone" PRIMARY KEY ("zone_id"),
    CONSTRAINT "uq_service_zone_code" UNIQUE ("code"),
    CONSTRAINT "ck_service_zone_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."service_zone" IS 'Vùng phục vụ theo địa chỉ cấu hình.
Ràng buộc nghiệp vụ: Quy tắc ánh xạ địa chỉ được duyệt; không gán cứng danh mục hành chính trong mã.
Cấu trúc coverage_snapshot: Mã vùng và quy tắc đối chiếu địa chỉ đã được cấu hình; không chứa truy vấn thực thi tự do.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."service_zone"."zone_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."service_zone"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."service_zone"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."service_zone"."coverage_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."service_zone"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T067 service_rate: Biểu phí giao lắp có hiệu lực
CREATE TABLE dien_may."service_rate" (
    "rate_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "service_id" uuid NOT NULL,
    "zone_id" uuid NOT NULL,
    "category_id" uuid,
    "rule_snapshot" jsonb NOT NULL,
    "valid_from" timestamptz NOT NULL,
    "valid_to" timestamptz,
    CONSTRAINT "pk_service_rate" PRIMARY KEY ("rate_id"),
    CONSTRAINT "ck_service_rate_valid_range" CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE dien_may."service_rate" IS 'Biểu phí giao lắp có hiệu lực.
Ràng buộc nghiệp vụ: Đơn chụp tiền dịch vụ; thay biểu phí không sửa phí đã chốt.
Cấu trúc rule_snapshot: Đơn vị tính phí, mức/biên áp dụng, phụ phí, điều kiện vùng, ca và hiệu lực.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."service_rate"."rate_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."service_rate"."service_id" IS 'Liên kết dịch vụ thu phí giao lắp hoặc phát sinh được bán thành dòng đơn.
FK → service_definition.service_id.';
COMMENT ON COLUMN dien_may."service_rate"."zone_id" IS 'Liên kết vùng phục vụ theo địa chỉ cấu hình.
FK → service_zone.zone_id.';
COMMENT ON COLUMN dien_may."service_rate"."category_id" IS 'Liên kết nhóm hàng có cấu trúc phân cấp.
FK → category.category_id.';
COMMENT ON COLUMN dien_may."service_rate"."rule_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."service_rate"."valid_from" IS 'Thời điểm bắt đầu hiệu lực, được tính vào khoảng áp dụng.';
COMMENT ON COLUMN dien_may."service_rate"."valid_to" IS 'Thời điểm kết thúc hiệu lực, không được tính vào khoảng; NULL là chưa ấn định kết thúc.';

-- T068 service_slot: Ca năng lực cho loại công việc tại vùng và cửa hàng
CREATE TABLE dien_may."service_slot" (
    "slot_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "store_id" uuid NOT NULL,
    "zone_id" uuid NOT NULL,
    "service_kind" varchar(40) NOT NULL,
    "starts_at" timestamptz NOT NULL,
    "ends_at" timestamptz NOT NULL,
    "capacity_units" integer NOT NULL,
    "weight_capacity" numeric(24,6),
    "required_skill" varchar(100),
    "row_version" integer NOT NULL DEFAULT 1,
    CONSTRAINT "pk_service_slot" PRIMARY KEY ("slot_id"),
    CONSTRAINT "ck_service_slot_service_kind_domain" CHECK ("service_kind" IN ('DELIVERY', 'INSTALLATION', 'PICKUP')),
    CONSTRAINT "ck_service_slot_capacity_units_positive" CHECK ("capacity_units" > 0),
    CONSTRAINT "ck_service_slot_weight_capacity_nonnegative" CHECK ("weight_capacity" >= 0),
    CONSTRAINT "ck_service_slot_row_version_positive" CHECK ("row_version" > 0),
    CONSTRAINT "ck_service_slot_time" CHECK (ends_at > starts_at)
);
COMMENT ON TABLE dien_may."service_slot" IS 'Ca năng lực cho loại công việc tại vùng và cửa hàng.
Ràng buộc nghiệp vụ: Thời gian có múi giờ; ends > starts; kiểm cả số chỗ, tải trọng và kỹ năng.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."service_slot"."slot_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."service_slot"."store_id" IS 'Liên kết cửa hàng hoặc điểm điều hành bán hàng.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."service_slot"."zone_id" IS 'Liên kết vùng phục vụ theo địa chỉ cấu hình.
FK → service_zone.zone_id.';
COMMENT ON COLUMN dien_may."service_slot"."service_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."service_slot"."starts_at" IS 'Thời điểm bắt đầu ca dịch vụ theo múi giờ hiển thị.';
COMMENT ON COLUMN dien_may."service_slot"."ends_at" IS 'Thời điểm kết thúc ca; phải sau starts_at.';
COMMENT ON COLUMN dien_may."service_slot"."capacity_units" IS 'Số đơn vị năng lực tối đa của ca theo loại công việc được cấu hình.';
COMMENT ON COLUMN dien_may."service_slot"."weight_capacity" IS 'Tổng tải trọng tối đa của ca; NULL là không áp tiêu chí tải riêng, không bỏ kiểm số chỗ.';
COMMENT ON COLUMN dien_may."service_slot"."required_skill" IS 'Mã kỹ năng cần có để thực hiện công việc hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."service_slot"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';

-- T069 slot_reservation: Giữ năng lực ca cùng vòng đời giữ hàng
CREATE TABLE dien_may."slot_reservation" (
    "slot_reservation_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "slot_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "units" integer NOT NULL,
    "weight_units" numeric(24,6) NOT NULL,
    "state" varchar(40) NOT NULL,
    "expires_at" timestamptz,
    CONSTRAINT "pk_slot_reservation" PRIMARY KEY ("slot_reservation_id"),
    CONSTRAINT "ck_slot_reservation_units_positive" CHECK ("units" > 0),
    CONSTRAINT "ck_slot_reservation_weight_units_nonnegative" CHECK ("weight_units" >= 0),
    CONSTRAINT "ck_slot_reservation_state_domain" CHECK ("state" IN ('HELD', 'COMMITTED', 'CONSUMED', 'RELEASED'))
);
COMMENT ON TABLE dien_may."slot_reservation" IS 'Giữ năng lực ca cùng vòng đời giữ hàng.
Ràng buộc nghiệp vụ: Cấm vượt năng lực kể cả hai yêu cầu đồng thời. Đổi lịch giữ ca mới và nhả ca cũ nguyên tử; lịch cũ giữ để truy vết.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."slot_reservation"."slot_reservation_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."slot_reservation"."slot_id" IS 'Liên kết ca năng lực cho loại công việc tại vùng và cửa hàng.
FK → service_slot.slot_id.';
COMMENT ON COLUMN dien_may."slot_reservation"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."slot_reservation"."units" IS 'Số đơn vị năng lực mà đơn đang giữ hoặc sử dụng trong một ca.';
COMMENT ON COLUMN dien_may."slot_reservation"."weight_units" IS 'Phần tải trọng mà đơn đang chiếm trong ca, dùng cùng tiêu chí số chỗ.';
COMMENT ON COLUMN dien_may."slot_reservation"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."slot_reservation"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';

-- T070 dispatch: Phiếu xuất thực hiện đơn R1
CREATE TABLE dien_may."dispatch" (
    "document_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "warehouse_id" uuid NOT NULL,
    "status" varchar(40) NOT NULL,
    "posted_at" timestamptz,
    CONSTRAINT "pk_dispatch" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_dispatch_order_id" UNIQUE ("order_id"),
    CONSTRAINT "ck_dispatch_status_domain" CHECK ("status" IN ('DRAFT', 'POSTED', 'REVERSED'))
);
COMMENT ON TABLE dien_may."dispatch" IS 'Phiếu xuất thực hiện đơn R1.
Ràng buộc nghiệp vụ: R1 một phiếu xuất bán cho đơn; có thể sửa nháp nhưng chốt một lần. Thu hồi sau xuất dùng chứng từ trả, không tạo lại xuất trên cùng đơn; tái bán dùng đơn mới.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."dispatch"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."dispatch"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."dispatch"."warehouse_id" IS 'Liên kết kho thực hoặc kho ảo hàng đang chuyển.
FK → warehouse.warehouse_id.';
COMMENT ON COLUMN dien_may."dispatch"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."dispatch"."posted_at" IS 'Thời điểm chứng từ được ghi sổ chính thức; NULL khi chưa ghi sổ.';

-- T071 dispatch_line: Dòng xuất chỉ liên kết dòng hàng có SKU
CREATE TABLE dien_may."dispatch_line" (
    "line_id" uuid NOT NULL,
    "dispatch_id" uuid NOT NULL,
    "order_line_id" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "cost_amount_snapshot" numeric(24,6) NOT NULL,
    CONSTRAINT "pk_dispatch_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_dispatch_line_quantity_positive" CHECK ("quantity" > 0)
);
COMMENT ON TABLE dien_may."dispatch_line" IS 'Dòng xuất chỉ liên kết dòng hàng có SKU.
Ràng buộc nghiệp vụ: Order line cùng đơn, có SKU; số xuất bằng lượng cần thực hiện R1; máy và vị trí thực xuất từ stock_movement.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."dispatch_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."dispatch_line"."dispatch_id" IS 'Liên kết phiếu xuất thực hiện đơn r1.
FK → dispatch.document_id.';
COMMENT ON COLUMN dien_may."dispatch_line"."order_line_id" IS 'Liên kết dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."dispatch_line"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."dispatch_line"."cost_amount_snapshot" IS 'Tổng giá vốn của lượng hàng thực xuất, chụp từ các movement thuộc dòng xuất.';

-- T072 shipment: Hồ sơ giao hoặc nhận tại cửa hàng của đơn
CREATE TABLE dien_may."shipment" (
    "document_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "dispatch_id" uuid,
    "slot_reservation_id" uuid,
    "provider_reference" text,
    "status" varchar(40) NOT NULL,
    "delivered_at" timestamptz,
    CONSTRAINT "pk_shipment" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_shipment_order_id" UNIQUE ("order_id"),
    CONSTRAINT "uq_shipment_dispatch_id" UNIQUE ("dispatch_id"),
    CONSTRAINT "ck_shipment_status_domain" CHECK ("status" IN ('TO_SCHEDULE', 'SCHEDULED', 'DISPATCHED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED', 'RETURNED', 'READY_FOR_PICKUP', 'PICKED_UP'))
);
COMMENT ON TABLE dien_may."shipment" IS 'Hồ sơ giao hoặc nhận tại cửa hàng của đơn.
Ràng buộc nghiệp vụ: Một hồ sơ R1, nhiều lần thử; dispatch và ca phải cùng đơn. Nhận tại quầy vẫn có dấu vết xác minh và bàn giao.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."shipment"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."shipment"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."shipment"."dispatch_id" IS 'Liên kết phiếu xuất thực hiện đơn r1.
FK → dispatch.document_id.';
COMMENT ON COLUMN dien_may."shipment"."slot_reservation_id" IS 'Liên kết giữ năng lực ca cùng vòng đời giữ hàng.
FK → slot_reservation.slot_reservation_id.';
COMMENT ON COLUMN dien_may."shipment"."provider_reference" IS 'Mã tham chiếu do đối tác cấp, phục vụ tra cứu và đối soát.';
COMMENT ON COLUMN dien_may."shipment"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."shipment"."delivered_at" IS 'Thời điểm khách đã nhận đủ hàng hoặc lấy hàng hợp lệ.';

-- T073 shipment_item: Lượng bàn giao gắn dòng xuất
CREATE TABLE dien_may."shipment_item" (
    "shipment_id" uuid NOT NULL,
    "dispatch_line_id" uuid NOT NULL,
    "quantity" integer NOT NULL,
    CONSTRAINT "pk_shipment_item" PRIMARY KEY ("shipment_id", "dispatch_line_id"),
    CONSTRAINT "ck_shipment_item_quantity_positive" CHECK ("quantity" > 0)
);
COMMENT ON TABLE dien_may."shipment_item" IS 'Lượng bàn giao gắn dòng xuất.
Ràng buộc nghiệp vụ: Cùng đơn và phiếu xuất của shipment; không gắn một dòng xuất vào hồ sơ giao khác.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."shipment_item"."shipment_id" IS 'Liên kết hồ sơ giao hoặc nhận tại cửa hàng của đơn.
FK → shipment.document_id.';
COMMENT ON COLUMN dien_may."shipment_item"."dispatch_line_id" IS 'Dòng hàng thực xuất được đưa vào hồ sơ giao.
FK → dispatch_line.line_id.';
COMMENT ON COLUMN dien_may."shipment_item"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';

-- T074 delivery_attempt: Một lần thử giao, giữ nguyên lịch sử thất bại
CREATE TABLE dien_may."delivery_attempt" (
    "attempt_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "shipment_id" uuid NOT NULL,
    "attempt_no" integer NOT NULL,
    "started_at" timestamptz NOT NULL,
    "result" varchar(40) NOT NULL,
    "recipient_snapshot" jsonb,
    "verification_challenge_id" uuid,
    "reason" varchar(500),
    "completed_at" timestamptz,
    CONSTRAINT "pk_delivery_attempt" PRIMARY KEY ("attempt_id"),
    CONSTRAINT "uq_delivery_attempt_shipment_id_attempt_no" UNIQUE ("shipment_id", "attempt_no"),
    CONSTRAINT "ck_delivery_attempt_attempt_no_positive" CHECK ("attempt_no" > 0),
    CONSTRAINT "ck_delivery_attempt_result_domain" CHECK ("result" IN ('IN_PROGRESS', 'DELIVERED', 'FAILED', 'RECALLED'))
);
COMMENT ON TABLE dien_may."delivery_attempt" IS 'Một lần thử giao, giữ nguyên lịch sử thất bại.
Ràng buộc nghiệp vụ: Chứng cứ qua document_attachment của shipment, gắn attempt_id trong metadata đã kiểm schema; không lưu tiền thu như nguồn tiền chuẩn tại đây.
Cấu trúc recipient_snapshot: Tên người nhận, kết quả xác minh, thời điểm bàn giao; bằng chứng tệp lưu qua file_asset.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."delivery_attempt"."attempt_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."delivery_attempt"."shipment_id" IS 'Liên kết hồ sơ giao hoặc nhận tại cửa hàng của đơn.
FK → shipment.document_id.';
COMMENT ON COLUMN dien_may."delivery_attempt"."attempt_no" IS 'Số thứ tự lần thử trong cùng yêu cầu; lần thử mới không đồng nghĩa nghĩa vụ tiền mới.';
COMMENT ON COLUMN dien_may."delivery_attempt"."started_at" IS 'Thời điểm bắt đầu ca hoặc lần thử công việc.';
COMMENT ON COLUMN dien_may."delivery_attempt"."result" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."delivery_attempt"."recipient_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."delivery_attempt"."verification_challenge_id" IS 'Lần xác minh nhận hàng đúng mục đích và đúng đơn, không tái sử dụng OTP.
FK → verification_challenge.challenge_id.';
COMMENT ON COLUMN dien_may."delivery_attempt"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';
COMMENT ON COLUMN dien_may."delivery_attempt"."completed_at" IS 'Thời điểm hoàn thành công việc hoặc đơn; NULL khi chưa đạt điều kiện hoàn thành.';

-- T075 installation_job: Công việc lắp tổng cho đơn có yêu cầu lắp R1
CREATE TABLE dien_may."installation_job" (
    "document_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "slot_reservation_id" uuid,
    "status" varchar(40) NOT NULL,
    "acceptance_snapshot" jsonb,
    "accepted_at" timestamptz,
    CONSTRAINT "pk_installation_job" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_installation_job_order_id" UNIQUE ("order_id"),
    CONSTRAINT "ck_installation_job_status_domain" CHECK ("status" IN ('NOT_STARTED', 'SCHEDULED', 'IN_PROGRESS', 'ACCEPTED', 'REWORK_REQUIRED', 'CANCELLED'))
);
COMMENT ON TABLE dien_may."installation_job" IS 'Công việc lắp tổng cho đơn có yêu cầu lắp R1.
Cấu trúc acceptance_snapshot: Người xác nhận, hạng mục đã kiểm, kết quả đạt/chưa đạt và thời điểm nghiệm thu.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."installation_job"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."installation_job"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."installation_job"."slot_reservation_id" IS 'Liên kết giữ năng lực ca cùng vòng đời giữ hàng.
FK → slot_reservation.slot_reservation_id.';
COMMENT ON COLUMN dien_may."installation_job"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."installation_job"."acceptance_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."installation_job"."accepted_at" IS 'Thời điểm khách nghiệm thu kết quả lắp đặt đạt.';

-- T076 installation_item: Checklist lắp trên từng dòng thiết bị
CREATE TABLE dien_may."installation_item" (
    "installation_id" uuid NOT NULL,
    "order_line_id" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "checklist_snapshot" jsonb NOT NULL,
    "result" varchar(40) NOT NULL,
    CONSTRAINT "pk_installation_item" PRIMARY KEY ("installation_id", "order_line_id"),
    CONSTRAINT "ck_installation_item_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_installation_item_result_domain" CHECK ("result" IN ('PENDING', 'PASS', 'FAIL'))
);
COMMENT ON TABLE dien_may."installation_item" IS 'Checklist lắp trên từng dòng thiết bị.
Ràng buộc nghiệp vụ: Dòng cùng đơn và yêu cầu lắp; nếu cần máy cụ thể, checklist phải tham chiếu danh sách serial đã giao qua dispatch/movement.
Cấu trúc checklist_snapshot: Danh sách hạng mục, giá trị đo/kết quả và serial đã giao được đối chiếu với dòng xuất.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."installation_item"."installation_id" IS 'Liên kết công việc lắp tổng cho đơn có yêu cầu lắp r1.
FK → installation_job.document_id.';
COMMENT ON COLUMN dien_may."installation_item"."order_line_id" IS 'Liên kết dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."installation_item"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."installation_item"."checklist_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."installation_item"."result" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';

-- T077 employee_skill: Kỹ năng có hiệu lực của nhân viên giao lắp
CREATE TABLE dien_may."employee_skill" (
    "employee_id" uuid NOT NULL,
    "skill_code" varchar(100) NOT NULL,
    "valid_until" date,
    CONSTRAINT "pk_employee_skill" PRIMARY KEY ("employee_id", "skill_code")
);
COMMENT ON TABLE dien_may."employee_skill" IS 'Kỹ năng có hiệu lực của nhân viên giao lắp.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."employee_skill"."employee_id" IS 'Liên kết nhân sự vận hành và phạm vi cửa hàng chính.
FK → employee.employee_id.';
COMMENT ON COLUMN dien_may."employee_skill"."skill_code" IS 'Mã kỹ năng nhân viên được xác nhận có thể thực hiện; là một phần khóa ghép cùng employee_id.';
COMMENT ON COLUMN dien_may."employee_skill"."valid_until" IS 'Ngày hết hiệu lực kỹ năng nhân viên; NULL nếu chưa quy định mốc hết hiệu lực.';

-- T078 work_assignment: Phân công nhân viên cho giao hoặc lắp
CREATE TABLE dien_may."work_assignment" (
    "assignment_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "employee_id" uuid NOT NULL,
    "shipment_id" uuid,
    "installation_id" uuid,
    "assigned_by" uuid NOT NULL,
    "state" varchar(40) NOT NULL,
    "assigned_at" timestamptz NOT NULL,
    CONSTRAINT "pk_work_assignment" PRIMARY KEY ("assignment_id"),
    CONSTRAINT "ck_work_assignment_state_domain" CHECK ("state" IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS', 'DONE', 'CANCELLED')),
    CONSTRAINT "ck_work_assignment_target" CHECK (num_nonnulls(shipment_id, installation_id) = 1)
);
COMMENT ON TABLE dien_may."work_assignment" IS 'Phân công nhân viên cho giao hoặc lắp.
Ràng buộc nghiệp vụ: XOR shipment/installation. Cần kiểm kỹ năng, ca và khả năng trùng lịch; không cấp quyền xem mọi đơn chỉ vì có vai trò giao hàng.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."work_assignment"."assignment_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."work_assignment"."employee_id" IS 'Liên kết nhân sự vận hành và phạm vi cửa hàng chính.
FK → employee.employee_id.';
COMMENT ON COLUMN dien_may."work_assignment"."shipment_id" IS 'Liên kết hồ sơ giao hoặc nhận tại cửa hàng của đơn.
FK → shipment.document_id.';
COMMENT ON COLUMN dien_may."work_assignment"."installation_id" IS 'Liên kết công việc lắp tổng cho đơn có yêu cầu lắp r1.
FK → installation_job.document_id.';
COMMENT ON COLUMN dien_may."work_assignment"."assigned_by" IS 'Người phân công nhân viên thực hiện công việc.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."work_assignment"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."work_assignment"."assigned_at" IS 'Thời điểm phân công được ghi nhận cho nhân viên.';

-- ============================================================================
-- M09 Thu tiền COD đối soát và hóa đơn
-- ============================================================================

-- T079 payment_provider: Định danh đối tác tiền hoặc cấu hình quỹ nội bộ
CREATE TABLE dien_may."payment_provider" (
    "provider_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "kind" varchar(40) NOT NULL,
    "secret_ref" text,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_payment_provider" PRIMARY KEY ("provider_id"),
    CONSTRAINT "uq_payment_provider_code" UNIQUE ("code"),
    CONSTRAINT "ck_payment_provider_kind_domain" CHECK ("kind" IN ('GATEWAY', 'BANK', 'INTERNAL_CASH')),
    CONSTRAINT "ck_payment_provider_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);
COMMENT ON TABLE dien_may."payment_provider" IS 'Định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."payment_provider"."provider_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."payment_provider"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."payment_provider"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';
COMMENT ON COLUMN dien_may."payment_provider"."kind" IS 'Phân loại đối tượng, quyết định các trường và quy tắc bắt buộc tương ứng.';
COMMENT ON COLUMN dien_may."payment_provider"."secret_ref" IS 'Tham chiếu cấu hình bí mật trong kho quản lý secret, không lưu khóa truy cập rõ.';
COMMENT ON COLUMN dien_may."payment_provider"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T080 payment_attempt: Yêu cầu hoặc lần thử thu, không đồng nghĩa tiền đã nhận
CREATE TABLE dien_may."payment_attempt" (
    "attempt_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "order_id" uuid NOT NULL,
    "provider_id" uuid NOT NULL,
    "merchant_reference" varchar(255) NOT NULL,
    "requested_amount" numeric(19,0) NOT NULL,
    "currency" varchar(100) NOT NULL DEFAULT 'VND',
    "state" varchar(40) NOT NULL,
    "expires_at" timestamptz NOT NULL,
    "idempotency_key" varchar(255) NOT NULL,
    CONSTRAINT "pk_payment_attempt" PRIMARY KEY ("attempt_id"),
    CONSTRAINT "uq_payment_attempt_merchant_reference" UNIQUE ("merchant_reference"),
    CONSTRAINT "uq_payment_attempt_idempotency_key" UNIQUE ("idempotency_key"),
    CONSTRAINT "ck_payment_attempt_requested_amount_positive" CHECK ("requested_amount" > 0),
    CONSTRAINT "ck_payment_attempt_requested_amount_nonnegative" CHECK ("requested_amount" >= 0),
    CONSTRAINT "ck_payment_attempt_state_domain" CHECK ("state" IN ('CREATED', 'PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED', 'RECONCILE_REQUIRED'))
);
COMMENT ON TABLE dien_may."payment_attempt" IS 'Yêu cầu hoặc lần thử thu, không đồng nghĩa tiền đã nhận.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."payment_attempt"."attempt_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."payment_attempt"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."payment_attempt"."provider_id" IS 'Liên kết định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
FK → payment_provider.provider_id.';
COMMENT ON COLUMN dien_may."payment_attempt"."merchant_reference" IS 'Mã yêu cầu thanh toán do hệ thống tạo và gửi đối tác.';
COMMENT ON COLUMN dien_may."payment_attempt"."requested_amount" IS 'Số tiền yêu cầu đối tác thu trong một lần thử, chưa phải khoản thực thu.';
COMMENT ON COLUMN dien_may."payment_attempt"."currency" IS 'Mã tiền tệ của khoản tiền; R1 chỉ dùng VND và phải khớp toàn giao dịch.
Mặc định: VND cho R1.';
COMMENT ON COLUMN dien_may."payment_attempt"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."payment_attempt"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';
COMMENT ON COLUMN dien_may."payment_attempt"."idempotency_key" IS 'Khóa yêu cầu chống lặp; cùng khóa nhưng khác nội dung phải bị từ chối.';

-- T081 payment_event: Chứng cứ callback tra cứu hoặc xác nhận thủ công
CREATE TABLE dien_may."payment_event" (
    "payment_event_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "provider_id" uuid NOT NULL,
    "attempt_id" uuid,
    "receipt_id" uuid,
    "provider_event_key" varchar(255) NOT NULL,
    "payload_hash" text NOT NULL,
    "verification_result" varchar(40) NOT NULL,
    "payload_redacted" jsonb NOT NULL,
    "received_at" timestamptz NOT NULL,
    CONSTRAINT "pk_payment_event" PRIMARY KEY ("payment_event_id"),
    CONSTRAINT "uq_payment_event_provider_id_provider_event_key" UNIQUE ("provider_id", "provider_event_key"),
    CONSTRAINT "ck_payment_event_verification_result_domain" CHECK ("verification_result" IN ('VERIFIED', 'INVALID', 'REVIEW_REQUIRED'))
);
COMMENT ON TABLE dien_may."payment_event" IS 'Chứng cứ callback tra cứu hoặc xác nhận thủ công.
Ràng buộc nghiệp vụ: Thông báo sai xác thực không tạo receipt xác nhận. Nếu nhà cung cấp không có mã sự kiện, khóa suy ra theo hợp đồng và fingerprint; không dùng thứ tự đến làm chân lý.
Cấu trúc payload_redacted: Nội dung sự kiện sau khi che token, OTP, mật khẩu, bí mật đối tác và dữ liệu thẻ nhạy cảm.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."payment_event"."payment_event_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."payment_event"."provider_id" IS 'Liên kết định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
FK → payment_provider.provider_id.';
COMMENT ON COLUMN dien_may."payment_event"."attempt_id" IS 'Liên kết yêu cầu hoặc lần thử thu, không đồng nghĩa tiền đã nhận.
FK → payment_attempt.attempt_id.';
COMMENT ON COLUMN dien_may."payment_event"."receipt_id" IS 'Liên kết một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ.
FK → payment_receipt.receipt_id.';
COMMENT ON COLUMN dien_may."payment_event"."provider_event_key" IS 'Mã sự kiện phía đối tác hoặc khóa suy ra theo hợp đồng để chống xử lý callback lặp.';
COMMENT ON COLUMN dien_may."payment_event"."payload_hash" IS 'Dấu băm nội dung chuẩn hóa để kiểm thay đổi và đối chiếu sự kiện trùng.';
COMMENT ON COLUMN dien_may."payment_event"."verification_result" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."payment_event"."payload_redacted" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."payment_event"."received_at" IS 'Thời điểm hệ thống hoặc bộ phận tiếp nhận ghi nhận đã nhận thực tế.';

-- T082 payment_receipt: Một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ
CREATE TABLE dien_may."payment_receipt" (
    "receipt_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "provider_id" uuid NOT NULL,
    "attempt_id" uuid,
    "declared_order_id" uuid,
    "provider_transaction_id" varchar(255),
    "internal_receipt_no" varchar(100) NOT NULL,
    "method" varchar(40) NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    "currency" varchar(100) NOT NULL DEFAULT 'VND',
    "collector_employee_id" uuid,
    "confirmed_by" uuid,
    "confirmed_at" timestamptz NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_payment_receipt" PRIMARY KEY ("receipt_id"),
    CONSTRAINT "uq_payment_receipt_internal_receipt_no" UNIQUE ("internal_receipt_no"),
    CONSTRAINT "uq_payment_receipt_provider_id_provider_transaction_id" UNIQUE ("provider_id", "provider_transaction_id"),
    CONSTRAINT "ck_payment_receipt_method_domain" CHECK ("method" IN ('ONLINE', 'TRANSFER', 'CASH', 'COD')),
    CONSTRAINT "ck_payment_receipt_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_payment_receipt_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_payment_receipt_status_domain" CHECK ("status" IN ('CONFIRMED', 'FROZEN')),
    CONSTRAINT "ck_payment_receipt_cod_collector" CHECK (method <> 'COD' OR collector_employee_id IS NOT NULL)
);
COMMENT ON TABLE dien_may."payment_receipt" IS 'Một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ.
Ràng buộc nghiệp vụ: Hai mã tiền thật khác nhau đều được ghi. Tiền lệch chưa phân bổ vẫn tồn tại; allocated/overpaid lấy từ funding_slice, không sửa amount thu gốc. COD bắt buộc collector.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."payment_receipt"."receipt_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."payment_receipt"."provider_id" IS 'Liên kết định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
FK → payment_provider.provider_id.';
COMMENT ON COLUMN dien_may."payment_receipt"."attempt_id" IS 'Lần thử gắn với khoản thu nếu nhận diện được; không UNIQUE vì có thể có nhiều khoản thực thu.
FK → payment_attempt.attempt_id.';
COMMENT ON COLUMN dien_may."payment_receipt"."declared_order_id" IS 'Đơn mà bên nộp khai báo; không thay việc phân bổ tiền và không tự chứng minh đủ tiền đơn.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."payment_receipt"."provider_transaction_id" IS 'Mã của khoản thực thu phía đối tác; chỉ duy nhất trong cùng nhà cung cấp.';
COMMENT ON COLUMN dien_may."payment_receipt"."internal_receipt_no" IS 'Số biên nhận tiền nội bộ duy nhất, có cả khi giao dịch không có mã đối tác.';
COMMENT ON COLUMN dien_may."payment_receipt"."method" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."payment_receipt"."amount" IS 'Khoản tiền thật đã được xác minh nhận; bất biến, kể cả phần đang chưa phân bổ hoặc thu thừa.';
COMMENT ON COLUMN dien_may."payment_receipt"."currency" IS 'Mã tiền tệ của khoản tiền; R1 chỉ dùng VND và phải khớp toàn giao dịch.
Mặc định: VND cho R1.';
COMMENT ON COLUMN dien_may."payment_receipt"."collector_employee_id" IS 'Nhân viên thu tiền mặt/COD; bắt buộc với COD để theo dõi khoản còn phải nộp quỹ.
FK → employee.employee_id.';
COMMENT ON COLUMN dien_may."payment_receipt"."confirmed_by" IS 'Người xác nhận chứng từ thu thủ công; có thể NULL với kết quả đối tác đã xác thực.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."payment_receipt"."confirmed_at" IS 'Thời điểm xác nhận hợp lệ theo loại đối tượng.';
COMMENT ON COLUMN dien_may."payment_receipt"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T083 cash_remittance: Lần nhân viên nộp khoản tiền đã thu về quỹ
CREATE TABLE dien_may."cash_remittance" (
    "document_id" uuid NOT NULL,
    "collector_employee_id" uuid NOT NULL,
    "received_by" uuid NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    "received_at" timestamptz NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_cash_remittance" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_cash_remittance_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_cash_remittance_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_cash_remittance_status_domain" CHECK ("status" IN ('DRAFT', 'POSTED', 'CANCELLED'))
);
COMMENT ON TABLE dien_may."cash_remittance" IS 'Lần nhân viên nộp khoản tiền đã thu về quỹ.
Ràng buộc nghiệp vụ: Không tạo thêm payment_receipt khách; chỉ quyết toán công nợ người thu.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."cash_remittance"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."cash_remittance"."collector_employee_id" IS 'Liên kết nhân sự vận hành và phạm vi cửa hàng chính.
FK → employee.employee_id.';
COMMENT ON COLUMN dien_may."cash_remittance"."received_by" IS 'Người nhận tiền nộp quỹ và xác nhận chứng từ nộp.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."cash_remittance"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';
COMMENT ON COLUMN dien_may."cash_remittance"."received_at" IS 'Thời điểm hệ thống hoặc bộ phận tiếp nhận ghi nhận đã nhận thực tế.';
COMMENT ON COLUMN dien_may."cash_remittance"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T084 cash_remittance_allocation: Khoản thu COD nào đã được nộp bao nhiêu
CREATE TABLE dien_may."cash_remittance_allocation" (
    "remittance_id" uuid NOT NULL,
    "receipt_id" uuid NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_cash_remittance_allocation" PRIMARY KEY ("remittance_id", "receipt_id"),
    CONSTRAINT "ck_cash_remittance_allocation_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_cash_remittance_allocation_amount_nonnegative" CHECK ("amount" >= 0)
);
COMMENT ON TABLE dien_may."cash_remittance_allocation" IS 'Khoản thu COD nào đã được nộp bao nhiêu.
Ràng buộc nghiệp vụ: Receipt COD/cash thuộc đúng người nộp; tổng phân bổ bằng chứng từ nộp và không vượt phần chưa nộp của mỗi receipt.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."cash_remittance_allocation"."remittance_id" IS 'Liên kết lần nhân viên nộp khoản tiền đã thu về quỹ.
FK → cash_remittance.document_id.';
COMMENT ON COLUMN dien_may."cash_remittance_allocation"."receipt_id" IS 'Liên kết một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ.
FK → payment_receipt.receipt_id.';
COMMENT ON COLUMN dien_may."cash_remittance_allocation"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';

-- T085 reconciliation_batch: Kỳ hoặc tệp đối soát với nhà cung cấp
CREATE TABLE dien_may."reconciliation_batch" (
    "batch_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "provider_id" uuid NOT NULL,
    "source_file_id" uuid,
    "source_digest" text NOT NULL,
    "period_from" timestamptz NOT NULL,
    "period_to" timestamptz NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_reconciliation_batch" PRIMARY KEY ("batch_id"),
    CONSTRAINT "uq_reconciliation_batch_provider_id_source_digest" UNIQUE ("provider_id", "source_digest"),
    CONSTRAINT "ck_reconciliation_batch_status_domain" CHECK ("status" IN ('IMPORTED', 'MATCHING', 'REVIEW_REQUIRED', 'CLOSED')),
    CONSTRAINT "ck_reconciliation_batch_period" CHECK (period_to > period_from)
);
COMMENT ON TABLE dien_may."reconciliation_batch" IS 'Kỳ hoặc tệp đối soát với nhà cung cấp.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."batch_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."provider_id" IS 'Liên kết định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
FK → payment_provider.provider_id.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."source_file_id" IS 'Tệp dữ liệu đối tác dùng làm nguồn đối soát, đã kiểm checksum.
FK → file_asset.file_id.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."source_digest" IS 'Dấu băm nguồn tệp hoặc dữ liệu đối tác để tránh nhập lặp cùng nguồn.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."period_from" IS 'Thời điểm bắt đầu khoảng đối soát.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."period_to" IS 'Thời điểm kết thúc khoảng đối soát, quy ước biên thời gian theo hợp đồng.';
COMMENT ON COLUMN dien_may."reconciliation_batch"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';

-- T086 reconciliation_item: Một dòng đối soát thu hoặc hoàn
CREATE TABLE dien_may."reconciliation_item" (
    "item_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "batch_id" uuid NOT NULL,
    "receipt_id" uuid,
    "refund_attempt_id" uuid,
    "provider_reference" varchar(255) NOT NULL,
    "gross_amount" numeric(19,0) NOT NULL,
    "fee_amount" numeric(19,0) NOT NULL,
    "net_amount" numeric(19,0) NOT NULL,
    "result" varchar(40) NOT NULL,
    "resolution_note" varchar(500),
    "resolved_by" uuid,
    CONSTRAINT "pk_reconciliation_item" PRIMARY KEY ("item_id"),
    CONSTRAINT "ck_reconciliation_item_result_domain" CHECK ("result" IN ('UNMATCHED', 'MATCHED', 'MISSING_INTERNAL', 'MISSING_EXTERNAL', 'AMOUNT_MISMATCH', 'FEE_MISMATCH', 'RESOLVED')),
    CONSTRAINT "ck_reconciliation_item_match_target" CHECK (num_nonnulls(receipt_id, refund_attempt_id) <= 1)
);
COMMENT ON TABLE dien_may."reconciliation_item" IS 'Một dòng đối soát thu hoặc hoàn.
Ràng buộc nghiệp vụ: Tối đa một trong receipt/refund, có thể cả hai NULL nếu chưa khớp; đối soát không tự tạo khoản thu giả.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."reconciliation_item"."item_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."reconciliation_item"."batch_id" IS 'Liên kết kỳ hoặc tệp đối soát với nhà cung cấp.
FK → reconciliation_batch.batch_id.';
COMMENT ON COLUMN dien_may."reconciliation_item"."receipt_id" IS 'Liên kết một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ.
FK → payment_receipt.receipt_id.';
COMMENT ON COLUMN dien_may."reconciliation_item"."refund_attempt_id" IS 'Liên kết một lần gọi hoặc tra cứu việc hoàn.
FK → refund_attempt.attempt_id.';
COMMENT ON COLUMN dien_may."reconciliation_item"."provider_reference" IS 'Mã tham chiếu do đối tác cấp, phục vụ tra cứu và đối soát.';
COMMENT ON COLUMN dien_may."reconciliation_item"."gross_amount" IS 'Số tiền gộp của dòng đối soát trước khi trừ phí.';
COMMENT ON COLUMN dien_may."reconciliation_item"."fee_amount" IS 'Phí đối tác được ghi trong dòng đối soát, không phải khoản giảm doanh thu hàng tự động.';
COMMENT ON COLUMN dien_may."reconciliation_item"."net_amount" IS 'Giá trị thuần của dòng đối soát hoặc hóa đơn theo loại chứng từ.';
COMMENT ON COLUMN dien_may."reconciliation_item"."result" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."reconciliation_item"."resolution_note" IS 'Nội dung tra soát và cách xử lý sai lệch; không dùng để tự sửa khoản thu gốc.';
COMMENT ON COLUMN dien_may."reconciliation_item"."resolved_by" IS 'Người chịu trách nhiệm chốt cách xử lý dòng đối soát.
FK → user_account.user_id.';

-- T087 invoice: Yêu cầu hóa đơn và tham chiếu nhà cung cấp phát hành
CREATE TABLE dien_may."invoice" (
    "document_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "adjustment_of_id" uuid,
    "buyer_snapshot" jsonb NOT NULL,
    "provider_invoice_key" varchar(255),
    "request_key" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    "issued_at" timestamptz,
    CONSTRAINT "pk_invoice" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_invoice_provider_invoice_key" UNIQUE ("provider_invoice_key"),
    CONSTRAINT "uq_invoice_request_key" UNIQUE ("request_key"),
    CONSTRAINT "ck_invoice_status_domain" CHECK ("status" IN ('DRAFT', 'PENDING', 'ISSUED', 'FAILED', 'ADJUSTED')),
    CONSTRAINT "ck_invoice_not_self_adjustment" CHECK (adjustment_of_id IS NULL OR adjustment_of_id <> document_id)
);
COMMENT ON TABLE dien_may."invoice" IS 'Yêu cầu hóa đơn và tham chiếu nhà cung cấp phát hành.
Ràng buộc nghiệp vụ: Một đơn có thể có hóa đơn gốc và các chứng từ điều chỉnh; không ép quan hệ một một. Thời điểm phát hành theo OQ04, không tự suy từ completed_at.
Cấu trúc buyer_snapshot: Tên người mua/tổ chức, mã số thuế và địa chỉ hóa đơn tại lúc gửi phát hành.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."invoice"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."invoice"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."invoice"."adjustment_of_id" IS 'Hóa đơn gốc được chứng từ hiện tại điều chỉnh, không sửa nội dung đã phát hành.
FK → invoice.document_id.';
COMMENT ON COLUMN dien_may."invoice"."buyer_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."invoice"."provider_invoice_key" IS 'Mã hóa đơn do nhà cung cấp phát hành; chỉ có khi nhận được kết quả hợp lệ.';
COMMENT ON COLUMN dien_may."invoice"."request_key" IS 'Khóa nghiệp vụ chống gửi yêu cầu phát hành hóa đơn trùng.';
COMMENT ON COLUMN dien_may."invoice"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."invoice"."issued_at" IS 'Thời điểm hóa đơn được xác nhận phát hành thành công.';

-- T088 invoice_line: Nội dung dòng hóa đơn được chụp khi gửi
CREATE TABLE dien_may."invoice_line" (
    "line_id" uuid NOT NULL,
    "invoice_id" uuid NOT NULL,
    "order_line_id" uuid,
    "line_snapshot" jsonb NOT NULL,
    "quantity" integer NOT NULL,
    "net_amount" numeric(19,0) NOT NULL,
    "tax_amount" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_invoice_line" PRIMARY KEY ("line_id")
);
COMMENT ON TABLE dien_may."invoice_line" IS 'Nội dung dòng hóa đơn được chụp khi gửi.
Ràng buộc nghiệp vụ: Dòng điều chỉnh được phân loại và ký tiền theo hợp đồng hóa đơn; không sửa dòng hóa đơn đã phát hành.
Cấu trúc line_snapshot: Tên, đơn vị, loại điều chỉnh và thông tin dòng được gửi nhà cung cấp hóa đơn.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."invoice_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."invoice_line"."invoice_id" IS 'Liên kết yêu cầu hóa đơn và tham chiếu nhà cung cấp phát hành.
FK → invoice.document_id.';
COMMENT ON COLUMN dien_may."invoice_line"."order_line_id" IS 'Liên kết dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."invoice_line"."line_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."invoice_line"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."invoice_line"."net_amount" IS 'Giá trị thuần của dòng đối soát hoặc hóa đơn theo loại chứng từ.';
COMMENT ON COLUMN dien_may."invoice_line"."tax_amount" IS 'Tiền thuế được chụp trên dòng hóa đơn, tách khỏi tiền hàng theo định dạng đối tác.';

-- ============================================================================
-- M10 Phân bổ nguồn tiền hoàn và đổi hàng
-- ============================================================================

-- T089 funding_slice: Phần tiền truy nguyên đến một khoản thực thu, hỗ trợ chia và chuyển qua đổi hàng
CREATE TABLE dien_may."funding_slice" (
    "slice_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "receipt_id" uuid NOT NULL,
    "parent_slice_id" uuid,
    "order_line_id" uuid,
    "case_item_id" uuid,
    "amount" numeric(19,0) NOT NULL,
    "state" varchar(40) NOT NULL,
    "row_version" integer NOT NULL DEFAULT 1,
    CONSTRAINT "pk_funding_slice" PRIMARY KEY ("slice_id"),
    CONSTRAINT "ck_funding_slice_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_funding_slice_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_funding_slice_state_domain" CHECK ("state" IN ('UNAPPLIED', 'ASSIGNED', 'RETURN_CREDIT', 'CREDIT_HELD', 'REFUND_HELD', 'REFUNDED', 'SPLIT')),
    CONSTRAINT "ck_funding_slice_row_version_positive" CHECK ("row_version" > 0),
    CONSTRAINT "ck_funding_slice_not_self_parent" CHECK (parent_slice_id IS NULL OR parent_slice_id <> slice_id),
    CONSTRAINT "ck_funding_slice_state_target" CHECK ((state <> 'ASSIGNED' OR order_line_id IS NOT NULL) AND (state NOT IN ('RETURN_CREDIT','CREDIT_HELD') OR case_item_id IS NOT NULL) AND (state <> 'UNAPPLIED' OR order_line_id IS NULL))
);
COMMENT ON TABLE dien_may."funding_slice" IS 'Phần tiền truy nguyên đến một khoản thực thu, hỗ trợ chia và chuyển qua đổi hàng.
Ràng buộc nghiệp vụ: Mỗi receipt có đúng một nút gốc bằng receipt.amount. Nút chia giữ state SPLIT; tổng con trực tiếp bằng cha, cùng receipt và không có chu trình. Chỉ lá hoạt động mới được chiếm/hoàn/chuyển; ASSIGNED cần order_line, RETURN_CREDIT cần case_item; UNAPPLIED không gắn đơn. amount > 0 và bất biến. Xem chương phân tích tiền để hiểu trần toàn chuỗi.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."funding_slice"."slice_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."funding_slice"."receipt_id" IS 'Liên kết một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ.
FK → payment_receipt.receipt_id.';
COMMENT ON COLUMN dien_may."funding_slice"."parent_slice_id" IS 'Nút cha cùng receipt; NULL duy nhất tại nút gốc, không cho tạo chu trình.
FK → funding_slice.slice_id.';
COMMENT ON COLUMN dien_may."funding_slice"."order_line_id" IS 'Dòng được nguồn tiền này quyết toán hoặc truy nguyên; bắt buộc ở ASSIGNED, không có ở UNAPPLIED.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."funding_slice"."case_item_id" IS 'Dòng hậu mãi cho phép tạo tiền trả; bắt buộc với RETURN_CREDIT, giữ truy nguồn hàng trả.
FK → after_sales_case_item.line_id.';
COMMENT ON COLUMN dien_may."funding_slice"."amount" IS 'Phần giá trị tiền bất biến của nút; tổng con trực tiếp phải bằng cha khi chia.';
COMMENT ON COLUMN dien_may."funding_slice"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."funding_slice"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';

-- T090 order_adjustment: Chứng từ điều chỉnh nghĩa vụ phải thu, khác lệnh hoàn tiền
CREATE TABLE dien_may."order_adjustment" (
    "document_id" uuid NOT NULL,
    "order_id" uuid NOT NULL,
    "case_id" uuid,
    "cause_document_id" uuid NOT NULL,
    "kind" varchar(40) NOT NULL,
    "direction" varchar(40) NOT NULL,
    "reversal_of_id" uuid,
    "total_reduction" numeric(19,0) NOT NULL,
    "state" varchar(40) NOT NULL,
    "posted_at" timestamptz,
    CONSTRAINT "pk_order_adjustment" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_order_adjustment_reversal_of_id" UNIQUE ("reversal_of_id"),
    CONSTRAINT "ck_order_adjustment_kind_domain" CHECK ("kind" IN ('RETURN', 'CANCEL', 'RECALL')),
    CONSTRAINT "ck_order_adjustment_direction_domain" CHECK ("direction" IN ('REDUCE', 'RESTORE')),
    CONSTRAINT "ck_order_adjustment_total_reduction_nonnegative" CHECK ("total_reduction" >= 0),
    CONSTRAINT "ck_order_adjustment_state_domain" CHECK ("state" IN ('DRAFT', 'POSTED', 'CANCELLED')),
    CONSTRAINT "ck_order_adjustment_direction_source" CHECK ((direction = 'RESTORE') = (reversal_of_id IS NOT NULL)),
    CONSTRAINT "ck_order_adjustment_not_self_reversal" CHECK (reversal_of_id IS NULL OR reversal_of_id <> document_id)
);
COMMENT ON TABLE dien_may."order_adjustment" IS 'Chứng từ điều chỉnh nghĩa vụ phải thu, khác lệnh hoàn tiền.
Ràng buộc nghiệp vụ: Duyệt và ghi trước hoặc đồng thời giải phóng tiền đã phân bổ. REDUCE không có reversal_of; RESTORE tham chiếu một REDUCE đã POSTED cùng đơn, đảo toàn chứng từ một lần. Cả gốc và đảo giữ POSTED, tính có dấu REDUCE +1, RESTORE -1. Cấm đảo nếu chưa xử lý backing đã chuyển/hoàn; không xóa dấu tiền đã thực hiện.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."order_adjustment"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."order_adjustment"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."order_adjustment"."case_id" IS 'Liên kết hồ sơ hậu mãi thống nhất định danh, tách loại xử lý.
FK → after_sales_case.document_id.';
COMMENT ON COLUMN dien_may."order_adjustment"."cause_document_id" IS 'Đơn/hồ sơ phát sinh nghĩa vụ điều chỉnh hoặc hoàn, phải khớp lý do và các dòng tiền.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."order_adjustment"."kind" IS 'Phân loại đối tượng, quyết định các trường và quy tắc bắt buộc tương ứng.';
COMMENT ON COLUMN dien_may."order_adjustment"."direction" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."order_adjustment"."reversal_of_id" IS 'Chứng từ REDUCE gốc được RESTORE đảo toàn bộ một lần; cả hai vẫn giữ trạng thái POSTED.
FK → order_adjustment.document_id.';
COMMENT ON COLUMN dien_may."order_adjustment"."total_reduction" IS 'Tổng giảm nghĩa vụ của chứng từ trước áp dụng chiều REDUCE hoặc RESTORE.';
COMMENT ON COLUMN dien_may."order_adjustment"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."order_adjustment"."posted_at" IS 'Thời điểm chứng từ được ghi sổ chính thức; NULL khi chưa ghi sổ.';

-- T091 order_adjustment_line: Giảm nghĩa vụ từng dòng và phân biệt phí khấu trừ
CREATE TABLE dien_may."order_adjustment_line" (
    "line_id" uuid NOT NULL,
    "adjustment_id" uuid NOT NULL,
    "order_line_id" uuid NOT NULL,
    "case_resolution_id" uuid,
    "reversal_of_line_id" uuid,
    "quantity" integer NOT NULL,
    "gross_reduction_amount" numeric(19,0) NOT NULL,
    "retained_fee_amount" numeric(19,0) NOT NULL,
    "net_reduction_amount" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_order_adjustment_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "uq_order_adjustment_line_reversal_of_line_id" UNIQUE ("reversal_of_line_id"),
    CONSTRAINT "ck_order_adjustment_line_quantity_nonnegative" CHECK ("quantity" >= 0),
    CONSTRAINT "ck_order_adjustment_line_gross_reduction_amount_nonnegative" CHECK ("gross_reduction_amount" >= 0),
    CONSTRAINT "ck_order_adjustment_line_retained_fee_amount_nonnegative" CHECK ("retained_fee_amount" >= 0),
    CONSTRAINT "ck_order_adjustment_line_net_reduction_amount_nonnegative" CHECK ("net_reduction_amount" >= 0),
    CONSTRAINT "ck_order_adjustment_line_net_reduction" CHECK (net_reduction_amount = gross_reduction_amount - retained_fee_amount),
    CONSTRAINT "ck_order_adjustment_line_not_self_reversal" CHECK (reversal_of_line_id IS NULL OR reversal_of_line_id <> line_id)
);
COMMENT ON TABLE dien_may."order_adjustment_line" IS 'Giảm nghĩa vụ từng dòng và phân biệt phí khấu trừ.
Ràng buộc nghiệp vụ: Dòng cùng đơn; net_reduction = gross_reduction - retained_fee >= 0. RESTORE phải mirror đúng dòng gốc theo reversal_of_line; chiều tính theo header. Tổng giảm ròng hiệu lực không vượt nghĩa vụ dòng; lượng trả và tiền giảm kiểm độc lập. Phí khấu trừ có chính sách/duyệt, báo cáo tách phí khỏi doanh thu hàng.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."adjustment_id" IS 'Liên kết chứng từ điều chỉnh nghĩa vụ phải thu, khác lệnh hoàn tiền.
FK → order_adjustment.document_id.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."order_line_id" IS 'Liên kết dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."case_resolution_id" IS 'Phiên bản quyết định hậu mãi làm căn cứ điều chỉnh dòng tiền phải thu.
FK → case_resolution.resolution_id.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."reversal_of_line_id" IS 'Dòng gốc được dòng đảo mirror đúng số lượng và các khoản tiền, theo chứng từ đảo.
FK → order_adjustment_line.line_id.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."gross_reduction_amount" IS 'Giá trị nghĩa vụ được giảm trước phí khấu trừ của dòng trả hoặc hủy.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."retained_fee_amount" IS 'Phí được giữ lại có chính sách và phê duyệt; báo cáo tách khỏi doanh thu hàng.';
COMMENT ON COLUMN dien_may."order_adjustment_line"."net_reduction_amount" IS 'Giảm ròng bằng gross_reduction_amount trừ retained_fee_amount.';

-- T092 funding_slice_event: Nhật ký chuyển trạng thái và chia nguồn tiền bất biến
CREATE TABLE dien_may."funding_slice_event" (
    "event_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "slice_id" uuid NOT NULL,
    "source_document_id" uuid NOT NULL,
    "actor_id" uuid,
    "from_state" varchar(40),
    "to_state" varchar(40) NOT NULL,
    "occurred_at" timestamptz NOT NULL,
    "operation_key" varchar(255) NOT NULL,
    CONSTRAINT "pk_funding_slice_event" PRIMARY KEY ("event_id"),
    CONSTRAINT "uq_funding_slice_event_operation_key" UNIQUE ("operation_key"),
    CONSTRAINT "ck_funding_slice_event_from_state_domain" CHECK ("from_state" IN ('UNAPPLIED', 'ASSIGNED', 'RETURN_CREDIT', 'CREDIT_HELD', 'REFUND_HELD', 'REFUNDED', 'SPLIT')),
    CONSTRAINT "ck_funding_slice_event_to_state_domain" CHECK ("to_state" IN ('UNAPPLIED', 'ASSIGNED', 'RETURN_CREDIT', 'CREDIT_HELD', 'REFUND_HELD', 'REFUNDED', 'SPLIT'))
);
COMMENT ON TABLE dien_may."funding_slice_event" IS 'Nhật ký chuyển trạng thái và chia nguồn tiền bất biến.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."funding_slice_event"."event_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."funding_slice_event"."slice_id" IS 'Liên kết phần tiền truy nguyên đến một khoản thực thu, hỗ trợ chia và chuyển qua đổi hàng.
FK → funding_slice.slice_id.';
COMMENT ON COLUMN dien_may."funding_slice_event"."source_document_id" IS 'Chứng từ nguồn giải thích vì sao phát sinh sổ hoặc sự kiện.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."funding_slice_event"."actor_id" IS 'Tài khoản thực hiện thao tác; NULL cho sự kiện hệ thống được nhận diện trong audit.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."funding_slice_event"."from_state" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."funding_slice_event"."to_state" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."funding_slice_event"."occurred_at" IS 'Thời điểm sự kiện nghiệp vụ xảy ra, giữ để dựng đúng thứ tự xử lý.';
COMMENT ON COLUMN dien_may."funding_slice_event"."operation_key" IS 'Khóa nghiệp vụ của thao tác để chống ghi nhận cùng hiệu ứng nhiều lần.';

-- T093 refund_request: Nghĩa vụ hoàn có phê duyệt cho một khoản thu gốc
CREATE TABLE dien_may."refund_request" (
    "document_id" uuid NOT NULL,
    "receipt_id" uuid NOT NULL,
    "provider_id" uuid NOT NULL,
    "cause_document_id" uuid NOT NULL,
    "case_id" uuid,
    "reason" varchar(40) NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    "currency" varchar(100) NOT NULL DEFAULT 'VND',
    "state" varchar(40) NOT NULL,
    "provider_refund_reference" varchar(255) NOT NULL,
    "provider_refund_id" varchar(100),
    CONSTRAINT "pk_refund_request" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_refund_request_provider_refund_reference" UNIQUE ("provider_refund_reference"),
    CONSTRAINT "uq_refund_request_provider_id_provider_refund_id" UNIQUE ("provider_id", "provider_refund_id"),
    CONSTRAINT "ck_refund_request_reason_domain" CHECK ("reason" IN ('RETURN', 'CANCEL', 'OVERPAYMENT', 'LATE_PAYMENT')),
    CONSTRAINT "ck_refund_request_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_refund_request_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_refund_request_state_domain" CHECK ("state" IN ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'PROCESSING', 'SUCCEEDED', 'FAILED', 'UNKNOWN', 'REJECTED', 'CANCELLED'))
);
COMMENT ON TABLE dien_may."refund_request" IS 'Nghĩa vụ hoàn có phê duyệt cho một khoản thu gốc.
Ràng buộc nghiệp vụ: Một hồ sơ có thể tạo nhiều yêu cầu nếu có nhiều receipt; mỗi yêu cầu chỉ một receipt. cause_document chỉ đúng hồ sơ/đơn phát sinh nghĩa vụ; case nếu có phải khớp. Tổng refund_slice bằng amount và phải được duyệt trước gửi. Mã hoàn thật duy nhất ở cấp request, không ở cấp cuộc gọi/tra cứu.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."refund_request"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."refund_request"."receipt_id" IS 'Liên kết một khoản thực thu đáng tin cậy, kể cả thu thừa hoặc chưa phân bổ.
FK → payment_receipt.receipt_id.';
COMMENT ON COLUMN dien_may."refund_request"."provider_id" IS 'Liên kết định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
FK → payment_provider.provider_id.';
COMMENT ON COLUMN dien_may."refund_request"."cause_document_id" IS 'Đơn/hồ sơ phát sinh nghĩa vụ điều chỉnh hoặc hoàn, phải khớp lý do và các dòng tiền.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."refund_request"."case_id" IS 'Liên kết hồ sơ hậu mãi thống nhất định danh, tách loại xử lý.
FK → after_sales_case.document_id.';
COMMENT ON COLUMN dien_may."refund_request"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';
COMMENT ON COLUMN dien_may."refund_request"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';
COMMENT ON COLUMN dien_may."refund_request"."currency" IS 'Mã tiền tệ của khoản tiền; R1 chỉ dùng VND và phải khớp toàn giao dịch.
Mặc định: VND cho R1.';
COMMENT ON COLUMN dien_may."refund_request"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."refund_request"."provider_refund_reference" IS 'Mã nghiệp vụ hoàn ổn định do hệ thống cấp, được giữ khi gọi hoặc tra cứu lại.';
COMMENT ON COLUMN dien_may."refund_request"."provider_refund_id" IS 'Mã khoản hoàn thật của đối tác; UNIQUE cùng provider_id ở cấp yêu cầu, không ở cấp log gọi.';

-- T094 refund_slice: Phần nguồn tiền lá bị khóa cho một yêu cầu hoàn
CREATE TABLE dien_may."refund_slice" (
    "refund_request_id" uuid NOT NULL,
    "slice_id" uuid NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    "state" varchar(40) NOT NULL,
    CONSTRAINT "pk_refund_slice" PRIMARY KEY ("refund_request_id", "slice_id"),
    CONSTRAINT "ck_refund_slice_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_refund_slice_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_refund_slice_state_domain" CHECK ("state" IN ('HELD', 'REFUNDED', 'RELEASED'))
);
COMMENT ON TABLE dien_may."refund_slice" IS 'Phần nguồn tiền lá bị khóa cho một yêu cầu hoàn.
Ràng buộc nghiệp vụ: Slice cùng receipt, là lá; amount bằng toàn lá, chia trước nếu hoàn ít hơn. Timeout giữ HELD; chỉ thất bại được xác minh mới RELEASED. Lịch sử các lần thất bại được giữ.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."refund_slice"."refund_request_id" IS 'Liên kết nghĩa vụ hoàn có phê duyệt cho một khoản thu gốc.
FK → refund_request.document_id.';
COMMENT ON COLUMN dien_may."refund_slice"."slice_id" IS 'Liên kết phần tiền truy nguyên đến một khoản thực thu, hỗ trợ chia và chuyển qua đổi hàng.
FK → funding_slice.slice_id.';
COMMENT ON COLUMN dien_may."refund_slice"."amount" IS 'Giá trị toàn bộ lá tiền bị giữ cho hoàn; muốn hoàn ít hơn phải chia lá trước.';
COMMENT ON COLUMN dien_may."refund_slice"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';

-- T095 refund_attempt: Một lần gọi hoặc tra cứu việc hoàn
CREATE TABLE dien_may."refund_attempt" (
    "attempt_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "refund_request_id" uuid NOT NULL,
    "attempt_no" integer NOT NULL,
    "provider_id" uuid NOT NULL,
    "idempotency_key" varchar(255) NOT NULL,
    "provider_refund_id" varchar(100),
    "state" varchar(40) NOT NULL,
    "requested_at" timestamptz NOT NULL,
    "verified_at" timestamptz,
    CONSTRAINT "pk_refund_attempt" PRIMARY KEY ("attempt_id"),
    CONSTRAINT "uq_refund_attempt_refund_request_id_attempt_no" UNIQUE ("refund_request_id", "attempt_no"),
    CONSTRAINT "ck_refund_attempt_attempt_no_positive" CHECK ("attempt_no" > 0),
    CONSTRAINT "ck_refund_attempt_state_domain" CHECK ("state" IN ('CREATED', 'PROCESSING', 'SUCCEEDED', 'FAILED', 'UNKNOWN'))
);
COMMENT ON TABLE dien_may."refund_attempt" IS 'Một lần gọi hoặc tra cứu việc hoàn.
Ràng buộc nghiệp vụ: Các attempt cùng request có thể lặp provider_refund_id của cùng khoản hoàn thật và phải khớp provider của request. Thử mạng lại dùng mã nghiệp vụ ổn định; UNKNOWN phải tra cứu trước lệnh tiền mới. Sự thành công chỉ tiêu thụ các lá đã khóa một lần.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."refund_attempt"."attempt_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."refund_attempt"."refund_request_id" IS 'Liên kết nghĩa vụ hoàn có phê duyệt cho một khoản thu gốc.
FK → refund_request.document_id.';
COMMENT ON COLUMN dien_may."refund_attempt"."attempt_no" IS 'Số thứ tự lần thử trong cùng yêu cầu; lần thử mới không đồng nghĩa nghĩa vụ tiền mới.';
COMMENT ON COLUMN dien_may."refund_attempt"."provider_id" IS 'Liên kết định danh đối tác tiền hoặc cấu hình quỹ nội bộ.
FK → payment_provider.provider_id.';
COMMENT ON COLUMN dien_may."refund_attempt"."idempotency_key" IS 'Khóa yêu cầu chống lặp; cùng khóa nhưng khác nội dung phải bị từ chối.';
COMMENT ON COLUMN dien_may."refund_attempt"."provider_refund_id" IS 'Mã khoản hoàn đối tác quan sát được; được phép lặp ở nhiều cuộc gọi cùng refund_request.';
COMMENT ON COLUMN dien_may."refund_attempt"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."refund_attempt"."requested_at" IS 'Thời điểm tạo đề nghị hoặc gửi yêu cầu xử lý.';
COMMENT ON COLUMN dien_may."refund_attempt"."verified_at" IS 'Thời điểm thông tin hoặc kết quả được xác minh; NULL nghĩa chưa được xác minh.';

-- T096 exchange_credit: Bù trừ có kiểm soát từ hồ sơ trả sang đơn đổi, không phải ví
CREATE TABLE dien_may."exchange_credit" (
    "document_id" uuid NOT NULL,
    "return_case_id" uuid NOT NULL,
    "target_order_id" uuid NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    "state" varchar(40) NOT NULL,
    CONSTRAINT "pk_exchange_credit" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_exchange_credit_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_exchange_credit_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_exchange_credit_state_domain" CHECK ("state" IN ('DRAFT', 'APPROVED', 'APPLIED', 'REVERSED'))
);
COMMENT ON TABLE dien_may."exchange_credit" IS 'Bù trừ có kiểm soát từ hồ sơ trả sang đơn đổi, không phải ví.
Ràng buộc nghiệp vụ: Đơn đích khác đơn nguồn; đúng người mua hoặc ủy quyền được duyệt. Tổng line bằng amount; tín dụng áp dụng tính là nguồn quyết toán, không là tiền thu mới.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."exchange_credit"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."exchange_credit"."return_case_id" IS 'Hồ sơ trả có phương án đổi được duyệt, cung cấp nguồn tín dụng cho đơn mới.
FK → after_sales_case.document_id.';
COMMENT ON COLUMN dien_may."exchange_credit"."target_order_id" IS 'Đơn mới nhận tín dụng, phải khác đơn nguồn và đúng người mua/ủy quyền hợp lệ.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."exchange_credit"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';
COMMENT ON COLUMN dien_may."exchange_credit"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';

-- T097 exchange_credit_line: Ghi dấu chuyển một phần nguồn tiền sang dòng đơn mới
CREATE TABLE dien_may."exchange_credit_line" (
    "line_id" uuid NOT NULL,
    "credit_id" uuid NOT NULL,
    "source_slice_id" uuid NOT NULL,
    "target_slice_id" uuid,
    "target_order_line_id" uuid NOT NULL,
    "amount" numeric(19,0) NOT NULL,
    CONSTRAINT "pk_exchange_credit_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "uq_exchange_credit_line_target_slice_id" UNIQUE ("target_slice_id"),
    CONSTRAINT "ck_exchange_credit_line_amount_positive" CHECK ("amount" > 0),
    CONSTRAINT "ck_exchange_credit_line_amount_nonnegative" CHECK ("amount" >= 0)
);
COMMENT ON TABLE dien_may."exchange_credit_line" IS 'Ghi dấu chuyển một phần nguồn tiền sang dòng đơn mới.
Ràng buộc nghiệp vụ: Chia nguồn đúng amount trước tạo đề nghị, khóa toàn lá source từ RETURN_CREDIT sang CREDIT_HELD khi tạo line; target NULL tới khi áp dụng. Source chuyển SPLIT khi áp dụng, target là con mới cùng receipt và ASSIGNED vào đúng đơn đích, amount bằng toàn lá nguồn. Hủy trước áp dụng trả source về RETURN_CREDIT. Một source chỉ một credit line hiệu lực; không hoàn hoặc chuyển tiếp lá đang khóa.
Kiểm soát ghi: Chỉ ghi qua dịch vụ tài chính với khóa chống lặp và kiểm trạng thái. Nội dung tiền đã xác nhận không sửa hồi tố; trạng thái và phần giữ được cập nhật theo chứng cứ.';
COMMENT ON COLUMN dien_may."exchange_credit_line"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."exchange_credit_line"."credit_id" IS 'Liên kết bù trừ có kiểm soát từ hồ sơ trả sang đơn đổi, không phải ví.
FK → exchange_credit.document_id.';
COMMENT ON COLUMN dien_may."exchange_credit_line"."source_slice_id" IS 'Lá RETURN_CREDIT được giữ toàn bộ sang CREDIT_HELD; chỉ một đề nghị hiệu lực được chiếm lá.
FK → funding_slice.slice_id.';
COMMENT ON COLUMN dien_may."exchange_credit_line"."target_slice_id" IS 'Lá con ASSIGNED vào đơn đổi sau áp dụng; NULL khi đề nghị mới đang giữ và chưa áp dụng.
FK → funding_slice.slice_id.';
COMMENT ON COLUMN dien_may."exchange_credit_line"."target_order_line_id" IS 'Dòng của đơn đổi được nhận nguồn quyết toán đã truy gốc.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."exchange_credit_line"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';

-- ============================================================================
-- M11 Đổi trả bảo hành và giữ hộ
-- ============================================================================

-- T098 after_sales_case: Hồ sơ hậu mãi thống nhất định danh, tách loại xử lý
CREATE TABLE dien_may."after_sales_case" (
    "document_id" uuid NOT NULL,
    "order_id" uuid,
    "customer_id" uuid NOT NULL,
    "case_kind" varchar(40) NOT NULL,
    "status" varchar(40) NOT NULL,
    "requested_at" timestamptz NOT NULL,
    "contact_snapshot" jsonb NOT NULL,
    "reason" varchar(500) NOT NULL,
    CONSTRAINT "pk_after_sales_case" PRIMARY KEY ("document_id"),
    CONSTRAINT "ck_after_sales_case_case_kind_domain" CHECK ("case_kind" IN ('RETURN', 'WARRANTY', 'RECALL')),
    CONSTRAINT "ck_after_sales_case_status_domain" CHECK ("status" IN ('OPEN', 'AWAITING_INTAKE', 'RECEIVED', 'INSPECTING', 'APPROVAL_PENDING', 'APPROVED', 'REJECTED', 'IN_PROGRESS', 'READY_FOR_RETURN', 'RETURNED', 'CLOSED', 'CANCELLED')),
    CONSTRAINT "ck_after_sales_case_order_required" CHECK (case_kind = 'WARRANTY' OR order_id IS NOT NULL)
);
COMMENT ON TABLE dien_may."after_sales_case" IS 'Hồ sơ hậu mãi thống nhất định danh, tách loại xử lý.
Ràng buộc nghiệp vụ: RETURN/RECALL cần đơn; WARRANTY ngoài hệ thống chỉ khi OQ05 cho phép. RECALL là thu hồi toàn đơn trước hoàn tất R1.
Cấu trúc contact_snapshot: name, phone, email và thông tin liên hệ tại mốc ghi nhận; không tự cập nhật từ hồ sơ hiện hành.
Kiểm soát ghi: Bản nháp được sửa theo quyền. Sau duyệt/chốt, trường ảnh hưởng tiền, tồn hoặc nghĩa vụ bị khóa; thay đổi theo nghiệp vụ phiên bản, đảo hoặc chứng từ liên kết.';
COMMENT ON COLUMN dien_may."after_sales_case"."document_id" IS 'Cùng ID với business_document; đây là khóa của header nghiệp vụ, không phát sinh ID thứ hai.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."after_sales_case"."order_id" IS 'Liên kết đơn thương mại, khác trạng thái tiền giao và lắp.
FK → sales_order.document_id.';
COMMENT ON COLUMN dien_may."after_sales_case"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."after_sales_case"."case_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."after_sales_case"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."after_sales_case"."requested_at" IS 'Thời điểm tạo đề nghị hoặc gửi yêu cầu xử lý.';
COMMENT ON COLUMN dien_may."after_sales_case"."contact_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."after_sales_case"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';

-- T099 after_sales_case_item: Hàng và lượng yêu cầu trong một hồ sơ
CREATE TABLE dien_may."after_sales_case_item" (
    "line_id" uuid NOT NULL,
    "case_id" uuid NOT NULL,
    "order_line_id" uuid,
    "device_id" uuid,
    "sku_id" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "policy_version_id" uuid,
    "received_at" timestamptz,
    "intake_snapshot" jsonb NOT NULL,
    CONSTRAINT "pk_after_sales_case_item" PRIMARY KEY ("line_id"),
    CONSTRAINT "ck_after_sales_case_item_quantity_positive" CHECK ("quantity" > 0),
    CONSTRAINT "ck_after_sales_case_item_serial_quantity" CHECK (device_id IS NULL OR quantity = 1)
);
COMMENT ON TABLE dien_may."after_sales_case_item" IS 'Hàng và lượng yêu cầu trong một hồ sơ.
Ràng buộc nghiệp vụ: Có serial thì quantity = 1 và device đúng SKU, đúng lịch sử xuất của order_line. RETURN phải có order_line cùng đơn; tổng lượng trả được duyệt/đang giữ không vượt đã giao còn được trả.
Cấu trúc intake_snapshot: Tình trạng ngoài, lỗi khai báo, phụ kiện đi kèm và kết quả tiếp nhận; tệp riêng theo quyền.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."line_id" IS 'Cùng ID với business_document_line; liên kết dòng nghiệp vụ với định danh dòng dùng chung.
FK → business_document_line.line_id.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."case_id" IS 'Liên kết hồ sơ hậu mãi thống nhất định danh, tách loại xử lý.
FK → after_sales_case.document_id.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."order_line_id" IS 'Liên kết dòng hàng hoặc phí dịch vụ có nghĩa vụ và tiền riêng.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."device_id" IS 'Liên kết một máy cụ thể, không gộp với sku hoặc dòng đơn.
FK → device.device_id.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."sku_id" IS 'Liên kết biến thể bán được theo màu dung lượng hoặc cấu hình.
FK → sku.sku_id.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."quantity" IS 'Số lượng đơn vị của dòng nghiệp vụ, diễn giải theo loại hàng hoặc dịch vụ.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."policy_version_id" IS 'Liên kết nội dung chính sách đã duyệt có phiên bản.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."received_at" IS 'Thời điểm hệ thống hoặc bộ phận tiếp nhận ghi nhận đã nhận thực tế.';
COMMENT ON COLUMN dien_may."after_sales_case_item"."intake_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';

-- T100 case_resolution: Kết quả kiểm định và phương án được duyệt cho từng dòng
CREATE TABLE dien_may."case_resolution" (
    "resolution_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "case_item_id" uuid NOT NULL,
    "decision_version" integer NOT NULL,
    "state" varchar(40) NOT NULL,
    "resolution_kind" varchar(40) NOT NULL,
    "inspection_snapshot" jsonb NOT NULL,
    "approved_amount" numeric(19,0) NOT NULL,
    "deduction_amount" numeric(19,0) NOT NULL,
    "approval_request_id" uuid,
    "decided_at" timestamptz,
    CONSTRAINT "pk_case_resolution" PRIMARY KEY ("resolution_id"),
    CONSTRAINT "uq_case_resolution_case_item_id_decision_version" UNIQUE ("case_item_id", "decision_version"),
    CONSTRAINT "ck_case_resolution_decision_version_positive" CHECK ("decision_version" > 0),
    CONSTRAINT "ck_case_resolution_state_domain" CHECK ("state" IN ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SUPERSEDED')),
    CONSTRAINT "ck_case_resolution_resolution_kind_domain" CHECK ("resolution_kind" IN ('REFUND', 'EXCHANGE', 'REPAIR', 'REJECT', 'RECALL')),
    CONSTRAINT "ck_case_resolution_approved_amount_nonnegative" CHECK ("approved_amount" >= 0),
    CONSTRAINT "ck_case_resolution_deduction_amount_nonnegative" CHECK ("deduction_amount" >= 0)
);
COMMENT ON TABLE dien_may."case_resolution" IS 'Kết quả kiểm định và phương án được duyệt cho từng dòng.
Ràng buộc nghiệp vụ: Bản nháp mới không thay bản duyệt hiện hành; chỉ đổi khi đã xử lý các nghĩa vụ phát sinh của bản trước và duyệt phiên bản mới. Tiền duyệt không tự là lệnh hoàn; nguồn chi là refund_request hoặc exchange_credit có truy vết.
Cấu trúc inspection_snapshot: Hạng mục kiểm, kết quả, nguyên nhân lỗi, mức đáp ứng chính sách và đề xuất xử lý.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."case_resolution"."resolution_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."case_resolution"."case_item_id" IS 'Liên kết hàng và lượng yêu cầu trong một hồ sơ.
FK → after_sales_case_item.line_id.';
COMMENT ON COLUMN dien_may."case_resolution"."decision_version" IS 'Số thứ tự phiên bản phương án xử lý một dòng hậu mãi.';
COMMENT ON COLUMN dien_may."case_resolution"."state" IS 'Trạng thái phiên bản quyết định; bản DRAFT mới không tự che phương án APPROVED hiện hành.';
COMMENT ON COLUMN dien_may."case_resolution"."resolution_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."case_resolution"."inspection_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."case_resolution"."approved_amount" IS 'Giá trị phương án được duyệt, chưa đồng nghĩa đã hoàn hoặc chuyển tín dụng.';
COMMENT ON COLUMN dien_may."case_resolution"."deduction_amount" IS 'Phần khấu trừ được duyệt theo tình trạng, chính sách và chứng cứ.';
COMMENT ON COLUMN dien_may."case_resolution"."approval_request_id" IS 'Liên kết đề nghị duyệt gắn phiên bản nội dung chứng từ cụ thể.
FK → approval_request.request_id.';
COMMENT ON COLUMN dien_may."case_resolution"."decided_at" IS 'Thời điểm quyết định xử lý được ghi nhận.';

-- T101 warranty_job: Công việc sửa cho thiết bị, có thể qua hãng hoặc nhiều lần sửa
CREATE TABLE dien_may."warranty_job" (
    "warranty_job_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "case_item_id" uuid NOT NULL,
    "assigned_employee_id" uuid,
    "service_supplier_id" uuid,
    "external_reference" text,
    "quote_order_line_id" uuid,
    "quote_approval_snapshot" jsonb,
    "status" varchar(40) NOT NULL,
    "expected_return_at" timestamptz,
    "result_snapshot" jsonb,
    CONSTRAINT "pk_warranty_job" PRIMARY KEY ("warranty_job_id"),
    CONSTRAINT "ck_warranty_job_status_domain" CHECK ("status" IN ('CREATED', 'DIAGNOSING', 'QUOTE_PENDING', 'CUSTOMER_APPROVAL_PENDING', 'IN_REPAIR', 'AT_PROVIDER', 'READY_TO_RETURN', 'RETURNED', 'CANCELLED'))
);
COMMENT ON TABLE dien_may."warranty_job" IS 'Công việc sửa cho thiết bị, có thể qua hãng hoặc nhiều lần sửa.
Ràng buộc nghiệp vụ: Phí sửa nếu có tạo dòng dịch vụ trên đơn thu phí liên kết; phải có chấp thuận trước sửa. Giữ máy theo device_event, không đưa vào tồn COMPANY.
Cấu trúc quote_approval_snapshot: Nội dung báo giá khách đã chấp thuận, người/thời điểm/kênh xác minh và tham chiếu chứng cứ.
Cấu trúc result_snapshot: Kết quả xử lý theo schema của nghiệp vụ; không chứa dữ liệu bí mật hoặc payload thô không kiểm.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."warranty_job"."warranty_job_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."warranty_job"."case_item_id" IS 'Liên kết hàng và lượng yêu cầu trong một hồ sơ.
FK → after_sales_case_item.line_id.';
COMMENT ON COLUMN dien_may."warranty_job"."assigned_employee_id" IS 'Nhân viên kỹ thuật được phân công sửa máy.
FK → employee.employee_id.';
COMMENT ON COLUMN dien_may."warranty_job"."service_supplier_id" IS 'Trung tâm hãng hoặc đối tác sửa chữa chịu trách nhiệm công việc.
FK → supplier.supplier_id.';
COMMENT ON COLUMN dien_may."warranty_job"."external_reference" IS 'Mã tiếp nhận hoặc chứng từ ở đơn vị bên ngoài.';
COMMENT ON COLUMN dien_may."warranty_job"."quote_order_line_id" IS 'Dòng dịch vụ của đơn thu phí sửa, chỉ được thực hiện sau khi khách chấp thuận.
FK → sales_order_line.line_id.';
COMMENT ON COLUMN dien_may."warranty_job"."quote_approval_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."warranty_job"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."warranty_job"."expected_return_at" IS 'Thời điểm dự kiến trả máy cho khách, dùng cảnh báo quá hẹn.';
COMMENT ON COLUMN dien_may."warranty_job"."result_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';

-- T102 case_event: Lịch sử trạng thái bàn giao giữ hộ và trả máy
CREATE TABLE dien_may."case_event" (
    "case_event_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "case_id" uuid NOT NULL,
    "case_item_id" uuid,
    "actor_id" uuid,
    "event_type" varchar(100) NOT NULL,
    "custodian_employee_id" uuid,
    "custodian_supplier_id" uuid,
    "evidence_file_id" uuid,
    "payload_snapshot" jsonb NOT NULL,
    "occurred_at" timestamptz NOT NULL,
    CONSTRAINT "pk_case_event" PRIMARY KEY ("case_event_id")
);
COMMENT ON TABLE dien_may."case_event" IS 'Lịch sử trạng thái bàn giao giữ hộ và trả máy.
Ràng buộc nghiệp vụ: Nếu có item thì phải thuộc case. Bàn giao ghi người giữ nhận và trả; thiết bị ngoài kho có device_event tương ứng. Từ chối sau nhận phải có bước trả lại khách.
Cấu trúc payload_snapshot: Nội dung sự kiện bàn giao/chuyển trạng thái đã được kiểm schema, có thời điểm và kết quả.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."case_event"."case_event_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."case_event"."case_id" IS 'Liên kết hồ sơ hậu mãi thống nhất định danh, tách loại xử lý.
FK → after_sales_case.document_id.';
COMMENT ON COLUMN dien_may."case_event"."case_item_id" IS 'Liên kết hàng và lượng yêu cầu trong một hồ sơ.
FK → after_sales_case_item.line_id.';
COMMENT ON COLUMN dien_may."case_event"."actor_id" IS 'Tài khoản thực hiện thao tác; NULL cho sự kiện hệ thống được nhận diện trong audit.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."case_event"."event_type" IS 'Mã loại sự kiện, dùng để chọn đúng cách xử lý và cấu trúc payload.';
COMMENT ON COLUMN dien_may."case_event"."custodian_employee_id" IS 'Nhân viên đang nhận trách nhiệm giữ hoặc bàn giao máy trong sự kiện.
FK → employee.employee_id.';
COMMENT ON COLUMN dien_may."case_event"."custodian_supplier_id" IS 'Đơn vị ngoài đang nhận trách nhiệm giữ máy trong sự kiện.
FK → supplier.supplier_id.';
COMMENT ON COLUMN dien_may."case_event"."evidence_file_id" IS 'Tệp chứng cứ được kiểm quyền và thời hạn lưu giữ.
FK → file_asset.file_id.';
COMMENT ON COLUMN dien_may."case_event"."payload_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."case_event"."occurred_at" IS 'Thời điểm sự kiện nghiệp vụ xảy ra, giữ để dựng đúng thứ tự xử lý.';

-- ============================================================================
-- M12 Chứng từ phê duyệt và vận hành
-- ============================================================================

-- T103 business_document: Định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ
CREATE TABLE dien_may."business_document" (
    "document_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "document_type" varchar(100) NOT NULL,
    "document_code" varchar(100) NOT NULL,
    "store_id" uuid,
    "created_by" uuid,
    "created_at" timestamptz NOT NULL,
    "business_at" timestamptz NOT NULL,
    "row_version" integer NOT NULL DEFAULT 1,
    CONSTRAINT "pk_business_document" PRIMARY KEY ("document_id"),
    CONSTRAINT "uq_business_document_document_type_document_code" UNIQUE ("document_type", "document_code"),
    CONSTRAINT "ck_business_document_row_version_positive" CHECK ("row_version" > 0)
);
COMMENT ON TABLE dien_may."business_document" IS 'Định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
Ràng buộc nghiệp vụ: Mỗi chứng từ có đúng một subtype cùng PK, đúng document_type. Status nằm ở subtype; không dùng document_type + target_id thay FK chứng từ cốt lõi. Tác vụ hệ thống được created_by NULL nhưng audit phải có actor_kind.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."business_document"."document_id" IS 'Định danh chứng từ dùng chung cho header subtype; mỗi chứng từ có đúng một subtype đúng loại.';
COMMENT ON COLUMN dien_may."business_document"."document_type" IS 'Mã loại chứng từ, dùng kiểm subtype được phép của document_id.';
COMMENT ON COLUMN dien_may."business_document"."document_code" IS 'Số chứng từ hiển thị, duy nhất trong phạm vi document_type.';
COMMENT ON COLUMN dien_may."business_document"."store_id" IS 'Liên kết cửa hàng hoặc điểm điều hành bán hàng.
FK → store.store_id.';
COMMENT ON COLUMN dien_may."business_document"."created_by" IS 'Tài khoản tạo chứng từ hoặc lô dữ liệu; NULL chỉ với tác vụ hệ thống có audit phù hợp.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."business_document"."created_at" IS 'Thời điểm hệ thống ghi nhận tạo bản ghi, không cho người dùng sửa lùi.';
COMMENT ON COLUMN dien_may."business_document"."business_at" IS 'Thời điểm nghiệp vụ được ghi nhận hiệu lực, không đồng nhất với thời điểm nhập hệ thống.';
COMMENT ON COLUMN dien_may."business_document"."row_version" IS 'Số phiên bản để phát hiện ghi bằng dữ liệu cũ; tăng khi thay đổi projection hoặc chứng từ.
Mặc định: 1 khi tạo; tăng nguyên tử khi ghi thay đổi.';

-- T104 business_document_line: Định danh dòng chứng từ cho tham chiếu sổ kho và tài chính
CREATE TABLE dien_may."business_document_line" (
    "line_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "document_id" uuid NOT NULL,
    "line_no" integer NOT NULL,
    CONSTRAINT "pk_business_document_line" PRIMARY KEY ("line_id"),
    CONSTRAINT "uq_business_document_line_document_id_line_no" UNIQUE ("document_id", "line_no"),
    CONSTRAINT "ck_business_document_line_line_no_positive" CHECK ("line_no" > 0)
);
COMMENT ON TABLE dien_may."business_document_line" IS 'Định danh dòng chứng từ cho tham chiếu sổ kho và tài chính.
Ràng buộc nghiệp vụ: Mỗi dòng có đúng một subtype đúng loại header; FK header trong bảng con phải trùng document_id ở đây. Chứng từ đã chốt không đổi line_no.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."business_document_line"."line_id" IS 'Định danh dòng dùng chung cho subtype dòng; phải thuộc đúng header và loại chứng từ.';
COMMENT ON COLUMN dien_may."business_document_line"."document_id" IS 'Liên kết định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."business_document_line"."line_no" IS 'Số thứ tự dòng trong một chứng từ, không đổi sau chốt.';

-- T105 policy: Nhận diện một chính sách nghiệp vụ
CREATE TABLE dien_may."policy" (
    "policy_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "policy_kind" varchar(40) NOT NULL,
    "name" varchar(255) NOT NULL,
    CONSTRAINT "pk_policy" PRIMARY KEY ("policy_id"),
    CONSTRAINT "uq_policy_code" UNIQUE ("code"),
    CONSTRAINT "ck_policy_policy_kind_domain" CHECK ("policy_kind" IN ('TERMS', 'RETURN', 'WARRANTY', 'APPROVAL', 'RETENTION'))
);
COMMENT ON TABLE dien_may."policy" IS 'Nhận diện một chính sách nghiệp vụ.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."policy"."policy_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."policy"."code" IS 'Mã nghiệp vụ ổn định dùng để tra cứu; chuẩn hóa trước khi kiểm duy nhất.';
COMMENT ON COLUMN dien_may."policy"."policy_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."policy"."name" IS 'Tên hiển thị của đối tượng trong giao diện và báo cáo.';

-- T106 policy_version: Nội dung chính sách đã duyệt có phiên bản
CREATE TABLE dien_may."policy_version" (
    "policy_version_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "policy_id" uuid NOT NULL,
    "version_no" integer NOT NULL,
    "schema_version" integer NOT NULL,
    "rules_snapshot" jsonb NOT NULL,
    "valid_from" timestamptz NOT NULL,
    "valid_to" timestamptz,
    "approved_by" uuid,
    "approved_at" timestamptz,
    CONSTRAINT "pk_policy_version" PRIMARY KEY ("policy_version_id"),
    CONSTRAINT "uq_policy_version_policy_id_version_no" UNIQUE ("policy_id", "version_no"),
    CONSTRAINT "ck_policy_version_version_no_positive" CHECK ("version_no" > 0),
    CONSTRAINT "ck_policy_version_schema_version_positive" CHECK ("schema_version" > 0),
    CONSTRAINT "ck_policy_version_valid_range" CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE dien_may."policy_version" IS 'Nội dung chính sách đã duyệt có phiên bản.
Ràng buộc nghiệp vụ: Không sửa phiên bản đã áp dụng. RETURN/WARRANTY trên dòng đơn phải đúng policy_kind; RETENTION chỉ theo thời hạn được doanh nghiệp duyệt.
Cấu trúc rules_snapshot: schema_version và tham số theo policy_kind: TERMS là điều kiện bán, RETURN là mốc/thời hạn/tình trạng/phí, WARRANTY là quyền lợi/loại trừ, APPROVAL là cấp/hạn mức, RETENTION là loại dữ liệu/thời hạn.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."policy_version"."policy_version_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."policy_version"."policy_id" IS 'Liên kết nhận diện một chính sách nghiệp vụ.
FK → policy.policy_id.';
COMMENT ON COLUMN dien_may."policy_version"."version_no" IS 'Số thứ tự phiên bản trong cùng đối tượng cha, không dùng lại phiên bản đã công bố.';
COMMENT ON COLUMN dien_may."policy_version"."schema_version" IS 'Phiên bản cấu trúc dữ liệu JSON hoặc thông điệp để chọn đúng bộ kiểm tra.';
COMMENT ON COLUMN dien_may."policy_version"."rules_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."policy_version"."valid_from" IS 'Thời điểm bắt đầu hiệu lực, được tính vào khoảng áp dụng.';
COMMENT ON COLUMN dien_may."policy_version"."valid_to" IS 'Thời điểm kết thúc hiệu lực, không được tính vào khoảng; NULL là chưa ấn định kết thúc.';
COMMENT ON COLUMN dien_may."policy_version"."approved_by" IS 'Người duyệt nội dung phiên bản chính sách.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."policy_version"."approved_at" IS 'Thời điểm người có thẩm quyền phê duyệt; không đồng nghĩa đã thực hiện giao dịch.';

-- T107 approval_request: Đề nghị duyệt gắn phiên bản nội dung chứng từ cụ thể
CREATE TABLE dien_may."approval_request" (
    "request_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "document_id" uuid NOT NULL,
    "policy_version_id" uuid NOT NULL,
    "requested_by" uuid NOT NULL,
    "action_code" varchar(100) NOT NULL,
    "document_version" integer NOT NULL,
    "payload_hash" text NOT NULL,
    "amount" numeric(19,0),
    "status" varchar(40) NOT NULL,
    "requested_at" timestamptz NOT NULL,
    CONSTRAINT "pk_approval_request" PRIMARY KEY ("request_id"),
    CONSTRAINT "ck_approval_request_document_version_positive" CHECK ("document_version" > 0),
    CONSTRAINT "ck_approval_request_amount_nonnegative" CHECK ("amount" >= 0),
    CONSTRAINT "ck_approval_request_status_domain" CHECK ("status" IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED', 'SUPERSEDED', 'CANCELLED'))
);
COMMENT ON TABLE dien_may."approval_request" IS 'Đề nghị duyệt gắn phiên bản nội dung chứng từ cụ thể.
Ràng buộc nghiệp vụ: Khi nội dung tiền/lượng thay đổi sau đề nghị phải hết hiệu lực kết quả duyệt cũ; kiểm quyền và hạn mức cả khi duyệt lẫn thực hiện.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."approval_request"."request_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."approval_request"."document_id" IS 'Liên kết định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."approval_request"."policy_version_id" IS 'Liên kết nội dung chính sách đã duyệt có phiên bản.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."approval_request"."requested_by" IS 'Người đề nghị duyệt; phải khác người duyệt thực tế.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."approval_request"."action_code" IS 'Hành động đang được đề nghị duyệt trên chứng từ.';
COMMENT ON COLUMN dien_may."approval_request"."document_version" IS 'Phiên bản nội dung chứng từ mà đề nghị duyệt đang ràng buộc.';
COMMENT ON COLUMN dien_may."approval_request"."payload_hash" IS 'Dấu băm nội dung chuẩn hóa để kiểm thay đổi và đối chiếu sự kiện trùng.';
COMMENT ON COLUMN dien_may."approval_request"."amount" IS 'Giá trị tiền của bản ghi, không suy ra trạng thái tiền đã thành công chỉ từ trường này.';
COMMENT ON COLUMN dien_may."approval_request"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."approval_request"."requested_at" IS 'Thời điểm tạo đề nghị hoặc gửi yêu cầu xử lý.';

-- T108 approval_decision: Quyết định một bước hoặc cấp duyệt, lưu người thực tế
CREATE TABLE dien_may."approval_decision" (
    "decision_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "request_id" uuid NOT NULL,
    "step_no" integer NOT NULL,
    "decided_by" uuid NOT NULL,
    "assignment_id" uuid NOT NULL,
    "decision" varchar(40) NOT NULL,
    "reason" varchar(500) NOT NULL,
    "decided_at" timestamptz NOT NULL,
    CONSTRAINT "pk_approval_decision" PRIMARY KEY ("decision_id"),
    CONSTRAINT "uq_approval_decision_request_id_step_no" UNIQUE ("request_id", "step_no"),
    CONSTRAINT "ck_approval_decision_step_no_positive" CHECK ("step_no" > 0),
    CONSTRAINT "ck_approval_decision_decision_domain" CHECK ("decision" IN ('APPROVE', 'REJECT'))
);
COMMENT ON TABLE dien_may."approval_decision" IS 'Quyết định một bước hoặc cấp duyệt, lưu người thực tế.
Ràng buộc nghiệp vụ: decided_by khác requested_by kể cả có nhiều vai trò; assignment phải là của người duyệt, còn hiệu lực và đủ phạm vi/hạn mức.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."approval_decision"."decision_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."approval_decision"."request_id" IS 'Liên kết đề nghị duyệt gắn phiên bản nội dung chứng từ cụ thể.
FK → approval_request.request_id.';
COMMENT ON COLUMN dien_may."approval_decision"."step_no" IS 'Số thứ tự cấp hoặc bước duyệt trong một đề nghị.';
COMMENT ON COLUMN dien_may."approval_decision"."decided_by" IS 'Người thực tế ghi quyết định, được kiểm quyền và hạn mức tại thời điểm duyệt.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."approval_decision"."assignment_id" IS 'Liên kết cấp vai trò cho người dùng trong thời gian và phạm vi.
FK → user_role_assignment.assignment_id.';
COMMENT ON COLUMN dien_may."approval_decision"."decision" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."approval_decision"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';
COMMENT ON COLUMN dien_may."approval_decision"."decided_at" IS 'Thời điểm quyết định xử lý được ghi nhận.';

-- T109 file_asset: Tệp được kiểm loại quyền truy cập và thời hạn
CREATE TABLE dien_may."file_asset" (
    "file_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "storage_key" text NOT NULL,
    "original_name" varchar(255) NOT NULL,
    "content_type" varchar(100) NOT NULL,
    "size_bytes" bigint NOT NULL,
    "checksum" text NOT NULL,
    "visibility" varchar(40) NOT NULL,
    "scan_status" varchar(40) NOT NULL,
    "retention_until" timestamptz,
    CONSTRAINT "pk_file_asset" PRIMARY KEY ("file_id"),
    CONSTRAINT "uq_file_asset_storage_key" UNIQUE ("storage_key"),
    CONSTRAINT "ck_file_asset_size_bytes_nonnegative" CHECK ("size_bytes" >= 0),
    CONSTRAINT "ck_file_asset_visibility_domain" CHECK ("visibility" IN ('PUBLIC_PRODUCT', 'PRIVATE_EVIDENCE')),
    CONSTRAINT "ck_file_asset_scan_status_domain" CHECK ("scan_status" IN ('PENDING', 'CLEAN', 'BLOCKED'))
);
COMMENT ON TABLE dien_may."file_asset" IS 'Tệp được kiểm loại quyền truy cập và thời hạn.
Ràng buộc nghiệp vụ: Không lưu URL ký tạm như địa chỉ bền vững; quyền truy cập lấy từ đối tượng sở hữu.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."file_asset"."file_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."file_asset"."storage_key" IS 'Khóa lưu tệp bền vững; không phải URL ký tạm hoặc đường dẫn công khai mặc định.';
COMMENT ON COLUMN dien_may."file_asset"."original_name" IS 'Tên tệp gốc dùng hiển thị, không dùng để xây đường dẫn lưu trữ tin cậy.';
COMMENT ON COLUMN dien_may."file_asset"."content_type" IS 'Loại nội dung tệp đã được kiểm tra từ dữ liệu thực.';
COMMENT ON COLUMN dien_may."file_asset"."size_bytes" IS 'Kích thước tệp theo byte; kiểm giới hạn trước và sau xử lý.';
COMMENT ON COLUMN dien_may."file_asset"."checksum" IS 'Dấu băm kiểm toàn vẹn tệp khi lưu, chuyển và tải lại.';
COMMENT ON COLUMN dien_may."file_asset"."visibility" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."file_asset"."scan_status" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."file_asset"."retention_until" IS 'Mốc lưu giữ của tệp theo chính sách đã duyệt; NULL chưa đồng nghĩa được xóa.';

-- T110 document_attachment: Liên kết tệp với chứng từ nghiệp vụ bằng FK thật
CREATE TABLE dien_may."document_attachment" (
    "attachment_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "document_id" uuid NOT NULL,
    "file_id" uuid NOT NULL,
    "purpose" varchar(100) NOT NULL,
    "context_snapshot" jsonb,
    "attached_by" uuid,
    CONSTRAINT "pk_document_attachment" PRIMARY KEY ("attachment_id")
);
COMMENT ON TABLE dien_may."document_attachment" IS 'Liên kết tệp với chứng từ nghiệp vụ bằng FK thật.
Ràng buộc nghiệp vụ: context chỉ bổ sung thứ tự/lần thử, không thay FK cốt lõi. Tệp nhạy cảm không tự trở thành công khai khi gắn vào chứng từ.
Cấu trúc context_snapshot: Ngữ cảnh bổ sung như lần giao hoặc thứ tự ảnh; không thay FK đối tượng sở hữu tệp.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."document_attachment"."attachment_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."document_attachment"."document_id" IS 'Liên kết định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."document_attachment"."file_id" IS 'Liên kết tệp được kiểm loại quyền truy cập và thời hạn.
FK → file_asset.file_id.';
COMMENT ON COLUMN dien_may."document_attachment"."purpose" IS 'Vai trò của tệp đối với chứng từ, ví dụ ảnh bàn giao, biên bản kiểm định hoặc chứng từ tiền.';
COMMENT ON COLUMN dien_may."document_attachment"."context_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."document_attachment"."attached_by" IS 'Người gắn tệp với chứng từ; quyền tệp kế thừa đối tượng nghiệp vụ.
FK → user_account.user_id.';

-- T111 audit_event: Nhật ký bất biến cho truy vết thay đổi và an ninh
CREATE TABLE dien_may."audit_event" (
    "audit_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "document_id" uuid,
    "actor_id" uuid,
    "actor_kind" varchar(40) NOT NULL,
    "target_kind" varchar(100) NOT NULL,
    "target_reference" text NOT NULL,
    "action" varchar(100) NOT NULL,
    "before_redacted" jsonb,
    "after_redacted" jsonb,
    "reason" varchar(500),
    "correlation_id" varchar(100) NOT NULL,
    "occurred_at" timestamptz NOT NULL,
    CONSTRAINT "pk_audit_event" PRIMARY KEY ("audit_id"),
    CONSTRAINT "ck_audit_event_actor_kind_domain" CHECK ("actor_kind" IN ('USER', 'SYSTEM', 'PROVIDER'))
);
COMMENT ON TABLE dien_may."audit_event" IS 'Nhật ký bất biến cho truy vết thay đổi và an ninh.
Ràng buộc nghiệp vụ: Target tổng quát chỉ dùng cho audit; chứng từ quan trọng vẫn có FK. Không chứa mật khẩu/OTP/token rõ.
Cấu trúc before_redacted: Dữ liệu trước thay đổi đã che thông tin không cần cho audit.
Cấu trúc after_redacted: Dữ liệu sau thay đổi đã che thông tin không cần cho audit.
Kiểm soát ghi: Nội dung bản ghi là lịch sử bất biến; không sửa hoặc xóa để che thao tác. Sai sót được giải thích bằng sự kiện/chứng từ đối ứng theo nghiệp vụ.';
COMMENT ON COLUMN dien_may."audit_event"."audit_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."audit_event"."document_id" IS 'Liên kết định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."audit_event"."actor_id" IS 'Tài khoản thực hiện thao tác; NULL cho sự kiện hệ thống được nhận diện trong audit.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."audit_event"."actor_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."audit_event"."target_kind" IS 'Loại đối tượng được audit; chỉ phục vụ nhật ký tổng quát.';
COMMENT ON COLUMN dien_may."audit_event"."target_reference" IS 'Mã tham chiếu phục vụ audit ngoài chứng từ';
COMMENT ON COLUMN dien_may."audit_event"."action" IS 'Mã hành động cụ thể, ví dụ xem, tạo, xác nhận, ghi sổ hoặc duyệt.';
COMMENT ON COLUMN dien_may."audit_event"."before_redacted" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."audit_event"."after_redacted" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."audit_event"."reason" IS 'Lý do thực hiện hoặc từ chối nghiệp vụ; bắt buộc khi hủy, điều chỉnh hoặc duyệt ngoại lệ.';
COMMENT ON COLUMN dien_may."audit_event"."correlation_id" IS 'Mã liên kết chuỗi yêu cầu, chứng từ và sự kiện để truy vết.';
COMMENT ON COLUMN dien_may."audit_event"."occurred_at" IS 'Thời điểm sự kiện nghiệp vụ xảy ra, giữ để dựng đúng thứ tự xử lý.';

-- T112 outbox_event: Sự kiện được ghi cùng giao dịch để gửi tin cậy
CREATE TABLE dien_may."outbox_event" (
    "event_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "document_id" uuid,
    "event_type" varchar(100) NOT NULL,
    "aggregate_version" integer NOT NULL,
    "schema_version" integer NOT NULL,
    "payload_redacted" jsonb NOT NULL,
    "correlation_id" varchar(100) NOT NULL,
    "published_at" timestamptz,
    "retry_count" integer NOT NULL DEFAULT 0,
    CONSTRAINT "pk_outbox_event" PRIMARY KEY ("event_id"),
    CONSTRAINT "ck_outbox_event_aggregate_version_positive" CHECK ("aggregate_version" > 0),
    CONSTRAINT "ck_outbox_event_schema_version_positive" CHECK ("schema_version" > 0),
    CONSTRAINT "ck_outbox_event_retry_count_nonnegative" CHECK ("retry_count" >= 0)
);
COMMENT ON TABLE dien_may."outbox_event" IS 'Sự kiện được ghi cùng giao dịch để gửi tin cậy.
Cấu trúc payload_redacted: Nội dung sự kiện sau khi che token, OTP, mật khẩu, bí mật đối tác và dữ liệu thẻ nhạy cảm.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."outbox_event"."event_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."outbox_event"."document_id" IS 'Liên kết định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."outbox_event"."event_type" IS 'Mã loại sự kiện, dùng để chọn đúng cách xử lý và cấu trúc payload.';
COMMENT ON COLUMN dien_may."outbox_event"."aggregate_version" IS 'Phiên bản đối tượng phát sự kiện để kiểm thứ tự và phát hiện xử lý dữ liệu cũ.';
COMMENT ON COLUMN dien_may."outbox_event"."schema_version" IS 'Phiên bản cấu trúc dữ liệu JSON hoặc thông điệp để chọn đúng bộ kiểm tra.';
COMMENT ON COLUMN dien_may."outbox_event"."payload_redacted" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."outbox_event"."correlation_id" IS 'Mã liên kết chuỗi yêu cầu, chứng từ và sự kiện để truy vết.';
COMMENT ON COLUMN dien_may."outbox_event"."published_at" IS 'Thời điểm công bố hoặc gửi sự kiện thành công theo loại bản ghi.';
COMMENT ON COLUMN dien_may."outbox_event"."retry_count" IS 'Số lần thử lại đã thực hiện; không tăng hiệu ứng nghiệp vụ khi gửi lặp.
Mặc định: 0 khi tạo tác vụ.';

-- T113 inbox_event: Chống xử lý lặp sự kiện đối tác hoặc dịch vụ
CREATE TABLE dien_may."inbox_event" (
    "inbox_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "source" varchar(100) NOT NULL,
    "external_event_id" varchar(100) NOT NULL,
    "payload_hash" text NOT NULL,
    "received_at" timestamptz NOT NULL,
    "processed_at" timestamptz,
    "result" varchar(40) NOT NULL,
    CONSTRAINT "pk_inbox_event" PRIMARY KEY ("inbox_id"),
    CONSTRAINT "uq_inbox_event_source_external_event_id" UNIQUE ("source", "external_event_id"),
    CONSTRAINT "ck_inbox_event_result_domain" CHECK ("result" IN ('RECEIVED', 'PROCESSED', 'RETRY_REQUIRED', 'REJECTED'))
);
COMMENT ON TABLE dien_may."inbox_event" IS 'Chống xử lý lặp sự kiện đối tác hoặc dịch vụ.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."inbox_event"."inbox_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."inbox_event"."source" IS 'Mã hệ thống gửi sự kiện, tạo phạm vi duy nhất cho external_event_id.';
COMMENT ON COLUMN dien_may."inbox_event"."external_event_id" IS 'Mã sự kiện phía nguồn, được dùng cùng source để chống lặp.';
COMMENT ON COLUMN dien_may."inbox_event"."payload_hash" IS 'Dấu băm nội dung chuẩn hóa để kiểm thay đổi và đối chiếu sự kiện trùng.';
COMMENT ON COLUMN dien_may."inbox_event"."received_at" IS 'Thời điểm hệ thống hoặc bộ phận tiếp nhận ghi nhận đã nhận thực tế.';
COMMENT ON COLUMN dien_may."inbox_event"."processed_at" IS 'Thời điểm sự kiện đã được xử lý bền vững; NULL khi còn chờ.';
COMMENT ON COLUMN dien_may."inbox_event"."result" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';

-- T114 idempotency_request: Ghi kết quả yêu cầu theo khóa và nội dung
CREATE TABLE dien_may."idempotency_request" (
    "request_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "scope_key" varchar(255) NOT NULL,
    "idempotency_key" varchar(255) NOT NULL,
    "request_hash" text NOT NULL,
    "document_id" uuid,
    "result_snapshot" jsonb,
    "state" varchar(40) NOT NULL,
    "expires_at" timestamptz NOT NULL,
    CONSTRAINT "pk_idempotency_request" PRIMARY KEY ("request_id"),
    CONSTRAINT "uq_idempotency_request_scope_key_idempotency_key" UNIQUE ("scope_key", "idempotency_key"),
    CONSTRAINT "ck_idempotency_request_state_domain" CHECK ("state" IN ('IN_PROGRESS', 'SUCCEEDED', 'FAILED'))
);
COMMENT ON TABLE dien_may."idempotency_request" IS 'Ghi kết quả yêu cầu theo khóa và nội dung.
Ràng buộc nghiệp vụ: Cùng khóa khác hash bị từ chối. Ràng buộc chống trùng lâu dài của tiền/posting còn tồn tại sau khi bản ghi kỹ thuật hết hạn.
Cấu trúc result_snapshot: Kết quả xử lý theo schema của nghiệp vụ; không chứa dữ liệu bí mật hoặc payload thô không kiểm.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."idempotency_request"."request_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."idempotency_request"."scope_key" IS 'Bao gồm chủ thể hoặc phiên và loại thao tác';
COMMENT ON COLUMN dien_may."idempotency_request"."idempotency_key" IS 'Khóa yêu cầu chống lặp; cùng khóa nhưng khác nội dung phải bị từ chối.';
COMMENT ON COLUMN dien_may."idempotency_request"."request_hash" IS 'Dấu băm nội dung yêu cầu; phải so sánh khi khóa chống lặp được gửi lại.';
COMMENT ON COLUMN dien_may."idempotency_request"."document_id" IS 'Liên kết định danh chứng từ dùng chung, không chứa một trạng thái thay mọi nghiệp vụ.
FK → business_document.document_id.';
COMMENT ON COLUMN dien_may."idempotency_request"."result_snapshot" IS 'Dữ liệu có schema, được kiểm trước khi lưu; cấu trúc được mô tả dưới bảng.';
COMMENT ON COLUMN dien_may."idempotency_request"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."idempotency_request"."expires_at" IS 'Thời điểm hết hạn theo mục đích bản ghi; tác vụ hết hạn còn phải kiểm trạng thái hiện tại.';

-- T115 notification: Tác vụ gửi thông báo, tách thành công nghiệp vụ với gửi tin
CREATE TABLE dien_may."notification" (
    "notification_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "event_id" uuid NOT NULL,
    "customer_id" uuid,
    "template_code" varchar(100) NOT NULL,
    "destination_encrypted" text NOT NULL,
    "recipient_fingerprint" text NOT NULL,
    "channel" varchar(40) NOT NULL,
    "state" varchar(40) NOT NULL,
    "retry_count" integer NOT NULL DEFAULT 0,
    "sent_at" timestamptz,
    CONSTRAINT "pk_notification" PRIMARY KEY ("notification_id"),
    CONSTRAINT "uq_notification_event_id_template_code_channel_re_a05e43e79e" UNIQUE ("event_id", "template_code", "channel", "recipient_fingerprint"),
    CONSTRAINT "ck_notification_channel_domain" CHECK ("channel" IN ('SMS', 'EMAIL', 'IN_APP')),
    CONSTRAINT "ck_notification_state_domain" CHECK ("state" IN ('PENDING', 'SENDING', 'SENT', 'FAILED', 'ABANDONED')),
    CONSTRAINT "ck_notification_retry_count_nonnegative" CHECK ("retry_count" >= 0)
);
COMMENT ON TABLE dien_may."notification" IS 'Tác vụ gửi thông báo, tách thành công nghiệp vụ với gửi tin.
Ràng buộc nghiệp vụ: Dùng fingerprint ổn định có bảo vệ; không so ciphertext khác nonce. Không gửi thất bại rồi đảo đơn đã ghi sổ.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."notification"."notification_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."notification"."event_id" IS 'Liên kết sự kiện được ghi cùng giao dịch để gửi tin cậy.
FK → outbox_event.event_id.';
COMMENT ON COLUMN dien_may."notification"."customer_id" IS 'Liên kết hồ sơ người mua gồm khách vãng lai không có tài khoản.
FK → customer.customer_id.';
COMMENT ON COLUMN dien_may."notification"."template_code" IS 'Mã mẫu thông báo phù hợp loại sự kiện và ngôn ngữ.';
COMMENT ON COLUMN dien_may."notification"."destination_encrypted" IS 'Địa chỉ nhận thông báo được mã hóa, chỉ giải mã khi thực sự cần gửi.';
COMMENT ON COLUMN dien_may."notification"."recipient_fingerprint" IS 'Dấu định danh người nhận ổn định có bảo vệ, dùng chống gửi trùng khi ciphertext có nonce khác.';
COMMENT ON COLUMN dien_may."notification"."channel" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."notification"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."notification"."retry_count" IS 'Số lần thử lại đã thực hiện; không tăng hiệu ứng nghiệp vụ khi gửi lặp.
Mặc định: 0 khi tạo tác vụ.';
COMMENT ON COLUMN dien_may."notification"."sent_at" IS 'Thời điểm dịch vụ gửi xác nhận đã gửi; không tự suy là khách đã đọc.';

-- T116 import_batch: Một lô nhập có kiểm và chốt nguyên tử trong phạm vi công bố
CREATE TABLE dien_may."import_batch" (
    "batch_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "file_id" uuid NOT NULL,
    "import_kind" varchar(100) NOT NULL,
    "source_digest" text NOT NULL,
    "created_by" uuid NOT NULL,
    "cutoff_at" timestamptz,
    "state" varchar(40) NOT NULL,
    "row_count" integer NOT NULL DEFAULT 0,
    "error_count" integer NOT NULL DEFAULT 0,
    "result_report_file_id" uuid,
    CONSTRAINT "pk_import_batch" PRIMARY KEY ("batch_id"),
    CONSTRAINT "uq_import_batch_import_kind_source_digest_cutoff_at" UNIQUE NULLS NOT DISTINCT ("import_kind", "source_digest", "cutoff_at"),
    CONSTRAINT "ck_import_batch_state_domain" CHECK ("state" IN ('UPLOADED', 'VALIDATING', 'INVALID', 'VALIDATED', 'POSTED', 'CANCELLED')),
    CONSTRAINT "ck_import_batch_row_count_nonnegative" CHECK ("row_count" >= 0),
    CONSTRAINT "ck_import_batch_error_count_nonnegative" CHECK ("error_count" >= 0)
);
COMMENT ON TABLE dien_may."import_batch" IS 'Một lô nhập có kiểm và chốt nguyên tử trong phạm vi công bố.
Ràng buộc nghiệp vụ: Tồn đầu cần chứng từ source tương ứng; không ghi nửa lô sau khi kiểm lỗi. Chi tiết lỗi theo dòng lưu trong tệp báo cáo có schema và phiên bản.
Kiểm soát ghi: Tạo và cập nhật bởi luồng có kiểm quyền, hết hạn/thu hồi theo chính sách. Xóa dữ liệu tạm chỉ sau thời hạn được duyệt, không làm mất chứng từ nghiệp vụ liên quan.';
COMMENT ON COLUMN dien_may."import_batch"."batch_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."import_batch"."file_id" IS 'Liên kết tệp được kiểm loại quyền truy cập và thời hạn.
FK → file_asset.file_id.';
COMMENT ON COLUMN dien_may."import_batch"."import_kind" IS 'Loại dữ liệu nhập, xác định mẫu tệp và bộ kiểm tra.';
COMMENT ON COLUMN dien_may."import_batch"."source_digest" IS 'Dấu băm nguồn tệp hoặc dữ liệu đối tác để tránh nhập lặp cùng nguồn.';
COMMENT ON COLUMN dien_may."import_batch"."created_by" IS 'Tài khoản tạo chứng từ hoặc lô dữ liệu; NULL chỉ với tác vụ hệ thống có audit phù hợp.
FK → user_account.user_id.';
COMMENT ON COLUMN dien_may."import_batch"."cutoff_at" IS 'Mốc chốt dữ liệu tồn đầu hoặc lô chuyển đổi, tách khỏi ngày tải tệp.';
COMMENT ON COLUMN dien_may."import_batch"."state" IS 'Trạng thái xử lý hiện tại; không cho sửa trực tiếp để bỏ qua bước nghiệp vụ.';
COMMENT ON COLUMN dien_may."import_batch"."row_count" IS 'Số dòng đọc được trong lô nhập sau khi loại dòng tiêu đề theo mẫu.
Mặc định: 0 trước khi đọc tệp; sau đó do tiến trình kiểm đếm ghi.';
COMMENT ON COLUMN dien_may."import_batch"."error_count" IS 'Số lỗi kiểm tra của lô nhập, đối chiếu với tệp báo cáo lỗi.
Mặc định: 0 trước khi kiểm tệp; sau đó do tiến trình kiểm tra ghi.';
COMMENT ON COLUMN dien_may."import_batch"."result_report_file_id" IS 'Tệp báo cáo lỗi theo dòng và kết quả kiểm lô nhập.
FK → file_asset.file_id.';

-- T117 content_page: Phiên bản nội dung công bố như banner hoặc chính sách
CREATE TABLE dien_may."content_page" (
    "content_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "policy_version_id" uuid,
    "slug" varchar(255) NOT NULL,
    "version_no" integer NOT NULL,
    "content_kind" varchar(40) NOT NULL,
    "body" text NOT NULL,
    "status" varchar(40) NOT NULL,
    "published_at" timestamptz,
    CONSTRAINT "pk_content_page" PRIMARY KEY ("content_id"),
    CONSTRAINT "uq_content_page_slug_version_no" UNIQUE ("slug", "version_no"),
    CONSTRAINT "ck_content_page_version_no_positive" CHECK ("version_no" > 0),
    CONSTRAINT "ck_content_page_content_kind_domain" CHECK ("content_kind" IN ('PAGE', 'BANNER')),
    CONSTRAINT "ck_content_page_status_domain" CHECK ("status" IN ('DRAFT', 'PUBLISHED', 'ARCHIVED'))
);
COMMENT ON TABLE dien_may."content_page" IS 'Phiên bản nội dung công bố như banner hoặc chính sách.
Ràng buộc nghiệp vụ: Đánh giá và điểm khách hàng thuộc R2, không đưa vào mô hình R1 này.
Kiểm soát ghi: Được tạo và cập nhật theo vai trò/phạm vi. Nếu đã được chứng từ tham chiếu thì vô hiệu hóa hoặc tạo phiên bản, không xóa làm mất dữ liệu lịch sử.';
COMMENT ON COLUMN dien_may."content_page"."content_id" IS 'Định danh bất biến của bản ghi; không dùng mã hiển thị hoặc dữ liệu cá nhân làm khóa.';
COMMENT ON COLUMN dien_may."content_page"."policy_version_id" IS 'Liên kết nội dung chính sách đã duyệt có phiên bản.
FK → policy_version.policy_version_id.';
COMMENT ON COLUMN dien_may."content_page"."slug" IS 'Khóa đường dẫn nội dung công bố; không dùng slug làm khóa chính.';
COMMENT ON COLUMN dien_may."content_page"."version_no" IS 'Số thứ tự phiên bản trong cùng đối tượng cha, không dùng lại phiên bản đã công bố.';
COMMENT ON COLUMN dien_may."content_page"."content_kind" IS 'Giá trị phân loại hoặc trạng thái có kiểm soát; tập giá trị được liệt kê dưới bảng.';
COMMENT ON COLUMN dien_may."content_page"."body" IS 'Nội dung trang hoặc banner; nội dung HTML cần được lọc an toàn trước công bố.';
COMMENT ON COLUMN dien_may."content_page"."status" IS 'Trạng thái hiện tại của đối tượng; chỉ chuyển theo điều kiện nghiệp vụ được phép.';
COMMENT ON COLUMN dien_may."content_page"."published_at" IS 'Thời điểm công bố hoặc gửi sự kiện thành công theo loại bản ghi.';

-- KHÓA NGOẠI: thêm sau tất cả CREATE TABLE để xử lý quan hệ vòng.

ALTER TABLE dien_may."store_warehouse" ADD CONSTRAINT "fk_store_warehouse_store_id" FOREIGN KEY ("store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."store_warehouse" ADD CONSTRAINT "fk_store_warehouse_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."warehouse_location" ADD CONSTRAINT "fk_warehouse_location_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."employee" ADD CONSTRAINT "fk_employee_user_id" FOREIGN KEY ("user_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."employee" ADD CONSTRAINT "fk_employee_home_store_id" FOREIGN KEY ("home_store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."role_permission" ADD CONSTRAINT "fk_role_permission_role_id" FOREIGN KEY ("role_id") REFERENCES dien_may."role" ("role_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."role_permission" ADD CONSTRAINT "fk_role_permission_permission_id" FOREIGN KEY ("permission_id") REFERENCES dien_may."permission" ("permission_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."access_scope" ADD CONSTRAINT "fk_access_scope_store_id" FOREIGN KEY ("store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."access_scope" ADD CONSTRAINT "fk_access_scope_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."user_role_assignment" ADD CONSTRAINT "fk_user_role_assignment_user_id" FOREIGN KEY ("user_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."user_role_assignment" ADD CONSTRAINT "fk_user_role_assignment_role_id" FOREIGN KEY ("role_id") REFERENCES dien_may."role" ("role_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."user_role_assignment" ADD CONSTRAINT "fk_user_role_assignment_scope_id" FOREIGN KEY ("scope_id") REFERENCES dien_may."access_scope" ("scope_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."user_role_assignment" ADD CONSTRAINT "fk_user_role_assignment_granted_by" FOREIGN KEY ("granted_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."user_role_assignment" ADD CONSTRAINT "fk_user_role_assignment_delegation_source_id" FOREIGN KEY ("delegation_source_id") REFERENCES dien_may."user_role_assignment" ("assignment_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."auth_session" ADD CONSTRAINT "fk_auth_session_user_id" FOREIGN KEY ("user_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."verification_challenge" ADD CONSTRAINT "fk_verification_challenge_user_id" FOREIGN KEY ("user_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."verification_challenge" ADD CONSTRAINT "fk_verification_challenge_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."category" ADD CONSTRAINT "fk_category_parent_id" FOREIGN KEY ("parent_id") REFERENCES dien_may."category" ("category_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."product" ADD CONSTRAINT "fk_product_category_id" FOREIGN KEY ("category_id") REFERENCES dien_may."category" ("category_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."product" ADD CONSTRAINT "fk_product_brand_id" FOREIGN KEY ("brand_id") REFERENCES dien_may."brand" ("brand_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sku" ADD CONSTRAINT "fk_sku_product_id" FOREIGN KEY ("product_id") REFERENCES dien_may."product" ("product_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."attribute_definition" ADD CONSTRAINT "fk_attribute_definition_category_id" FOREIGN KEY ("category_id") REFERENCES dien_may."category" ("category_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sku_attribute_value" ADD CONSTRAINT "fk_sku_attribute_value_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sku_attribute_value" ADD CONSTRAINT "fk_sku_attribute_value_attribute_id" FOREIGN KEY ("attribute_id") REFERENCES dien_may."attribute_definition" ("attribute_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."product_media" ADD CONSTRAINT "fk_product_media_product_id" FOREIGN KEY ("product_id") REFERENCES dien_may."product" ("product_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."product_media" ADD CONSTRAINT "fk_product_media_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."product_media" ADD CONSTRAINT "fk_product_media_file_id" FOREIGN KEY ("file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."purchase_order" ADD CONSTRAINT "fk_purchase_order_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."purchase_order" ADD CONSTRAINT "fk_purchase_order_supplier_id" FOREIGN KEY ("supplier_id") REFERENCES dien_may."supplier" ("supplier_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."purchase_order" ADD CONSTRAINT "fk_purchase_order_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."purchase_order_line" ADD CONSTRAINT "fk_purchase_order_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."purchase_order_line" ADD CONSTRAINT "fk_purchase_order_line_purchase_order_id" FOREIGN KEY ("purchase_order_id") REFERENCES dien_may."purchase_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."purchase_order_line" ADD CONSTRAINT "fk_purchase_order_line_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."goods_receipt" ADD CONSTRAINT "fk_goods_receipt_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."goods_receipt" ADD CONSTRAINT "fk_goods_receipt_purchase_order_id" FOREIGN KEY ("purchase_order_id") REFERENCES dien_may."purchase_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."goods_receipt" ADD CONSTRAINT "fk_goods_receipt_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."goods_receipt_line" ADD CONSTRAINT "fk_goods_receipt_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."goods_receipt_line" ADD CONSTRAINT "fk_goods_receipt_line_receipt_id" FOREIGN KEY ("receipt_id") REFERENCES dien_may."goods_receipt" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."goods_receipt_line" ADD CONSTRAINT "fk_goods_receipt_line_purchase_order_line_id" FOREIGN KEY ("purchase_order_line_id") REFERENCES dien_may."purchase_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."supplier_return" ADD CONSTRAINT "fk_supplier_return_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."supplier_return" ADD CONSTRAINT "fk_supplier_return_supplier_id" FOREIGN KEY ("supplier_id") REFERENCES dien_may."supplier" ("supplier_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."supplier_return" ADD CONSTRAINT "fk_supplier_return_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."supplier_return_line" ADD CONSTRAINT "fk_supplier_return_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."supplier_return_line" ADD CONSTRAINT "fk_supplier_return_line_supplier_return_id" FOREIGN KEY ("supplier_return_id") REFERENCES dien_may."supplier_return" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."supplier_return_line" ADD CONSTRAINT "fk_supplier_return_line_receipt_line_id" FOREIGN KEY ("receipt_line_id") REFERENCES dien_may."goods_receipt_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_lot" ADD CONSTRAINT "fk_stock_lot_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_lot" ADD CONSTRAINT "fk_stock_lot_receipt_line_id" FOREIGN KEY ("receipt_line_id") REFERENCES dien_may."goods_receipt_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_lot" ADD CONSTRAINT "fk_stock_lot_opening_line_id" FOREIGN KEY ("opening_line_id") REFERENCES dien_may."opening_balance_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_lot" ADD CONSTRAINT "fk_stock_lot_import_batch_id" FOREIGN KEY ("import_batch_id") REFERENCES dien_may."import_batch" ("batch_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance" ADD CONSTRAINT "fk_opening_balance_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance" ADD CONSTRAINT "fk_opening_balance_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance" ADD CONSTRAINT "fk_opening_balance_import_batch_id" FOREIGN KEY ("import_batch_id") REFERENCES dien_may."import_batch" ("batch_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance_line" ADD CONSTRAINT "fk_opening_balance_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance_line" ADD CONSTRAINT "fk_opening_balance_line_opening_balance_id" FOREIGN KEY ("opening_balance_id") REFERENCES dien_may."opening_balance" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance_line" ADD CONSTRAINT "fk_opening_balance_line_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."opening_balance_line" ADD CONSTRAINT "fk_opening_balance_line_location_id" FOREIGN KEY ("location_id") REFERENCES dien_may."warehouse_location" ("location_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."inventory_position" ADD CONSTRAINT "fk_inventory_position_location_id" FOREIGN KEY ("location_id") REFERENCES dien_may."warehouse_location" ("location_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."inventory_position" ADD CONSTRAINT "fk_inventory_position_lot_id" FOREIGN KEY ("lot_id") REFERENCES dien_may."stock_lot" ("lot_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."inventory_position" ADD CONSTRAINT "fk_inventory_position_owner_customer_id" FOREIGN KEY ("owner_customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_balance" ADD CONSTRAINT "fk_stock_balance_position_id" FOREIGN KEY ("position_id") REFERENCES dien_may."inventory_position" ("position_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_balance" ADD CONSTRAINT "fk_stock_balance_last_posting_id" FOREIGN KEY ("last_posting_id") REFERENCES dien_may."stock_posting" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_cost_balance" ADD CONSTRAINT "fk_stock_cost_balance_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_cost_balance" ADD CONSTRAINT "fk_stock_cost_balance_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_posting" ADD CONSTRAINT "fk_stock_posting_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_posting" ADD CONSTRAINT "fk_stock_posting_source_document_id" FOREIGN KEY ("source_document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_posting" ADD CONSTRAINT "fk_stock_posting_reversal_of_id" FOREIGN KEY ("reversal_of_id") REFERENCES dien_may."stock_posting" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement" ADD CONSTRAINT "fk_stock_movement_posting_id" FOREIGN KEY ("posting_id") REFERENCES dien_may."stock_posting" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement" ADD CONSTRAINT "fk_stock_movement_source_line_id" FOREIGN KEY ("source_line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement" ADD CONSTRAINT "fk_stock_movement_from_position_id" FOREIGN KEY ("from_position_id") REFERENCES dien_may."inventory_position" ("position_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement" ADD CONSTRAINT "fk_stock_movement_to_position_id" FOREIGN KEY ("to_position_id") REFERENCES dien_may."inventory_position" ("position_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement" ADD CONSTRAINT "fk_stock_movement_reversal_of_id" FOREIGN KEY ("reversal_of_id") REFERENCES dien_may."stock_movement" ("movement_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device" ADD CONSTRAINT "fk_device_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device" ADD CONSTRAINT "fk_device_origin_lot_id" FOREIGN KEY ("origin_lot_id") REFERENCES dien_may."stock_lot" ("lot_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device" ADD CONSTRAINT "fk_device_current_position_id" FOREIGN KEY ("current_position_id") REFERENCES dien_may."inventory_position" ("position_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device" ADD CONSTRAINT "fk_device_owner_customer_id" FOREIGN KEY ("owner_customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device_identifier" ADD CONSTRAINT "fk_device_identifier_device_id" FOREIGN KEY ("device_id") REFERENCES dien_may."device" ("device_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement_device" ADD CONSTRAINT "fk_stock_movement_device_movement_id" FOREIGN KEY ("movement_id") REFERENCES dien_may."stock_movement" ("movement_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement_device" ADD CONSTRAINT "fk_stock_movement_device_device_id" FOREIGN KEY ("device_id") REFERENCES dien_may."device" ("device_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_movement_device" ADD CONSTRAINT "fk_stock_movement_device_device_allocation_id" FOREIGN KEY ("device_allocation_id") REFERENCES dien_may."device_allocation" ("allocation_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device_event" ADD CONSTRAINT "fk_device_event_device_id" FOREIGN KEY ("device_id") REFERENCES dien_may."device" ("device_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device_event" ADD CONSTRAINT "fk_device_event_source_document_id" FOREIGN KEY ("source_document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device_event" ADD CONSTRAINT "fk_device_event_movement_id" FOREIGN KEY ("movement_id") REFERENCES dien_may."stock_movement" ("movement_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_reservation" ADD CONSTRAINT "fk_stock_reservation_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_reservation" ADD CONSTRAINT "fk_stock_reservation_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_reservation" ADD CONSTRAINT "fk_stock_reservation_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stock_reservation" ADD CONSTRAINT "fk_stock_reservation_transfer_line_id" FOREIGN KEY ("transfer_line_id") REFERENCES dien_may."transfer_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device_allocation" ADD CONSTRAINT "fk_device_allocation_reservation_id" FOREIGN KEY ("reservation_id") REFERENCES dien_may."stock_reservation" ("reservation_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."device_allocation" ADD CONSTRAINT "fk_device_allocation_device_id" FOREIGN KEY ("device_id") REFERENCES dien_may."device" ("device_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order" ADD CONSTRAINT "fk_transfer_order_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order" ADD CONSTRAINT "fk_transfer_order_from_warehouse_id" FOREIGN KEY ("from_warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order" ADD CONSTRAINT "fk_transfer_order_to_warehouse_id" FOREIGN KEY ("to_warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order" ADD CONSTRAINT "fk_transfer_order_transit_warehouse_id" FOREIGN KEY ("transit_warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order_line" ADD CONSTRAINT "fk_transfer_order_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order_line" ADD CONSTRAINT "fk_transfer_order_line_transfer_id" FOREIGN KEY ("transfer_id") REFERENCES dien_may."transfer_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."transfer_order_line" ADD CONSTRAINT "fk_transfer_order_line_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake" ADD CONSTRAINT "fk_stocktake_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake" ADD CONSTRAINT "fk_stocktake_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake" ADD CONSTRAINT "fk_stocktake_scope_location_id" FOREIGN KEY ("scope_location_id") REFERENCES dien_may."warehouse_location" ("location_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake" ADD CONSTRAINT "fk_stocktake_scope_sku_id" FOREIGN KEY ("scope_sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake_line" ADD CONSTRAINT "fk_stocktake_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake_line" ADD CONSTRAINT "fk_stocktake_line_stocktake_id" FOREIGN KEY ("stocktake_id") REFERENCES dien_may."stocktake" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake_line" ADD CONSTRAINT "fk_stocktake_line_position_id" FOREIGN KEY ("position_id") REFERENCES dien_may."inventory_position" ("position_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake_observation" ADD CONSTRAINT "fk_stocktake_observation_stocktake_id" FOREIGN KEY ("stocktake_id") REFERENCES dien_may."stocktake" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake_observation" ADD CONSTRAINT "fk_stocktake_observation_device_id" FOREIGN KEY ("device_id") REFERENCES dien_may."device" ("device_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."stocktake_observation" ADD CONSTRAINT "fk_stocktake_observation_observed_location_id" FOREIGN KEY ("observed_location_id") REFERENCES dien_may."warehouse_location" ("location_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."price_list" ADD CONSTRAINT "fk_price_list_store_id" FOREIGN KEY ("store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."price_entry" ADD CONSTRAINT "fk_price_entry_price_list_id" FOREIGN KEY ("price_list_id") REFERENCES dien_may."price_list" ("price_list_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."price_entry" ADD CONSTRAINT "fk_price_entry_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."promotion_version" ADD CONSTRAINT "fk_promotion_version_promotion_id" FOREIGN KEY ("promotion_id") REFERENCES dien_may."promotion" ("promotion_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."promotion_sku" ADD CONSTRAINT "fk_promotion_sku_promotion_version_id" FOREIGN KEY ("promotion_version_id") REFERENCES dien_may."promotion_version" ("promotion_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."promotion_sku" ADD CONSTRAINT "fk_promotion_sku_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."voucher" ADD CONSTRAINT "fk_voucher_promotion_version_id" FOREIGN KEY ("promotion_version_id") REFERENCES dien_may."promotion_version" ("promotion_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."voucher_claim" ADD CONSTRAINT "fk_voucher_claim_voucher_id" FOREIGN KEY ("voucher_id") REFERENCES dien_may."voucher" ("voucher_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."voucher_claim" ADD CONSTRAINT "fk_voucher_claim_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer" ADD CONSTRAINT "fk_customer_user_id" FOREIGN KEY ("user_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer" ADD CONSTRAINT "fk_customer_merged_into_id" FOREIGN KEY ("merged_into_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer_contact" ADD CONSTRAINT "fk_customer_contact_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer_address" ADD CONSTRAINT "fk_customer_address_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer_consent" ADD CONSTRAINT "fk_customer_consent_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer_consent" ADD CONSTRAINT "fk_customer_consent_policy_version_id" FOREIGN KEY ("policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."customer_consent" ADD CONSTRAINT "fk_customer_consent_evidence_file_id" FOREIGN KEY ("evidence_file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cart" ADD CONSTRAINT "fk_cart_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cart_item" ADD CONSTRAINT "fk_cart_item_cart_id" FOREIGN KEY ("cart_id") REFERENCES dien_may."cart" ("cart_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cart_item" ADD CONSTRAINT "fk_cart_item_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order" ADD CONSTRAINT "fk_sales_order_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order" ADD CONSTRAINT "fk_sales_order_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order" ADD CONSTRAINT "fk_sales_order_store_id" FOREIGN KEY ("store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order" ADD CONSTRAINT "fk_sales_order_fulfillment_warehouse_id" FOREIGN KEY ("fulfillment_warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order" ADD CONSTRAINT "fk_sales_order_replacement_for_order_id" FOREIGN KEY ("replacement_for_order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order" ADD CONSTRAINT "fk_sales_order_terms_policy_version_id" FOREIGN KEY ("terms_policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_service_id" FOREIGN KEY ("service_id") REFERENCES dien_may."service_definition" ("service_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_price_entry_id" FOREIGN KEY ("price_entry_id") REFERENCES dien_may."price_entry" ("price_entry_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_return_policy_version_id" FOREIGN KEY ("return_policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."sales_order_line" ADD CONSTRAINT "fk_sales_order_line_warranty_policy_version_id" FOREIGN KEY ("warranty_policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_discount" ADD CONSTRAINT "fk_order_discount_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_discount" ADD CONSTRAINT "fk_order_discount_promotion_version_id" FOREIGN KEY ("promotion_version_id") REFERENCES dien_may."promotion_version" ("promotion_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_discount" ADD CONSTRAINT "fk_order_discount_voucher_claim_id" FOREIGN KEY ("voucher_claim_id") REFERENCES dien_may."voucher_claim" ("claim_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_discount" ADD CONSTRAINT "fk_order_discount_approval_request_id" FOREIGN KEY ("approval_request_id") REFERENCES dien_may."approval_request" ("request_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."discount_allocation" ADD CONSTRAINT "fk_discount_allocation_discount_id" FOREIGN KEY ("discount_id") REFERENCES dien_may."order_discount" ("discount_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."discount_allocation" ADD CONSTRAINT "fk_discount_allocation_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_status_history" ADD CONSTRAINT "fk_order_status_history_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_status_history" ADD CONSTRAINT "fk_order_status_history_actor_id" FOREIGN KEY ("actor_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."service_rate" ADD CONSTRAINT "fk_service_rate_service_id" FOREIGN KEY ("service_id") REFERENCES dien_may."service_definition" ("service_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."service_rate" ADD CONSTRAINT "fk_service_rate_zone_id" FOREIGN KEY ("zone_id") REFERENCES dien_may."service_zone" ("zone_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."service_rate" ADD CONSTRAINT "fk_service_rate_category_id" FOREIGN KEY ("category_id") REFERENCES dien_may."category" ("category_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."service_slot" ADD CONSTRAINT "fk_service_slot_store_id" FOREIGN KEY ("store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."service_slot" ADD CONSTRAINT "fk_service_slot_zone_id" FOREIGN KEY ("zone_id") REFERENCES dien_may."service_zone" ("zone_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."slot_reservation" ADD CONSTRAINT "fk_slot_reservation_slot_id" FOREIGN KEY ("slot_id") REFERENCES dien_may."service_slot" ("slot_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."slot_reservation" ADD CONSTRAINT "fk_slot_reservation_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."dispatch" ADD CONSTRAINT "fk_dispatch_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."dispatch" ADD CONSTRAINT "fk_dispatch_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."dispatch" ADD CONSTRAINT "fk_dispatch_warehouse_id" FOREIGN KEY ("warehouse_id") REFERENCES dien_may."warehouse" ("warehouse_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."dispatch_line" ADD CONSTRAINT "fk_dispatch_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."dispatch_line" ADD CONSTRAINT "fk_dispatch_line_dispatch_id" FOREIGN KEY ("dispatch_id") REFERENCES dien_may."dispatch" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."dispatch_line" ADD CONSTRAINT "fk_dispatch_line_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."shipment" ADD CONSTRAINT "fk_shipment_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."shipment" ADD CONSTRAINT "fk_shipment_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."shipment" ADD CONSTRAINT "fk_shipment_dispatch_id" FOREIGN KEY ("dispatch_id") REFERENCES dien_may."dispatch" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."shipment" ADD CONSTRAINT "fk_shipment_slot_reservation_id" FOREIGN KEY ("slot_reservation_id") REFERENCES dien_may."slot_reservation" ("slot_reservation_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."shipment_item" ADD CONSTRAINT "fk_shipment_item_shipment_id" FOREIGN KEY ("shipment_id") REFERENCES dien_may."shipment" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."shipment_item" ADD CONSTRAINT "fk_shipment_item_dispatch_line_id" FOREIGN KEY ("dispatch_line_id") REFERENCES dien_may."dispatch_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."delivery_attempt" ADD CONSTRAINT "fk_delivery_attempt_shipment_id" FOREIGN KEY ("shipment_id") REFERENCES dien_may."shipment" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."delivery_attempt" ADD CONSTRAINT "fk_delivery_attempt_verification_challenge_id" FOREIGN KEY ("verification_challenge_id") REFERENCES dien_may."verification_challenge" ("challenge_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."installation_job" ADD CONSTRAINT "fk_installation_job_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."installation_job" ADD CONSTRAINT "fk_installation_job_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."installation_job" ADD CONSTRAINT "fk_installation_job_slot_reservation_id" FOREIGN KEY ("slot_reservation_id") REFERENCES dien_may."slot_reservation" ("slot_reservation_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."installation_item" ADD CONSTRAINT "fk_installation_item_installation_id" FOREIGN KEY ("installation_id") REFERENCES dien_may."installation_job" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."installation_item" ADD CONSTRAINT "fk_installation_item_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."employee_skill" ADD CONSTRAINT "fk_employee_skill_employee_id" FOREIGN KEY ("employee_id") REFERENCES dien_may."employee" ("employee_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."work_assignment" ADD CONSTRAINT "fk_work_assignment_employee_id" FOREIGN KEY ("employee_id") REFERENCES dien_may."employee" ("employee_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."work_assignment" ADD CONSTRAINT "fk_work_assignment_shipment_id" FOREIGN KEY ("shipment_id") REFERENCES dien_may."shipment" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."work_assignment" ADD CONSTRAINT "fk_work_assignment_installation_id" FOREIGN KEY ("installation_id") REFERENCES dien_may."installation_job" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."work_assignment" ADD CONSTRAINT "fk_work_assignment_assigned_by" FOREIGN KEY ("assigned_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_attempt" ADD CONSTRAINT "fk_payment_attempt_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_attempt" ADD CONSTRAINT "fk_payment_attempt_provider_id" FOREIGN KEY ("provider_id") REFERENCES dien_may."payment_provider" ("provider_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_event" ADD CONSTRAINT "fk_payment_event_provider_id" FOREIGN KEY ("provider_id") REFERENCES dien_may."payment_provider" ("provider_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_event" ADD CONSTRAINT "fk_payment_event_attempt_id" FOREIGN KEY ("attempt_id") REFERENCES dien_may."payment_attempt" ("attempt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_event" ADD CONSTRAINT "fk_payment_event_receipt_id" FOREIGN KEY ("receipt_id") REFERENCES dien_may."payment_receipt" ("receipt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_receipt" ADD CONSTRAINT "fk_payment_receipt_provider_id" FOREIGN KEY ("provider_id") REFERENCES dien_may."payment_provider" ("provider_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_receipt" ADD CONSTRAINT "fk_payment_receipt_attempt_id" FOREIGN KEY ("attempt_id") REFERENCES dien_may."payment_attempt" ("attempt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_receipt" ADD CONSTRAINT "fk_payment_receipt_declared_order_id" FOREIGN KEY ("declared_order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_receipt" ADD CONSTRAINT "fk_payment_receipt_collector_employee_id" FOREIGN KEY ("collector_employee_id") REFERENCES dien_may."employee" ("employee_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."payment_receipt" ADD CONSTRAINT "fk_payment_receipt_confirmed_by" FOREIGN KEY ("confirmed_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cash_remittance" ADD CONSTRAINT "fk_cash_remittance_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cash_remittance" ADD CONSTRAINT "fk_cash_remittance_collector_employee_id" FOREIGN KEY ("collector_employee_id") REFERENCES dien_may."employee" ("employee_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cash_remittance" ADD CONSTRAINT "fk_cash_remittance_received_by" FOREIGN KEY ("received_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cash_remittance_allocation" ADD CONSTRAINT "fk_cash_remittance_allocation_remittance_id" FOREIGN KEY ("remittance_id") REFERENCES dien_may."cash_remittance" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."cash_remittance_allocation" ADD CONSTRAINT "fk_cash_remittance_allocation_receipt_id" FOREIGN KEY ("receipt_id") REFERENCES dien_may."payment_receipt" ("receipt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."reconciliation_batch" ADD CONSTRAINT "fk_reconciliation_batch_provider_id" FOREIGN KEY ("provider_id") REFERENCES dien_may."payment_provider" ("provider_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."reconciliation_batch" ADD CONSTRAINT "fk_reconciliation_batch_source_file_id" FOREIGN KEY ("source_file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."reconciliation_item" ADD CONSTRAINT "fk_reconciliation_item_batch_id" FOREIGN KEY ("batch_id") REFERENCES dien_may."reconciliation_batch" ("batch_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."reconciliation_item" ADD CONSTRAINT "fk_reconciliation_item_receipt_id" FOREIGN KEY ("receipt_id") REFERENCES dien_may."payment_receipt" ("receipt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."reconciliation_item" ADD CONSTRAINT "fk_reconciliation_item_refund_attempt_id" FOREIGN KEY ("refund_attempt_id") REFERENCES dien_may."refund_attempt" ("attempt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."reconciliation_item" ADD CONSTRAINT "fk_reconciliation_item_resolved_by" FOREIGN KEY ("resolved_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."invoice" ADD CONSTRAINT "fk_invoice_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."invoice" ADD CONSTRAINT "fk_invoice_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."invoice" ADD CONSTRAINT "fk_invoice_adjustment_of_id" FOREIGN KEY ("adjustment_of_id") REFERENCES dien_may."invoice" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."invoice_line" ADD CONSTRAINT "fk_invoice_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."invoice_line" ADD CONSTRAINT "fk_invoice_line_invoice_id" FOREIGN KEY ("invoice_id") REFERENCES dien_may."invoice" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."invoice_line" ADD CONSTRAINT "fk_invoice_line_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice" ADD CONSTRAINT "fk_funding_slice_receipt_id" FOREIGN KEY ("receipt_id") REFERENCES dien_may."payment_receipt" ("receipt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice" ADD CONSTRAINT "fk_funding_slice_parent_slice_id" FOREIGN KEY ("parent_slice_id") REFERENCES dien_may."funding_slice" ("slice_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice" ADD CONSTRAINT "fk_funding_slice_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice" ADD CONSTRAINT "fk_funding_slice_case_item_id" FOREIGN KEY ("case_item_id") REFERENCES dien_may."after_sales_case_item" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment" ADD CONSTRAINT "fk_order_adjustment_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment" ADD CONSTRAINT "fk_order_adjustment_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment" ADD CONSTRAINT "fk_order_adjustment_case_id" FOREIGN KEY ("case_id") REFERENCES dien_may."after_sales_case" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment" ADD CONSTRAINT "fk_order_adjustment_cause_document_id" FOREIGN KEY ("cause_document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment" ADD CONSTRAINT "fk_order_adjustment_reversal_of_id" FOREIGN KEY ("reversal_of_id") REFERENCES dien_may."order_adjustment" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment_line" ADD CONSTRAINT "fk_order_adjustment_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment_line" ADD CONSTRAINT "fk_order_adjustment_line_adjustment_id" FOREIGN KEY ("adjustment_id") REFERENCES dien_may."order_adjustment" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment_line" ADD CONSTRAINT "fk_order_adjustment_line_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment_line" ADD CONSTRAINT "fk_order_adjustment_line_case_resolution_id" FOREIGN KEY ("case_resolution_id") REFERENCES dien_may."case_resolution" ("resolution_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."order_adjustment_line" ADD CONSTRAINT "fk_order_adjustment_line_reversal_of_line_id" FOREIGN KEY ("reversal_of_line_id") REFERENCES dien_may."order_adjustment_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice_event" ADD CONSTRAINT "fk_funding_slice_event_slice_id" FOREIGN KEY ("slice_id") REFERENCES dien_may."funding_slice" ("slice_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice_event" ADD CONSTRAINT "fk_funding_slice_event_source_document_id" FOREIGN KEY ("source_document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."funding_slice_event" ADD CONSTRAINT "fk_funding_slice_event_actor_id" FOREIGN KEY ("actor_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_request" ADD CONSTRAINT "fk_refund_request_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_request" ADD CONSTRAINT "fk_refund_request_receipt_id" FOREIGN KEY ("receipt_id") REFERENCES dien_may."payment_receipt" ("receipt_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_request" ADD CONSTRAINT "fk_refund_request_provider_id" FOREIGN KEY ("provider_id") REFERENCES dien_may."payment_provider" ("provider_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_request" ADD CONSTRAINT "fk_refund_request_cause_document_id" FOREIGN KEY ("cause_document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_request" ADD CONSTRAINT "fk_refund_request_case_id" FOREIGN KEY ("case_id") REFERENCES dien_may."after_sales_case" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_slice" ADD CONSTRAINT "fk_refund_slice_refund_request_id" FOREIGN KEY ("refund_request_id") REFERENCES dien_may."refund_request" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_slice" ADD CONSTRAINT "fk_refund_slice_slice_id" FOREIGN KEY ("slice_id") REFERENCES dien_may."funding_slice" ("slice_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_attempt" ADD CONSTRAINT "fk_refund_attempt_refund_request_id" FOREIGN KEY ("refund_request_id") REFERENCES dien_may."refund_request" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."refund_attempt" ADD CONSTRAINT "fk_refund_attempt_provider_id" FOREIGN KEY ("provider_id") REFERENCES dien_may."payment_provider" ("provider_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit" ADD CONSTRAINT "fk_exchange_credit_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit" ADD CONSTRAINT "fk_exchange_credit_return_case_id" FOREIGN KEY ("return_case_id") REFERENCES dien_may."after_sales_case" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit" ADD CONSTRAINT "fk_exchange_credit_target_order_id" FOREIGN KEY ("target_order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit_line" ADD CONSTRAINT "fk_exchange_credit_line_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit_line" ADD CONSTRAINT "fk_exchange_credit_line_credit_id" FOREIGN KEY ("credit_id") REFERENCES dien_may."exchange_credit" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit_line" ADD CONSTRAINT "fk_exchange_credit_line_source_slice_id" FOREIGN KEY ("source_slice_id") REFERENCES dien_may."funding_slice" ("slice_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit_line" ADD CONSTRAINT "fk_exchange_credit_line_target_slice_id" FOREIGN KEY ("target_slice_id") REFERENCES dien_may."funding_slice" ("slice_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."exchange_credit_line" ADD CONSTRAINT "fk_exchange_credit_line_target_order_line_id" FOREIGN KEY ("target_order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case" ADD CONSTRAINT "fk_after_sales_case_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case" ADD CONSTRAINT "fk_after_sales_case_order_id" FOREIGN KEY ("order_id") REFERENCES dien_may."sales_order" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case" ADD CONSTRAINT "fk_after_sales_case_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case_item" ADD CONSTRAINT "fk_after_sales_case_item_line_id" FOREIGN KEY ("line_id") REFERENCES dien_may."business_document_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case_item" ADD CONSTRAINT "fk_after_sales_case_item_case_id" FOREIGN KEY ("case_id") REFERENCES dien_may."after_sales_case" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case_item" ADD CONSTRAINT "fk_after_sales_case_item_order_line_id" FOREIGN KEY ("order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case_item" ADD CONSTRAINT "fk_after_sales_case_item_device_id" FOREIGN KEY ("device_id") REFERENCES dien_may."device" ("device_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case_item" ADD CONSTRAINT "fk_after_sales_case_item_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."after_sales_case_item" ADD CONSTRAINT "fk_after_sales_case_item_policy_version_id" FOREIGN KEY ("policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_resolution" ADD CONSTRAINT "fk_case_resolution_case_item_id" FOREIGN KEY ("case_item_id") REFERENCES dien_may."after_sales_case_item" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_resolution" ADD CONSTRAINT "fk_case_resolution_approval_request_id" FOREIGN KEY ("approval_request_id") REFERENCES dien_may."approval_request" ("request_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."warranty_job" ADD CONSTRAINT "fk_warranty_job_case_item_id" FOREIGN KEY ("case_item_id") REFERENCES dien_may."after_sales_case_item" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."warranty_job" ADD CONSTRAINT "fk_warranty_job_assigned_employee_id" FOREIGN KEY ("assigned_employee_id") REFERENCES dien_may."employee" ("employee_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."warranty_job" ADD CONSTRAINT "fk_warranty_job_service_supplier_id" FOREIGN KEY ("service_supplier_id") REFERENCES dien_may."supplier" ("supplier_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."warranty_job" ADD CONSTRAINT "fk_warranty_job_quote_order_line_id" FOREIGN KEY ("quote_order_line_id") REFERENCES dien_may."sales_order_line" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_event" ADD CONSTRAINT "fk_case_event_case_id" FOREIGN KEY ("case_id") REFERENCES dien_may."after_sales_case" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_event" ADD CONSTRAINT "fk_case_event_case_item_id" FOREIGN KEY ("case_item_id") REFERENCES dien_may."after_sales_case_item" ("line_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_event" ADD CONSTRAINT "fk_case_event_actor_id" FOREIGN KEY ("actor_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_event" ADD CONSTRAINT "fk_case_event_custodian_employee_id" FOREIGN KEY ("custodian_employee_id") REFERENCES dien_may."employee" ("employee_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_event" ADD CONSTRAINT "fk_case_event_custodian_supplier_id" FOREIGN KEY ("custodian_supplier_id") REFERENCES dien_may."supplier" ("supplier_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."case_event" ADD CONSTRAINT "fk_case_event_evidence_file_id" FOREIGN KEY ("evidence_file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."business_document" ADD CONSTRAINT "fk_business_document_store_id" FOREIGN KEY ("store_id") REFERENCES dien_may."store" ("store_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."business_document" ADD CONSTRAINT "fk_business_document_created_by" FOREIGN KEY ("created_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."business_document_line" ADD CONSTRAINT "fk_business_document_line_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."policy_version" ADD CONSTRAINT "fk_policy_version_policy_id" FOREIGN KEY ("policy_id") REFERENCES dien_may."policy" ("policy_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."policy_version" ADD CONSTRAINT "fk_policy_version_approved_by" FOREIGN KEY ("approved_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."approval_request" ADD CONSTRAINT "fk_approval_request_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."approval_request" ADD CONSTRAINT "fk_approval_request_policy_version_id" FOREIGN KEY ("policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."approval_request" ADD CONSTRAINT "fk_approval_request_requested_by" FOREIGN KEY ("requested_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."approval_decision" ADD CONSTRAINT "fk_approval_decision_request_id" FOREIGN KEY ("request_id") REFERENCES dien_may."approval_request" ("request_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."approval_decision" ADD CONSTRAINT "fk_approval_decision_decided_by" FOREIGN KEY ("decided_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."approval_decision" ADD CONSTRAINT "fk_approval_decision_assignment_id" FOREIGN KEY ("assignment_id") REFERENCES dien_may."user_role_assignment" ("assignment_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."document_attachment" ADD CONSTRAINT "fk_document_attachment_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."document_attachment" ADD CONSTRAINT "fk_document_attachment_file_id" FOREIGN KEY ("file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."document_attachment" ADD CONSTRAINT "fk_document_attachment_attached_by" FOREIGN KEY ("attached_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."audit_event" ADD CONSTRAINT "fk_audit_event_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."audit_event" ADD CONSTRAINT "fk_audit_event_actor_id" FOREIGN KEY ("actor_id") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."outbox_event" ADD CONSTRAINT "fk_outbox_event_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."idempotency_request" ADD CONSTRAINT "fk_idempotency_request_document_id" FOREIGN KEY ("document_id") REFERENCES dien_may."business_document" ("document_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."notification" ADD CONSTRAINT "fk_notification_event_id" FOREIGN KEY ("event_id") REFERENCES dien_may."outbox_event" ("event_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."notification" ADD CONSTRAINT "fk_notification_customer_id" FOREIGN KEY ("customer_id") REFERENCES dien_may."customer" ("customer_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."import_batch" ADD CONSTRAINT "fk_import_batch_file_id" FOREIGN KEY ("file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."import_batch" ADD CONSTRAINT "fk_import_batch_created_by" FOREIGN KEY ("created_by") REFERENCES dien_may."user_account" ("user_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."import_batch" ADD CONSTRAINT "fk_import_batch_result_report_file_id" FOREIGN KEY ("result_report_file_id") REFERENCES dien_may."file_asset" ("file_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE dien_may."content_page" ADD CONSTRAINT "fk_content_page_policy_version_id" FOREIGN KEY ("policy_version_id") REFERENCES dien_may."policy_version" ("policy_version_id") ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

-- UNIQUE CÓ ĐIỀU KIỆN: giữ lịch sử sau khi bản ghi hết hiệu lực.

CREATE UNIQUE INDEX "ux_device_allocation_one_active_device" ON dien_may."device_allocation" ("device_id") WHERE state = 'ACTIVE';
CREATE UNIQUE INDEX "ux_funding_slice_one_root_receipt" ON dien_may."funding_slice" ("receipt_id") WHERE parent_slice_id IS NULL;
CREATE UNIQUE INDEX "ux_refund_slice_one_active_refund" ON dien_may."refund_slice" ("slice_id") WHERE state IN ('HELD','REFUNDED');
CREATE UNIQUE INDEX "ux_case_resolution_one_approved_resolution" ON dien_may."case_resolution" ("case_item_id") WHERE state = 'APPROVED';

-- CHỈ MỤC TRUY VẤN VÀ FK: bỏ qua nếu đã có khóa/index cùng tiền tố.

CREATE INDEX "ix_store_warehouse_warehouse_id" ON dien_may."store_warehouse" ("warehouse_id");
CREATE INDEX "ix_employee_home_store_id" ON dien_may."employee" ("home_store_id");
CREATE INDEX "ix_role_permission_permission_id" ON dien_may."role_permission" ("permission_id");
CREATE INDEX "ix_access_scope_store_id" ON dien_may."access_scope" ("store_id");
CREATE INDEX "ix_access_scope_warehouse_id" ON dien_may."access_scope" ("warehouse_id");
CREATE INDEX "ix_user_role_assignment_delegation_source_id" ON dien_may."user_role_assignment" ("delegation_source_id");
CREATE INDEX "ix_user_role_assignment_granted_by" ON dien_may."user_role_assignment" ("granted_by");
CREATE INDEX "ix_user_role_assignment_role_id" ON dien_may."user_role_assignment" ("role_id");
CREATE INDEX "ix_user_role_assignment_scope_id" ON dien_may."user_role_assignment" ("scope_id");
CREATE INDEX "ix_user_role_assignment_user_id" ON dien_may."user_role_assignment" ("user_id");
CREATE INDEX "ix_auth_session_user_id" ON dien_may."auth_session" ("user_id");
CREATE INDEX "ix_verification_challenge_order_id" ON dien_may."verification_challenge" ("order_id");
CREATE INDEX "ix_verification_challenge_user_id" ON dien_may."verification_challenge" ("user_id");
CREATE INDEX "ix_category_parent_id" ON dien_may."category" ("parent_id");
CREATE INDEX "ix_product_brand_id" ON dien_may."product" ("brand_id");
CREATE INDEX "ix_product_category_id" ON dien_may."product" ("category_id");
CREATE INDEX "ix_sku_product_id" ON dien_may."sku" ("product_id");
CREATE INDEX "ix_sku_attribute_value_attribute_id" ON dien_may."sku_attribute_value" ("attribute_id");
CREATE INDEX "ix_product_media_file_id" ON dien_may."product_media" ("file_id");
CREATE INDEX "ix_product_media_product_id" ON dien_may."product_media" ("product_id");
CREATE INDEX "ix_product_media_sku_id" ON dien_may."product_media" ("sku_id");
CREATE INDEX "ix_purchase_order_supplier_id" ON dien_may."purchase_order" ("supplier_id");
CREATE INDEX "ix_purchase_order_warehouse_id" ON dien_may."purchase_order" ("warehouse_id");
CREATE INDEX "ix_purchase_order_line_purchase_order_id" ON dien_may."purchase_order_line" ("purchase_order_id");
CREATE INDEX "ix_purchase_order_line_sku_id" ON dien_may."purchase_order_line" ("sku_id");
CREATE INDEX "ix_goods_receipt_purchase_order_id" ON dien_may."goods_receipt" ("purchase_order_id");
CREATE INDEX "ix_goods_receipt_warehouse_id" ON dien_may."goods_receipt" ("warehouse_id");
CREATE INDEX "ix_goods_receipt_line_purchase_order_line_id" ON dien_may."goods_receipt_line" ("purchase_order_line_id");
CREATE INDEX "ix_goods_receipt_line_receipt_id" ON dien_may."goods_receipt_line" ("receipt_id");
CREATE INDEX "ix_supplier_return_supplier_id" ON dien_may."supplier_return" ("supplier_id");
CREATE INDEX "ix_supplier_return_warehouse_id" ON dien_may."supplier_return" ("warehouse_id");
CREATE INDEX "ix_supplier_return_line_receipt_line_id" ON dien_may."supplier_return_line" ("receipt_line_id");
CREATE INDEX "ix_supplier_return_line_supplier_return_id" ON dien_may."supplier_return_line" ("supplier_return_id");
CREATE INDEX "ix_stock_lot_import_batch_id" ON dien_may."stock_lot" ("import_batch_id");
CREATE INDEX "ix_stock_lot_opening_line_id" ON dien_may."stock_lot" ("opening_line_id");
CREATE INDEX "ix_stock_lot_receipt_line_id" ON dien_may."stock_lot" ("receipt_line_id");
CREATE INDEX "ix_stock_lot_sku_id" ON dien_may."stock_lot" ("sku_id");
CREATE INDEX "ix_opening_balance_import_batch_id" ON dien_may."opening_balance" ("import_batch_id");
CREATE INDEX "ix_opening_balance_line_location_id" ON dien_may."opening_balance_line" ("location_id");
CREATE INDEX "ix_opening_balance_line_opening_balance_id" ON dien_may."opening_balance_line" ("opening_balance_id");
CREATE INDEX "ix_opening_balance_line_sku_id" ON dien_may."opening_balance_line" ("sku_id");
CREATE INDEX "ix_inventory_position_lot_id" ON dien_may."inventory_position" ("lot_id");
CREATE INDEX "ix_inventory_position_owner_customer_id" ON dien_may."inventory_position" ("owner_customer_id");
CREATE INDEX "ix_stock_balance_last_posting_id" ON dien_may."stock_balance" ("last_posting_id");
CREATE INDEX "ix_stock_cost_balance_sku_id" ON dien_may."stock_cost_balance" ("sku_id");
CREATE INDEX "ix_stock_posting_reversal_of_id" ON dien_may."stock_posting" ("reversal_of_id");
CREATE INDEX "ix_stock_movement_from_position_id" ON dien_may."stock_movement" ("from_position_id");
CREATE INDEX "ix_stock_movement_posting_id" ON dien_may."stock_movement" ("posting_id");
CREATE INDEX "ix_stock_movement_reversal_of_id" ON dien_may."stock_movement" ("reversal_of_id");
CREATE INDEX "ix_stock_movement_source_line_id" ON dien_may."stock_movement" ("source_line_id");
CREATE INDEX "ix_stock_movement_to_position_id" ON dien_may."stock_movement" ("to_position_id");
CREATE INDEX "ix_device_current_position_id_sku_id" ON dien_may."device" ("current_position_id", "sku_id");
CREATE INDEX "ix_device_origin_lot_id" ON dien_may."device" ("origin_lot_id");
CREATE INDEX "ix_device_owner_customer_id" ON dien_may."device" ("owner_customer_id");
CREATE INDEX "ix_device_sku_id" ON dien_may."device" ("sku_id");
CREATE INDEX "ix_stock_movement_device_device_allocation_id" ON dien_may."stock_movement_device" ("device_allocation_id");
CREATE INDEX "ix_stock_movement_device_device_id" ON dien_may."stock_movement_device" ("device_id");
CREATE INDEX "ix_device_event_device_id" ON dien_may."device_event" ("device_id");
CREATE INDEX "ix_device_event_movement_id" ON dien_may."device_event" ("movement_id");
CREATE INDEX "ix_device_event_source_document_id" ON dien_may."device_event" ("source_document_id");
CREATE INDEX "ix_stock_reservation_warehouse_id_sku_id_state" ON dien_may."stock_reservation" ("warehouse_id", "sku_id", "state");
CREATE INDEX "ix_stock_reservation_state_expires_at" ON dien_may."stock_reservation" ("state", "expires_at");
CREATE INDEX "ix_stock_reservation_order_line_id" ON dien_may."stock_reservation" ("order_line_id");
CREATE INDEX "ix_stock_reservation_sku_id" ON dien_may."stock_reservation" ("sku_id");
CREATE INDEX "ix_stock_reservation_transfer_line_id" ON dien_may."stock_reservation" ("transfer_line_id");
CREATE INDEX "ix_device_allocation_reservation_id_state" ON dien_may."device_allocation" ("reservation_id", "state");
CREATE INDEX "ix_device_allocation_device_id" ON dien_may."device_allocation" ("device_id");
CREATE INDEX "ix_transfer_order_from_warehouse_id" ON dien_may."transfer_order" ("from_warehouse_id");
CREATE INDEX "ix_transfer_order_to_warehouse_id" ON dien_may."transfer_order" ("to_warehouse_id");
CREATE INDEX "ix_transfer_order_transit_warehouse_id" ON dien_may."transfer_order" ("transit_warehouse_id");
CREATE INDEX "ix_transfer_order_line_sku_id" ON dien_may."transfer_order_line" ("sku_id");
CREATE INDEX "ix_transfer_order_line_transfer_id" ON dien_may."transfer_order_line" ("transfer_id");
CREATE INDEX "ix_stocktake_scope_location_id" ON dien_may."stocktake" ("scope_location_id");
CREATE INDEX "ix_stocktake_scope_sku_id" ON dien_may."stocktake" ("scope_sku_id");
CREATE INDEX "ix_stocktake_warehouse_id" ON dien_may."stocktake" ("warehouse_id");
CREATE INDEX "ix_stocktake_line_position_id" ON dien_may."stocktake_line" ("position_id");
CREATE INDEX "ix_stocktake_observation_device_id" ON dien_may."stocktake_observation" ("device_id");
CREATE INDEX "ix_stocktake_observation_observed_location_id" ON dien_may."stocktake_observation" ("observed_location_id");
CREATE INDEX "ix_stocktake_observation_stocktake_id" ON dien_may."stocktake_observation" ("stocktake_id");
CREATE INDEX "ix_price_list_store_id" ON dien_may."price_list" ("store_id");
CREATE INDEX "ix_price_entry_price_list_id_sku_id_valid_from_valid_to" ON dien_may."price_entry" ("price_list_id", "sku_id", "valid_from", "valid_to");
CREATE INDEX "ix_price_entry_sku_id" ON dien_may."price_entry" ("sku_id");
CREATE INDEX "ix_promotion_sku_sku_id" ON dien_may."promotion_sku" ("sku_id");
CREATE INDEX "ix_voucher_promotion_version_id" ON dien_may."voucher" ("promotion_version_id");
CREATE INDEX "ix_voucher_claim_voucher_id_state" ON dien_may."voucher_claim" ("voucher_id", "state");
CREATE INDEX "ix_customer_merged_into_id" ON dien_may."customer" ("merged_into_id");
CREATE INDEX "ix_customer_contact_customer_id" ON dien_may."customer_contact" ("customer_id");
CREATE INDEX "ix_customer_address_customer_id" ON dien_may."customer_address" ("customer_id");
CREATE INDEX "ix_customer_consent_customer_id" ON dien_may."customer_consent" ("customer_id");
CREATE INDEX "ix_customer_consent_evidence_file_id" ON dien_may."customer_consent" ("evidence_file_id");
CREATE INDEX "ix_customer_consent_policy_version_id" ON dien_may."customer_consent" ("policy_version_id");
CREATE INDEX "ix_cart_customer_id" ON dien_may."cart" ("customer_id");
CREATE INDEX "ix_cart_item_sku_id" ON dien_may."cart_item" ("sku_id");
CREATE INDEX "ix_sales_order_store_id_status_confirmed_at" ON dien_may."sales_order" ("store_id", "status", "confirmed_at");
CREATE INDEX "ix_sales_order_customer_id_completed_at" ON dien_may."sales_order" ("customer_id", "completed_at");
CREATE INDEX "ix_sales_order_fulfillment_warehouse_id" ON dien_may."sales_order" ("fulfillment_warehouse_id");
CREATE INDEX "ix_sales_order_replacement_for_order_id" ON dien_may."sales_order" ("replacement_for_order_id");
CREATE INDEX "ix_sales_order_terms_policy_version_id" ON dien_may."sales_order" ("terms_policy_version_id");
CREATE INDEX "ix_sales_order_line_order_id_line_id" ON dien_may."sales_order_line" ("order_id", "line_id");
CREATE INDEX "ix_sales_order_line_sku_id_order_id" ON dien_may."sales_order_line" ("sku_id", "order_id");
CREATE INDEX "ix_sales_order_line_price_entry_id" ON dien_may."sales_order_line" ("price_entry_id");
CREATE INDEX "ix_sales_order_line_return_policy_version_id" ON dien_may."sales_order_line" ("return_policy_version_id");
CREATE INDEX "ix_sales_order_line_service_id" ON dien_may."sales_order_line" ("service_id");
CREATE INDEX "ix_sales_order_line_warranty_policy_version_id" ON dien_may."sales_order_line" ("warranty_policy_version_id");
CREATE INDEX "ix_order_discount_approval_request_id" ON dien_may."order_discount" ("approval_request_id");
CREATE INDEX "ix_order_discount_order_id" ON dien_may."order_discount" ("order_id");
CREATE INDEX "ix_order_discount_promotion_version_id" ON dien_may."order_discount" ("promotion_version_id");
CREATE INDEX "ix_discount_allocation_order_line_id" ON dien_may."discount_allocation" ("order_line_id");
CREATE INDEX "ix_order_status_history_actor_id" ON dien_may."order_status_history" ("actor_id");
CREATE INDEX "ix_order_status_history_order_id" ON dien_may."order_status_history" ("order_id");
CREATE INDEX "ix_service_rate_category_id" ON dien_may."service_rate" ("category_id");
CREATE INDEX "ix_service_rate_service_id" ON dien_may."service_rate" ("service_id");
CREATE INDEX "ix_service_rate_zone_id" ON dien_may."service_rate" ("zone_id");
CREATE INDEX "ix_service_slot_store_id" ON dien_may."service_slot" ("store_id");
CREATE INDEX "ix_service_slot_zone_id" ON dien_may."service_slot" ("zone_id");
CREATE INDEX "ix_slot_reservation_order_id_state" ON dien_may."slot_reservation" ("order_id", "state");
CREATE INDEX "ix_slot_reservation_slot_id_state" ON dien_may."slot_reservation" ("slot_id", "state");
CREATE INDEX "ix_dispatch_warehouse_id" ON dien_may."dispatch" ("warehouse_id");
CREATE INDEX "ix_dispatch_line_dispatch_id" ON dien_may."dispatch_line" ("dispatch_id");
CREATE INDEX "ix_dispatch_line_order_line_id" ON dien_may."dispatch_line" ("order_line_id");
CREATE INDEX "ix_shipment_slot_reservation_id" ON dien_may."shipment" ("slot_reservation_id");
CREATE INDEX "ix_shipment_item_dispatch_line_id" ON dien_may."shipment_item" ("dispatch_line_id");
CREATE INDEX "ix_delivery_attempt_verification_challenge_id" ON dien_may."delivery_attempt" ("verification_challenge_id");
CREATE INDEX "ix_installation_job_slot_reservation_id" ON dien_may."installation_job" ("slot_reservation_id");
CREATE INDEX "ix_installation_item_order_line_id" ON dien_may."installation_item" ("order_line_id");
CREATE INDEX "ix_work_assignment_assigned_by" ON dien_may."work_assignment" ("assigned_by");
CREATE INDEX "ix_work_assignment_employee_id" ON dien_may."work_assignment" ("employee_id");
CREATE INDEX "ix_work_assignment_installation_id" ON dien_may."work_assignment" ("installation_id");
CREATE INDEX "ix_work_assignment_shipment_id" ON dien_may."work_assignment" ("shipment_id");
CREATE INDEX "ix_payment_attempt_order_id" ON dien_may."payment_attempt" ("order_id");
CREATE INDEX "ix_payment_attempt_provider_id" ON dien_may."payment_attempt" ("provider_id");
CREATE INDEX "ix_payment_event_attempt_id" ON dien_may."payment_event" ("attempt_id");
CREATE INDEX "ix_payment_event_receipt_id" ON dien_may."payment_event" ("receipt_id");
CREATE INDEX "ix_payment_receipt_declared_order_id_confirmed_at" ON dien_may."payment_receipt" ("declared_order_id", "confirmed_at");
CREATE INDEX "ix_payment_receipt_attempt_id" ON dien_may."payment_receipt" ("attempt_id");
CREATE INDEX "ix_payment_receipt_collector_employee_id" ON dien_may."payment_receipt" ("collector_employee_id");
CREATE INDEX "ix_payment_receipt_confirmed_by" ON dien_may."payment_receipt" ("confirmed_by");
CREATE INDEX "ix_cash_remittance_collector_employee_id" ON dien_may."cash_remittance" ("collector_employee_id");
CREATE INDEX "ix_cash_remittance_received_by" ON dien_may."cash_remittance" ("received_by");
CREATE INDEX "ix_cash_remittance_allocation_receipt_id" ON dien_may."cash_remittance_allocation" ("receipt_id");
CREATE INDEX "ix_reconciliation_batch_source_file_id" ON dien_may."reconciliation_batch" ("source_file_id");
CREATE INDEX "ix_reconciliation_item_batch_id" ON dien_may."reconciliation_item" ("batch_id");
CREATE INDEX "ix_reconciliation_item_receipt_id" ON dien_may."reconciliation_item" ("receipt_id");
CREATE INDEX "ix_reconciliation_item_refund_attempt_id" ON dien_may."reconciliation_item" ("refund_attempt_id");
CREATE INDEX "ix_reconciliation_item_resolved_by" ON dien_may."reconciliation_item" ("resolved_by");
CREATE INDEX "ix_invoice_adjustment_of_id" ON dien_may."invoice" ("adjustment_of_id");
CREATE INDEX "ix_invoice_order_id" ON dien_may."invoice" ("order_id");
CREATE INDEX "ix_invoice_line_invoice_id" ON dien_may."invoice_line" ("invoice_id");
CREATE INDEX "ix_invoice_line_order_line_id" ON dien_may."invoice_line" ("order_line_id");
CREATE INDEX "ix_funding_slice_order_line_id_state" ON dien_may."funding_slice" ("order_line_id", "state");
CREATE INDEX "ix_funding_slice_receipt_id_state" ON dien_may."funding_slice" ("receipt_id", "state");
CREATE INDEX "ix_funding_slice_case_item_id" ON dien_may."funding_slice" ("case_item_id");
CREATE INDEX "ix_funding_slice_parent_slice_id" ON dien_may."funding_slice" ("parent_slice_id");
CREATE INDEX "ix_order_adjustment_order_id_state_direction" ON dien_may."order_adjustment" ("order_id", "state", "direction");
CREATE INDEX "ix_order_adjustment_case_id" ON dien_may."order_adjustment" ("case_id");
CREATE INDEX "ix_order_adjustment_cause_document_id" ON dien_may."order_adjustment" ("cause_document_id");
CREATE INDEX "ix_order_adjustment_line_adjustment_id" ON dien_may."order_adjustment_line" ("adjustment_id");
CREATE INDEX "ix_order_adjustment_line_case_resolution_id" ON dien_may."order_adjustment_line" ("case_resolution_id");
CREATE INDEX "ix_order_adjustment_line_order_line_id" ON dien_may."order_adjustment_line" ("order_line_id");
CREATE INDEX "ix_funding_slice_event_actor_id" ON dien_may."funding_slice_event" ("actor_id");
CREATE INDEX "ix_funding_slice_event_slice_id" ON dien_may."funding_slice_event" ("slice_id");
CREATE INDEX "ix_funding_slice_event_source_document_id" ON dien_may."funding_slice_event" ("source_document_id");
CREATE INDEX "ix_refund_request_case_id" ON dien_may."refund_request" ("case_id");
CREATE INDEX "ix_refund_request_cause_document_id" ON dien_may."refund_request" ("cause_document_id");
CREATE INDEX "ix_refund_request_receipt_id" ON dien_may."refund_request" ("receipt_id");
CREATE INDEX "ix_refund_slice_slice_id" ON dien_may."refund_slice" ("slice_id");
CREATE INDEX "ix_refund_attempt_provider_id" ON dien_may."refund_attempt" ("provider_id");
CREATE INDEX "ix_exchange_credit_return_case_id" ON dien_may."exchange_credit" ("return_case_id");
CREATE INDEX "ix_exchange_credit_target_order_id" ON dien_may."exchange_credit" ("target_order_id");
CREATE INDEX "ix_exchange_credit_line_credit_id" ON dien_may."exchange_credit_line" ("credit_id");
CREATE INDEX "ix_exchange_credit_line_source_slice_id" ON dien_may."exchange_credit_line" ("source_slice_id");
CREATE INDEX "ix_exchange_credit_line_target_order_line_id" ON dien_may."exchange_credit_line" ("target_order_line_id");
CREATE INDEX "ix_after_sales_case_customer_id" ON dien_may."after_sales_case" ("customer_id");
CREATE INDEX "ix_after_sales_case_order_id" ON dien_may."after_sales_case" ("order_id");
CREATE INDEX "ix_after_sales_case_item_case_id" ON dien_may."after_sales_case_item" ("case_id");
CREATE INDEX "ix_after_sales_case_item_device_id" ON dien_may."after_sales_case_item" ("device_id");
CREATE INDEX "ix_after_sales_case_item_order_line_id" ON dien_may."after_sales_case_item" ("order_line_id");
CREATE INDEX "ix_after_sales_case_item_policy_version_id" ON dien_may."after_sales_case_item" ("policy_version_id");
CREATE INDEX "ix_after_sales_case_item_sku_id" ON dien_may."after_sales_case_item" ("sku_id");
CREATE INDEX "ix_case_resolution_approval_request_id" ON dien_may."case_resolution" ("approval_request_id");
CREATE INDEX "ix_warranty_job_assigned_employee_id" ON dien_may."warranty_job" ("assigned_employee_id");
CREATE INDEX "ix_warranty_job_case_item_id" ON dien_may."warranty_job" ("case_item_id");
CREATE INDEX "ix_warranty_job_quote_order_line_id" ON dien_may."warranty_job" ("quote_order_line_id");
CREATE INDEX "ix_warranty_job_service_supplier_id" ON dien_may."warranty_job" ("service_supplier_id");
CREATE INDEX "ix_case_event_actor_id" ON dien_may."case_event" ("actor_id");
CREATE INDEX "ix_case_event_case_id" ON dien_may."case_event" ("case_id");
CREATE INDEX "ix_case_event_case_item_id" ON dien_may."case_event" ("case_item_id");
CREATE INDEX "ix_case_event_custodian_employee_id" ON dien_may."case_event" ("custodian_employee_id");
CREATE INDEX "ix_case_event_custodian_supplier_id" ON dien_may."case_event" ("custodian_supplier_id");
CREATE INDEX "ix_case_event_evidence_file_id" ON dien_may."case_event" ("evidence_file_id");
CREATE INDEX "ix_business_document_store_id_business_at" ON dien_may."business_document" ("store_id", "business_at");
CREATE INDEX "ix_business_document_created_by" ON dien_may."business_document" ("created_by");
CREATE INDEX "ix_policy_version_approved_by" ON dien_may."policy_version" ("approved_by");
CREATE INDEX "ix_approval_request_document_id" ON dien_may."approval_request" ("document_id");
CREATE INDEX "ix_approval_request_policy_version_id" ON dien_may."approval_request" ("policy_version_id");
CREATE INDEX "ix_approval_request_requested_by" ON dien_may."approval_request" ("requested_by");
CREATE INDEX "ix_approval_decision_assignment_id" ON dien_may."approval_decision" ("assignment_id");
CREATE INDEX "ix_approval_decision_decided_by" ON dien_may."approval_decision" ("decided_by");
CREATE INDEX "ix_document_attachment_attached_by" ON dien_may."document_attachment" ("attached_by");
CREATE INDEX "ix_document_attachment_document_id" ON dien_may."document_attachment" ("document_id");
CREATE INDEX "ix_document_attachment_file_id" ON dien_may."document_attachment" ("file_id");
CREATE INDEX "ix_audit_event_document_id_occurred_at" ON dien_may."audit_event" ("document_id", "occurred_at");
CREATE INDEX "ix_audit_event_actor_id" ON dien_may."audit_event" ("actor_id");
CREATE INDEX "ix_audit_event_correlation_id" ON dien_may."audit_event" ("correlation_id");
CREATE INDEX "ix_outbox_event_document_id_aggregate_version" ON dien_may."outbox_event" ("document_id", "aggregate_version");
CREATE INDEX "ix_outbox_event_published_at_retry_count" ON dien_may."outbox_event" ("published_at", "retry_count");
CREATE INDEX "ix_inbox_event_result_received_at" ON dien_may."inbox_event" ("result", "received_at");
CREATE INDEX "ix_idempotency_request_state_expires_at" ON dien_may."idempotency_request" ("state", "expires_at");
CREATE INDEX "ix_idempotency_request_document_id" ON dien_may."idempotency_request" ("document_id");
CREATE INDEX "ix_notification_state_retry_count" ON dien_may."notification" ("state", "retry_count");
CREATE INDEX "ix_notification_customer_id" ON dien_may."notification" ("customer_id");
CREATE INDEX "ix_import_batch_created_by" ON dien_may."import_batch" ("created_by");
CREATE INDEX "ix_import_batch_file_id" ON dien_may."import_batch" ("file_id");
CREATE INDEX "ix_import_batch_result_report_file_id" ON dien_may."import_batch" ("result_report_file_id");
CREATE INDEX "ix_content_page_policy_version_id" ON dien_may."content_page" ("policy_version_id");

-- Hoàn tất toàn bộ 117 bảng. Các truy vấn kiểm kê dưới đây chỉ đọc.
COMMIT;

-- Kiểm kê sau khi chạy (không thay đổi dữ liệu):
SELECT count(*) AS so_bang FROM information_schema.tables
 WHERE table_schema = 'dien_may' AND table_type = 'BASE TABLE'; -- 117
SELECT count(*) AS so_cot FROM information_schema.columns
 WHERE table_schema = 'dien_may'; -- 813
SELECT contype, count(*) AS so_rang_buoc
 FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
 WHERE n.nspname = 'dien_may' GROUP BY contype ORDER BY contype;
-- contype f = 282; p = 117. u = UNIQUE thông thường, c = CHECK.
-- Các unique partial nằm trong pg_indexes, không nằm trong contype u.
