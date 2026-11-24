package com.dienmay.common;

import com.dienmay.common.ApiResponse.FieldErrorDetail;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.AccountStatusException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * Bắt mọi exception phát sinh trong controller/service và trả về {@link ApiResponse} cùng
 * một định dạng. Lỗi không lường trước được ghi log đầy đủ nhưng chỉ trả thông báo chung,
 * không lộ stack trace hay câu SQL cho client.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    // ---------- Lỗi nghiệp vụ do service chủ động ném ----------

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiResponse<Void>> handleApi(ApiException ex, HttpServletRequest req) {
        return build(ex.getErrorCode(), ex.getMessage(), req, ex.getDetails());
    }

    // ---------- Lỗi dữ liệu đầu vào ----------

    /** @Valid trên @RequestBody không đạt. */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidation(MethodArgumentNotValidException ex, HttpServletRequest req) {
        List<FieldErrorDetail> errors = ex.getBindingResult().getFieldErrors().stream()
                .map(fe -> new FieldErrorDetail(fe.getField(), fe.getDefaultMessage()))
                .toList();
        return build(ErrorCode.VALIDATION_ERROR, null, req, errors);
    }

    /** Ràng buộc trên tham số đơn (@RequestParam, @PathVariable) không đạt. */
    @ExceptionHandler(HandlerMethodValidationException.class)
    public ResponseEntity<ApiResponse<Void>> handleMethodValidation(HandlerMethodValidationException ex,
                                                                    HttpServletRequest req) {
        List<FieldErrorDetail> errors = ex.getParameterValidationResults().stream()
                .flatMap(r -> r.getResolvableErrors().stream()
                        .map(e -> new FieldErrorDetail(r.getMethodParameter().getParameterName(), e.getDefaultMessage())))
                .toList();
        return build(ErrorCode.VALIDATION_ERROR, null, req, errors);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleConstraint(ConstraintViolationException ex, HttpServletRequest req) {
        List<FieldErrorDetail> errors = ex.getConstraintViolations().stream()
                .map(v -> new FieldErrorDetail(v.getPropertyPath().toString(), v.getMessage()))
                .toList();
        return build(ErrorCode.VALIDATION_ERROR, null, req, errors);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnreadable(HttpMessageNotReadableException ex, HttpServletRequest req) {
        return build(ErrorCode.MALFORMED_REQUEST, null, req, null);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ApiResponse<Void>> handleTypeMismatch(MethodArgumentTypeMismatchException ex,
                                                                HttpServletRequest req) {
        return build(ErrorCode.VALIDATION_ERROR, null, req,
                List.of(new FieldErrorDetail(ex.getName(), "Sai kiểu dữ liệu: '" + ex.getValue() + "'")));
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ApiResponse<Void>> handleMissingParam(MissingServletRequestParameterException ex,
                                                                HttpServletRequest req) {
        return build(ErrorCode.VALIDATION_ERROR, null, req,
                List.of(new FieldErrorDetail(ex.getParameterName(), "Bắt buộc truyền tham số này")));
    }

    // ---------- Lỗi HTTP / định tuyến ----------

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNoResource(NoResourceFoundException ex, HttpServletRequest req) {
        return build(ErrorCode.ENDPOINT_NOT_FOUND, null, req, null);
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiResponse<Void>> handleMethod(HttpRequestMethodNotSupportedException ex,
                                                          HttpServletRequest req) {
        return build(ErrorCode.METHOD_NOT_ALLOWED,
                "Phương thức " + ex.getMethod() + " không được hỗ trợ cho đường dẫn này", req, null);
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    public ResponseEntity<ApiResponse<Void>> handleMediaType(HttpMediaTypeNotSupportedException ex,
                                                             HttpServletRequest req) {
        return build(ErrorCode.UNSUPPORTED_MEDIA_TYPE, null, req, null);
    }

    // ---------- Lỗi xác thực / phân quyền ----------

    @ExceptionHandler(BadCredentialsException.class)
    public ResponseEntity<ApiResponse<Void>> handleBadCredentials(BadCredentialsException ex, HttpServletRequest req) {
        return build(ErrorCode.INVALID_CREDENTIALS, null, req, null);
    }

    /** LockedException, DisabledException, AccountExpiredException... */
    @ExceptionHandler(AccountStatusException.class)
    public ResponseEntity<ApiResponse<Void>> handleAccountStatus(AccountStatusException ex, HttpServletRequest req) {
        return build(ErrorCode.ACCOUNT_LOCKED, null, req, null);
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ApiResponse<Void>> handleAuth(AuthenticationException ex, HttpServletRequest req) {
        return build(ErrorCode.UNAUTHORIZED, null, req, null);
    }

    /** @PreAuthorize từ chối (người dùng đã đăng nhập nhưng thiếu vai trò). */
    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiResponse<Void>> handleDenied(AccessDeniedException ex, HttpServletRequest req) {
        return build(ErrorCode.FORBIDDEN, null, req, null);
    }

    // ---------- Lỗi cơ sở dữ liệu ----------

    /** Lưới an toàn khi ràng buộc DB (UNIQUE, FK, CHECK) chặn lại mà service chưa kiểm trước. */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleIntegrity(DataIntegrityViolationException ex, HttpServletRequest req) {
        log.warn("Vi phạm ràng buộc dữ liệu tại {}: {}", req.getRequestURI(), ex.getMostSpecificCause().getMessage());
        return build(ErrorCode.DATA_INTEGRITY_VIOLATION, null, req, null);
    }

    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<ApiResponse<Void>> handleOptimisticLock(OptimisticLockingFailureException ex,
                                                                  HttpServletRequest req) {
        return build(ErrorCode.CONFLICT, "Dữ liệu vừa được người khác cập nhật, hãy tải lại và thử lại", req, null);
    }

    // ---------- Lỗi không lường trước ----------

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception ex, HttpServletRequest req) {
        log.error("Lỗi không xử lý được tại {} {}", req.getMethod(), req.getRequestURI(), ex);
        return build(ErrorCode.INTERNAL_ERROR, null, req, null);
    }

    private ResponseEntity<ApiResponse<Void>> build(ErrorCode code, String message, HttpServletRequest req,
                                                    List<FieldErrorDetail> errors) {
        return ResponseEntity.status(code.getStatus())
                .body(ApiResponse.error(code, message, req.getRequestURI(), errors));
    }
}
