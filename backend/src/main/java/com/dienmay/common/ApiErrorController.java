package com.dienmay.common;

import io.swagger.v3.oas.annotations.Hidden;
import jakarta.servlet.RequestDispatcher;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.boot.web.servlet.error.ErrorController;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Thay thế trang lỗi mặc định "/error" của Spring Boot (Whitelabel) cho những lỗi xảy ra
 * ngoài controller, ví dụ exception trong filter. Nhờ vậy client luôn nhận ApiResponse.
 */
@Hidden
@RestController
public class ApiErrorController implements ErrorController {

    @RequestMapping("/error")
    public ResponseEntity<ApiResponse<Void>> error(HttpServletRequest req) {
        Object statusAttr = req.getAttribute(RequestDispatcher.ERROR_STATUS_CODE);
        Object uriAttr = req.getAttribute(RequestDispatcher.ERROR_REQUEST_URI);
        int status = statusAttr instanceof Integer i ? i : 500;
        String path = uriAttr != null ? uriAttr.toString() : req.getRequestURI();
        ErrorCode code = switch (status) {
            case 400 -> ErrorCode.BAD_REQUEST;
            case 401 -> ErrorCode.UNAUTHORIZED;
            case 403 -> ErrorCode.FORBIDDEN;
            case 404 -> ErrorCode.ENDPOINT_NOT_FOUND;
            case 405 -> ErrorCode.METHOD_NOT_ALLOWED;
            case 415 -> ErrorCode.UNSUPPORTED_MEDIA_TYPE;
            case 429 -> ErrorCode.TOO_MANY_REQUESTS;
            default -> ErrorCode.INTERNAL_ERROR;
        };
        return ResponseEntity.status(code.getStatus()).body(ApiResponse.error(code, path));
    }
}
