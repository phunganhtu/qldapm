package com.dienmay.repository;

import com.dienmay.domain.UserAccount;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserAccountRepository extends JpaRepository<UserAccount, UUID> {
    Optional<UserAccount> findByLoginKeyIgnoreCase(String loginKey);
}
