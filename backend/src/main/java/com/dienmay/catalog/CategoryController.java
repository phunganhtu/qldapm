package com.dienmay.catalog;

import com.dienmay.catalog.CategoryService.CategoryRequest;
import com.dienmay.catalog.CategoryService.CategoryResponse;
import com.dienmay.common.ApiResponse;
import com.dienmay.domain.ActiveStatus;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/categories")
@Tag(name = "1. Nhóm hàng (category)")
public class CategoryController {
    private final CategoryService service;

    public CategoryController(CategoryService service) {
        this.service = service;
    }

    @GetMapping
    @Operation(summary = "Danh sách nhóm hàng, lọc theo trạng thái")
    public ApiResponse<List<CategoryResponse>> list(@RequestParam(required = false) ActiveStatus status) {
        return ApiResponse.ok(service.list(status));
    }

    @GetMapping("/{id}")
    public ApiResponse<CategoryResponse> get(@PathVariable UUID id) {
        return ApiResponse.ok(service.get(id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Thêm nhóm hàng")
    public ApiResponse<CategoryResponse> create(@Valid @RequestBody CategoryRequest req) {
        return ApiResponse.created(service.create(req), "Đã thêm nhóm hàng");
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Sửa nhóm hàng")
    public ApiResponse<CategoryResponse> update(@PathVariable UUID id, @Valid @RequestBody CategoryRequest req) {
        return ApiResponse.ok(service.update(id, req), "Đã cập nhật nhóm hàng");
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Ngừng nhóm hàng (xóa mềm → INACTIVE)")
    public ApiResponse<Void> delete(@PathVariable UUID id) {
        service.deactivate(id);
        return ApiResponse.ok(null, "Đã ngừng nhóm hàng");
    }
}
