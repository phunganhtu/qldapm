package com.dienmay.common;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;

/**
 * Ghi ApiResponse lỗi trực tiếp ra HttpServletResponse. Dùng ở những chỗ chạy TRƯỚC
 * controller (filter rate limit, entry point của Spring Security) nên @RestControllerAdvice
 * không bắt được, để định dạng lỗi vẫn giống hệt phần còn lại.
 */
@Component
public class ApiResponseWriter {
    private final ObjectMapper objectMapper;

    public ApiResponseWriter(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public void writeError(HttpServletResponse res, ErrorCode code, String message, String path) throws IOException {
        if (res.isCommitted()) {
            return;
        }
        res.setStatus(code.getStatus().value());
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(res.getOutputStream(), ApiResponse.error(code, message, path, null));
    }
}
