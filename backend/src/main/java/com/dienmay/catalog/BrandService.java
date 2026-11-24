package com.dienmay.catalog;

import com.dienmay.common.ApiException;
import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Brand;
import com.dienmay.domain.PublicationStatus;
import com.dienmay.repository.BrandRepository;
import com.dienmay.repository.ProductRepository;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class BrandService {
    private final BrandRepository brands;
    private final ProductRepository products;

    public BrandService(BrandRepository brands, ProductRepository products) {
        this.brands = brands;
        this.products = products;
    }

    public record BrandRequest(
            @NotBlank(message = "Bắt buộc nhập mã") @Size(max = 100) String code,
            @NotBlank(message = "Bắt buộc nhập tên") @Size(max = 255) String name,
            ActiveStatus status) {
    }

    public record BrandResponse(UUID id, String code, String name, ActiveStatus status) {
        static BrandResponse of(Brand b) {
            return new BrandResponse(b.getId(), b.getCode(), b.getName(), b.getStatus());
        }
    }

    @Transactional(readOnly = true)
    public List<BrandResponse> list(ActiveStatus status) {
        List<Brand> list = status == null ? brands.findAllByOrderByNameAsc() : brands.findByStatusOrderByNameAsc(status);
        return list.stream().map(BrandResponse::of).toList();
    }

    @Transactional(readOnly = true)
    public BrandResponse get(UUID id) {
        return BrandResponse.of(find(id));
    }

    public BrandResponse create(BrandRequest req) {
        String code = req.code().trim().toUpperCase();
        if (brands.existsByCodeIgnoreCase(code)) {
            throw ApiException.duplicate("Mã hãng '" + code + "' đã tồn tại");
        }
        Brand b = new Brand();
        apply(b, code, req);
        return BrandResponse.of(brands.save(b));
    }

    public BrandResponse update(UUID id, BrandRequest req) {
        Brand b = find(id);
        String code = req.code().trim().toUpperCase();
        if (brands.existsByCodeIgnoreCaseAndIdNot(code, id)) {
            throw ApiException.duplicate("Mã hãng '" + code + "' đã tồn tại");
        }
        if (req.status() == ActiveStatus.INACTIVE && b.getStatus() == ActiveStatus.ACTIVE) {
            ensureCanDeactivate(b);
        }
        apply(b, code, req);
        return BrandResponse.of(b);
    }

    /** Xóa mềm: chuyển INACTIVE. */
    public void deactivate(UUID id) {
        Brand b = find(id);
        ensureCanDeactivate(b);
        b.setStatus(ActiveStatus.INACTIVE);
    }

    private void apply(Brand b, String code, BrandRequest req) {
        b.setCode(code);
        b.setName(req.name().trim());
        if (req.status() != null) {
            b.setStatus(req.status());
        }
    }

    private void ensureCanDeactivate(Brand b) {
        if (products.existsByBrandIdAndPublicationStatusNotIn(b.getId(), Set.of(PublicationStatus.DISCONTINUED))) {
            throw ApiException.conflict("Hãng còn sản phẩm đang kinh doanh, không thể ngừng");
        }
    }

    Brand find(UUID id) {
        return brands.findById(id).orElseThrow(() -> ApiException.notFound("hãng", id));
    }
}
