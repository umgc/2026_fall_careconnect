package com.careconnect.security;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Before;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * Aspect that automatically checks permissions for methods annotated with @RequirePermission
 */
@Aspect
@Component
public class PermissionAspect {
    
    private static final Logger log = LoggerFactory.getLogger(PermissionAspect.class);
    
    @Autowired
    private AuthorizationService authorizationService;  // ✅ This should now be found
    
    @Autowired
    private UserRepository userRepository;
    
    /**
     * Before any method annotated with @RequirePermission runs,
     * check if the current user has the required permission
     */
    @Before("@annotation(requirePermission)")
    public void checkPermission(RequirePermission requirePermission) throws UnauthorizedException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        
        if (authentication == null || !authentication.isAuthenticated()) {
    log.warn("Unauthenticated access attempt");
    throw new UnauthorizedException("User not authenticated");
}
        
        String userEmail = authentication.getName();
        log.debug("Checking permission {} for user {}", requirePermission.value(), userEmail);
        
        User currentUser = userRepository.findByEmail(userEmail)
                .orElseThrow(() -> new UnauthorizedException("Authenticated user could not be resolved"));
        
        if (!authorizationService.hasPermission(currentUser, requirePermission.value())) {
            throw new AccessDeniedException("Required permission is not granted");
        }
        
        log.debug("Permission {} granted for user {}", requirePermission.value(), userEmail);
    }
}
