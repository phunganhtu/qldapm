package com.dienmay.config;

import com.dienmay.domain.*;
import com.dienmay.repository.*;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Dữ liệu mẫu cho demo, chỉ tạo khi bảng còn trống.
 *
 * Tài khoản thử (CHỈ dùng cho môi trường demo/dev):
 *   admin    / Admin@123    — ADMIN: toàn quyền
 *   thukho   / Thukho@123   — WAREHOUSE: xem tất cả, thêm/sửa/xóa thiết bị IMEI
 *   banhang  / Banhang@123  — SALES: chỉ xem
 *   khoa     / Khoa@123     — tài khoản bị khóa (LOCKED) để demo đăng nhập bị từ chối
 */
@Component
@ConditionalOnProperty(prefix = "app.seed", name = "enabled", havingValue = "true")
public class DataSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);

    private final UserAccountRepository users;
    private final RoleRepository roles;
    private final CategoryRepository categories;
    private final BrandRepository brands;
    private final ProductRepository products;
    private final SkuRepository skus;
    private final DeviceRepository devices;
    private final PasswordEncoder encoder;

    public DataSeeder(UserAccountRepository users, RoleRepository roles, CategoryRepository categories,
                      BrandRepository brands, ProductRepository products, SkuRepository skus,
                      DeviceRepository devices, PasswordEncoder encoder) {
        this.users = users;
        this.roles = roles;
        this.categories = categories;
        this.brands = brands;
        this.products = products;
        this.skus = skus;
        this.devices = devices;
        this.encoder = encoder;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (users.count() == 0) {
            seedUsers();
        }
        if (categories.count() == 0 && brands.count() == 0) {
            seedCatalog();
        }
    }

    private void seedUsers() {
        Role admin = roles.save(new Role("ADMIN", "Quản trị hệ thống"));
        Role warehouse = roles.save(new Role("WAREHOUSE", "Thủ kho"));
        Role sales = roles.save(new Role("SALES", "Nhân viên bán hàng"));
        user("admin", "Admin@123", admin, AccountStatus.ACTIVE);
        user("thukho", "Thukho@123", warehouse, AccountStatus.ACTIVE);
        user("banhang", "Banhang@123", sales, AccountStatus.ACTIVE);
        user("khoa", "Khoa@123", sales, AccountStatus.LOCKED);
        log.info("Đã tạo 4 tài khoản mẫu (xem README hoặc DataSeeder)");
    }

    private void user(String login, String rawPassword, Role role, AccountStatus status) {
        UserAccount u = new UserAccount(login, encoder.encode(rawPassword));
        u.getRoles().add(role);
        u.setStatus(status);
        users.save(u);
    }

    private void seedCatalog() {
        Category dienTu = category("DIEN_TU", "Điện tử", null);
        Category tivi = category("TIVI", "Tivi", dienTu);
        Category dienThoai = category("DIEN_THOAI", "Điện thoại", dienTu);
        Category dienLanh = category("DIEN_LANH", "Điện lạnh", null);
        Category tuLanh = category("TU_LANH", "Tủ lạnh", dienLanh);
        category("MAY_GIAT", "Máy giặt", dienLanh);

        Brand sony = brand("SONY", "Sony");
        Brand samsung = brand("SAMSUNG", "Samsung");
        Brand lg = brand("LG", "LG");
        Brand apple = brand("APPLE", "Apple");

        Product bravia = product("TV-SONY-BRAVIA7", "Google Tivi Sony Bravia 7 4K", tivi, sony,
                "Tivi Mini LED, 4K HDR, Google TV");
        Sku bravia65 = sku(bravia, "SONY-K65XR70", "4548736151234", "65 inch", true, true, "28.5",
                dims(1450, 83, 834));
        sku(bravia, "SONY-K55XR70", "4548736151241", "55 inch", true, true, "19.2", dims(1231, 83, 712));
        bravia.setPublicationStatus(PublicationStatus.PUBLISHED);

        Product s25 = product("DT-SS-S25", "Samsung Galaxy S25", dienThoai, samsung, "Điện thoại flagship");
        Sku s25Den = sku(s25, "SS-S25-256-DEN", "8806095412345", "256GB - Đen", true, false, "0.162",
                dims(147, 71, 7));
        sku(s25, "SS-S25-512-XANH", "8806095412352", "512GB - Xanh", true, false, "0.162", dims(147, 71, 7));
        s25.setPublicationStatus(PublicationStatus.PUBLISHED);

        Product ip16 = product("DT-APPLE-IP16", "iPhone 16", dienThoai, apple, null);
        sku(ip16, "IP16-128-DEN", "0195949812345", "128GB - Đen", true, false, "0.170", dims(147, 72, 8));

        Product tl = product("TL-LG-GN-D392", "Tủ lạnh LG Inverter 394 lít", tuLanh, lg, "Ngăn đá trên");
        sku(tl, "LG-GN-D392PS", "8806091234567", "394L - Bạc", true, true, "62", dims(600, 680, 1720));

        for (String imei : List.of("356938035643809", "356938035643817", "356938035643825")) {
            device(s25Den, imei);
        }
        device(bravia65, "SN-K65XR70-0001");
        device(bravia65, "SN-K65XR70-0002");
        log.info("Đã tạo dữ liệu mẫu danh mục: {} nhóm, {} hãng, {} sản phẩm, {} SKU, {} thiết bị",
                categories.count(), brands.count(), products.count(), skus.count(), devices.count());
    }

    private Category category(String code, String name, Category parent) {
        Category c = new Category();
        c.setCode(code);
        c.setName(name);
        c.setParent(parent);
        return categories.save(c);
    }

    private Brand brand(String code, String name) {
        Brand b = new Brand();
        b.setCode(code);
        b.setName(name);
        return brands.save(b);
    }

    private Product product(String code, String name, Category c, Brand b, String desc) {
        Product p = new Product();
        p.setCode(code);
        p.setName(name);
        p.setCategory(c);
        p.setBrand(b);
        p.setDescription(desc);
        return products.save(p);
    }

    private Sku sku(Product p, String code, String barcode, String variant, boolean serial, boolean install,
                    String weightKg, Map<String, Object> dims) {
        Sku s = new Sku();
        s.setProduct(p);
        s.setCode(code);
        s.setBarcode(barcode);
        s.setVariantName(variant);
        s.setUnitCode("CAI");
        s.setRequiresSerial(serial);
        s.setRequiresInstallation(install);
        s.setWeight(new BigDecimal(weightKg));
        s.setDimensionsSnapshot(dims);
        return skus.save(s);
    }

    private void device(Sku sku, String serial) {
        Device d = new Device();
        d.setSku(sku);
        d.setSerialRaw(serial);
        devices.save(d);
    }

    private static Map<String, Object> dims(int lengthMm, int widthMm, int heightMm) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("lengthMm", lengthMm);
        m.put("widthMm", widthMm);
        m.put("heightMm", heightMm);
        return m;
    }
}
