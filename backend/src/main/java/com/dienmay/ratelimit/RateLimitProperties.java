package com.dienmay.ratelimit;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Cấu hình trong application.yml, nhóm app.rate-limit.
 * capacity = số yêu cầu tối đa trong một period (VD: 5 lần / 1m).
 */
@ConfigurationProperties(prefix = "app.rate-limit")
public record RateLimitProperties(boolean enabled, Limit login, Limit api) {

    public record Limit(long capacity, Duration period) {
    }
}
