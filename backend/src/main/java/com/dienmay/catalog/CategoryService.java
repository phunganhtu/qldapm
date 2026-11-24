package com.dienmay.catalog;

import com.dienmay.common.ApiException;
import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Category;
import com.dienmay.domain.PublicationStatus;
import com.dienmay.repository.CategoryRepository;
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
public class CategoryService {
    private final CategoryRepository categories;
    private final ProductRepository products;

    public CategoryService(CategoryRepository categories, ProductRepository products) {
        this.categories = categories;
        this.products = products;
    }

    public record CategoryRequest(
            @NotBlank(message = "Bắt buộc nhập mã") @Size(max = 100) String code,
            @NotBlank(message = "Bắt buộc nhập tên") @Size(max = 255) String name,
            UUID parentId,
            ActiveStatus status) {
    }

    public record CategoryResponse(UUID id, String code, String name, UUID parentId, String parentName,
                                   ActiveStatus status) {
        static CategoryResponse of(Category c) {
            Category p = c.getParent();
            return new CategoryResponse(c.getId(), c.getCode(), c.getName(),
                    p == null ? null : p.getId(), p == null ? null : p.getName(), c.getStatus());
        }
    }

    @Transactional(readOnly = true)
    public List<CategoryResponse> list(ActiveStatus status) {
        List<Category> list = status == null ? categories.findAllByOrderByCodeAsc()
                : categories.findByStatusOrderByCodeAsc(status);
        return list.stream().map(CategoryResponse::of).toList();
    }

    @Transactional(readOnly = true)
    public CategoryResponse get(UUID id) {
        return CategoryResponse.of(find(id));
    }

    public CategoryResponse create(CategoryRequest req) {
        String code = req.code().trim().toUpperCase();
        if (categories.existsByCodeIgnoreCase(code)) {
            throw ApiException.duplicate("Mã nhóm hàng '" + code + "' đã tồn tại");
        }
        Category c = new Category();
        apply(c, code, req);
        return CategoryResponse.of(categories.save(c));
    }

    public CategoryResponse update(UUID id, CategoryRequest req) {
        Category c = find(id);
        String code = req.code().trim().toUpperCase();
        if (categories.existsByCodeIgnoreCaseAndIdNot(code, id)) {
            throw ApiException.duplicate("Mã nhóm hàng '" + code + "' đã tồn tại");
        }
        if (req.status() == ActiveStatus.INACTIVE && c.getStatus() == ActiveStatus.ACTIVE) {
            ensureCanDeactivate(c);
        }
        apply(c, code, req);
        return CategoryResponse.of(c);
    }

    /** Xóa mềm: chuyển INACTIVE, không xóa dòng để giữ lịch sử (FR07). */
    public void deactivate(UUID id) {
        Category c = find(id);
        ensureCanDeactivate(c);
        c.setStatus(ActiveStatus.INACTIVE);
    }

    private void apply(Category c, String code, CategoryRequest req) {
        c.setCode(code);
        c.setName(req.name().trim());
        if (req.status() != null) {
            c.setStatus(req.status());
        }
        if (req.parentId() == null) {
            c.setParent(null);
            return;
        }
        Category parent = categories.findById(req.parentId())
                .orElseThrow(() -> ApiException.badRequest("Nhóm cha không tồn tại: " + req.parentId()));
        // Chặn tự làm cha của chính mình hoặc tạo vòng lặp A -> B -> A.
        for (Category p = parent; p != null; p = p.getParent()) {
            if (c.getId() != null && p.getId().equals(c.getId())) {
                throw ApiException.badRequest("Không thể chọn nhóm cha tạo thành vòng lặp");
            }
        }
        c.setParent(parent);
    }

    private void ensureCanDeactivate(Category c) {
        if (categories.existsByParentIdAndStatus(c.getId(), ActiveStatus.ACTIVE)) {
            throw ApiException.conflict("Nhóm hàng còn nhóm con đang hoạt động, hãy ngừng các nhóm con trước");
        }
        if (products.existsByCategoryIdAndPublicationStatusNotIn(c.getId(), Set.of(PublicationStatus.DISCONTINUED))) {
            throw ApiException.conflict("Nhóm hàng còn sản phẩm đang kinh doanh, không thể ngừng");
        }
    }

    Category find(UUID id) {
        return categories.findById(id).orElseThrow(() -> ApiException.notFound("nhóm hàng", id));
    }
}
