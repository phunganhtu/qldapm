package com.dienmay.security;

import com.dienmay.domain.AccountStatus;
import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.UserAccount;
import com.dienmay.repository.UserAccountRepository;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Nạp tài khoản từ bảng user_account; vai trò đang ACTIVE thành ROLE_xxx. */
@Service
public class AppUserDetailsService implements UserDetailsService {
    private final UserAccountRepository users;

    public AppUserDetailsService(UserAccountRepository users) {
        this.users = users;
    }

    @Override
    @Transactional(readOnly = true)
    public UserDetails loadUserByUsername(String username) {
        UserAccount account = users.findByLoginKeyIgnoreCase(username)
                .orElseThrow(() -> new UsernameNotFoundException("Không tìm thấy tài khoản"));
        String[] roles = account.getRoles().stream()
                .filter(r -> r.getStatus() == ActiveStatus.ACTIVE)
                .map(r -> r.getCode())
                .toArray(String[]::new);
        return User.withUsername(account.getLoginKey())
                .password(account.getPasswordHash())
                .roles(roles)
                .accountLocked(account.getStatus() == AccountStatus.LOCKED)
                .disabled(account.getStatus() == AccountStatus.DISABLED)
                .build();
    }
}
