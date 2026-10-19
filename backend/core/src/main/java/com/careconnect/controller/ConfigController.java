package com.careconnect.controller;

import com.careconnect.dto.CompetencyScaleDtos;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.SystemConfigService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/v1/api/config")
public class ConfigController {

    private static final String KEY_MIN = "competency_scale_min";
    private static final String KEY_MAX = "competency_scale_max";
    private static final String KEY_LABEL_PREFIX = "competency_label_";

    private final SystemConfigService configService;
    private final UserRepository userRepository;

    public ConfigController(SystemConfigService configService, UserRepository userRepository) {
        this.configService = configService;
        this.userRepository = userRepository;
    }

    private static int parseIntOrDefault(String raw, int def) {
        if (raw == null) return def;
        try {
            return Integer.parseInt(raw.trim());
        } catch (Exception e) {
            return def;
        }
    }

    private static String defaultCompetencyLabel(int value) {
        switch (value) {
            case 1:
                return "Total Assistance";
            case 2:
                return "Maximum Assistance";
            case 3:
                return "Moderate Assistance";
            case 4:
                return "Minimal Assistance";
            case 5:
                return "Independent";
            default:
                return "";
        }
    }

    private User getCurrentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return userRepository.findByEmail(auth.getName())
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }

    @GetMapping("/competency-scale")
    public ResponseEntity<CompetencyScaleDtos.CompetencyScaleResponse> getCompetencyScale() {
        // Any authenticated user can read (SecurityConfig already requires auth for /v1/api/**).
        getCurrentUser();

        int min = parseIntOrDefault(configService.getValue(KEY_MIN).orElse(null), 1);
        int max = parseIntOrDefault(configService.getValue(KEY_MAX).orElse(null), 5);
        if (min > max) {
            min = 1;
            max = 5;
        }

        Map<Integer, String> labels = new LinkedHashMap<>();
        List<CompetencyScaleDtos.CompetencyScaleItem> items = new ArrayList<>();
        for (int v = min; v <= max; v++) {
            String label = configService.getValue(KEY_LABEL_PREFIX + v).orElse("");
            if (label != null) {
                label = label.trim();
            }
            if (label == null || label.isEmpty()) {
                label = defaultCompetencyLabel(v);
            }
            labels.put(v, label);
            items.add(new CompetencyScaleDtos.CompetencyScaleItem(v, label));
        }

        return ResponseEntity.ok(new CompetencyScaleDtos.CompetencyScaleResponse(min, max, labels, items));
    }

    @PutMapping("/competency-scale")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<CompetencyScaleDtos.CompetencyScaleResponse> putCompetencyScale(
            @RequestBody CompetencyScaleDtos.UpdateCompetencyScaleRequest request
    ) {
        User currentUser = getCurrentUser();

        Integer minReq = request.getMin();
        Integer maxReq = request.getMax();
        Map<Integer, String> labelsReq = request.getLabels();

        if (minReq == null || maxReq == null || labelsReq == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "min, max, and labels are required");
        }
        if (minReq < 1 || maxReq < 1 || minReq > maxReq) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Invalid min/max");
        }
        for (int v = minReq; v <= maxReq; v++) {
            String label = labelsReq.get(v);
            if (label == null || label.trim().isEmpty()) {
                throw new AppException(HttpStatus.BAD_REQUEST, "Missing label for value " + v);
            }
        }

        configService.setValue(KEY_MIN, String.valueOf(minReq), currentUser.getId());
        configService.setValue(KEY_MAX, String.valueOf(maxReq), currentUser.getId());
        for (int v = minReq; v <= maxReq; v++) {
            configService.setValue(KEY_LABEL_PREFIX + v, labelsReq.get(v).trim(), currentUser.getId());
        }

        // Return current scale
        Map<Integer, String> labels = new LinkedHashMap<>();
        List<CompetencyScaleDtos.CompetencyScaleItem> items = new ArrayList<>();
        for (int v = minReq; v <= maxReq; v++) {
            String label = labelsReq.get(v).trim();
            labels.put(v, label);
            items.add(new CompetencyScaleDtos.CompetencyScaleItem(v, label));
        }
        return ResponseEntity.ok(new CompetencyScaleDtos.CompetencyScaleResponse(minReq, maxReq, labels, items));
    }
}

