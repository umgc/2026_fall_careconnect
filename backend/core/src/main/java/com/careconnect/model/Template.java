package com.careconnect.model;

import java.util.List;

import io.micrometer.common.lang.Nullable;
import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "templates")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Template {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String name;
    @Nullable
    private String description;
    @Nullable
    private String frequency;
    @Nullable
    private int taskInterval;
    @Nullable
    private int doCount;
    @Nullable
    private List<Boolean> daysOfWeek;
    @Nullable
    private String timeOfDay;
    private int icon;
    @Nullable
    private List<String> notifications;
}
