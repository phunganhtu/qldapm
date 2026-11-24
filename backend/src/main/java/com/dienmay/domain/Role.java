package com.dienmay.domain;

import jakarta.persistence.*;
import java.util.UUID;

/** T007 role — vai trò, ví dụ ADMIN, WAREHOUSE, SALES. */
@Entity
@Table(name = "role")
public class Role {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "role_id")
    private UUID id;

    @Column(name = "code", nullable = false, unique = true, length = 100)
    private String code;

    @Column(name = "name", nullable = false, length = 255)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 40)
    private ActiveStatus status = ActiveStatus.ACTIVE;

    protected Role() {
    }

    public Role(String code, String name) {
        this.code = code;
        this.name = name;
    }

    public UUID getId() { return id; }
    public String getCode() { return code; }
    public String getName() { return name; }
    public ActiveStatus getStatus() { return status; }
}
