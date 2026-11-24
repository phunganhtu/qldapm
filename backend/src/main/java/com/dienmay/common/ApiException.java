package com.dienmay.common;

import com.dienmay.common.ApiResponse.FieldErrorDetail;
import java.util.List;

/** Lỗi nghiệp vụ mang {@link ErrorCode}; GlobalExceptionHandler chuyển thành ApiResponse. */
public class ApiException extends RuntimeException {
    private final ErrorCode errorCode;
    private final List<FieldErrorDetail> details;

    public ApiException(ErrorCode errorCode, String message) {
        this(errorCode, message, List.of());
    }

    public ApiException(ErrorCode errorCode, String message, List<FieldErrorDetail> details) {
        super(message == null ? errorCode.getDefaultMessage() : message);
        this.errorCode = errorCode;
        this.details = details == null ? List.of() : List.copyOf(details);
    }

    public ErrorCode getErrorCode() {
        return errorCode;
    }

    public List<FieldErrorDetail> getDetails() {
        return details;
    }

    public static ApiException notFound(String what, Object id) {
        return new ApiException(ErrorCode.RESOURCE_NOT_FOUND, "Không tìm thấy " + what + ": " + id);
    }

    /** Trùng mã/khóa duy nhất (mã hãng, mã SKU, mã vạch, Serial/IMEI...). */
    public static ApiException duplicate(String message) {
        return new ApiException(ErrorCode.DUPLICATE_RESOURCE, message);
    }

    /** Trạng thái dữ liệu hiện tại không cho phép thao tác (VD: còn sản phẩm đang bán). */
    public static ApiException conflict(String message) {
        return new ApiException(ErrorCode.CONFLICT, message);
    }

    /** Yêu cầu hợp lệ về định dạng nhưng vi phạm quy tắc nghiệp vụ. */
    public static ApiException badRequest(String message) {
        return new ApiException(ErrorCode.BUSINESS_RULE_VIOLATION, message);
    }
}
