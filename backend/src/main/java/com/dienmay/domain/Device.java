package com.dienmay.domain;

import jakarta.persistence.*;
import java.util.UUID;

/**
 * T037 device — một máy cụ thể định danh bằng Serial/IMEI.
 * serial_key là serial đã chuẩn hóa (viết hoa, bỏ khoảng trắng, gạch, chấm) và là khóa UNIQUE,
 * nên "3569-8701" và "35698701" bị coi là trùng (REQ-KHO-02, FR16).
 * Các cột origin_lot_id, current_position_id, owner_customer_id thuộc phân hệ kho/khách hàng
 * chưa có trong demo nên không ánh xạ (để NULL).
 */
@Entity
@Table(name = "device")
public class Device {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "device_id")
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "sku_id", nullable = false)
    private Sku sku;

    @Column(name = "serial_raw", nullable = false, columnDefinition = "text")
    private String serialRaw;

    @Column(name = "serial_key", nullable = false, unique = true, length = 255)
    private String serialKey;

    @Enumerated(EnumType.STRING)
    @Column(name = "ownership", nullable = false, length = 40)
    private DeviceOwnership ownership = DeviceOwnership.COMPANY;

    @Enumerated(EnumType.STRING)
    @Column(name = "condition_code", nullable = false, length = 40)
    private DeviceCondition conditionCode = DeviceCondition.SALEABLE;

    @Column(name = "row_version", nullable = false)
    private int rowVersion = 1;

    public static String normalizeSerial(String raw) {
        return raw == null ? null : raw.trim().toUpperCase().replaceAll("[\\s\\-_.]", "");
    }

    public UUID getId() { return id; }
    public Sku getSku() { return sku; }
    public void setSku(Sku sku) { this.sku = sku; }
    public String getSerialRaw() { return serialRaw; }
    public void setSerialRaw(String serialRaw) {
        this.serialRaw = serialRaw.trim();
        this.serialKey = normalizeSerial(serialRaw);
    }
    public String getSerialKey() { return serialKey; }
    public DeviceOwnership getOwnership() { return ownership; }
    public void setOwnership(DeviceOwnership ownership) { this.ownership = ownership; }
    public DeviceCondition getConditionCode() { return conditionCode; }
    public void setConditionCode(DeviceCondition conditionCode) { this.conditionCode = conditionCode; }
    public int getRowVersion() { return rowVersion; }
    public void bumpVersion() { this.rowVersion++; }
}
