package com.dienmay.device;

import com.dienmay.common.ApiResponse;
import com.dienmay.device.DeviceService.BatchRequest;
import com.dienmay.device.DeviceService.DeviceRequest;
import com.dienmay.device.DeviceService.DeviceResponse;
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
@Tag(name = "5. Thiết bị Serial/IMEI (device)")
public class DeviceController {
    private static final String CAN_WRITE = "hasAnyRole('ADMIN','WAREHOUSE')";
    private final DeviceService service;

    public DeviceController(DeviceService service) {
        this.service = service;
    }

    @GetMapping("/skus/{skuId}/devices")
    @Operation(summary = "Danh sách thiết bị của một SKU")
    public ApiResponse<List<DeviceResponse>> list(@PathVariable UUID skuId) {
        return ApiResponse.ok(service.listBySku(skuId));
    }

    @GetMapping("/devices/{id}")
    public ApiResponse<DeviceResponse> get(@PathVariable UUID id) {
        return ApiResponse.ok(service.get(id));
    }

    @GetMapping("/devices/lookup")
    @Operation(summary = "Tra cứu thiết bị theo Serial/IMEI (giả lập quét mã vạch)")
    public ApiResponse<DeviceResponse> lookup(@RequestParam String serial) {
        return ApiResponse.ok(service.lookup(serial));
    }

    @PostMapping("/skus/{skuId}/devices")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(CAN_WRITE)
    @Operation(summary = "Thêm một thiết bị (không cho trùng Serial/IMEI)")
    public ApiResponse<DeviceResponse> create(@PathVariable UUID skuId, @Valid @RequestBody DeviceRequest req) {
        return ApiResponse.created(service.create(skuId, req), "Đã thêm thiết bị");
    }

    @PostMapping("/skus/{skuId}/devices/batch")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(CAN_WRITE)
    @Operation(summary = "Nhập nhiều thiết bị một lần; một mã lỗi thì từ chối cả lô")
    public ApiResponse<List<DeviceResponse>> createBatch(@PathVariable UUID skuId,
                                                         @Valid @RequestBody BatchRequest req) {
        List<DeviceResponse> created = service.createBatch(skuId, req);
        return ApiResponse.created(created, "Đã nhập " + created.size() + " thiết bị");
    }

    @PutMapping("/devices/{id}")
    @PreAuthorize(CAN_WRITE)
    @Operation(summary = "Sửa serial hoặc tình trạng thiết bị")
    public ApiResponse<DeviceResponse> update(@PathVariable UUID id, @Valid @RequestBody DeviceRequest req) {
        return ApiResponse.ok(service.update(id, req), "Đã cập nhật thiết bị");
    }

    @DeleteMapping("/devices/{id}")
    @PreAuthorize(CAN_WRITE)
    @Operation(summary = "Xóa thiết bị quét nhầm (xóa cứng)")
    public ApiResponse<Void> delete(@PathVariable UUID id) {
        service.delete(id);
        return ApiResponse.ok(null, "Đã xóa thiết bị");
    }
}
