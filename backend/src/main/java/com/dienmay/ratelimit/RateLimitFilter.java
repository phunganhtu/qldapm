package com.dienmay.ratelimit;

import com.dienmay.common.ApiResponseWriter;
import com.dienmay.common.ErrorCode;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Bucket;
import io.github.bucket4j.ConsumptionProbe;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Duration;
import java.util.concurrent.TimeUnit;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Giới hạn tần suất gọi API bằng thuật toán token bucket (Bucket4j).
 *
 * <ul>
 *   <li>POST /api/auth/login: tính theo IP (chưa biết người dùng là ai).</li>
 *   <li>Các API /api/** khác: tính theo tài khoản nếu đã đăng nhập, ngược lại theo IP.</li>
 * </ul>
 * Mỗi phản hồi có header X-RateLimit-Limit và X-RateLimit-Remaining. Khi vượt giới hạn trả
 * 429 TOO_MANY_REQUESTS kèm header Retry-After (giây).
 *
 * Bucket lưu trong bộ nhớ, nên chỉ đúng khi chạy MỘT instance. Nếu chạy nhiều instance phải
 * chuyển sang Bucket4j + Redis để các máy dùng chung bộ đếm.
 *
 * Filter được gắn vào chuỗi Spring Security ngay SAU JwtAuthenticationFilter (xem SecurityConfig)
 * để đã biết người dùng; không đăng ký @Component để tránh chạy hai lần.
 */
public class RateLimitFilter extends OncePerRequestFilter {
    private static final String LOGIN_PATH = "/api/auth/login";

    private final RateLimitProperties props;
    private final ApiResponseWriter writer;
    private final Cache<String, Bucket> buckets = Caffeine.newBuilder()
            .expireAfterAccess(Duration.ofMinutes(30))
            .maximumSize(100_000)
            .build();

    public RateLimitFilter(RateLimitProperties props, ApiResponseWriter writer) {
        this.props = props;
        this.writer = writer;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !props.enabled() || !request.getRequestURI().startsWith("/api/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        boolean isLogin = HttpMethod.POST.matches(request.getMethod()) && LOGIN_PATH.equals(request.getRequestURI());
        RateLimitProperties.Limit limit = isLogin ? props.login() : props.api();
        String key = (isLogin ? "login:" : "api:") + clientKey(request, isLogin);

        Bucket bucket = buckets.get(key, k -> newBucket(limit));
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);
        response.setHeader("X-RateLimit-Limit", String.valueOf(limit.capacity()));
        response.setHeader("X-RateLimit-Remaining", String.valueOf(probe.getRemainingTokens()));

        if (probe.isConsumed()) {
            chain.doFilter(request, response);
            return;
        }
        long retryAfter = Math.max(1, TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill()) + 1);
        response.setHeader("Retry-After", String.valueOf(retryAfter));
        String message = isLogin
                ? "Thử đăng nhập quá nhiều lần, vui lòng thử lại sau " + retryAfter + " giây"
                : "Bạn gửi quá nhiều yêu cầu, vui lòng thử lại sau " + retryAfter + " giây";
        writer.writeError(response, ErrorCode.TOO_MANY_REQUESTS, message, request.getRequestURI());
    }

    private static Bucket newBucket(RateLimitProperties.Limit limit) {
        return Bucket.builder()
                .addLimit(Bandwidth.builder()
                        .capacity(limit.capacity())
                        .refillGreedy(limit.capacity(), limit.period())
                        .build())
                .build();
    }

    private static String clientKey(HttpServletRequest request, boolean isLogin) {
        if (!isLogin) {
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            if (auth != null && auth.isAuthenticated() && !(auth instanceof AnonymousAuthenticationToken)) {
                return "user:" + auth.getName();
            }
        }
        // Dùng địa chỉ kết nối thực. Không tin header X-Forwarded-For vì client tự sửa được;
        // nếu chạy sau reverse proxy thì cấu hình server.forward-headers-strategy=native.
        return "ip:" + request.getRemoteAddr();
    }
}
