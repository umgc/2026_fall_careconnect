# CareConnect RBAC Programmer's Guide

## Table of Contents

1. [Overview](#overview)
2. [Roles & Permissions](#roles--permissions)
3. [Backend RBAC](#backend-rbac)
4. [Frontend RBAC](#frontend-rbac)
5. [Authentication Flow](#authentication-flow)
6. [How-To Recipes](#how-to-recipes)

---

## Overview

CareConnect uses a **role-based access control (RBAC)** system with four roles and 26 granular permissions. Authorization is enforced on both the backend (Spring Security + custom annotations) and frontend (Flutter widgets + permission helpers). JWT tokens carry the user's role, enabling both layers to make access decisions.

### Architecture at a Glance

```
┌─────────────────────────────────────────────────────────┐
│                     Frontend (Flutter)                   │
│                                                         │
│  UserProvider ──▶ RoleHelper / PermissionHelper          │
│       │                    │                             │
│       ▼                    ▼                             │
│  Route Guards      RoleWidgets / PermissionButton        │
│  (GoRouter)        (Conditional UI rendering)            │
└────────────────────────┬────────────────────────────────┘
                         │ JWT in Authorization header
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  Backend (Spring Boot)                    │
│                                                         │
│  JwtAuthenticationFilter ──▶ SecurityContext              │
│       │                            │                     │
│       ▼                            ▼                     │
│  SecurityConfig            AuthorizationService          │
│  (route-level auth)        @RequirePermission             │
│                            (method-level auth)            │
└─────────────────────────────────────────────────────────┘
```

---

## Roles & Permissions

### The Four Roles

| Role | Hierarchy Level | Description | Can Modify Data? |
|------|:-:|---|:-:|
| **ADMIN** | 0 | Full system access | Yes |
| **CAREGIVER** | 1 | Professional managing patients | Yes |
| **PATIENT** | 2 | Individual receiving care | Yes (own data) |
| **FAMILY_MEMBER** | 3 | Read-only access to a linked patient | No |

Each user has **exactly one role**, assigned at registration or by an administrator.

### Permission Matrix

| Permission | ADMIN | CAREGIVER | PATIENT | FAMILY_MEMBER |
|---|:-:|:-:|:-:|:-:|
| **User Management** | | | | |
| VIEW_ALL_USERS | x | | | |
| MANAGE_USERS | x | | | |
| ASSIGN_ROLES | x | | | |
| **Patient Management** | | | | |
| VIEW_ALL_PATIENTS | x | | | |
| VIEW_ASSIGNED_PATIENTS | x | x | | |
| CREATE_PATIENTS | x | x | | |
| UPDATE_PATIENTS | x | x | | |
| DELETE_PATIENTS | x | | | |
| **Task Management** | | | | |
| CREATE_TASKS | x | x | | |
| VIEW_TASKS | x | x | x | x |
| UPDATE_TASKS | x | x | | |
| DELETE_TASKS | x | x | | |
| COMPLETE_TASKS | x | x | x | |
| **Health Data** | | | | |
| VIEW_HEALTH_DATA | x | x | x | x |
| RECORD_HEALTH_DATA | x | x | x | |
| EXPORT_HEALTH_DATA | x | x | | |
| **Medications** | | | | |
| VIEW_MEDICATIONS | x | x | | |
| MANAGE_MEDICATIONS | x | x | | |
| **Billing** | | | | |
| VIEW_BILLING | x | x | | |
| MANAGE_SUBSCRIPTIONS | x | x | | |
| **Communication** | | | | |
| SEND_MESSAGES | x | x | x | |
| VIEW_MESSAGES | x | x | x | x |
| **Analytics** | | | | |
| VIEW_ANALYTICS | x | x | | |
| EXPORT_REPORTS | x | x | | |
| **Other** | | | | |
| USE_AI_FEATURES | x | x | x | |
| MANAGE_DEVICES | x | x | | |

**Summary:** ADMIN has all 26 permissions, CAREGIVER has 18-19, PATIENT has 7, FAMILY_MEMBER has 3 (read-only).

---

## Backend RBAC

### Key Files

| File | Purpose |
|---|---|
| `backend/core/.../security/Role.java` | Role enum with hierarchy & utility methods |
| `backend/core/.../security/Permission.java` | 26 permission enum values |
| `backend/core/.../security/RolePermissionService.java` | Static role-to-permission mappings |
| `backend/core/.../security/JwtTokenProvider.java` | JWT creation, validation, renewal |
| `backend/core/.../security/JwtAuthenticationFilter.java` | Extracts JWT, sets SecurityContext |
| `backend/core/.../security/AuthorizationService.java` | Permission & role enforcement methods |
| `backend/core/.../security/RequirePermission.java` | Annotation for declarative permission checks |
| `backend/core/.../security/PermissionAspect.java` | AspectJ interceptor for @RequirePermission |
| `backend/core/.../config/SecurityConfig.java` | Spring Security filter chain & route rules |
| `backend/core/.../model/User.java` | User entity with role/permission helpers |
| `backend/core/.../util/SecurityUtil.java` | Resolves current user from SecurityContext |

### JWT Token Structure

Tokens are signed with **HS256** and contain:

```json
{
  "sub": "user@example.com",
  "role": "CAREGIVER",
  "iat": 1710000000,
  "exp": 1710010800,
  "iss": "careconnect"
}
```

- **Default TTL:** 3 hours
- **Renewal threshold:** Automatically renewed when < 5 minutes remain
- **Delivery:** HttpOnly cookie (`AUTH=<token>`) or `Authorization: Bearer <token>` header

### Route-Level Security (SecurityConfig.java)

Spring Security defines two filter chains:

```java
// Public endpoints — no authentication required
.requestMatchers("/v1/api/auth/**").permitAll()
.requestMatchers("/v1/api/users/reset-password").permitAll()
.requestMatchers("/v1/api/billing/quote").permitAll()
.requestMatchers("/v1/api/address/**").permitAll()

// Admin-only endpoints
.requestMatchers("/v1/api/debug/**").hasRole("ADMIN")

// Everything else requires authentication
.anyRequest().authenticated()
```

### Method-Level Security — Three Patterns

#### Pattern 1: @RequirePermission Annotation (Preferred)

The cleanest approach. Apply the annotation to any controller method:

```java
@PostMapping
@RequirePermission(Permission.CREATE_TASKS)
public ResponseEntity<Task> createTask(@RequestBody TaskDto dto) {
    // Only users with CREATE_TASKS permission reach this code.
    // ADMIN and CAREGIVER have this permission.
    // PATIENT and FAMILY_MEMBER get a 403.
    return ResponseEntity.ok(taskService.create(dto));
}
```

The `PermissionAspect` intercepts the call, extracts the current user from `SecurityContext`, and calls `authorizationService.requirePermission()`. If the check fails, an `UnauthorizedException` (HTTP 403) is thrown before the method body executes.

#### Pattern 2: Programmatic Role Checks

Use `AuthorizationService` directly for role-based checks:

```java
@GetMapping("/{caregiverId}/patients")
public ResponseEntity<List<PatientDto>> getPatients(
        @PathVariable Long caregiverId) {
    User currentUser = securityUtil.resolveCurrentUser();
    authorizationService.requireAdminOrCaregiver(currentUser);
    // ...
}
```

Available enforcement methods:

```java
// Role-based (throw UnauthorizedException on failure)
authorizationService.requireAdmin(user);
authorizationService.requireCaregiver(user);
authorizationService.requireAdminOrCaregiver(user);

// Permission-based (throw on failure)
authorizationService.requirePermission(user, Permission.CREATE_TASKS);
authorizationService.requireAllPermissions(user, perm1, perm2);
authorizationService.requireAnyPermission(user, perm1, perm2);

// Patient access (ownership / link verification)
authorizationService.requirePatientAccess(user, patientId);
authorizationService.requireSelfOrAdmin(user, targetUserId);

// Non-throwing checks (return boolean)
authorizationService.hasPermission(user, permission);
authorizationService.canModifyData(user);
authorizationService.isAuthenticated(user);
```

#### Pattern 3: Switch on Role (Data-Scoping)

For endpoints where all roles can access the endpoint but see different data:

```java
@GetMapping("/{patientUserId}")
public ResponseEntity<?> getPatient(@PathVariable Long patientUserId) {
    User currentUser = getCurrentUser();

    switch (currentUser.getRole()) {
        case PATIENT:
            // Can only view own data
            if (!currentUser.getId().equals(patientUserId)) {
                throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
            }
            break;
        case CAREGIVER:
            // Must have an active link to this patient
            if (!caregiverPatientLinkService.hasAccessToPatient(
                    currentUser.getId(), patientUserId)) {
                throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
            }
            break;
        case FAMILY_MEMBER:
            // Must have an active link to this patient
            if (!familyMemberService.hasAccessToPatient(
                    currentUser.getId(), patientUserId)) {
                throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
            }
            break;
        case ADMIN:
            break; // unrestricted
    }
    // Return patient data...
}
```

### Using the Role Enum

```java
Role role = user.getRole();

// Hierarchy checks
role.getHierarchyLevel();                    // 0=ADMIN, 1=CAREGIVER, 2=PATIENT, 3=FAMILY_MEMBER
role.hasHigherOrEqualAuthorityThan(other);   // Compare authority levels
role.canModifyData();                        // false for FAMILY_MEMBER

// Type checks
role.isAdmin();
role.isCaregiver();
role.isPatient();
role.isFamilyMember();

// Display
role.getDisplayName();   // "Administrator", "Caregiver", etc.
role.getDescription();   // Longer description

// Parse from string
Role r = Role.fromString("CAREGIVER");
```

### Using the User Entity

The `User` model has convenience methods that delegate to `RolePermissionService`:

```java
User user = securityUtil.resolveCurrentUser();

user.hasPermission(Permission.CREATE_TASKS);        // single check
user.hasAllPermissions(Permission.VIEW_TASKS, ...);  // all required
user.hasAnyPermission(Permission.VIEW_TASKS, ...);   // at least one
user.getPermissions();                               // Set<Permission>
user.isAdmin();                                      // role shortcut
user.canModifyData();                                // false for FAMILY_MEMBER
```

### Exception Handling

```java
// Permission denied
throw UnauthorizedException.forPermission(email, permission);
// → HTTP 403: "User user@example.com lacks permission CREATE_TASKS"

// Role denied
throw UnauthorizedException.forRole(email, requiredRole, actualRole);
// → HTTP 403: "User user@example.com has role PATIENT but ADMIN is required"
```

### Database Schema

```sql
CREATE TABLE users (
    id        BIGSERIAL PRIMARY KEY,
    email     VARCHAR(254) NOT NULL UNIQUE,
    password  VARCHAR(255) NOT NULL,
    role      VARCHAR(20) NOT NULL
              CHECK (role IN ('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER', 'ADMIN')),
    status    VARCHAR(20) DEFAULT 'ACTIVE',
    -- ...
);
```

---

## Frontend RBAC

The frontend is a **Flutter** application. RBAC is enforced at three levels: route guards, conditional widget rendering, and permission-gated actions.

### Key Files

| File | Purpose |
|---|---|
| `frontend/lib/models/role.dart` | Role enum with string conversions |
| `frontend/lib/models/permission.dart` | Permission enum (mirrors backend) |
| `frontend/lib/utils/role_helper.dart` | Static role-check utility methods |
| `frontend/lib/utils/permission_helper.dart` | Role-to-permission mappings & checks |
| `frontend/lib/providers/user_provider.dart` | ChangeNotifier holding user session state |
| `frontend/lib/services/auth_token_manager.dart` | JWT storage, retrieval, expiry checks |
| `frontend/lib/services/user_role_storage_service.dart` | Persistent role/ID storage |
| `frontend/lib/services/enhanced_auth_service.dart` | Login with role validation |
| `frontend/lib/services/role_validator.dart` | Validates expected vs actual role |
| `frontend/lib/widgets/role_widgets.dart` | Conditional rendering widgets |
| `frontend/lib/widgets/role_mismatch_dialog.dart` | Dialog for wrong-role login |
| `frontend/lib/config/router/app_router.dart` | GoRouter with auth guards |
| `frontend/lib/config/navigation/bottom_nav_config.dart` | Role-based navigation tabs |

### State Management

User state is managed by `UserProvider` (a `ChangeNotifier`) and persisted across app restarts via two storage services:

```
┌──────────────────┐      sync      ┌─────────────────────────┐
│   UserProvider    │ ◀────────────▶ │ UserRoleStorageService   │
│  (in-memory)     │                │ (SharedPreferences)      │
│                  │                └─────────────────────────┘
│  _user           │      sync      ┌─────────────────────────┐
│  _patientModel   │ ◀────────────▶ │ AuthTokenManager         │
│  _caregiverModel │                │ (SecureStorage / prefs)   │
└──────────────────┘                └─────────────────────────┘
```

**UserProvider key properties & methods:**

```dart
// State
UserSession? get user;
bool get isLoggedIn;
bool get isCaregiver;
bool get isPatient;

// Lifecycle
await initializeUser();       // App startup — restore from storage
setUser(UserSession session);  // After login
await fetchUserDetails();     // Load role-specific data from API
clearUser();                  // Logout
await validateSession();      // Check token validity
```

**UserSession key properties:**

```dart
int id;
String email;
String role;          // "ADMIN", "CAREGIVER", "PATIENT", "FAMILY_MEMBER"
String token;         // JWT
int? patientId;
int? caregiverId;
bool get hasWriteAccess;  // true for CAREGIVER only
```

### Route Protection (GoRouter)

Routes are protected in `app_router.dart` using `FutureBuilder` to check authentication state:

```dart
GoRoute(
  path: '/dashboard',
  builder: (context, state) {
    return FutureBuilder<UserData>(
      future: UserRoleStorageService().getUserData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return LoadingScreen();

        final userData = snapshot.data!;
        if (!userData.isLoggedIn || userData.userId <= 0) {
          // Not authenticated — redirect to login
          return LoginPage();
        }

        // Build role-specific screen configuration
        final config = _buildConfigForRole(userData);
        return MainScreen(config: config);
      },
    );
  },
)
```

### Role-Based Navigation

Different roles see different bottom navigation tabs:

```dart
// BottomNavConfig.getNavItemsForRole(role)

// PATIENT sees:
//   Home | Symptoms | Health | Messages | Menu

// CAREGIVER sees:
//   Patients | Dashboard | Messages | Analytics | Menu
```

The `MainScreenConfig` factory methods configure the shell per role:

```dart
MainScreenConfig.forPatient(userId, patientId);
MainScreenConfig.forCaregiver(userId, caregiverId, patientId);
MainScreenConfig.forFamilyMember(userId, patientId);
```

### Conditional UI Rendering

#### Role Widgets

Wrap UI sections with role-specific widgets to show/hide based on the user's role:

```dart
// Show only to admins
AdminOnly(
  userRole: currentRole,
  child: ElevatedButton(
    onPressed: () => manageUsers(),
    child: Text('Manage Users'),
  ),
)

// Show to caregivers and admins
CaregiverOrAdmin(
  userRole: currentRole,
  child: TaskCreateButton(),
)

// Hide from family members (show to everyone else)
NotFamilyMember(
  userRole: currentRole,
  child: EditHealthDataForm(),
)

// Custom role check
RoleWidget(
  userRole: currentRole,
  shouldShow: (role) => role == 'ADMIN' || role == 'CAREGIVER',
  child: SomeWidget(),
)
```

#### Permission Widgets

For finer-grained control, use permission-based widgets:

```dart
// Button only appears if user has CREATE_TASKS permission
PermissionButton(
  permission: Permission.CREATE_TASKS,
  onPressed: () => createTask(),
  child: Text('New Task'),
)

// Icon button gated on permission
PermissionIconButton(
  permission: Permission.DELETE_PATIENTS,
  onPressed: () => deletePatient(),
  icon: Icon(Icons.delete),
)

// Menu item gated on permission
PermissionMenuItem(
  permission: Permission.MANAGE_MEDICATIONS,
  leading: Icon(Icons.medical_services),
  title: 'Manage Medications',
  onTap: () => openMedications(),
)
```

### RoleHelper Utility

Static methods for quick role checks:

```dart
RoleHelper.isAdmin(role);            // bool
RoleHelper.isCaregiver(role);        // includes FAMILY_LINK
RoleHelper.isPatient(role);
RoleHelper.isFamilyMember(role);
RoleHelper.isCaregiverOrAdmin(role);
RoleHelper.canModifyData(role);      // false for FAMILY_MEMBER
RoleHelper.canManagePatients(role);  // CAREGIVER or ADMIN
RoleHelper.getRoleDisplayName(role); // "Administrator", etc.
RoleHelper.getRoleColorValue(role);  // Color for role badges
```

### PermissionHelper Utility

Mirrors the backend `RolePermissionService` exactly:

```dart
PermissionHelper.hasPermission(role, Permission.CREATE_TASKS);     // bool
PermissionHelper.hasAnyPermission(role, [perm1, perm2]);           // bool
PermissionHelper.hasAllPermissions(role, [perm1, perm2]);          // bool
```

### Role Validation on Login

The `EnhancedAuthService` validates that the user's actual role matches the login flow they used (e.g., a patient shouldn't log in via the caregiver login page):

```dart
final result = await EnhancedAuthService.loginWithRoleValidation(
  email: email,
  password: password,
  expectedRole: 'CAREGIVER',
);

if (!result.isSuccess) {
  // Show RoleMismatchDialog — offers to redirect to correct login page
  showDialog(context: context, builder: (_) => RoleMismatchDialog(...));
}
```

### Token Management

```dart
final manager = AuthTokenManager();

// Save after login
await manager.saveAuthData(jwtToken, userSession);

// Get token for API calls
String? token = await manager.getJwtToken();  // null if expired

// Get auth headers for HTTP requests
Map<String, String> headers = await manager.getAuthHeaders();
// → {"Authorization": "Bearer <token>", "Content-Type": "application/json"}

// Session staleness (60-minute inactivity timeout)
bool stale = await manager.isSessionStale(maxInactiveMinutes: 60);

// Restore on app startup
UserSession? session = await manager.restoreSession();

// Clear on logout
await manager.clearAuthData();
```

---

## Authentication Flow

### Login Flow (End-to-End)

```
1. User enters credentials on login page
                    │
2. Frontend calls   │  POST /v1/api/auth/login
   AuthService      │  Body: { email, password }
                    ▼
3. Backend verifies credentials, creates JWT with role claim
   Returns: { token, user: { id, email, role, ... } }
                    │
4. Frontend stores  │  AuthTokenManager.saveAuthData(token, session)
   token & session  │  UserRoleStorageService.setUserData(role, userId, ...)
                    │  UserProvider.setUser(session)
                    ▼
5. Frontend loads   │  UserProvider.fetchUserDetails()
   role-specific    │  (calls patient or caregiver API based on role)
   data             │
                    ▼
6. Navigate to role-appropriate dashboard
   - PATIENT → /dashboard/patient
   - CAREGIVER → /dashboard/caregiver
```

### Request Authentication Flow

```
1. Frontend makes API request
   Headers: { Authorization: "Bearer <jwt>" }
                    │
                    ▼
2. JwtAuthenticationFilter intercepts request
   - Extracts token from header or AUTH cookie
   - Validates signature & expiration
   - Extracts email + role from claims
   - Sets SecurityContext with authenticated user
   - If token near expiry, issues renewed token
                    │
                    ▼
3. SecurityConfig checks route-level rules
   - Public route? → Allow
   - Admin-only route? → Check role
   - Otherwise → Require authenticated
                    │
                    ▼
4. Controller method executes
   - @RequirePermission checks permission via PermissionAspect
   - Or manual authorizationService.require*() calls
   - Or switch-on-role for data scoping
                    │
                    ▼
5. Success → 200 with data
   Unauthorized → 403 with error message
```

### Session Lifecycle

```
App Start
    │
    ▼
UserProvider.initializeUser()
    │
    ├── AuthTokenManager.restoreSession()
    │       │
    │       ├── Token exists & valid? ──▶ Set user, fetchUserDetails()
    │       │
    │       └── No token or expired? ──▶ Clear state, show login
    │
    ▼
During Use
    │
    ├── Each API call updates last-activity timestamp
    ├── Token auto-renewed when < 5 min remaining
    ├── 60-minute inactivity timeout → auto-logout
    │
    ▼
Logout
    │
    ├── POST /v1/api/auth/logout
    ├── AuthTokenManager.clearAuthData()
    ├── UserRoleStorageService.clearUserData()
    └── UserProvider.clearUser()
```

---

## How-To Recipes

### Add a New Permission

1. **Backend** — Add to `Permission.java` enum:
   ```java
   MANAGE_SCHEDULES("manage:schedules", "Manage Schedules", PermissionCategory.SCHEDULING)
   ```

2. **Backend** — Map it to roles in `RolePermissionService.java`:
   ```java
   // In the static initializer block, add to relevant role sets:
   caregiverPermissions.add(Permission.MANAGE_SCHEDULES);
   ```

3. **Frontend** — Add to `permission.dart` enum:
   ```dart
   MANAGE_SCHEDULES,
   ```

4. **Frontend** — Add to role mappings in `permission_helper.dart`:
   ```dart
   // In _getCaregiverPermissions():
   Permission.MANAGE_SCHEDULES,
   ```

### Protect a New Backend Endpoint

**Option A — Annotation (recommended for simple permission checks):**
```java
@PostMapping("/schedules")
@RequirePermission(Permission.MANAGE_SCHEDULES)
public ResponseEntity<Schedule> createSchedule(@RequestBody ScheduleDto dto) {
    // Only users with MANAGE_SCHEDULES permission can reach this
}
```

**Option B — Programmatic (for complex logic):**
```java
@PutMapping("/schedules/{id}")
public ResponseEntity<Schedule> updateSchedule(
        @PathVariable Long id, @RequestBody ScheduleDto dto) {
    User user = securityUtil.resolveCurrentUser();
    authorizationService.requirePermission(user, Permission.MANAGE_SCHEDULES);

    // Additional ownership check
    Schedule schedule = scheduleService.findById(id);
    if (!schedule.getCreatedBy().equals(user.getId()) && !user.isAdmin()) {
        throw new AppException(HttpStatus.FORBIDDEN, "Can only edit own schedules");
    }
    // ...
}
```

### Hide a Frontend UI Element by Role

```dart
// Using role widgets
CaregiverOrAdmin(
  userRole: provider.user?.role ?? '',
  child: FloatingActionButton(
    onPressed: () => createSchedule(),
    child: Icon(Icons.add),
  ),
)

// Using permission widgets
PermissionButton(
  permission: Permission.MANAGE_SCHEDULES,
  onPressed: () => createSchedule(),
  child: Text('New Schedule'),
)

// Using helpers directly in build logic
if (RoleHelper.canManagePatients(currentRole)) {
  // show management controls
}

if (PermissionHelper.hasPermission(currentRole, Permission.MANAGE_SCHEDULES)) {
  // show schedule controls
}
```

### Starting Bedrock ###
1. **Enter credentials** 
  Need to install AWS CLI and run:
       aws configure
  
  You will need to enter the following data:
  AWS Access Key ID: YOUR_KEY
  AWS Secret Access Key: YOUR_SECRET
  Default region name: us-east-1
  Default output format: json

  If you have a student account after the aws secret access key
  you will need to enter an AWS session token. You know you have
  a student account if your AWS access key ID starts with ASIA. 
  FOr the student account you will need to put the new keys in 
  every day. For a regular account the AWS access key starts
  with AZIA.

2. **Set S3 Bucket**
  In your AWS account you will need to create a S3 bucket and
  remember the name you give it.

  On windows in powershell enter the command:
        $env:AWS_S3_BUCKET="name_of_bucket"
  
  Alternatively you can go to your application-dev.properties
  and enter the bucket name in: 
        aws.s3.bucket="enter bucket name here"

3. **Request access to the model**
  In your AWS account go amazon bedrock, go to playground, select
  model. In section 1 click amazon, in section 2 click Nova Lite 1.0
  then click apply. Write anythng in the prompt at the bottom and
  make sure you get a response. This means you have access to it. If
  not you will need to request access to it.

4. **Enable LLM and AWS**
  In application-dev.properties make sure you have:
    careconnect.aws.enabled=true
    careconnect.llm.enabled=true
    careconnect.ai.provider=bedrock

5. **Run Backend**
  In a terminal/powershell/visual studio code go togi the /backend/core
  directory and run the command:
      .\mvnw,cmd clean install
      .\mvnw.cmd spring-boot: run "-Dspring-boot.run.profiles=dev"

6. **Test via Swagger UI**
  Open in a browser:
      http://localhost:8080/swagger-ui/index.html
  
  Find the endpoint:
      POST /v1/api/invoices/extract-llm
  
  You will need an image of an invoice as a JPEG or PNG. Click on
  the execute button and you should see:
      {
        "invoice": {
        "invoiceNumber": 
        "provider": {
          "name": 
        },
        "amounts": {
          "total":
        },
        "aiSummary": "{ ... AI extracted JSON ... }"
        }
      }  

### Add a New Role

> Adding a new role is a significant change. Follow these steps carefully.

1. **Database** — Add migration to update the CHECK constraint:
   ```sql
   ALTER TABLE users DROP CONSTRAINT users_role_check;
   ALTER TABLE users ADD CONSTRAINT users_role_check
       CHECK (role IN ('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER', 'ADMIN', 'NEW_ROLE'));
   ```

2. **Backend** — Add to `Role.java` enum with hierarchy level, display name, description.

3. **Backend** — Add permission set in `RolePermissionService.java`.

4. **Backend** — Update `AuthorizationService.java` if new composite checks are needed.

5. **Frontend** — Add to `role.dart` and `role-enum.dart`.

6. **Frontend** — Add permission mappings in `permission_helper.dart`.

7. **Frontend** — Add helper methods to `role_helper.dart`.

8. **Frontend** — Add role widget variant in `role_widgets.dart` if needed.

9. **Frontend** — Add navigation config in `bottom_nav_config.dart` and `main_screen_config.dart`.

10. **Frontend** — Update `role_validator.dart` for login flow routing.

### Test RBAC During Development

The frontend includes a built-in RBAC test screen at `frontend/lib/screens/rbac_test_screen.dart`. It provides:

- Mock login buttons for each role
- Live display of current user info
- Visual indicators showing which role-based widgets are visible
- Permission-gated button testing

Use this screen during development to verify that your role/permission changes work correctly across all roles without needing to log in and out repeatedly.
