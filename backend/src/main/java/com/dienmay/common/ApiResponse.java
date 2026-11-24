package com.dienmay.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import java.time.OffsetDateTime;
import java.util.List;
import org.springframework.http.HttpStatus;

/**
 * Định dạng phản hồi thống nhất cho MỌI API, kể cả khi lỗi.
 *
 * <pre>
 * Thành công: {"success":true,"status":200,"code":"SUCCESS","message":"...","data":{...},"timestamp":"..."}
 * Lỗi:       {"success":false,"status":409,"code":"DUPLICATE_RESOURCE","message":"...",
 *             "errors":[{"field":"code","message":"..."}],"path":"/api/brands","timestamp":"..."}
 * </pre>
 *
 * @param success   true nếu xử lý thành công
 * @param status    HTTP status (lặp lại trong body cho client tiện đọc)
 * @param code      "SUCCESS" hoặc tên một {@link ErrorCode}
 * @param message   thông báo cho người dùng
 * @param data      dữ liệu trả về (chỉ có khi thành công)
 * @param errors    chi tiết lỗi theo trường/dòng (chỉ có khi lỗi kiểm tra dữ liệu)
 * @param path      đường dẫn gây lỗi (chỉ có khi lỗi)
 * @param timestamp thời điểm phản hồi
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({"success", "status", "code", "message", "data", "errors", "path", "timestamp"})
public record ApiResponse<T>(
        boolean success,
        int status,
        String code,
        String message,
        T data,
        List<FieldErrorDetail> errors,
        String path,
        OffsetDateTime timestamp) {

    public static final String SUCCESS_CODE = "SUCCESS";

    /** Chi tiết một lỗi: field có thể là tên trường ("code") hoặc vị trí ("serials[2]"). */
    public record FieldErrorDetail(String field, String message) {
    }

    public static <T> ApiResponse<T> ok(T data) {
        return ok(data, "Thành công");
    }

    public static <T> ApiResponse<T> ok(T data, String message) {
        return new ApiResponse<>(true, HttpStatus.OK.value(), SUCCESS_CODE, message, data, null, null,
                OffsetDateTime.now());
    }

    public static <T> ApiResponse<T> created(T data, String message) {
        return new ApiResponse<>(true, HttpStatus.CREATED.value(), SUCCESS_CODE, message, data, null, null,
                OffsetDateTime.now());
    }

    public static ApiResponse<Void> error(ErrorCode code, String message, String path,
                                          List<FieldErrorDetail> errors) {
        return new ApiResponse<>(false, code.getStatus().value(), code.name(),
                message == null ? code.getDefaultMessage() : message, null,
                errors == null || errors.isEmpty() ? null : errors, path, OffsetDateTime.now());
    }

    public static ApiResponse<Void> error(ErrorCode code, String path) {
        return error(code, null, path, null);
    }
}
