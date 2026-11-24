package com.dienmay.repository;

import com.dienmay.domain.Device;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceRepository extends JpaRepository<Device, UUID> {
    List<Device> findBySkuIdOrderBySerialKeyAsc(UUID skuId);
    Optional<Device> findBySerialKey(String serialKey);
    boolean existsBySerialKey(String serialKey);
    boolean existsBySerialKeyAndIdNot(String serialKey, UUID id);
    long countBySkuId(UUID skuId);
}
