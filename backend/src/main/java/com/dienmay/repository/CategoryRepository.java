package com.dienmay.repository;

import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Category;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CategoryRepository extends JpaRepository<Category, UUID> {
    boolean existsByCodeIgnoreCase(String code);
    boolean existsByCodeIgnoreCaseAndIdNot(String code, UUID id);
    boolean existsByParentIdAndStatus(UUID parentId, ActiveStatus status);
    List<Category> findAllByOrderByCodeAsc();
    List<Category> findByStatusOrderByCodeAsc(ActiveStatus status);
}
