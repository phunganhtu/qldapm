-- ============================================================================
-- SCHEMA DEMO — trích từ SRSnDB/postgres.sql (ERD v1.1)
-- Gồm: category, brand, product, sku, device, user_account, role
--      + bảng đơn giản hóa user_account_role (thay cho user_role_assignment +
--        access_scope trong bản đầy đủ, vốn cần cửa hàng/kho/phạm vi).
-- Cột và CHECK giữ nguyên như bản đầy đủ; chỉ bỏ các FK trỏ tới bảng không có
-- trong demo (stock_lot, inventory_position, customer).
-- Dùng IF NOT EXISTS để chạy lại mỗi lần khởi động không lỗi. Nếu database đã
-- chạy postgres.sql đầy đủ, script chỉ tạo thêm bảng user_account_role.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS dien_may;

CREATE TABLE IF NOT EXISTS dien_may."category" (
    "category_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "parent_id" uuid,
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_category" PRIMARY KEY ("category_id"),
    CONSTRAINT "uq_category_code" UNIQUE ("code"),
    CONSTRAINT "ck_category_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT "ck_category_not_self_parent" CHECK (parent_id IS NULL OR parent_id <> category_id),
    CONSTRAINT "fk_category_parent_id" FOREIGN KEY ("parent_id") REFERENCES dien_may."category" ("category_id")
);

CREATE TABLE IF NOT EXISTS dien_may."brand" (
    "brand_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_brand" PRIMARY KEY ("brand_id"),
    CONSTRAINT "uq_brand_code" UNIQUE ("code"),
    CONSTRAINT "ck_brand_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);

CREATE TABLE IF NOT EXISTS dien_may."product" (
    "product_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "category_id" uuid NOT NULL,
    "brand_id" uuid NOT NULL,
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "description" text,
    "publication_status" varchar(40) NOT NULL,
    CONSTRAINT "pk_product" PRIMARY KEY ("product_id"),
    CONSTRAINT "uq_product_code" UNIQUE ("code"),
    CONSTRAINT "ck_product_publication_status_domain" CHECK ("publication_status" IN ('DRAFT', 'PUBLISHED', 'HIDDEN', 'DISCONTINUED')),
    CONSTRAINT "fk_product_category_id" FOREIGN KEY ("category_id") REFERENCES dien_may."category" ("category_id"),
    CONSTRAINT "fk_product_brand_id" FOREIGN KEY ("brand_id") REFERENCES dien_may."brand" ("brand_id")
);

CREATE TABLE IF NOT EXISTS dien_may."sku" (
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
    CONSTRAINT "ck_sku_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT "fk_sku_product_id" FOREIGN KEY ("product_id") REFERENCES dien_may."product" ("product_id")
);

CREATE TABLE IF NOT EXISTS dien_may."device" (
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
    CONSTRAINT "ck_device_customer_owner" CHECK ((ownership = 'CUSTOMER') = (owner_customer_id IS NOT NULL)),
    CONSTRAINT "fk_device_sku_id" FOREIGN KEY ("sku_id") REFERENCES dien_may."sku" ("sku_id")
);

CREATE TABLE IF NOT EXISTS dien_may."user_account" (
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

CREATE TABLE IF NOT EXISTS dien_may."role" (
    "role_id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "code" varchar(100) NOT NULL,
    "name" varchar(255) NOT NULL,
    "status" varchar(40) NOT NULL,
    CONSTRAINT "pk_role" PRIMARY KEY ("role_id"),
    CONSTRAINT "uq_role_code" UNIQUE ("code"),
    CONSTRAINT "ck_role_status_domain" CHECK ("status" IN ('ACTIVE', 'INACTIVE'))
);

-- Bảng đơn giản hóa riêng cho demo (không có trong ERD v1.1).
CREATE TABLE IF NOT EXISTS dien_may."user_account_role" (
    "user_id" uuid NOT NULL,
    "role_id" uuid NOT NULL,
    CONSTRAINT "pk_user_account_role" PRIMARY KEY ("user_id", "role_id"),
    CONSTRAINT "fk_user_account_role_user_id" FOREIGN KEY ("user_id") REFERENCES dien_may."user_account" ("user_id"),
    CONSTRAINT "fk_user_account_role_role_id" FOREIGN KEY ("role_id") REFERENCES dien_may."role" ("role_id")
);

CREATE INDEX IF NOT EXISTS "ix_product_category_id" ON dien_may."product" ("category_id");
CREATE INDEX IF NOT EXISTS "ix_product_brand_id" ON dien_may."product" ("brand_id");
CREATE INDEX IF NOT EXISTS "ix_sku_product_id" ON dien_may."sku" ("product_id");
CREATE INDEX IF NOT EXISTS "ix_device_sku_id" ON dien_may."device" ("sku_id");
