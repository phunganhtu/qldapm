package com.dienmay.catalog;

import com.dienmay.catalog.SkuService.SkuResponse;
import com.dienmay.common.ApiException;
import com.dienmay.common.PageResponse;
import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Brand;
import com.dienmay.domain.Category;
import com.dienmay.domain.Product;
import com.dienmay.domain.PublicationStatus;
import com.dienmay.domain.Sku;
import com.dienmay.repository.ProductRepository;
import com.dienmay.repository.SkuRepository;
import jakarta.persistence.criteria.Predicate;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class ProductService {
    private final ProductRepository products;
    private final SkuRepository skus;
    private final CategoryService categoryService;
    private final BrandService brandService;

    public ProductService(ProductRepository products, SkuRepository skus, CategoryService categoryService,
                          BrandService brandService) {
        this.products = products;
        this.skus = skus;
        this.categoryService = categoryService;
        this.brandService = brandService;
    }

    public record ProductRequest(
            @NotBlank(message = "Bắt buộc nhập mã") @Size(max = 100) String code,
            @NotBlank(message = "Bắt buộc nhập tên") @Size(max = 255) String name,
            String description,
            @NotNull(message = "Bắt buộc chọn nhóm hàng") UUID categoryId,
            @NotNull(message = "Bắt buộc chọn hãng") UUID brandId,
            PublicationStatus publicationStatus) {
    }

    public record Ref(UUID id, String code, String name) {
    }

    public record ProductResponse(UUID id, String code, String name, String description, Ref category, Ref brand,
                                  PublicationStatus publicationStatus, List<SkuResponse> skus) {
        static ProductResponse of(Product p, List<SkuResponse> skus) {
            Category c = p.getCategory();
            Brand b = p.getBrand();
            return new ProductResponse(p.getId(), p.getCode(), p.getName(), p.getDescription(),
                    new Ref(c.getId(), c.getCode(), c.getName()), new Ref(b.getId(), b.getCode(), b.getName()),
                    p.getPublicationStatus(), skus);
        }
    }

    /** Tìm theo tên/mã (q), lọc nhóm, hãng, trạng thái; có phân trang (FR08). */
    @Transactional(readOnly = true)
    public PageResponse<ProductResponse> search(String q, UUID categoryId, UUID brandId, PublicationStatus status,
                                                Pageable pageable) {
        Specification<Product> spec = (root, query, cb) -> {
            List<Predicate> ps = new ArrayList<>();
            if (q != null && !q.isBlank()) {
                String like = "%" + q.trim().toLowerCase() + "%";
                ps.add(cb.or(cb.like(cb.lower(root.get("name")), like), cb.like(cb.lower(root.get("code")), like)));
            }
            if (categoryId != null) {
                ps.add(cb.equal(root.get("category").get("id"), categoryId));
            }
            if (brandId != null) {
                ps.add(cb.equal(root.get("brand").get("id"), brandId));
            }
            if (status != null) {
                ps.add(cb.equal(root.get("publicationStatus"), status));
            }
            return cb.and(ps.toArray(Predicate[]::new));
        };
        return PageResponse.of(products.findAll(spec, pageable), p -> ProductResponse.of(p, null));
    }

    @Transactional(readOnly = true)
    public ProductResponse get(UUID id) {
        Product p = find(id);
        return ProductResponse.of(p, skus.findByProductIdOrderByCodeAsc(id).stream().map(SkuResponse::of).toList());
    }

    public ProductResponse create(ProductRequest req) {
        String code = req.code().trim().toUpperCase();
        if (products.existsByCodeIgnoreCase(code)) {
            throw ApiException.duplicate("Mã sản phẩm '" + code + "' đã tồn tại");
        }
        if (req.publicationStatus() == PublicationStatus.PUBLISHED) {
            throw ApiException.badRequest("Sản phẩm mới chưa có SKU nên không thể công bố ngay; hãy tạo ở DRAFT");
        }
        Product p = new Product();
        apply(p, code, req);
        return ProductResponse.of(products.save(p), List.of());
    }

    public ProductResponse update(UUID id, ProductRequest req) {
        Product p = find(id);
        String code = req.code().trim().toUpperCase();
        if (products.existsByCodeIgnoreCaseAndIdNot(code, id)) {
            throw ApiException.duplicate("Mã sản phẩm '" + code + "' đã tồn tại");
        }
        apply(p, code, req);
        if (p.getPublicationStatus() == PublicationStatus.DISCONTINUED) {
            deactivateSkus(id);
        }
        return get(id);
    }

    /** Xóa mềm: ngừng kinh doanh sản phẩm và ngừng toàn bộ SKU của nó (FR07). */
    public void discontinue(UUID id) {
        Product p = find(id);
        p.setPublicationStatus(PublicationStatus.DISCONTINUED);
        deactivateSkus(id);
    }

    private void apply(Product p, String code, ProductRequest req) {
        Category category = categoryService.find(req.categoryId());
        Brand brand = brandService.find(req.brandId());
        if (category.getStatus() != ActiveStatus.ACTIVE) {
            throw ApiException.badRequest("Nhóm hàng '" + category.getName() + "' đã ngừng, không thể gán sản phẩm");
        }
        if (brand.getStatus() != ActiveStatus.ACTIVE) {
            throw ApiException.badRequest("Hãng '" + brand.getName() + "' đã ngừng, không thể gán sản phẩm");
        }
        if (req.publicationStatus() == PublicationStatus.PUBLISHED && p.getId() != null
                && skus.findByProductIdOrderByCodeAsc(p.getId()).stream()
                        .noneMatch(s -> s.getStatus() == ActiveStatus.ACTIVE)) {
            throw ApiException.badRequest("Phải có ít nhất một SKU đang hoạt động trước khi công bố sản phẩm");
        }
        p.setCode(code);
        p.setName(req.name().trim());
        p.setDescription(req.description());
        p.setCategory(category);
        p.setBrand(brand);
        if (req.publicationStatus() != null) {
            p.setPublicationStatus(req.publicationStatus());
        }
    }

    private void deactivateSkus(UUID productId) {
        for (Sku s : skus.findByProductIdOrderByCodeAsc(productId)) {
            s.setStatus(ActiveStatus.INACTIVE);
        }
    }

    Product find(UUID id) {
        return products.findById(id).orElseThrow(() -> ApiException.notFound("sản phẩm", id));
    }
}
