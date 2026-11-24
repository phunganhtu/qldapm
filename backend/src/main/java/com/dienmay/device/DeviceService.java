package com.dienmay.device;

import com.dienmay.common.ApiException;
import com.dienmay.common.ApiResponse.FieldErrorDetail;
import com.dienmay.common.ErrorCode;
import com.dienmay.domain.ActiveStatus;
import com.dienmay.domain.Device;
import com.dienmay.domain.DeviceCondition;
import com.dienmay.domain.DeviceOwnership;
import com.dienmay.domain.Sku;
import com.dienmay.repository.DeviceRepository;
import com.dienmay.repository.SkuRepository;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Quản lý thiết bị theo Serial/IMEI (REQ-KHO-02, FR16):
 * - Chỉ SKU có requires_serial = true mới được gắn serial.
 * - Serial được chuẩn hóa thành serial_key; không cho trùng trong toàn hệ thống.
 * - Nhập theo lô (quét nhiều mã): một mã lỗi thì từ chối cả lô (UC03, bước ngoại lệ).
 */
@Service
@Transactional
public class DeviceService {
    private final DeviceRepository devices;
    private final SkuRepository skus;

    public DeviceService(DeviceRepository devices, SkuRepository skus) {
        this.devices = devices;
        this.skus = skus;
    }

    public record DeviceRequest(
            @NotBlank(message = "Bắt buộc nhập Serial/IMEI") @Size(max = 255) String serial,
            DeviceCondition conditionCode) {
    }

    public record BatchRequest(
            @NotEmpty(message = "Danh sách serial không được rỗng")
            @Size(max = 500, message = "Tối đa 500 serial mỗi lần") List<@NotBlank String> serials,
            DeviceCondition conditionCode) {
    }

    public record DeviceResponse(UUID id, UUID skuId, String skuCode, String serialRaw, String serialKey,
                                 DeviceOwnership ownership, DeviceCondition conditionCode, int rowVersion) {
        static DeviceResponse of(Device d) {
            return new DeviceResponse(d.getId(), d.getSku().getId(), d.getSku().getCode(), d.getSerialRaw(),
                    d.getSerialKey(), d.getOwnership(), d.getConditionCode(), d.getRowVersion());
        }
    }

    @Transactional(readOnly = true)
    public List<DeviceResponse> listBySku(UUID skuId) {
        findSku(skuId);
        return devices.findBySkuIdOrderBySerialKeyAsc(skuId).stream().map(DeviceResponse::of).toList();
    }

    @Transactional(readOnly = true)
    public DeviceResponse get(UUID id) {
        return DeviceResponse.of(find(id));
    }

    /** Tra cứu khi quét mã vạch: chấp nhận serial có khoảng trắng, gạch nối, chữ thường. */
    @Transactional(readOnly = true)
    public DeviceResponse lookup(String serial) {
        String key = Device.normalizeSerial(serial);
        return devices.findBySerialKey(key).map(DeviceResponse::of)
                .orElseThrow(() -> ApiException.notFound("thiết bị có Serial/IMEI", serial));
    }

    public DeviceResponse create(UUID skuId, DeviceRequest req) {
        Sku sku = findSerialSku(skuId);
        String key = requireValidKey(req.serial());
        if (devices.existsBySerialKey(key)) {
            throw ApiException.duplicate("Serial/IMEI '" + req.serial().trim() + "' đã tồn tại trong hệ thống");
        }
        return DeviceResponse.of(devices.save(newDevice(sku, req.serial(), req.conditionCode())));
    }

    public List<DeviceResponse> createBatch(UUID skuId, BatchRequest req) {
        Sku sku = findSerialSku(skuId);
        List<FieldErrorDetail> errors = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < req.serials().size(); i++) {
            String serial = req.serials().get(i);
            String key = Device.normalizeSerial(serial);
            String field = "serials[" + i + "]";
            if (key.isEmpty()) {
                errors.add(new FieldErrorDetail(field, "'" + serial + "' rỗng sau khi chuẩn hóa"));
            } else if (!seen.add(key)) {
                errors.add(new FieldErrorDetail(field, "'" + serial + "' bị quét trùng trong cùng lô"));
            } else if (devices.existsBySerialKey(key)) {
                errors.add(new FieldErrorDetail(field, "'" + serial + "' đã tồn tại trong hệ thống"));
            }
        }
        if (!errors.isEmpty()) {
            throw new ApiException(ErrorCode.DUPLICATE_RESOURCE,
                    "Từ chối cả lô vì có " + errors.size() + " serial lỗi", errors);
        }
        List<Device> created = req.serials().stream().map(s -> newDevice(sku, s, req.conditionCode())).toList();
        return devices.saveAll(created).stream().map(DeviceResponse::of).toList();
    }

    public DeviceResponse update(UUID id, DeviceRequest req) {
        Device d = find(id);
        String key = requireValidKey(req.serial());
        if (devices.existsBySerialKeyAndIdNot(key, id)) {
            throw ApiException.duplicate("Serial/IMEI '" + req.serial().trim() + "' đã tồn tại trong hệ thống");
        }
        d.setSerialRaw(req.serial());
        if (req.conditionCode() != null) {
            d.setConditionCode(req.conditionCode());
        }
        d.bumpVersion();
        return DeviceResponse.of(d);
    }

    /** Xóa cứng: dùng để sửa trường hợp quét nhầm khi thiết bị chưa phát sinh chứng từ nào. */
    public void delete(UUID id) {
        devices.delete(find(id));
    }

    private Device newDevice(Sku sku, String serial, DeviceCondition condition) {
        Device d = new Device();
        d.setSku(sku);
        d.setSerialRaw(serial);
        d.setOwnership(DeviceOwnership.COMPANY);
        d.setConditionCode(condition == null ? DeviceCondition.SALEABLE : condition);
        return d;
    }

    private static String requireValidKey(String serial) {
        String key = Device.normalizeSerial(serial);
        if (key == null || key.isEmpty()) {
            throw ApiException.badRequest("Serial/IMEI không hợp lệ");
        }
        return key;
    }

    private Sku findSerialSku(UUID skuId) {
        Sku sku = findSku(skuId);
        if (!sku.isRequiresSerial()) {
            throw ApiException.badRequest("SKU '" + sku.getCode() + "' không quản lý theo Serial/IMEI");
        }
        if (sku.getStatus() != ActiveStatus.ACTIVE) {
            throw ApiException.badRequest("SKU '" + sku.getCode() + "' đã ngừng, không thể nhập thiết bị");
        }
        return sku;
    }

    private Sku findSku(UUID skuId) {
        return skus.findById(skuId).orElseThrow(() -> ApiException.notFound("SKU", skuId));
    }

    private Device find(UUID id) {
        return devices.findById(id).orElseThrow(() -> ApiException.notFound("thiết bị", id));
    }
}
