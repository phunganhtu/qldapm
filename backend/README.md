# Backend demo — Danh mục sản phẩm siêu thị điện máy

Spring Boot 3.4 · Java 17 · Spring Security + JWT · Spring Data JPA · PostgreSQL (hoặc H2 để chạy nhanh) · Swagger UI.

Phạm vi demo: CRUD cho **nhóm hàng, hãng, sản phẩm, SKU** và **thiết bị Serial/IMEI**. Các bảng được trích từ `SRSnDB/postgres.sql` (ERD v1.1, nhóm M01, M02, M04).

## 1. Chạy nhanh (không cần cài database)

Dùng H2 chạy trong RAM. Dữ liệu mất khi tắt ứng dụng.

```powershell
cd backend
.\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=h2"
```

## 2. Chạy với PostgreSQL

1. Tạo database tên `dien_may`.
2. Chạy ứng dụng. Ứng dụng tự tạo schema `dien_may` và các bảng (file `src/main/resources/db/schema-postgres.sql`) nếu chưa có.

```powershell
cd backend
$env:DB_URL="jdbc:postgresql://localhost:5432/dien_may"; $env:DB_USERNAME="postgres"; $env:DB_PASSWORD="mat_khau_cua_ban"
.\mvnw.cmd spring-boot:run
```

Nếu database đã chạy `postgres.sql` đầy đủ (117 bảng), ứng dụng dùng luôn các bảng đó và chỉ tạo thêm bảng `user_account_role`.

## 3. Mở Swagger để demo

- Swagger UI: http://localhost:8080/swagger-ui.html
- H2 console (chỉ profile h2): http://localhost:8080/h2-console, JDBC URL `jdbc:h2:mem:dienmay`, user `sa`, để trống mật khẩu.

Các bước demo:

1. Gọi `POST /api/auth/login` với một tài khoản ở bảng dưới, rồi copy `accessToken`.
2. Bấm **Authorize** (góc phải), dán token vào, bấm Authorize.
3. Gọi các API.

## 4. Tài khoản mẫu (chỉ dùng cho demo)

| Tài khoản | Mật khẩu | Vai trò | Quyền |
|---|---|---|---|
| admin | Admin@123 | ADMIN | Toàn quyền |
| thukho | Thukho@123 | WAREHOUSE | Xem tất cả; thêm/sửa/xóa thiết bị IMEI |
| banhang | Banhang@123 | SALES | Chỉ xem |
| khoa | Khoa@123 | SALES | Tài khoản bị khóa, đăng nhập bị từ chối |

Ứng dụng tự tạo tài khoản và dữ liệu mẫu (Sony, Samsung, LG, Apple; Tivi, Điện thoại, Tủ lạnh...) khi bảng còn trống. Phần này nằm ở `config/DataSeeder.java`; muốn tắt thì đặt `app.seed.enabled=false`.

## 5. Danh sách API

Tất cả API (trừ đăng nhập) cần header `Authorization: Bearer <token>`.

| Nhóm | Phương thức & đường dẫn | Quyền ghi |
|---|---|---|
| Đăng nhập | `POST /api/auth/login`, `GET /api/auth/me` | — |
| Nhóm hàng | `GET/POST /api/categories`, `GET/PUT/DELETE /api/categories/{id}` | ADMIN |
| Hãng | `GET/POST /api/brands`, `GET/PUT/DELETE /api/brands/{id}` | ADMIN |
| Sản phẩm | `GET /api/products?q=&categoryId=&brandId=&status=&page=&size=&sort=`, `POST`, `GET/PUT/DELETE /api/products/{id}` | ADMIN |
| SKU | `GET/POST /api/products/{productId}/skus`, `GET/PUT/DELETE /api/skus/{id}` | ADMIN |
| Thiết bị | `GET/POST /api/skus/{skuId}/devices`, `POST /api/skus/{skuId}/devices/batch`, `GET /api/devices/lookup?serial=`, `GET/PUT/DELETE /api/devices/{id}` | ADMIN, WAREHOUSE |

## 6. Định dạng phản hồi thống nhất

Mọi API, kể cả khi lỗi 401, 403, 404, 429, 500, đều trả cùng một khung `ApiResponse` (`common/ApiResponse.java`).

Thành công:
```json
{
  "success": true,
  "status": 201,
  "code": "SUCCESS",
  "message": "Đã thêm hãng",
  "data": { "id": "…", "code": "TCL", "name": "TCL", "status": "ACTIVE" },
  "timestamp": "2026-11-24T18:03:13.54+07:00"
}
```

Lỗi (`errors` chỉ có khi có lỗi theo từng trường hoặc từng dòng):
```json
{
  "success": false,
  "status": 409,
  "code": "DUPLICATE_RESOURCE",
  "message": "Từ chối cả lô vì có 2 serial lỗi",
  "errors": [
    { "field": "serials[2]", "message": "'111' bị quét trùng trong cùng lô" },
    { "field": "serials[3]", "message": "'356938035643817' đã tồn tại trong hệ thống" }
  ],
  "path": "/api/skus/…/devices/batch",
  "timestamp": "…"
}
```

- Danh sách có phân trang: `data` là `{ content, page, size, totalElements, totalPages }`.
- Xóa thành công: trả 200, không có `data`, chỉ có `message`.

Lỗi được bắt ở 3 nơi, nhưng tất cả đều trả cùng định dạng trên:

| Nơi xử lý | Bắt lỗi gì |
|---|---|
| `GlobalExceptionHandler` (`@RestControllerAdvice`) | Lỗi trong controller/service: nghiệp vụ, kiểm tra dữ liệu, JSON sai, 404, 405, 415, ràng buộc DB, lỗi không lường trước (500, không lộ stack trace) |
| `SecurityConfig` + `ApiResponseWriter` | 401 chưa đăng nhập / token sai, 403 thiếu quyền ở tầng filter |
| `ApiErrorController` (thay trang `/error` mặc định) | Lỗi xảy ra ngoài controller, ví dụ URL bị tường lửa của Spring Security chặn |

### Bảng mã lỗi (`common/ErrorCode.java`)

Frontend nên dựa vào `code`, không dựa vào `message`.

| code | HTTP | Khi nào |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Thiếu trường, sai kiểu tham số, thiếu tham số (xem `errors`) |
| `MALFORMED_REQUEST` | 400 | Body JSON sai cú pháp hoặc enum không hợp lệ |
| `BUSINESS_RULE_VIOLATION` | 400 | Vi phạm quy tắc nghiệp vụ (VD: công bố sản phẩm chưa có SKU) |
| `BAD_REQUEST` | 400 | Yêu cầu bị chặn trước khi tới controller |
| `UNAUTHORIZED` | 401 | Thiếu token / token sai / hết hạn |
| `INVALID_CREDENTIALS` | 401 | Sai tên đăng nhập hoặc mật khẩu |
| `ACCOUNT_LOCKED` | 403 | Tài khoản bị khóa hoặc vô hiệu hóa |
| `FORBIDDEN` | 403 | Đã đăng nhập nhưng không đủ quyền |
| `RESOURCE_NOT_FOUND` | 404 | Không tìm thấy bản ghi theo id/serial |
| `ENDPOINT_NOT_FOUND` | 404 | Gọi sai đường dẫn API |
| `METHOD_NOT_ALLOWED` | 405 | Sai phương thức HTTP |
| `DUPLICATE_RESOURCE` | 409 | Trùng mã, mã vạch, Serial/IMEI |
| `CONFLICT` | 409 | Trạng thái hiện tại không cho phép (VD: ngừng hãng còn sản phẩm) |
| `DATA_INTEGRITY_VIOLATION` | 409 | DB chặn vì ràng buộc (lưới an toàn) |
| `UNSUPPORTED_MEDIA_TYPE` | 415 | Content-Type không phải JSON |
| `TOO_MANY_REQUESTS` | 429 | Vượt giới hạn tần suất |
| `INTERNAL_ERROR` | 500 | Lỗi không lường trước (chi tiết chỉ ghi vào log) |

## 7. Giới hạn tần suất (rate limit)

Dùng thuật toán token bucket (thư viện Bucket4j), cài trong `ratelimit/RateLimitFilter.java`. Filter này chạy sau bước đọc JWT nên biết người gọi là ai.

| Loại request | Tính theo | Mặc định |
|---|---|---|
| `POST /api/auth/login` | IP | 5 lần / phút (chống dò mật khẩu) |
| Các API `/api/**` khác | Tài khoản (nếu đã đăng nhập), ngược lại theo IP | 100 lần / phút |

- Mỗi phản hồi `/api/**` có header `X-RateLimit-Limit` và `X-RateLimit-Remaining`.
- Khi vượt giới hạn: trả 429 `TOO_MANY_REQUESTS` kèm header `Retry-After` (số giây phải chờ).
- Token được nạp lại dần dần, không phải đợi hết cả phút. Ví dụ 100 lần/phút thì cứ khoảng 0,6 giây có thêm 1 lượt.
- Mỗi tài khoản có bộ đếm riêng: admin bị chặn thì thukho vẫn gọi được.

Cấu hình trong `application.yml` (nhóm `app.rate-limit`) hoặc qua biến môi trường. Muốn demo cho nhanh thì hạ giới hạn:
```powershell
.\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=h2" "-Dspring-boot.run.arguments=--app.rate-limit.api.capacity=10"
```
Đặt `RATE_LIMIT_ENABLED=false` để tắt hẳn.

Bộ đếm lưu trong RAM nên chỉ đúng khi chạy **một** instance. Nếu chạy nhiều instance phải chuyển sang Bucket4j + Redis.

## 8. Quy tắc nghiệp vụ có thể demo

| Tình huống | Kết quả | Căn cứ SRS |
|---|---|---|
| Không gửi token / token hết hạn | 401 | FR02 |
| `banhang` thêm hãng | 403 | FR02 (kiểm quyền ở máy chủ) |
| Đăng nhập `khoa` | 403, tài khoản bị khóa | FR01 |
| Thêm mã hãng/nhóm/sản phẩm/SKU/mã vạch trùng | 409 | uq_* trong ERD |
| Thêm IMEI `3569-3803-5643-809` khi đã có `356938035643809` | 409: serial được chuẩn hóa trước khi so trùng | REQ-KHO-02, FR16 |
| Nhập lô serial có một mã trùng | 409, từ chối **cả lô**, liệt kê từng mã lỗi | UC03 |
| Gắn serial cho SKU không quản lý serial | 400 | FR16 |
| Công bố (PUBLISHED) sản phẩm chưa có SKU đang hoạt động | 400 | FR05 |
| Ngừng nhóm hàng/hãng còn sản phẩm đang kinh doanh | 409 | Toàn vẹn dữ liệu |
| Chọn nhóm cha tạo vòng lặp | 400 | ck_category_not_self_parent |
| `DELETE` nhóm, hãng, SKU | Xóa mềm → `INACTIVE` | FR07 (không xóa cứng) |
| `DELETE` sản phẩm | → `DISCONTINUED`, toàn bộ SKU → `INACTIVE` | FR07 |
| `DELETE` thiết bị | Xóa cứng (sửa trường hợp quét nhầm) | — |

## 9. Cấu trúc mã nguồn

```
src/main/java/com/dienmay
├── auth/         Đăng nhập, phát JWT
├── security/     JwtService, JwtAuthenticationFilter, nạp tài khoản từ DB
├── config/       SecurityConfig (phân quyền), OpenApiConfig (Swagger), DataSeeder
├── domain/       Entity JPA + enum khớp CHECK trong postgres.sql
├── repository/   Spring Data JPA
├── catalog/      Nhóm hàng, hãng, sản phẩm, SKU (service + controller)
├── device/       Thiết bị Serial/IMEI
├── ratelimit/    Giới hạn tần suất (Bucket4j)
└── common/       ApiResponse, ErrorCode, xử lý lỗi tập trung, phân trang
```

## 10. Khác biệt so với ERD đầy đủ

- Phân quyền trong ERD dùng `user_role_assignment` + `access_scope` (theo cửa hàng/kho). Bản demo dùng bảng đơn giản `user_account_role(user_id, role_id)`.
- Bảng `device` không ánh xạ `origin_lot_id`, `current_position_id`, `owner_customer_id` (thuộc phân hệ kho và khách hàng chưa làm), nên các cột này để NULL.
- Khóa JWT mặc định trong `application.yml` chỉ dùng để demo. Khi triển khai thật, đặt biến môi trường `JWT_SECRET` (chuỗi Base64, tối thiểu 32 byte).
