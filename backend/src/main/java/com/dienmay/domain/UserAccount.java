package com.dienmay.domain;

import jakarta.persistence.*;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

/** T005 user_account — tài khoản đăng nhập. Vai trò gán qua bảng demo user_account_role. */
@Entity
@Table(name = "user_account")
public class UserAccount {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "user_id")
    private UUID id;

    @Column(name = "login_key", nullable = false, unique = true, length = 255)
    private String loginKey;

    @Column(name = "password_hash", nullable = false, columnDefinition = "text")
    private String passwordHash;

    @Enumerated(EnumType.STRING)
    @Column(name = "account_kind", nullable = false, length = 40)
    private AccountKind accountKind = AccountKind.STAFF;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 40)
    private AccountStatus status = AccountStatus.ACTIVE;

    @ManyToMany(fetch = FetchType.EAGER)
    @JoinTable(name = "user_account_role",
            joinColumns = @JoinColumn(name = "user_id"),
            inverseJoinColumns = @JoinColumn(name = "role_id"))
    private Set<Role> roles = new HashSet<>();

    protected UserAccount() {
    }

    public UserAccount(String loginKey, String passwordHash) {
        this.loginKey = loginKey;
        this.passwordHash = passwordHash;
    }

    public UUID getId() { return id; }
    public String getLoginKey() { return loginKey; }
    public String getPasswordHash() { return passwordHash; }
    public AccountKind getAccountKind() { return accountKind; }
    public AccountStatus getStatus() { return status; }
    public void setStatus(AccountStatus status) { this.status = status; }
    public Set<Role> getRoles() { return roles; }
}
