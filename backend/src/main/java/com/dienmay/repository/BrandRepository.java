package com.dienmay.repository;

import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Brand;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BrandRepository extends JpaRepository<Brand, UUID> {
    boolean existsByCodeIgnoreCase(String code);
    boolean existsByCodeIgnoreCaseAndIdNot(String code, UUID id);
    List<Brand> findAllByOrderByNameAsc();
    List<Brand> findByStatusOrderByNameAsc(ActiveStatus status);
}
