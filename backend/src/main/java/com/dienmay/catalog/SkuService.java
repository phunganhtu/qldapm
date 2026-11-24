package com.dienmay.catalog;

import com.dienmay.common.ApiException;
import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Product;
import com.dienmay.domain.PublicationStatus;
import com.dienmay.domain.Sku;
import com.dienmay.repository.DeviceRepository;
import com.dienmay.repository.ProductRepository;
import com.dienmay.repository.SkuRepository;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class SkuService {
    private final SkuRepository skus;
    private final ProductRepository products;
    private final DeviceRepository devices;

    public SkuService(SkuRepository skus, ProductRepository products, DeviceRepository devices) {
        this.skus = skus;
        this.products = products;
        this.devices = devices;
    }

    public record SkuRequest(
            @NotBlank(message = "Bắt buộc nhập mã SKU") @Size(max = 50) String code,
            @Size(max = 100) String barcode,
            @NotBlank(message = "Bắt buộc nhập tên biến thể") @Size(max = 255) String variantName,
            @NotBlank(message = "Bắt buộc nhập đơn vị tính") @Size(max = 100) String unitCode,
            @NotNull(message = "Bắt buộc chọn có quản lý serial hay không") Boolean requiresSerial,
            @NotNull(message = "Bắt buộc chọn có cần lắp đặt hay không") Boolean requiresInstallation,
            @NotNull(message = "Bắt buộc nhập khối lượng")
            @DecimalMin(value = "0", message = "Khối lượng không được âm") BigDecimal weight,
            Map<String, Object> dimensions,
            ActiveStatus status) {
    }

    public record SkuResponse(UUID id, UUID productId, String code, String barcode, String variantName,
                              String unitCode, boolean requiresSerial, boolean requiresInstallation,
                              BigDecimal weight, Map<String, Object> dimensions, ActiveStatus status) {
        static SkuResponse of(Sku s) {
            return new SkuResponse(s.getId(), s.getProduct().getId(), s.getCode(), s.getBarcode(),
                    s.getVariantName(), s.getUnitCode(), s.isRequiresSerial(), s.isRequiresInstallation(),
                    s.getWeight(), s.getDimensionsSnapshot(), s.getStatus());
        }
    }

    @Transactional(readOnly = true)
    public List<SkuResponse> listByProduct(UUID productId) {
        if (!products.existsById(productId)) {
            throw ApiException.notFound("sản phẩm", productId);
        }
        return skus.findByProductIdOrderByCodeAsc(productId).stream().map(SkuResponse::of).toList();
    }

    @Transactional(readOnly = true)
    public SkuResponse get(UUID id) {
        return SkuResponse.of(find(id));
    }

    public SkuResponse create(UUID productId, SkuRequest req) {
        Product product = products.findById(productId).orElseThrow(() -> ApiException.notFound("sản phẩm", productId));
        if (product.getPublicationStatus() == PublicationStatus.DISCONTINUED) {
            throw ApiException.badRequest("Sản phẩm đã ngừng kinh doanh, không thể thêm SKU");
        }
        String code = req.code().trim().toUpperCase();
        String barcode = blankToNull(req.barcode());
        if (skus.existsByCodeIgnoreCase(code)) {
            throw ApiException.duplicate("Mã SKU '" + code + "' đã tồn tại");
        }
        if (barcode != null && skus.existsByBarcode(barcode)) {
            throw ApiException.duplicate("Mã vạch '" + barcode + "' đã được dùng cho SKU khác");
        }
        Sku s = new Sku();
        s.setProduct(product);
        apply(s, code, barcode, req);
        return SkuResponse.of(skus.save(s));
    }

    public SkuResponse update(UUID id, SkuRequest req) {
        Sku s = find(id);
        String code = req.code().trim().toUpperCase();
        String barcode = blankToNull(req.barcode());
        if (skus.existsByCodeIgnoreCaseAndIdNot(code, id)) {
            throw ApiException.duplicate("Mã SKU '" + code + "' đã tồn tại");
        }
        if (barcode != null && skus.existsByBarcodeAndIdNot(barcode, id)) {
            throw ApiException.duplicate("Mã vạch '" + barcode + "' đã được dùng cho SKU khác");
        }
        if (s.isRequiresSerial() && !req.requiresSerial() && devices.countBySkuId(id) > 0) {
            throw ApiException.conflict("SKU đã có thiết bị Serial/IMEI, không thể tắt quản lý serial");
        }
        apply(s, code, barcode, req);
        return SkuResponse.of(s);
    }

    /** Xóa mềm: chuyển INACTIVE. */
    public void deactivate(UUID id) {
        find(id).setStatus(ActiveStatus.INACTIVE);
    }

    private void apply(Sku s, String code, String barcode, SkuRequest req) {
        s.setCode(code);
        s.setBarcode(barcode);
        s.setVariantName(req.variantName().trim());
        s.setUnitCode(req.unitCode().trim());
        s.setRequiresSerial(req.requiresSerial());
        s.setRequiresInstallation(req.requiresInstallation());
        s.setWeight(req.weight());
        s.setDimensionsSnapshot(req.dimensions() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(req.dimensions()));
        if (req.status() != null) {
            s.setStatus(req.status());
        }
    }

    private static String blankToNull(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    Sku find(UUID id) {
        return skus.findById(id).orElseThrow(() -> ApiException.notFound("SKU", id));
    }
}
