package com.careconnect.security;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class PermissionAspectTest {

    private UserRepository userRepository;
    private RecordingUserRepository userRepositoryHandler;

    private PermissionAspect permissionAspect;

    private final RecordingAuthorizationService recordingAuthorizationService = new RecordingAuthorizationService();

    @BeforeEach
    void setUp() throws Exception {
        permissionAspect = new PermissionAspect();
        setField(permissionAspect, "authorizationService", recordingAuthorizationService);
        userRepositoryHandler = new RecordingUserRepository("patient@test.com");
        userRepository = userRepositoryForHandler(userRepositoryHandler);
        setField(permissionAspect, "userRepository", userRepository);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void checkPermission_resolvesCurrentUserAndDelegatesPermissionCheck() throws UnauthorizedException {
        User user = new User();
        user.setId(7L);
        user.setEmail("patient@test.com");
        user.setRole(Role.PATIENT);

        Authentication authentication = new UsernamePasswordAuthenticationToken("patient@test.com", "token", List.of());
        SecurityContextHolder.getContext().setAuthentication(authentication);
        userRepositoryHandler.user = user;

        permissionAspect.checkPermission(permission(Permission.VIEW_HEALTH_DATA));

        assertThat(userRepositoryHandler.lastEmail).isEqualTo("patient@test.com");
        assertThat(recordingAuthorizationService.lastUser).isSameAs(user);
        assertThat(recordingAuthorizationService.lastPermission).isEqualTo(Permission.VIEW_HEALTH_DATA);
    }

    private RequirePermission permission(Permission value) {
        return new RequirePermission() {
            @Override
            public Permission value() {
                return value;
            }

            @Override
            public Class<? extends Annotation> annotationType() {
                return RequirePermission.class;
            }
        };
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static UserRepository userRepositoryForHandler(RecordingUserRepository handler) {
        return (UserRepository) Proxy.newProxyInstance(
                UserRepository.class.getClassLoader(),
                new Class<?>[]{UserRepository.class},
                handler
        );
    }

    private static final class RecordingUserRepository implements InvocationHandler {
        private final String expectedEmail;
        private User user;
        private String lastEmail;

        private RecordingUserRepository(String expectedEmail) {
            this.expectedEmail = expectedEmail;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            if ("findByEmail".equals(method.getName())) {
                lastEmail = (String) args[0];
                if (expectedEmail.equals(lastEmail) && user != null) {
                    return Optional.of(user);
                }
                return Optional.empty();
            }
            if ("toString".equals(method.getName())) {
                return "RecordingUserRepository";
            }
            throw new UnsupportedOperationException("Unhandled method: " + method.getName());
        }
    }

    private static final class RecordingAuthorizationService extends AuthorizationService {
        private User lastUser;
        private Permission lastPermission;

        @Override
        public void requirePermission(User user, Permission permission) throws UnauthorizedException {
            lastUser = user;
            lastPermission = permission;
            super.requirePermission(user, permission);
        }
    }
}
