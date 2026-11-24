package com.dienmay.repository;

import com.dienmay.domain.Product;
import com.dienmay.domain.PublicationStatus;
import java.util.Collection;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

public interface ProductRepository extends JpaRepository<Product, UUID>, JpaSpecificationExecutor<Product> {
    boolean existsByCodeIgnoreCase(String code);
    boolean existsByCodeIgnoreCaseAndIdNot(String code, UUID id);
    boolean existsByCategoryIdAndPublicationStatusNotIn(UUID categoryId, Collection<PublicationStatus> statuses);
    boolean existsByBrandIdAndPublicationStatusNotIn(UUID brandId, Collection<PublicationStatus> statuses);
}
