package com.dienmay.config;

import com.dienmay.common.ApiResponseWriter;
import com.dienmay.common.ErrorCode;
import com.dienmay.ratelimit.RateLimitFilter;
import com.dienmay.ratelimit.RateLimitProperties;
import com.dienmay.security.AppUserDetailsService;
import com.dienmay.security.JwtAuthenticationFilter;
import com.dienmay.security.JwtProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Chuỗi filter: JwtAuthenticationFilter (xác định người dùng) → RateLimitFilter (giới hạn
 * tần suất theo người dùng/IP) → phân quyền → controller.
 *
 * Phân quyền:
 * - /api/auth/login, Swagger, H2 console: không cần đăng nhập.
 * - Mọi API GET: chỉ cần đăng nhập (ADMIN, WAREHOUSE, SALES đều xem được).
 * - Ghi danh mục/hãng/sản phẩm/SKU: ADMIN. Ghi thiết bị IMEI: ADMIN hoặc WAREHOUSE
 *   (khai báo bằng @PreAuthorize trên từng controller).
 */
@Configuration
@EnableMethodSecurity
@EnableConfigurationProperties({JwtProperties.class, RateLimitProperties.class})
public class SecurityConfig {

    @Bean
    public RateLimitFilter rateLimitFilter(RateLimitProperties props, ApiResponseWriter writer) {
        return new RateLimitFilter(props, writer);
    }

    /** Filter là bean nên Spring Boot sẽ tự đăng ký thêm vào servlet container; tắt để không chạy 2 lần. */
    @Bean
    public FilterRegistrationBean<RateLimitFilter> disableRateLimitAutoRegistration(RateLimitFilter filter) {
        FilterRegistrationBean<RateLimitFilter> reg = new FilterRegistrationBean<>(filter);
        reg.setEnabled(false);
        return reg;
    }

    @Bean
    public FilterRegistrationBean<JwtAuthenticationFilter> disableJwtAutoRegistration(JwtAuthenticationFilter filter) {
        FilterRegistrationBean<JwtAuthenticationFilter> reg = new FilterRegistrationBean<>(filter);
        reg.setEnabled(false);
        return reg;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http, JwtAuthenticationFilter jwtFilter,
                                           RateLimitFilter rateLimitFilter, ApiResponseWriter writer) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> { })
                .headers(h -> h.frameOptions(f -> f.sameOrigin())) // cho H2 console
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.POST, "/api/auth/login").permitAll()
                        .requestMatchers("/swagger-ui.html", "/swagger-ui/**", "/v3/api-docs/**").permitAll()
                        .requestMatchers("/h2-console/**").permitAll()
                        .requestMatchers("/error").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((req, res, e) ->
                                writer.writeError(res, ErrorCode.UNAUTHORIZED, null, req.getRequestURI()))
                        .accessDeniedHandler((req, res, e) ->
                                writer.writeError(res, ErrorCode.FORBIDDEN, null, req.getRequestURI())))
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterAfter(rateLimitFilter, JwtAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public AuthenticationManager authenticationManager(AppUserDetailsService uds, PasswordEncoder encoder) {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider();
        provider.setUserDetailsService(uds);
        provider.setPasswordEncoder(encoder);
        return new ProviderManager(provider);
    }
}
