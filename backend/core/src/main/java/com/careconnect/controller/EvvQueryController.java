package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.User;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/v1/api/evv/records")
@RequiredArgsConstructor
public class EvvQueryController {
    private final EvvRecordRepository evvRecordRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping
    public List<EvvRecord> list(@RequestParam(required = false) String status, @RequestParam(required = false) Long caregiverId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        if (status != null && caregiverId != null)
            return evvRecordRepository.findByCaregiverIdAndStatus(caregiverId, status);
        if (status != null) return evvRecordRepository.findByStatus(status);
        return evvRecordRepository.findAll();
    }
}
