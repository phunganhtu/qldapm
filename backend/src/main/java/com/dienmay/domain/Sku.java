package com.dienmay.domain;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/** T017 sku — biến thể (màu, dung lượng, kích thước) có mã, mã vạch, cờ serial/lắp đặt. */
@Entity
@Table(name = "sku")
public class Sku {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "sku_id")
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "product_id", nullable = false)
    private Product product;

    @Column(name = "code", nullable = false, unique = true, length = 50)
    private String code;

    @Column(name = "barcode", unique = true, length = 100)
    private String barcode;

    @Column(name = "variant_name", nullable = false, length = 255)
    private String variantName;

    @Column(name = "unit_code", nullable = false, length = 100)
    private String unitCode;

    @Column(name = "requires_serial", nullable = false)
    private boolean requiresSerial;

    @Column(name = "requires_installation", nullable = false)
    private boolean requiresInstallation;

    @Column(name = "weight", nullable = false, precision = 24, scale = 6)
    private BigDecimal weight;

    /** Kích thước dạng JSON, ví dụ {"lengthMm":1450,"widthMm":83,"heightMm":834}. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "dimensions_snapshot", nullable = false)
    private Map<String, Object> dimensionsSnapshot = new LinkedHashMap<>();

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 40)
    private ActiveStatus status = ActiveStatus.ACTIVE;

    public UUID getId() { return id; }
    public Product getProduct() { return product; }
    public void setProduct(Product product) { this.product = product; }
    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getBarcode() { return barcode; }
    public void setBarcode(String barcode) { this.barcode = barcode; }
    public String getVariantName() { return variantName; }
    public void setVariantName(String variantName) { this.variantName = variantName; }
    public String getUnitCode() { return unitCode; }
    public void setUnitCode(String unitCode) { this.unitCode = unitCode; }
    public boolean isRequiresSerial() { return requiresSerial; }
    public void setRequiresSerial(boolean requiresSerial) { this.requiresSerial = requiresSerial; }
    public boolean isRequiresInstallation() { return requiresInstallation; }
    public void setRequiresInstallation(boolean requiresInstallation) { this.requiresInstallation = requiresInstallation; }
    public BigDecimal getWeight() { return weight; }
    public void setWeight(BigDecimal weight) { this.weight = weight; }
    public Map<String, Object> getDimensionsSnapshot() { return dimensionsSnapshot; }
    public void setDimensionsSnapshot(Map<String, Object> dimensionsSnapshot) { this.dimensionsSnapshot = dimensionsSnapshot; }
    public ActiveStatus getStatus() { return status; }
    public void setStatus(ActiveStatus status) { this.status = status; }
}
