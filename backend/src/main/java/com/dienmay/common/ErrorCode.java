package com.dienmay.common;

import org.springframework.http.HttpStatus;

/**
 * Mã lỗi nghiệp vụ dùng chung. Frontend nên dựa vào "code" (ổn định) thay vì "message"
 * (có thể đổi câu chữ). Mỗi mã gắn với một HTTP status cố định.
 */
public enum ErrorCode {
    BAD_REQUEST(HttpStatus.BAD_REQUEST, "Yêu cầu không hợp lệ"),
    VALIDATION_ERROR(HttpStatus.BAD_REQUEST, "Dữ liệu không hợp lệ"),
    MALFORMED_REQUEST(HttpStatus.BAD_REQUEST, "Body JSON sai định dạng hoặc giá trị enum không hợp lệ"),
    BUSINESS_RULE_VIOLATION(HttpStatus.BAD_REQUEST, "Vi phạm quy tắc nghiệp vụ"),
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "Chưa đăng nhập hoặc token không hợp lệ/hết hạn"),
    INVALID_CREDENTIALS(HttpStatus.UNAUTHORIZED, "Sai tên đăng nhập hoặc mật khẩu"),
    ACCOUNT_LOCKED(HttpStatus.FORBIDDEN, "Tài khoản đã bị khóa hoặc vô hiệu hóa"),
    FORBIDDEN(HttpStatus.FORBIDDEN, "Bạn không có quyền thực hiện thao tác này"),
    RESOURCE_NOT_FOUND(HttpStatus.NOT_FOUND, "Không tìm thấy dữ liệu"),
    ENDPOINT_NOT_FOUND(HttpStatus.NOT_FOUND, "Không tìm thấy API"),
    METHOD_NOT_ALLOWED(HttpStatus.METHOD_NOT_ALLOWED, "Phương thức HTTP không được hỗ trợ"),
    DUPLICATE_RESOURCE(HttpStatus.CONFLICT, "Dữ liệu đã tồn tại"),
    CONFLICT(HttpStatus.CONFLICT, "Xung đột dữ liệu"),
    DATA_INTEGRITY_VIOLATION(HttpStatus.CONFLICT,
            "Dữ liệu vi phạm ràng buộc của cơ sở dữ liệu (trùng mã hoặc đang được tham chiếu)"),
    UNSUPPORTED_MEDIA_TYPE(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Content-Type không được hỗ trợ, hãy dùng application/json"),
    TOO_MANY_REQUESTS(HttpStatus.TOO_MANY_REQUESTS, "Bạn gửi quá nhiều yêu cầu, vui lòng thử lại sau"),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "Lỗi hệ thống, vui lòng thử lại sau");

    private final HttpStatus status;
    private final String defaultMessage;

    ErrorCode(HttpStatus status, String defaultMessage) {
        this.status = status;
        this.defaultMessage = defaultMessage;
    }

    public HttpStatus getStatus() {
        return status;
    }

    public String getDefaultMessage() {
        return defaultMessage;
    }
}
