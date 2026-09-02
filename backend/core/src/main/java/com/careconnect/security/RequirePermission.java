package com.careconnect.security;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Annotation to require a specific permission for a controller method.
 * <p>
 * Usage:
 *
 * @GetMapping("/{id}")
 * @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS) public ResponseEntity<?> getPatient(@PathVariable Long id) { ... }
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RequirePermission {
    Permission value();  // ✅ Permission is in the same package, so no import needed
}