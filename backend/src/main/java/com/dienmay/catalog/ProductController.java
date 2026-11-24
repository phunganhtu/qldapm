package com.dienmay.catalog;

import com.dienmay.catalog.ProductService.ProductRequest;
import com.dienmay.catalog.ProductService.ProductResponse;
import com.dienmay.common.ApiResponse;
import com.dienmay.common.PageResponse;
import com.dienmay.domain.PublicationStatus;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/products")
@Tag(name = "3. Sản phẩm (product)")
public class ProductController {
    private final ProductService service;

    public ProductController(ProductService service) {
        this.service = service;
    }

    @GetMapping
    @Operation(summary = "Tìm và lọc sản phẩm (q, categoryId, brandId, status) có phân trang")
    public ApiResponse<PageResponse<ProductResponse>> search(@RequestParam(required = false) String q,
                                                             @RequestParam(required = false) UUID categoryId,
                                                             @RequestParam(required = false) UUID brandId,
                                                             @RequestParam(required = false) PublicationStatus status,
                                                             @ParameterObject @PageableDefault(size = 20, sort = "name",
                                                                     direction = Sort.Direction.ASC) Pageable pageable) {
        return ApiResponse.ok(service.search(q, categoryId, brandId, status, pageable));
    }

    @GetMapping("/{id}")
    @Operation(summary = "Chi tiết sản phẩm kèm danh sách SKU")
    public ApiResponse<ProductResponse> get(@PathVariable UUID id) {
        return ApiResponse.ok(service.get(id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Thêm sản phẩm (mặc định DRAFT)")
    public ApiResponse<ProductResponse> create(@Valid @RequestBody ProductRequest req) {
        return ApiResponse.created(service.create(req), "Đã thêm sản phẩm");
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Sửa sản phẩm / đổi trạng thái công bố")
    public ApiResponse<ProductResponse> update(@PathVariable UUID id, @Valid @RequestBody ProductRequest req) {
        return ApiResponse.ok(service.update(id, req), "Đã cập nhật sản phẩm");
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Ngừng kinh doanh (xóa mềm → DISCONTINUED, SKU → INACTIVE)")
    public ApiResponse<Void> delete(@PathVariable UUID id) {
        service.discontinue(id);
        return ApiResponse.ok(null, "Đã ngừng kinh doanh sản phẩm");
    }
}
