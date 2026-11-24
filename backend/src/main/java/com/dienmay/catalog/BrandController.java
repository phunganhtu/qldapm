package com.dienmay.catalog;

import com.dienmay.catalog.BrandService.BrandRequest;
import com.dienmay.catalog.BrandService.BrandResponse;
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
@RequestMapping("/api/brands")
@Tag(name = "2. Hãng (brand)")
public class BrandController {
    private final BrandService service;

    public BrandController(BrandService service) {
        this.service = service;
    }

    @GetMapping
    @Operation(summary = "Danh sách hãng, lọc theo trạng thái")
    public ApiResponse<List<BrandResponse>> list(@RequestParam(required = false) ActiveStatus status) {
        return ApiResponse.ok(service.list(status));
    }

    @GetMapping("/{id}")
    public ApiResponse<BrandResponse> get(@PathVariable UUID id) {
        return ApiResponse.ok(service.get(id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Thêm hãng")
    public ApiResponse<BrandResponse> create(@Valid @RequestBody BrandRequest req) {
        return ApiResponse.created(service.create(req), "Đã thêm hãng");
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Sửa hãng")
    public ApiResponse<BrandResponse> update(@PathVariable UUID id, @Valid @RequestBody BrandRequest req) {
        return ApiResponse.ok(service.update(id, req), "Đã cập nhật hãng");
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Ngừng hãng (xóa mềm → INACTIVE)")
    public ApiResponse<Void> delete(@PathVariable UUID id) {
        service.deactivate(id);
        return ApiResponse.ok(null, "Đã ngừng hãng");
    }
}
