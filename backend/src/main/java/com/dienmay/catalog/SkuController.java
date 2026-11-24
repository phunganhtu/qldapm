package com.dienmay.catalog;

import com.dienmay.catalog.SkuService.SkuRequest;
import com.dienmay.catalog.SkuService.SkuResponse;
import com.dienmay.common.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
@Tag(name = "4. Biến thể (sku)")
public class SkuController {
    private final SkuService service;

    public SkuController(SkuService service) {
        this.service = service;
    }

    @GetMapping("/products/{productId}/skus")
    @Operation(summary = "Danh sách SKU của một sản phẩm")
    public ApiResponse<List<SkuResponse>> list(@PathVariable UUID productId) {
        return ApiResponse.ok(service.listByProduct(productId));
    }

    @GetMapping("/skus/{id}")
    public ApiResponse<SkuResponse> get(@PathVariable UUID id) {
        return ApiResponse.ok(service.get(id));
    }

    @PostMapping("/products/{productId}/skus")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Thêm SKU cho sản phẩm")
    public ApiResponse<SkuResponse> create(@PathVariable UUID productId, @Valid @RequestBody SkuRequest req) {
        return ApiResponse.created(service.create(productId, req), "Đã thêm SKU");
    }

    @PutMapping("/skus/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Sửa SKU")
    public ApiResponse<SkuResponse> update(@PathVariable UUID id, @Valid @RequestBody SkuRequest req) {
        return ApiResponse.ok(service.update(id, req), "Đã cập nhật SKU");
    }

    @DeleteMapping("/skus/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Ngừng SKU (xóa mềm → INACTIVE)")
    public ApiResponse<Void> delete(@PathVariable UUID id) {
        service.deactivate(id);
        return ApiResponse.ok(null, "Đã ngừng SKU");
    }
}
