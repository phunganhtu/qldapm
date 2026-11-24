package com.dienmay.auth;

import com.dienmay.common.ApiResponse;
import com.dienmay.security.JwtService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.List;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
@Tag(name = "0. Đăng nhập")
public class AuthController {
    private final AuthenticationManager authManager;
    private final JwtService jwtService;

    public AuthController(AuthenticationManager authManager, JwtService jwtService) {
        this.authManager = authManager;
        this.jwtService = jwtService;
    }

    public record LoginRequest(@NotBlank(message = "Bắt buộc nhập tên đăng nhập") String username,
                               @NotBlank(message = "Bắt buộc nhập mật khẩu") String password) {
    }

    public record LoginResponse(String accessToken, String tokenType, Instant expiresAt, String username,
                                List<String> roles) {
    }

    public record MeResponse(String username, List<String> roles) {
    }

    @PostMapping("/login")
    @Operation(summary = "Đăng nhập, nhận JWT (giới hạn số lần thử theo IP)")
    public ApiResponse<LoginResponse> login(@Valid @RequestBody LoginRequest req) {
        Authentication auth = authManager.authenticate(
                new UsernamePasswordAuthenticationToken(req.username().trim(), req.password()));
        UserDetails user = (UserDetails) auth.getPrincipal();
        JwtService.IssuedToken token = jwtService.issue(user);
        return ApiResponse.ok(new LoginResponse(token.token(), "Bearer", token.expiresAt(), user.getUsername(),
                roles(user)), "Đăng nhập thành công");
    }

    @GetMapping("/me")
    @Operation(summary = "Thông tin tài khoản đang đăng nhập")
    public ApiResponse<MeResponse> me(@AuthenticationPrincipal UserDetails user) {
        return ApiResponse.ok(new MeResponse(user.getUsername(), roles(user)));
    }

    private static List<String> roles(UserDetails user) {
        return user.getAuthorities().stream().map(GrantedAuthority::getAuthority)
                .map(a -> a.replaceFirst("^ROLE_", "")).sorted().toList();
    }
}
