# CareConnect 2025 Programmer's Guide

## Introduction

### Purpose and Vision

This Programmer's Guide serves as the central hub of technical knowledge for the CareConnect platform, a comprehensive healthcare management system designed to connect patients, caregivers, and family members in a seamless digital ecosystem. Its purpose is threefold:

**Onboarding**: To rapidly acclimate new developers to our complex, multi-technology stack by explaining the architectural decisions and development workflows. Rather than simply listing technologies, we explain *why* each was chosen and how they work together to create a cohesive healthcare platform.

**Reference**: To provide clear, actionable examples and explanations for implementing features across the frontend, backend, and integrated services. Each code example is accompanied by context explaining its role in the larger system architecture.

**Troubleshooting**: To offer a curated set of solutions for common pitfalls, ensuring developer efficiency and system stability. Our troubleshooting sections follow a Problem → Root Cause → Step-by-Step Solution approach for clarity.

This document goes beyond simply listing endpoints and code; it explains the reasoning behind our design patterns, such as why we chose JWT for stateless authentication in a healthcare context and how our WebSocket architecture ensures real-time updates for critical patient alerts.

### Intended Audience

This guide is designed for:

- **New developers** joining the CareConnect team who need to understand not just what the system does, but why it was built this way
- **Experienced engineers** seeking reference material for implementing new features or debugging complex issues
- **System administrators** who need to understand the architecture to properly deploy and maintain the platform
- **Technical leads** who need to make informed decisions about future architectural directions

The guide assumes familiarity with software development principles but provides context for domain-specific healthcare considerations and our specific technology choices.

### Technology Overview and Rationale

CareConnect is built with a carefully selected stack of modern, scalable technologies. Each choice was made to balance healthcare industry requirements, developer productivity, and long-term maintainability:

**Frontend - Flutter (cross-platform mobile/web)**
We selected Flutter for its unique ability to create truly native experiences across iOS, Android, web, and desktop from a single codebase. In healthcare, where users may access the platform from various devices, this cross-platform capability is crucial. Flutter's reactive framework and rich widget library also enable us to build complex, accessible UIs that meet healthcare usability standards.

**Backend - Spring Boot 3.4.5 with Java 17**
Spring Boot was chosen for its enterprise-grade maturity, extensive ecosystem, and strong security features—all critical for healthcare applications handling sensitive patient data. Java 17's modern features (sealed classes, records, pattern matching) allow us to write more expressive, type-safe code while maintaining backwards compatibility with existing Java systems common in healthcare infrastructure.

**Database - PostgreSQL with JPA/Hibernate**
PostgreSQL provides the ACID compliance and data integrity guarantees essential for medical records. Its support for JSON columns allows us to store flexible health data structures while maintaining strong relational integrity for core entities like users and medications. JPA/Hibernate abstracts database operations while giving us fine-grained control when needed for complex healthcare queries.

**AI Integration - Spring AI + DeepSeek/LangChain4j**
Healthcare applications benefit enormously from AI for tasks like health risk assessment and intelligent scheduling. We use Spring AI's abstraction layer with DeepSeek and LangChain4j to provide AI-powered features while maintaining the flexibility to switch or combine AI providers as the technology evolves.

**Security - JWT-based authentication**
JWT (JSON Web Tokens) enable stateless authentication, crucial for our distributed architecture and real-time features. In healthcare, where audit trails and precise access control are mandatory, JWT's self-contained claims allow us to verify user identity and permissions without database lookups on every request, while still maintaining security through signature verification.

**Real-time Communication - WebSocket**
Healthcare scenarios often require immediate notification (medication reminders, vital sign alerts, emergency communications). WebSocket provides the persistent, bidirectional connection needed for these real-time features, while our fallback to HTTP polling ensures reliability even in constrained network environments.

**Cloud Infrastructure - AWS**
AWS provides the scalability, security certifications (HIPAA compliance options), and service breadth needed for healthcare applications. Our infrastructure-as-code approach using Terraform ensures reproducible, auditable deployments—a requirement for regulated healthcare environments.

## Architecture Overview

### System Architecture and Design Philosophy

CareConnect follows a microservices-inspired architecture with clear separation between frontend, backend, and data layers. This architectural approach was chosen to enable independent scaling, deployment, and development of each layer while maintaining loose coupling and high cohesion—principles essential for a healthcare platform that must evolve rapidly to meet changing regulatory and clinical requirements.

#### Layered Architecture Benefits

**Frontend Isolation**: The Flutter frontend communicates with the backend exclusively through well-defined REST and WebSocket APIs. This means we can completely rewrite the mobile app, add a web interface, or develop a desktop client without touching backend code. For healthcare providers who might want to access CareConnect from different devices (tablet in patient rooms, desktop in offices, mobile while on rounds), this flexibility is crucial.

**Backend Independence**: The Spring Boot backend owns all business logic and data validation. Even if the frontend is compromised or contains bugs, the backend enforces all critical rules (medication dosages, user permissions, data validation). In healthcare, this defense-in-depth approach is a regulatory requirement.

**Data Layer Abstraction**: The database is accessed only through JPA repositories, never via direct SQL in controllers or frontend code. This abstraction makes it possible to migrate to a different database, implement read replicas for scaling, or add caching layers without affecting the rest of the application.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend Layer                           │
│                                                                 │
│  Responsibility: User interface and user experience             │
│  Technology: Flutter (Dart)                                     │
│  Key Concerns: Cross-platform compatibility, offline support,   │
│                accessibility, responsive design                 │
├─────────────────────────────────────────────────────────────────┤
│  Flutter App (Web, iOS, Android, Desktop)                      │
│  ├── Provider (State Management)                               │
│  │   └── Manages UI state, exposes data to widgets            │
│  ├── GoRouter (Navigation)                                     │
│  │   └── Declarative routing, deep linking, guards            │
│  ├── Dio (HTTP Client)                                         │
│  │   └── REST API calls, interceptors, error handling         │
│  └── Features (Modular Architecture)                           │
│      └── Self-contained feature modules (auth, health, etc.)  │
└─────────────────────────────────────────────────────────────────┘
                                │
                         HTTP/WebSocket
                   (JSON over HTTPS/WSS)
                                │
┌─────────────────────────────────────────────────────────────────┐
│                        Backend Layer                            │
│                                                                 │
│  Responsibility: Business logic, data validation, security      │
│  Technology: Spring Boot (Java 17)                              │
│  Key Concerns: HIPAA compliance, data integrity, performance,   │
│                API versioning, audit logging                    │
├─────────────────────────────────────────────────────────────────┤
│  Spring Boot Application                                        │
│  ├── Controllers (REST API)                                    │
│  │   └── HTTP request handling, parameter validation,         │
│  │       response formatting, API documentation                │
│  ├── Services (Business Logic)                                 │
│  │   └── Transaction management, complex workflows,           │
│  │       business rules enforcement, orchestration             │
│  ├── Repositories (Data Access)                                │
│  │   └── Database queries, JPA entity management,             │
│  │       query optimization, data retrieval                    │
│  ├── WebSocket (Real-time Communication)                       │
│  │   └── Persistent connections, event streaming,             │
│  │       push notifications, bidirectional messaging           │
│  └── Security (JWT Authentication)                             │
│      └── Token validation, authorization, RBAC,               │
│          session management, security filters                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                           JDBC/JPA
                    (SQL over TCP/IP)
                                │
┌─────────────────────────────────────────────────────────────────┐
│                         Data Layer                              │
│                                                                 │
│  Responsibility: Data persistence, integrity, backup            │
│  Technology: PostgreSQL 15+                                     │
│  Key Concerns: ACID compliance, encryption at rest, backups,    │
│                query performance, data retention                │
├─────────────────────────────────────────────────────────────────┤
│  PostgreSQL Database                                            │
│  ├── User Management                                            │
│  │   └── Authentication credentials, user profiles,           │
│  │       roles and permissions, account status                 │
│  ├── Health Data                                                │
│  │   └── Vital signs, medications, allergies, conditions,     │
│  │       lab results, medical history                          │
│  ├── Communication                                              │
│  │   └── Messages, call logs, notifications, WebSocket        │
│  │       connection tracking, chat history                     │
│  └── File Storage                                               │
│      └── Medical records metadata, file paths, document        │
│          categories, upload timestamps, access logs            │
└─────────────────────────────────────────────────────────────────┘
```

#### Data Flow Example: Recording a Blood Pressure Reading

To understand how these layers work together, let's trace a complete user action through the system:

1. **User Input (Frontend Layer)**:
   - Patient opens Health screen, taps "Record Vital Sign"
   - Enters blood pressure: 140/90 mmHg
   - Adds note: "Measured after morning medication"
   - Taps "Save"

2. **State Management (Frontend)**:
   - HealthProvider's `recordVitalSign()` method is called
   - Provider sets `isLoading = true`, triggering UI to show loading indicator
   - Provider calls HealthService to make API request

3. **API Request (Frontend → Backend)**:
   - Dio HTTP client constructs POST request to `/api/health/vitals`
   - AuthInterceptor automatically adds JWT token from secure storage
   - Request body: `{"type": "blood_pressure", "systolic": 140, "diastolic": 90, "notes": "..."}`
   - LoggingInterceptor logs request for debugging

4. **Request Reception (Backend - Controller Layer)**:
   - `HealthController.recordVitalSign()` receives request
   - Spring Security validates JWT token, extracts user ID
   - JSR-380 validation checks request body structure
   - Controller passes validated DTO to Service layer

5. **Business Logic (Backend - Service Layer)**:
   - `HealthService.recordVitalSign()` begins transaction
   - Verifies user exists and has permission to record vitals
   - Converts DTO to JPA entity
   - Saves entity via Repository (triggers database INSERT)
   - **Critical business logic**: Checks if 140/90 exceeds patient's normal range
   - If abnormal, calls NotificationService to alert caregiver
   - Converts saved entity back to DTO
   - Returns DTO to controller

6. **Data Persistence (Backend - Repository/Database)**:
   - JPA translates entity to SQL: `INSERT INTO vital_signs (user_id, type, systolic, diastolic, ...) VALUES (...)`
   - PostgreSQL executes INSERT within transaction
   - Database enforces constraints (foreign keys, not-null, unique)
   - Returns generated ID and timestamp
   - Transaction commits (all data saved) or rolls back (on any error)

7. **Response (Backend → Frontend)**:
   - Controller returns HTTP 201 Created with saved vital sign data
   - ErrorInterceptor doesn't trigger (successful response)
   - Dio receives response and parses JSON

8. **State Update (Frontend)**:
   - HealthProvider updates local state with new vital sign
   - Calls `notifyListeners()` to rebuild UI
   - HealthScreen automatically updates to show new reading
   - Loading indicator disappears

9. **Real-time Notification (Parallel Flow)**:
   - If reading was abnormal, NotificationService also sent WebSocket message
   - Caregiver's app, connected to `/ws/careconnect`, receives alert
   - Their HealthDashboard automatically shows "Patient [Name] recorded elevated BP: 140/90"
   - Caregiver can tap notification to view patient's full vital history

**Total time**: ~500ms from button tap to UI update and caregiver notification. This is the power of a well-architected system: complex workflows feel instantaneous to users.

#### Why This Architecture for Healthcare?

**Auditability**: Every layer logs its actions. We can trace a medication order from UI tap → API call → service logic → database insert → notification sent, critical for regulatory compliance.

**Security**: Multiple validation layers. Even if frontend is compromised, backend still enforces business rules. Even if backend is misconfigured, database constraints prevent invalid data.

**Scalability**: Each layer can scale independently. High load from mobile users? Scale frontend servers. Complex analytics queries? Scale database read replicas. Real-time notifications spiking? Scale WebSocket handlers.

**Maintainability**: Clear separation of concerns. UI developers work in Flutter, backend developers in Spring Boot, database admins tune PostgreSQL—all in parallel without conflicts.

**Testability**: Each layer can be tested in isolation. Mock the API for frontend tests, mock the database for service tests, integration tests verify the full stack.

### Technology Stack

**Frontend (Flutter):**
- **Framework**: Flutter 3.9.2+
- **State Management**: Provider
- **Routing**: GoRouter
- **HTTP Client**: Dio
- **Local Storage**: SharedPreferences, SQLite
- **Real-time**: WebSocket, Socket.IO

**Backend (Spring Boot):**
- **Framework**: Spring Boot 3.4.5
- **Security**: Spring Security + JWT
- **Data Access**: Spring Data JPA
- **Database**: PostgreSQL 15+
- **WebSocket**: Spring WebSocket
- **Documentation**: OpenAPI 3

**Infrastructure:**
- **Cloud Provider**: AWS
- **Infrastructure as Code**: Terraform
- **Containerization**: Docker
- **CI/CD**: GitHub Actions

## Development Environment Setup

Setting up a development environment for CareConnect requires careful orchestration of multiple technologies: Flutter for the frontend, Java/Spring Boot for the backend, PostgreSQL for the database, and various supporting tools. This section guides you through the setup process, explaining not just the *what* but the *why* behind each requirement.

### Prerequisites and System Requirements

Before beginning, ensure your system meets these requirements. These aren't arbitrary—each is chosen to match production environment requirements and ensure team-wide compatibility.

#### Essential Software

**Flutter SDK 3.9.2 or higher**
- **Why this version?** Flutter 3.9.2 introduced stable support for desktop platforms (Windows, macOS, Linux), which CareConnect uses for caregiver dashboard applications. Earlier versions had breaking API changes that would require code modifications.
- **Installation**: Download from [flutter.dev](https://flutter.dev/docs/get-started/install)
- **Verification**: Run `flutter doctor -v` after installation
- **Common issues**: Ensure Flutter bin directory is in your PATH

**Java Development Kit (JDK) 17**
- **Why version 17 specifically?** Spring Boot 3.4.5 requires Java 17 minimum. This version includes critical features like Records (used for DTOs), sealed classes (used for domain modeling), and pattern matching (used in service layer logic).
- **Not Java 11 or 8**: These older versions lack language features our codebase uses. Compilation will fail with cryptic errors.
- **Not Java 18+**: While these would work, Java 17 is the current LTS (Long Term Support) version, matching what we deploy to production.
- **Installation**: Use OpenJDK from [adoptium.net](https://adoptium.net/) or your system package manager
- **Verification**: `java -version` should show `openjdk version "17.x.x"`

**Maven 3.6 or higher**
- **Why Maven?** Spring Boot projects traditionally use Maven for dependency management. While Gradle is an alternative, Maven's declarative approach and extensive plugin ecosystem make it ideal for our complex dependency graph (Spring AI milestones, security libraries, database drivers, etc.).
- **Installation**: Often bundled with Java IDEs, or download from [maven.apache.org](https://maven.apache.org/)
- **Note**: CareConnect includes Maven Wrapper (`mvnw`), so Maven installation is optional—the wrapper downloads the correct version automatically.
- **Verification**: `./mvnw -version` (uses wrapper) or `mvn -version` (uses system Maven)

**PostgreSQL 15 or higher** (previously MySQL, recently migrated)
- **Why PostgreSQL?** Superior support for JSON columns (storing flexible health data), better ACID compliance (critical for medical records), more robust handling of concurrent transactions (multiple caregivers accessing same patient data).
- **Why not MySQL?** MySQL was the original database, but PostgreSQL's advanced features (JSONB indexing, row-level security, materialized views) better support our analytics and reporting needs.
- **Installation**: 
  - **macOS**: `brew install postgresql@15`
  - **Windows**: Download installer from [postgresql.org](https://www.postgresql.org/download/windows/)
  - **Linux**: `sudo apt install postgresql-15` (Ubuntu/Debian)
  - **Docker**: `docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:15`
- **Verification**: `psql --version` should show PostgreSQL 15.x

**Git (latest version)**
- **Why Git?** Version control is essential for team collaboration. CareConnect uses GitHub for source control, CI/CD, and issue tracking.
- **Installation**: Download from [git-scm.com](https://git-scm.com/)
- **Configuration**: After installation, configure your identity:
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "your.email@example.com"
  ```
- **Verification**: `git --version`

**Integrated Development Environment (IDE)**
- **VS Code**: Lightweight, excellent Flutter support via extensions, fast startup. Recommended for frontend development.
  - Required extensions: "Flutter", "Dart"
  - Recommended: "GitLens", "Error Lens", "Prettier"
  
- **Android Studio**: Official Android IDE, includes Android SDK and emulator. Best for testing Android-specific features.
  - Includes Flutter plugin
  - Required for Android builds
  
- **IntelliJ IDEA**: Powerful Java IDE, excellent Spring Boot integration. Recommended for backend development.
  - Ultimate edition has better Spring support (paid)
  - Community edition works fine for basic development (free)
  - Required plugins: "Spring Boot", "JPA Buddy"

**Why multiple IDEs?** Different tools excel at different tasks. VS Code is fast for quick frontend edits, Android Studio is essential for mobile debugging, IntelliJ is unmatched for Spring Boot refactoring. Most developers keep all three installed and use whichever fits the current task.

### Clone and Initial Setup

#### 1. Clone the Repository

```bash
# Clone from GitHub (use SSH if you have SSH keys configured)
git clone https://github.com/umgc/2025_fall.git
cd 2025_fall/careconnect2025

# Or use HTTPS
git clone https://github.com/umgc/2025_fall.git
cd 2025_fall/careconnect2025
```

**Repository Structure Overview**: The repository contains multiple projects:
- `careconnect2025/frontend/` - Flutter mobile/web application
- `careconnect2025/backend/core/` - Spring Boot backend API
- `careconnect2025/terraform_aws/` - Infrastructure as Code for AWS deployment
- `careconnect2025/docs/` - Documentation including this guide

#### 2. Set Up PostgreSQL Database

```bash
# Start PostgreSQL (if not already running)
# macOS: brew services start postgresql@15
# Linux: sudo systemctl start postgresql
# Windows: Start from Services or PostgreSQL menu

# Create database and user
psql -U postgres  # Connect as postgres superuser
```

Then in the psql prompt:
```sql
-- Create dedicated database for CareConnect
CREATE DATABASE careconnect;

-- Create dedicated user (security best practice: don't use postgres superuser)
CREATE USER careconnect WITH ENCRYPTED PASSWORD 'your_secure_password_here';

-- Grant all privileges on the database to the user
GRANT ALL PRIVILEGES ON DATABASE careconnect TO careconnect;

-- Grant schema creation (needed for Flyway migrations)
GRANT CREATE ON DATABASE careconnect TO careconnect;

-- Exit psql
\q
```

**Why a dedicated user?** In production, the application should never connect as the postgres superuser. Using a limited user means even if the application is compromised, attackers can't drop other databases or modify PostgreSQL settings. This principle of least privilege is a security best practice.

**Why this password?** For local development, use a simple password. For production, environment variables provide secure passwords.

#### 3. Configure Backend Environment

Create `backend/core/src/main/resources/application-dev.properties`:

```properties
# Database Configuration
# JDBC URL points to local PostgreSQL instance
spring.datasource.url=jdbc:postgresql://localhost:5432/careconnect
spring.datasource.username=careconnect
spring.datasource.password=your_secure_password_here
spring.datasource.driver-class-name=org.postgresql.Driver

# JPA Configuration
# ddl-auto=update automatically creates/updates tables based on @Entity classes
# This is convenient for development but NEVER use in production
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true  # Log all SQL queries (helpful for debugging)
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.properties.hibernate.format_sql=true  # Pretty-print SQL in logs

# Server Configuration
server.port=8080  # Backend listens on port 8080
server.servlet.context-path=/  # Root path (no prefix like /api)

# JWT Configuration
# IMPORTANT: Generate a strong secret for development
# openssl rand -base64 32  # Use this command to generate
jwt.secret=YourStrongJwtSecretKeyHereMinimum32CharactersLong
jwt.expiration=86400000  # 24 hours in milliseconds

# CORS Configuration
# Allow frontend to connect from these origins during development
cors.allowed-origins=http://localhost:3000,http://localhost:50030,http://127.0.0.1:3000

# Logging
logging.level.com.careconnect=DEBUG  # Verbose logging for our code
logging.level.org.springframework.web=DEBUG  # See all HTTP requests
logging.level.org.hibernate.SQL=DEBUG  # See all SQL queries

# Development-specific settings
spring.devtools.restart.enabled=true  # Auto-restart on code changes
spring.jpa.properties.hibernate.show_sql=true
```

**Critical Settings Explained**:
- `ddl-auto=update`: Automatically creates tables when you run the app. Convenient but dangerous—doesn't handle schema changes well, can cause data loss. Use Flyway migrations in production.
- `show-sql=true`: Logs every SQL query. Essential for debugging but creates huge logs in production—disable there.
- `jwt.secret`: Must be at least 32 characters for HS256 algorithm. In production, load from environment variable, not hardcoded.

#### 4. Set Up Frontend Environment

Create `frontend/.env`:

```bash
# API Configuration
# These differ by platform because of how emulators handle localhost
CC_BASE_URL_WEB=http://localhost:8080        # Web app running in browser
CC_BASE_URL_ANDROID=http://10.0.2.2:8080     # Android emulator special IP
CC_BASE_URL_IOS=http://localhost:8080        # iOS simulator
CC_BASE_URL_OTHER=http://localhost:8080      # Desktop platforms

# JWT Configuration (must match backend)
JWT_SECRET=YourStrongJwtSecretKeyHereMinimum32CharactersLong

# AI Services (optional for basic development)
DEEPSEEK_API_KEY=your_deepseek_api_key_here  # Only needed for AI features
OPENAI_API_KEY=your_openai_api_key_here      # Only needed for AI chat

# Backend Authentication
CC_BACKEND_TOKEN=your_backend_token  # For server-to-server communication
```

**Platform-Specific Base URLs**: 
- Web: Uses standard `localhost:8080`
- Android emulator: Uses `10.0.2.2` which is a special IP that the Android emulator maps to the host machine's `localhost`
- iOS simulator: Can use `localhost` directly because it shares the host's network

The app automatically selects the correct URL based on the platform it's running on.

#### 5. Install Dependencies

**Backend**:
```bash
cd backend/core

# Using Maven Wrapper (recommended - uses exact version project needs)
./mvnw clean install

# This downloads all dependencies from Maven Central and Spring repositories
# First time takes 5-10 minutes depending on internet speed
# Subsequent runs are fast (dependencies are cached in ~/.m2/repository)
```

**Frontend**:
```bash
cd frontend

# Download all Dart packages declared in pubspec.yaml
flutter pub get

# Verify Flutter setup
flutter doctor -v

# This checks:
# ✓ Flutter SDK installed
# ✓ Android toolchain (if you want Android builds)
# ✓ Xcode (macOS only, if you want iOS builds)
# ✓ Chrome (for web builds)
# ✓ VS Code / Android Studio (optional)
```

**Understanding `flutter doctor` output**:
- ✓ Green checkmark: All good
- ⚠ Yellow warning: Optional feature not configured (e.g., iOS on Windows)
- ✗ Red X: Required component missing or broken

#### 6. Run and Verify

**Start Backend**:
```bash
cd backend/core

# Run with development profile
./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# Or run the JAR directly after building
./mvnw clean package
java -jar target/careconnect-backend-1.0.0.jar --spring.profiles.active=dev
```

**Verify backend is running**:
```bash
# Check health endpoint
curl http://localhost:8080/actuator/health
# Should return: {"status":"UP"}

# Check API documentation
# Open browser to: http://localhost:8080/swagger-ui/index.html
```

**Start Frontend**:
```bash
cd frontend

# Run on Chrome (web)
flutter run -d chrome

# Run on Android emulator (start emulator first from Android Studio)
flutter run -d emulator-5554

# Run on iOS simulator (macOS only)
flutter run -d iPhone

# Run on desktop (current OS)
flutter run -d macos  # or windows, or linux
```

**Common First-Run Issues**:
- "Connection refused": Backend not running or wrong port
- "CORS error": Check `cors.allowed-origins` in backend properties
- "401 Unauthorized": Frontend using wrong API key or backend JWT secret mismatch
- "Database connection failed": PostgreSQL not running or wrong credentials

#### 7. Verify Full Stack Integration

Once both frontend and backend are running:

1. **Open the app** (automatically opens in Flutter)
2. **Navigate to login screen**
3. **Register a new account**:
   - Email: `test@example.com`
   - Password: `password123`
   - Name: `Test User`
4. **Verify you're redirected to dashboard**
5. **Check backend logs** - should see:
   ```
   INFO - User test@example.com registered
   INFO - JWT token generated for user test@example.com
   DEBUG - SELECT * FROM users WHERE email = 'test@example.com'
   ```

If all this works, your development environment is fully configured!

### Development Workflow

**Typical Development Session**:
```bash
# Terminal 1: Backend
cd backend/core
./mvnw spring-boot:run

# Terminal 2: Frontend
cd frontend
flutter run -d chrome

# Terminal 3: Database (if needed)
psql -U careconnect -d careconnect

# Make code changes
# Backend: Changes auto-reload with spring-devtools
# Frontend: Hot reload with 'r' in terminal, hot restart with 'R'
```

**Pro Tips**:
- Use IDE debuggers instead of print statements for complex issues
- Run `flutter analyze` before committing to catch Dart warnings
- Run `./mvnw verify` before pushing to catch Java issues
- Keep backend logs visible to see API calls as you interact with frontend
- Use browser DevTools (F12) to inspect API requests/responses

### Project Structure

```
careconnect2025/
├── frontend/                   # Flutter application
│   ├── lib/
│   │   ├── config/            # Configuration files
│   │   ├── features/          # Feature modules
│   │   ├── models/            # Data models
│   │   ├── providers/         # State management
│   │   ├── services/          # API services
│   │   └── main.dart          # App entry point
│   ├── assets/                # Static assets
│   ├── test/                  # Unit tests
│   └── pubspec.yaml           # Dependencies
├── backend/                   # Spring Boot application
│   └── core/
│       ├── src/main/java/com/careconnect/
│       │   ├── controller/    # REST controllers
│       │   ├── service/       # Business logic
│       │   ├── repository/    # Data access
│       │   ├── model/         # Entity models
│       │   ├── dto/           # Data transfer objects
│       │   ├── config/        # Configuration
│       │   └── exception/     # Exception handling
│       ├── src/main/resources/ # Configuration files
│       └── pom.xml            # Maven dependencies
├── terraform_aws/             # AWS infrastructure
└── docs/                      # Documentation
```

### Environment Configuration

#### Frontend Environment (.env)

```bash
# API Configuration
CC_BASE_URL_WEB=http://localhost:8080
CC_BASE_URL_ANDROID=http://10.0.2.2:8080
CC_BASE_URL_OTHER=http://localhost:8080

# JWT Configuration
JWT_SECRET=your_jwt_secret_key_here

# AI Services
DEEPSEEK_API_KEY=your_deepseek_api_key
OPENAI_API_KEY=your_openai_api_key

# Backend Authentication
CC_BACKEND_TOKEN=your_backend_token
```

#### Backend Configuration (application.properties)

```properties
# Database Configuration
spring.datasource.url=jdbc:postgresql://localhost:5432/careconnect
spring.datasource.username=careconnect
spring.datasource.password=your_password
spring.datasource.driver-class-name=org.postgresql.Driver

# JPA Configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect

# Server Configuration
server.port=8080
server.servlet.context-path=/

# JWT Configuration
jwt.secret=your_jwt_secret_key_32_characters_minimum
jwt.expiration=86400000

# CORS Configuration
cors.allowed-origins=http://localhost:3000,http://localhost:50030,http://127.0.0.1:3000
```

## Frontend Development (Flutter)

### Project Architecture

The frontend follows a feature-based modular architecture:

```
lib/
├── config/                    # App configuration
│   ├── environment_config.dart
│   ├── network/
│   └── theme/
├── features/                  # Feature modules
│   ├── auth/                  # Authentication
│   ├── dashboard/             # Main dashboard
│   ├── health/                # Health tracking
│   ├── communication/         # Messaging & calls
│   ├── social/                # Social features
│   └── [feature_name]/
│       ├── data/              # Data layer
│       ├── models/            # Domain models
│       ├── presentation/      # UI layer
│       └── services/          # Feature services
├── shared/                    # Shared components
│   ├── widgets/
│   ├── utils/
│   └── constants/
└── main.dart
```

### State Management with Provider

CareConnect uses the Provider package for state management, selected for its simplicity, excellent documentation, and suitability for our mid-complexity application. It follows the inherited widget pattern, making state accessible across the widget tree without excessive boilerplate—a key consideration when building healthcare UIs that need to share patient data across many screens.

#### Architectural Pattern: Feature-Specific ChangeNotifiers

We implement a single, feature-specific ChangeNotifier for each major domain (e.g., AuthProvider, HealthDataProvider). This encapsulates all state and business logic related to that feature, following the single responsibility principle and making the codebase easier to navigate for developers new to the project.

#### Key Implementation Details

**Private State Variables**: All state variables (like `_currentUser`, `_isLoading`) are prefixed with underscore, making them private to the provider class. This prevents external mutation and ensures all changes go through controlled methods—critical for maintaining data integrity in a healthcare application where unauthorized state changes could have serious consequences.

**Public Getters for Read-Only Access**: We expose state via public getters (e.g., `User? get currentUser`). This provides read-only access to the UI, enforcing a unidirectional data flow that makes the application's behavior predictable and debuggable.

**State Modification Through Public Methods**: State is only changed within public methods (e.g., `login()`, `logout()`). These methods are responsible for:
- **API Communication**: Calling the appropriate service layer methods
- **State Updates**: Modifying the private variables based on the result
- **Persistence**: Managing local storage of tokens or user data for offline access
- **Notifications**: Calling `notifyListeners()` to inform the UI of state changes and trigger rebuilds

#### Example: Authentication Flow in AuthProvider

Below is the complete authentication flow, demonstrating how a user login request flows through the provider:

```dart
// providers/auth_provider.dart
class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  // Public interface for the UI to access state
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> login(String email, String password) async {
    // 1. Signal the start of an async operation
    //    This allows the UI to show a loading indicator
    _setLoading(true);
    _clearError();

    try {
      // 2. Delegate the network call to the service layer
      //    Separation of concerns: providers handle state, services handle API
      final response = await _authService.login(email, password);

      // 3. Update the app state on success
      //    Store the authenticated user for access throughout the app
      _currentUser = response.user;
      
      // 4. Persist authentication tokens securely
      //    This enables the user to stay logged in between sessions
      await _tokenManager.saveTokens(response.tokens);
      
      // 5. Clear any previous errors
      _error = null;

    } catch (e) {
      // 6. Handle errors and update state accordingly
      //    Provide user-friendly error messages rather than raw exceptions
      _setError('Login failed: Please check your credentials.');
      
      // 7. Log the error for debugging while keeping sensitive data private
      _logger.error('Login failed for email: $email', error: e);
    } finally {
      // 8. Signal the end of the operation
      //    This ensures the loading state is cleared even if an error occurred
      _setLoading(false);
    }
  }

  // Private method to handle loading state consistently
  // By centralizing this logic, we ensure notifyListeners() is never forgotten
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners(); // This is what tells all listening widgets to rebuild
  }
  
  void _clearError() {
    _error = null;
    notifyListeners();
  }
  
  void _setError(String error) {
    _error = error;
    notifyListeners();
  }
}
```

#### Usage in UI

A LoginScreen would use `context.watch<AuthProvider>()` to listen to this state and react accordingly:

```dart
class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Watch the provider - this widget rebuilds when the provider notifies
    final authProvider = context.watch<AuthProvider>();
    
    // React to different states
    if (authProvider.isLoading) {
      return LoadingSpinner(); // Show loading during authentication
    }
    
    if (authProvider.error != null) {
      return ErrorMessage(authProvider.error!); // Show user-friendly error
    }
    
    if (authProvider.currentUser != null) {
      // Navigate to dashboard on successful login
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/dashboard');
      });
    }
    
    return LoginForm(); // Show the login form
  }
}
```

This pattern ensures that authentication state flows in one direction (provider → UI), making it easy to reason about when and why the UI updates—a critical feature when dealing with sensitive healthcare data that requires precise access control.

### Routing Configuration with GoRouter

CareConnect uses GoRouter for declarative navigation, chosen for its type-safe routing, deep linking support, and excellent integration with Flutter's navigation 2.0 API. In a healthcare app where users might need to navigate directly to specific patient records or appointment details (via links from emails or notifications), GoRouter's URL-based routing is particularly valuable.

#### Why GoRouter Over Navigator 1.0?

Traditional Flutter navigation (Navigator 1.0) uses an imperative stack-based approach. While simple for basic apps, it becomes unwieldy for complex navigation flows. GoRouter provides:

- **URL-based routing**: Each screen has a path (e.g., `/dashboard/health`) that can be bookmarked or linked
- **Type-safe parameters**: Pass data between screens with compile-time safety
- **Declarative redirects**: Guard routes based on authentication state without repetitive checks
- **Deep linking**: Users can jump directly to specific screens from external links
- **Nested navigation**: Complex tab structures (like our dashboard with sub-tabs) are easier to manage

In healthcare, where clinicians might need to quickly navigate to a specific patient's recent vitals from an alert notification, this URL-based approach is much more robust than trying to programmatically push the right sequence of screens onto a stack.

#### Core Routing Structure

```dart
// config/router_config.dart
final GoRouter routerConfig = GoRouter(
  // Starting point when app launches
  initialLocation: '/splash',
  
  // Define all app routes
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    
    // Main dashboard with nested routes
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
      
      // Nested routes appear as tabs or sections within dashboard
      routes: [
        GoRoute(
          path: 'health',  // Full path: /dashboard/health
          builder: (context, state) => const HealthScreen(),
        ),
        GoRoute(
          path: 'messages',  // Full path: /dashboard/messages
          builder: (context, state) => const MessagesScreen(),
        ),
        
        // Parameterized route - accepts dynamic patient ID
        GoRoute(
          path: 'patient/:id',  // Full path: /dashboard/patient/123
          builder: (context, state) {
            // Extract the ID from the URL
            final patientId = state.pathParameters['id']!;
            return PatientDetailScreen(patientId: patientId);
          },
        ),
      ],
    ),
  ],
  
  // Global navigation guard - runs before every route
  redirect: (context, state) {
    // Check authentication status from our AuthProvider
    final isLoggedIn = context.read<AuthProvider>().currentUser != null;
    final isGoingToLogin = state.uri.path == '/login';
    final isGoingToSplash = state.uri.path == '/splash';

    // Logic: Unauthenticated users can only access login and splash
    if (!isLoggedIn && !isGoingToLogin && !isGoingToSplash) {
      // User trying to access protected route without login - redirect to login
      return '/login';
    }
    
    // Logic: Authenticated users shouldn't see login screen
    if (isLoggedIn && isGoingToLogin) {
      // Already logged in, redirect to dashboard instead
      return '/dashboard';
    }
    
    // No redirect needed - allow navigation to proceed
    return null;
  },
);
```

#### Understanding the Redirect Guard

The `redirect` function is CareConnect's authentication barrier. It runs before every navigation:

**Scenario 1: Unauthenticated User Tries to Access Dashboard**
1. User navigates to `/dashboard`
2. Redirect guard checks: `isLoggedIn = false`, `isGoingToLogin = false`
3. Guard returns `/login`, overriding the original destination
4. User lands on login screen instead of dashboard

**Scenario 2: User Logs In Successfully**
1. Login completes, `AuthProvider.currentUser` is set
2. App tries to navigate to `/login` (where they currently are)
3. Redirect guard checks: `isLoggedIn = true`, `isGoingToLogin = true`
4. Guard returns `/dashboard`, redirecting them away from login
5. User automatically lands on dashboard

**Scenario 3: Deep Link from Email**
1. User clicks link: `careconnect://app/dashboard/patient/456`
2. App launches, redirect guard checks authentication
3. If not logged in: redirected to `/login`, but the intended destination is remembered
4. After login, guard allows navigation to `/dashboard/patient/456`
5. User lands exactly where the link intended

This pattern ensures:
- Protected routes require authentication
- Authenticated users don't get stuck on login screen
- Deep links work correctly after authentication
- No need to check authentication in every screen's build method

#### Programmatic Navigation in Code

Components navigate using `context.go()` and `context.push()`:

```dart
// Replace current route (can't go back)
context.go('/dashboard/health');

// Push new route (can go back with back button)
context.push('/dashboard/patient/123');

// Navigate with named parameters
context.goNamed(
  'patientDetail',
  pathParameters: {'id': '123'},
  queryParameters: {'tab': 'vitals'},
);

// Go back
context.pop();
```

**When to use `go` vs `push`**:
- **go()**: Replaces the route (like after login - don't want back button to return to login)
- **push()**: Adds to history (like opening a patient detail - want back button to return to list)

#### Handling Deep Links from Notifications

Healthcare notifications often need to navigate directly to relevant data:

```dart
// When notification is tapped:
void handleNotificationTap(String type, String id) {
  switch (type) {
    case 'vital_alert':
      // Navigate directly to patient's vitals
      context.go('/dashboard/patient/$id?tab=vitals');
      break;
    case 'message':
      // Navigate to specific conversation
      context.go('/dashboard/messages/$id');
      break;
    case 'appointment':
      // Navigate to appointment detail
      context.go('/dashboard/appointments/$id');
      break;
  }
}
```

The URL-based routing makes these deep links trivial to implement and maintain.

#### Error Handling

GoRouter includes built-in error handling for invalid routes:

```dart
GoRouter(
  // ... routes ...
  
  // Called when navigation to unknown route
  errorBuilder: (context, state) {
    return ErrorScreen(
      message: 'Page not found: ${state.uri.path}',
      onRetry: () => context.go('/dashboard'),
    );
  },
);
```

This ensures users never see a blank screen, even if they manually type an invalid URL or follow a broken link.

#### Testing Considerations

GoRouter makes navigation testing straightforward:

```dart
testWidgets('redirects unauthenticated users to login', (tester) async {
  // Start with no authenticated user
  await tester.pumpWidget(MyApp());
  
  // Try to navigate to dashboard
  routerConfig.go('/dashboard');
  await tester.pumpAndSettle();
  
  // Verify we're on login instead
  expect(find.text('Login'), findsOneWidget);
  expect(find.text('Dashboard'), findsNothing);
});
```

The declarative nature makes it easy to verify routing logic without complex widget tree navigation.

### HTTP Client Configuration with Dio and Interceptors

CareConnect uses Dio as its HTTP client library instead of Flutter's built-in `http` package. This choice was made for Dio's powerful interceptor system, which is crucial for implementing cross-cutting concerns like authentication, logging, and error handling in a consistent, maintainable way.

#### Why Dio Over Built-in HTTP?

While Flutter's `http` package is simpler, Dio provides essential features for a production healthcare app:

- **Interceptors**: Modify requests/responses globally (add auth tokens, log traffic, transform errors)
- **Request cancellation**: Cancel in-flight requests when user navigates away (saves bandwidth, prevents race conditions)
- **File upload/download**: Built-in support with progress tracking (for medical records, lab results)
- **Timeout configuration**: Separate timeouts for connect vs receive (important for slow hospital networks)
- **Retry logic**: Automatic retry with exponential backoff (essential for reliability)
- **FormData support**: Multipart file uploads (medical document uploads)

In healthcare, where API calls might involve large files (MRI scans) or need perfect reliability (medication orders), these features are not luxuries—they're requirements.

#### Dio Configuration and Initialization

```dart
// config/network/api_client.dart
class ApiClient {
  late final Dio _dio;

  ApiClient() {
    // Base configuration for all requests
    _dio = Dio(BaseOptions(
      // Server URL from environment config (different for dev/staging/prod)
      baseUrl: EnvironmentConfig.baseUrl,
      
      // Connection timeout: How long to wait to establish connection
      // 30 seconds accommodates slow hospital WiFi
      connectTimeout: const Duration(seconds: 30),
      
      // Receive timeout: How long to wait for response after connection
      // 30 seconds accommodates large payloads (lab results PDFs)
      receiveTimeout: const Duration(seconds: 30),
      
      // Default headers for all requests
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptors in order - they execute sequentially
    _dio.interceptors.add(AuthInterceptor());      // 1. Add auth tokens
    _dio.interceptors.add(LoggingInterceptor());   // 2. Log requests/responses
    _dio.interceptors.add(ErrorInterceptor());     // 3. Transform errors
  }
  
  // Expose dio instance for making requests
  Dio get dio => _dio;
}
```

#### Understanding Interceptors

Interceptors in Dio work like middleware in Express or filters in Spring Boot. Each interceptor can:
- Inspect and modify outgoing requests before they're sent
- Inspect and modify incoming responses before they reach your code
- Handle errors globally instead of in every API call

**Interceptor Execution Order**:
```
Request Path:  Your Code → Auth → Logging → Error → Network
Response Path: Network → Error → Logging → Auth → Your Code
```

#### Authentication Interceptor: Automatic Token Injection

The authentication interceptor ensures every protected API call includes the user's JWT token, without developers needing to manually add it to each request:

```dart
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Retrieve stored JWT token from secure storage
    final token = await TokenManager.getAccessToken();
    
    if (token != null) {
      // Add Authorization header to every request
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    // Continue to next interceptor
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Special case: If server returns 401 Unauthorized, token might be expired
    if (err.response?.statusCode == 401) {
      // Attempt to refresh the token using refresh token
      final refreshed = await TokenManager.refreshToken();
      
      if (refreshed) {
        // Token refresh succeeded - retry the original request
        try {
          // Clone the original request with new token
          final clonedRequest = await _dio.fetch(err.requestOptions);
          
          // Resolve with successful response
          handler.resolve(clonedRequest);
          return;
        } catch (e) {
          // Retry failed - fall through to error handling
        }
      } else {
        // Token refresh failed - user needs to log in again
        // Clear stored tokens and navigate to login
        await TokenManager.clearTokens();
        // Navigate to login screen
        navigatorKey.currentState?.pushReplacementNamed('/login');
      }
    }
    
    // For non-401 errors or failed token refresh, pass error to next handler
    handler.next(err);
  }
}
```

**What this achieves**:
1. **Automatic authentication**: Developers never forget to add tokens
2. **Transparent token refresh**: If token expires mid-session, app automatically refreshes it and retries the request—user never notices
3. **Graceful session expiration**: If refresh token also expired, user is smoothly redirected to login

This is particularly important in healthcare where a user might leave the app open during a shift. When they return hours later, the app automatically handles the expired token without losing their work.

#### Logging Interceptor: Debugging and Audit Trail

The logging interceptor provides visibility into all network traffic, essential for debugging API integration issues and maintaining audit trails (required in healthcare):

```dart
class LoggingInterceptor extends Interceptor {
  final Logger _logger = Logger('API');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Log outgoing request details
    _logger.info('➡️ ${options.method} ${options.uri}');
    
    // Log headers (excluding sensitive ones)
    options.headers.forEach((key, value) {
      if (!_isSensitiveHeader(key)) {
        _logger.debug('Header: $key: $value');
      }
    });
    
    // Log request body (excluding sensitive data like passwords)
    if (options.data != null && !_containsSensitiveData(options.path)) {
      _logger.debug('Request body: ${options.data}');
    }
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Log successful response
    _logger.info('✅ ${response.statusCode} ${response.requestOptions.uri}');
    _logger.debug('Response data: ${response.data}');
    
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Log errors prominently
    _logger.error(
      '❌ ${err.response?.statusCode ?? 'ERROR'} ${err.requestOptions.uri}',
      error: err,
    );
    
    if (err.response?.data != null) {
      _logger.error('Error response: ${err.response?.data}');
    }
    
    handler.next(err);
  }
  
  bool _isSensitiveHeader(String key) {
    // Don't log authorization tokens or API keys
    return key.toLowerCase() == 'authorization' || 
           key.toLowerCase().contains('token') ||
           key.toLowerCase().contains('key');
  }
  
  bool _containsSensitiveData(String path) {
    // Don't log bodies of login/register requests (contain passwords)
    return path.contains('/auth/login') || 
           path.contains('/auth/register') ||
           path.contains('/password');
  }
}
```

**Why this matters**: In production, when a caregiver reports "the app says patient data failed to load," these logs let you see exactly what request was made and what error the server returned, dramatically speeding up debugging.

#### Error Interceptor: User-Friendly Error Messages

The error interceptor transforms technical HTTP errors into user-friendly messages, preventing users from seeing cryptic "DioException: 500" errors:

```dart
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Transform Dio errors into application-specific exceptions
    String message;
    
    if (err.type == DioExceptionType.connectionTimeout || 
        err.type == DioExceptionType.receiveTimeout) {
      // Network timeout - likely slow connection or server overload
      message = 'Connection timeout. Please check your internet connection and try again.';
    } else if (err.type == DioExceptionType.badResponse) {
      // Server returned an error status code
      final statusCode = err.response?.statusCode;
      
      switch (statusCode) {
        case 400:
          // Bad request - show server's error message if available
          message = err.response?.data['message'] ?? 
                   'Invalid request. Please check your input.';
          break;
        case 401:
          // Unauthorized - handled by AuthInterceptor, but provide fallback
          message = 'Authentication required. Please log in.';
          break;
        case 403:
          // Forbidden - user doesn't have permission
          message = 'You do not have permission to access this resource.';
          break;
        case 404:
          // Not found - resource doesn't exist
          message = 'The requested resource was not found.';
          break;
        case 500:
        case 502:
        case 503:
          // Server errors - show friendly message
          message = 'Server error. Our team has been notified. Please try again later.';
          break;
        default:
          message = 'An unexpected error occurred. Please try again.';
      }
    } else if (err.type == DioExceptionType.cancel) {
      // Request was cancelled (user navigated away) - don't show error
      handler.next(err);
      return;
    } else {
      // Unknown error - generic message
      message = 'Unable to connect to server. Please check your internet connection.';
    }
    
    // Create application-specific exception with user-friendly message
    final appException = ApiException(message, statusCode: err.response?.statusCode);
    
    // Log the technical error for debugging
    logger.error('API Error: ${err.message}', error: err);
    
    // Pass the user-friendly exception to application code
    handler.reject(DioException(
      requestOptions: err.requestOptions,
      error: appException,
      type: err.type,
    ));
  }
}
```

**Benefits**:
- Users see "Connection timeout" instead of "DioException: ConnectionTimeout"
- Developers get technical logs for debugging
- Consistent error messages across the entire app
- Healthcare-appropriate language (calm, reassuring, actionable)

#### Making Requests with Configured Client

With interceptors in place, making API calls is straightforward:

```dart
class HealthService {
  final ApiClient _apiClient;

  HealthService(this._apiClient);

  Future<List<VitalSign>> getVitalSigns() async {
    try {
      // Make request - interceptors automatically:
      // 1. Add auth token
      // 2. Log request
      // 3. Transform any errors
      final response = await _apiClient.dio.get('/api/health/vitals');
      
      // Parse response
      return (response.data as List)
          .map((json) => VitalSign.fromJson(json))
          .toList();
    } on ApiException catch (e) {
      // Error was already transformed by ErrorInterceptor
      throw HealthException(e.message);
    }
  }
}
```

Notice how clean this code is—no manual token injection, no response logging, no error transformation. All that complexity is handled by interceptors, ensuring consistency across all API calls in the application.

This architecture means:
- New developers can add API calls without worrying about auth or logging
- Changing how we handle authentication (e.g., switching from JWT to OAuth) only requires updating one file
- All API calls automatically benefit from improvements to error handling or logging
- Healthcare compliance requirements (like audit logging) are enforced automatically

### Feature Module Structure

CareConnect's frontend architecture organizes code by feature rather than by technical layer. This "feature-first" structure means all code related to a specific domain (like health tracking or messaging) lives together in one directory, making it easier to understand, maintain, and test features in isolation.

#### Why Feature-Based Organization?

**Traditional Layer-Based Approach (What We Avoid)**:
```
lib/
├── models/           # ALL models from ALL features mixed together
├── services/         # ALL services from ALL features mixed together
├── screens/          # ALL screens from ALL features mixed together
└── widgets/          # ALL widgets from ALL features mixed together
```
Problem: To understand the "health tracking" feature, you'd need to hunt through 4+ different directories. Adding a new feature means touching many directories.

**Feature-Based Approach (What We Use)**:
```
lib/
└── features/
    ├── health/       # Everything for health tracking in ONE place
    ├── messaging/    # Everything for messaging in ONE place
    └── auth/         # Everything for authentication in ONE place
```
Benefit: All health-related code is in one directory. To understand or modify health features, you only look in `features/health/`. New developers can explore one feature at a time without getting lost in the codebase.

#### Anatomy of a Feature Module

Each feature module follows a consistent internal structure that mirrors the application's architectural layers. Below is a concrete example using the Health feature, which manages vital signs, medications, and health records:

**Directory Structure**:
```
features/health/
├── models/           # Data structures (VitalSign, Medication, etc.)
├── services/         # API communication layer
├── providers/        # State management (HealthProvider)
├── presentation/     # UI components
│   ├── screens/      # Full-page screens
│   └── widgets/      # Reusable UI components
└── utils/            # Feature-specific utilities (formatters, validators)
```

**Data Flow Within a Feature**:
```
UI (Presentation) → Provider (State) → Service (API) → Model (Data Structure)
      ↓                   ↓                 ↓               ↓
  User taps button   Updates state    Makes HTTP call   Parses JSON
```

#### Practical Example: The Health Feature Module

Let's walk through how the Health feature implements this pattern to track vital signs like blood pressure and heart rate:

**1. Model Layer - Data Structures**

The `VitalSign` model represents a single vital sign measurement. Its responsibilities are:
- Define the structure of vital sign data (type, value, unit, timestamp)
- Provide JSON serialization/deserialization for API communication
- Ensure type safety (Dart's strong typing prevents bugs)

Example vital sign data flow:
- **From API**: JSON `{"id":"123", "type":"blood_pressure", "value":120, ...}` → VitalSign object
- **To UI**: VitalSign object → Display "Blood Pressure: 120/80 mmHg"
- **To API**: VitalSign object → JSON for saving new measurement

```dart
// features/health/models/vital_sign.dart
// VitalSign: Immutable data class representing a single vital sign measurement
// Immutability (final fields) ensures data integrity - once created, cannot be modified
// This prevents bugs where vital signs accidentally change after being recorded
class VitalSign {
  // Unique identifier from database - used for updates/deletes
  final String id;
  
  // Type of measurement: "blood_pressure", "heart_rate", "temperature", etc.
  // String instead of enum allows backend to add new types without app update
  final String type;
  
  // Numeric value of the measurement (e.g., 120 for systolic BP)
  final double value;
  
  // Unit of measurement: "mmHg", "bpm", "°F", etc.
  // Stored separately because different vital types use different units
  final String unit;
  
  // When this measurement was taken - critical for timeline and trending
  final DateTime timestamp;
  
  // Optional notes (e.g., "Taken after exercise")
  // Nullable (String?) because not all measurements have notes
  final String? notes;

  // Constructor with named parameters for clarity and safety
  // Example usage: VitalSign(id: "123", type: "heart_rate", value: 72, ...)
  VitalSign({
    required this.id,
    required this.type,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.notes,
  });

  // Factory constructor to create VitalSign from JSON received from API
  // Called automatically when parsing API responses
  // Example JSON: {"id":"123", "type":"heart_rate", "value":72, "unit":"bpm", ...}
  factory VitalSign.fromJson(Map<String, dynamic> json) {
    return VitalSign(
      id: json['id'],
      type: json['type'],
      // toDouble() handles both int and double from API (flexible parsing)
      value: json['value'].toDouble(),
      unit: json['unit'],
      // Parse ISO 8601 timestamp string into DateTime object
      timestamp: DateTime.parse(json['timestamp']),
      // notes might be null in JSON, which is fine (nullable String?)
      notes: json['notes'],
    );
  }
  
  // Convert VitalSign back to JSON for sending to API
  // Used when recording new vital signs or updating existing ones
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'value': value,
      'unit': unit,
      'timestamp': timestamp.toIso8601String(),
      'notes': notes,
    };
  }
}

**2. Service Layer - API Communication**

The `HealthService` class is responsible for all network communication related to health data. It acts as a facade over the raw HTTP client (Dio), providing a clean, type-safe interface for the rest of the application.

**Key Responsibilities**:
- **API Abstraction**: Hide HTTP details (URLs, methods, headers) from the rest of the app
- **Error Handling**: Convert network errors into domain-specific exceptions
- **Data Transformation**: Convert between API JSON and app models
- **Type Safety**: Ensure all API calls return the correct data types

**Why a Separate Service Layer?**
- **Testability**: Can mock the service to test UI without real API calls
- **Reusability**: Multiple screens can use the same service methods
- **Maintainability**: If API changes (e.g., endpoint URL), only update in one place
- **Separation of Concerns**: UI code doesn't need to know about HTTP details

```dart
// features/health/services/health_service.dart
// HealthService: Handles all API communication for health-related features
// This is the single source of truth for how the app talks to the health API
class HealthService {
  // Private API client - the underscore makes it private to this class
  // This ensures all API calls go through our defined methods, maintaining consistency
  final ApiClient _apiClient;

  // Constructor injection of ApiClient
  // This allows us to inject a mock client for testing
  HealthService(this._apiClient);

  /// Fetches all vital signs for the current user from the backend
  /// 
  /// Returns: List of VitalSign objects, ordered by most recent first
  /// Throws: HealthException if the API call fails or returns invalid data
  /// 
  /// Example usage:
  /// ```dart
  /// try {
  ///   final vitals = await healthService.getVitalSigns();
  ///   print('Found ${vitals.length} vital signs');
  /// } catch (e) {
  ///   print('Error loading vitals: $e');
  /// }
  /// ```
  Future<List<VitalSign>> getVitalSigns() async {
    try {
      // Make GET request to vitals endpoint
      // ApiClient automatically adds auth token from AuthInterceptor
      final response = await _apiClient.get('/api/health/vitals');
      
      // Parse response: API returns JSON array of vital sign objects
      // We map each JSON object to a VitalSign instance
      // Example API response: [{"id":"1", "type":"bp", ...}, {"id":"2", "type":"hr", ...}]
      return (response.data as List)
          .map((json) => VitalSign.fromJson(json))
          .toList();
    } catch (e) {
      // Wrap any errors in HealthException for consistent error handling
      // This could be a network error, timeout, 500 error, etc.
      // HealthException provides user-friendly error messages
      throw HealthException('Failed to fetch vital signs: $e');
    }
  }

  /// Records a new vital sign measurement
  /// 
  /// Parameters:
  ///   - vitalSign: The vital sign to record (should NOT have an ID yet)
  /// 
  /// Returns: The saved vital sign with server-generated ID and timestamp
  /// Throws: HealthException if recording fails (validation error, network error, etc.)
  /// 
  /// Example usage:
  /// ```dart
  /// final newVital = VitalSign(
  ///   type: 'blood_pressure',
  ///   value: 120,
  ///   unit: 'mmHg',
  ///   notes: 'After morning jog',
  /// );
  /// final saved = await healthService.recordVitalSign(newVital);
  /// print('Saved with ID: ${saved.id}');
  /// ```
  Future<VitalSign> recordVitalSign(VitalSign vitalSign) async {
    try {
      // Make POST request with vital sign data
      // vitalSign.toJson() converts the Dart object to JSON
      final response = await _apiClient.post(
        '/api/health/vitals',
        data: vitalSign.toJson(),
      );
      
      // Server returns the saved vital sign with generated ID and server timestamp
      // Parse it back into a VitalSign object
      return VitalSign.fromJson(response.data);
    } catch (e) {
      // If backend validation fails, this catches the error
      // Example errors: "Value out of range", "Invalid vital type"
      throw HealthException('Failed to record vital sign: $e');
    }
  }
}
```

**Design Pattern: Repository Pattern**

This service implements the Repository pattern, a common architectural pattern that:
- Provides a collection-like interface to data sources (in this case, the API)
- Abstracts away the details of where data comes from
- Makes it easy to switch data sources (e.g., API → local cache) without changing UI code

**Error Handling Strategy**

Notice how both methods use try-catch and throw `HealthException`:
- **Why not let errors bubble up?** Raw Dio exceptions contain technical details (HTTP status codes, headers) that UI shouldn't know about
- **HealthException**: Domain-specific exception with user-friendly messages
- **Consistency**: All health-related errors are the same type, simplifying error handling in UI

**Common Usage Pattern in Provider**:
```dart
class HealthProvider extends ChangeNotifier {
  final HealthService _healthService;
  List<VitalSign> _vitals = [];
  
  Future<void> loadVitals() async {
    try {
      _vitals = await _healthService.getVitalSigns();
      notifyListeners();  // Update UI
    } on HealthException catch (e) {
      // Show user-friendly error message in UI
      showError(e.message);
    }
  }
}
```

This layered approach (UI → Provider → Service → API) ensures:
- Each layer has a single responsibility
- Changes to one layer don't affect others
- Testing is straightforward (mock dependencies)
- Code is maintainable and readable

```

## Backend Development (Spring Boot)

### Project Structure

```java
com.careconnect/
├── CareconnectBackendApplication.java  # Main application
├── config/                             # Configuration classes
│   ├── SecurityConfig.java
│   ├── WebSocketConfig.java
│   └── OpenApiConfig.java
├── controller/                         # REST controllers
├── service/                            # Business logic
├── repository/                         # Data access layer
├── model/                              # JPA entities
├── dto/                                # Data transfer objects
├── exception/                          # Exception handling
└── util/                               # Utility classes
```

### Entity Models: Mapping Domain Objects to Database Tables

In Spring Boot applications, JPA (Java Persistence API) entities represent the bridge between our object-oriented Java code and the relational database. Each entity class maps to a database table, and each instance represents a row in that table. CareConnect uses JPA annotations to declaratively define this mapping, allowing Hibernate to automatically handle SQL generation, relationship management, and object-relational mapping complexity.

#### The Anatomy of a JPA Entity

Let's examine the `User` and `VitalSign` entities to understand how JPA annotations work together to create a robust data model for healthcare data:

**Design Principles**:
- **Entities Are POJOs (Plain Old Java Objects)**: Despite the annotations, entities remain simple Java classes with fields, constructors, getters, and setters
- **Annotations Define Behavior**: Rather than writing SQL, we use annotations like `@Entity`, `@Table`, `@Column` to tell Hibernate how to persist the object
- **Relationships Are Explicit**: `@OneToMany`, `@ManyToOne` define how entities relate to each other, mirroring foreign key relationships in the database
- **Validation At Multiple Layers**: JPA constraints (`nullable = false`) provide database-level validation, while JSR-380 annotations (`@Email`) provide application-level validation

Example entity with detailed explanations of JPA annotations:

```java
// model/User.java
// @Entity: Marks this class as a JPA entity - Hibernate will create a table for it
// This is the fundamental annotation that makes a class persistable
@Entity

// @Table: Specifies the table name in the database
// Without this, Hibernate would use the class name "User" as the table name
// We explicitly set it to "users" to avoid conflicts with SQL reserved words
@Table(name = "users")

// @EntityListeners: Enables JPA auditing for this entity
// AuditingEntityListener automatically populates createdDate, lastModifiedDate fields
// This is crucial for healthcare compliance - we need to know when records are created/modified
@EntityListeners(AuditingEntityListener.class)

// extends Auditable: Base class providing createdDate, lastModifiedDate, createdBy, lastModifiedBy
// These audit fields are required for HIPAA compliance and medical record regulations
public class User extends Auditable {

    // @Id: Marks this field as the primary key
    // Every entity must have exactly one @Id field
    @Id
    
    // @GeneratedValue: Database auto-generates this value on insert
    // IDENTITY strategy: Uses database auto-increment (SERIAL in PostgreSQL)
    // Alternative strategies: SEQUENCE (uses DB sequence), AUTO (database-dependent)
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // @Column: Defines column properties in the database
    // unique = true: Database enforces uniqueness (prevents duplicate emails)
    // nullable = false: Database enforces NOT NULL constraint
    // These constraints prevent data integrity issues at the database level
    @Column(unique = true, nullable = false)
    
    // @Email: JSR-380 validation annotation
    // Validates email format *before* trying to save to database
    // Provides better error messages than database constraint violations
    @Email
    private String email;

    // Password field: nullable = false but no @Email constraint
    // Stored as hashed value (BCrypt), never plain text
    @Column(nullable = false)
    private String password;

    @Column(nullable = false)
    private String firstName;

    @Column(nullable = false)
    private String lastName;

    // @Enumerated: Tells JPA how to store the enum value
    // EnumType.STRING: Store enum name as string ("PATIENT", "CAREGIVER", "ADMIN")
    // Why STRING not ORDINAL? If we add a new role in the middle of the enum,
    // ORDINAL values change, breaking existing data. STRING is stable.
    @Column(nullable = false)
    @Enumerated(EnumType.STRING)
    private UserRole role;  // UserRole is an enum: PATIENT, CAREGIVER, FAMILY_MEMBER, etc.

    // Boolean field with default value
    // active = true: Users start as active, can be deactivated (soft delete)
    // Soft deletes preserve data for compliance while preventing login
    @Column(nullable = false)
    private Boolean active = true;

    // @OneToMany: Defines a one-to-many relationship
    // One User can have many VitalSigns
    // mappedBy = "user": The VitalSign entity has a field called "user" that owns this relationship
    // cascade = CascadeType.ALL: Operations on User cascade to VitalSigns
    //   Example: If we delete a User, all their VitalSigns are also deleted
    // This prevents orphaned vital signs in the database
    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL)
    private List<VitalSign> vitalSigns = new ArrayList<>();

    // Constructors, getters, setters (omitted for brevity)
    // JPA requires a no-arg constructor (can be private)
    // Getters/setters allow JPA to access fields via reflection
}

// model/VitalSign.java
// VitalSign: Represents a single measurement (blood pressure, heart rate, etc.)
// Related to User via many-to-one relationship (many vitals belong to one user)
@Entity
@Table(name = "vital_signs")
public class VitalSign extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // @ManyToOne: Defines the many-to-one side of the relationship
    // Many VitalSigns belong to one User
    // fetch = FetchType.LAZY: Don't load the User object unless explicitly accessed
    // Why LAZY? Performance - we don't always need the full User object when querying vitals
    // Example: Loading 100 vitals with EAGER would also load 100 User objects (wasteful)
    @ManyToOne(fetch = FetchType.LAZY)
    
    // @JoinColumn: Specifies the foreign key column in the database
    // name = "user_id": The column in vital_signs table that references users.id
    // nullable = false: Every vital sign must belong to a user (referential integrity)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    // Type of measurement stored as string for flexibility
    // Examples: "blood_pressure", "heart_rate", "temperature", "oxygen_saturation"
    // String vs Enum: Allows adding new vital types without code changes
    @Column(nullable = false)
    private String type;

    // Numeric value of the measurement
    // Double allows decimals (e.g., temperature: 98.6°F)
    // Could be systolic BP (120), heart rate (72), temperature (36.5), etc.
    @Column(nullable = false)
    private Double value;

    // Unit of measurement - varies by vital type
    // Examples: "mmHg" (blood pressure), "bpm" (heart rate), "°C" (temperature)
    @Column(nullable = false)
    private String unit;

    // Optional notes field - might be null if no notes provided
    // No nullable = false constraint, so NULL is allowed in database
    @Column
    private String notes;

    // When this measurement was taken
    // LocalDateTime: Java 8 date/time type, timezone-neutral
    // Hibernate automatically converts between LocalDateTime and PostgreSQL TIMESTAMP
    @Column(nullable = false)
    private LocalDateTime measurementTime;

    // Constructors, getters, setters (omitted for brevity)
}
```

#### Understanding JPA Relationships

The `User` ↔ `VitalSign` relationship demonstrates the one-to-many/many-to-one pattern:

**From User's Perspective (One-to-Many)**:
```java
@OneToMany(mappedBy = "user", cascade = CascadeType.ALL)
private List<VitalSign> vitalSigns;
```
- One user has many vital signs
- `mappedBy = "user"`: VitalSign entity owns the relationship (has the foreign key)
- `cascade = ALL`: Deleting a user deletes all their vitals

**From VitalSign's Perspective (Many-to-One)**:
```java
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "user_id", nullable = false)
private User user;
```
- Many vitals belong to one user
- `fetch = LAZY`: Don't load the user unless accessed (performance optimization)
- `@JoinColumn`: Creates `user_id` foreign key column in `vital_signs` table

**Database Schema Generated**:
```sql
-- users table
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    first_name VARCHAR(255) NOT NULL,
    last_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_date TIMESTAMP,
    last_modified_date TIMESTAMP
);

-- vital_signs table
CREATE TABLE vital_signs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    type VARCHAR(255) NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    unit VARCHAR(50) NOT NULL,
    notes TEXT,
    measurement_time TIMESTAMP NOT NULL,
    created_date TIMESTAMP,
    last_modified_date TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

#### Why This Architecture Matters in Healthcare

**Data Integrity**: Annotations like `nullable = false` and `unique = true` prevent invalid data at the database level, crucial for medical records

**Audit Trail**: `extends Auditable` automatically tracks when records are created/modified, required for HIPAA compliance

**Referential Integrity**: Foreign key relationships ensure vital signs can't exist without a user, preventing orphaned data

**Soft Deletes**: `active` boolean allows deactivating users without deleting their medical history

**Type Safety**: Java's strong typing combined with JPA ensures only valid data structures reach the database



```java
// model/User.java
@Entity
@Table(name = "users")
@EntityListeners(AuditingEntityListener.class)
public class User extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    @Email
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(nullable = false)
    private String firstName;

    @Column(nullable = false)
    private String lastName;

    @Column(nullable = false)
    @Enumerated(EnumType.STRING)
    private UserRole role;

    @Column(nullable = false)
    private Boolean active = true;

    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL)
    private List<VitalSign> vitalSigns = new ArrayList<>();

    // Constructors, getters, setters
}

// model/VitalSign.java
@Entity
@Table(name = "vital_signs")
public class VitalSign extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(nullable = false)
    private String type;

    @Column(nullable = false)
    private Double value;

    @Column(nullable = false)
    private String unit;

    @Column
    private String notes;

    @Column(nullable = false)
    private LocalDateTime measurementTime;

    // Constructors, getters, setters
}
```

### Repository Layer: Spring Data JPA's Magic

Spring Data JPA is one of the most developer-friendly features in the Spring ecosystem. It dramatically reduces boilerplate code by automatically implementing database operations based solely on method names. Instead of writing SQL queries, you declare what you want, and Spring generates the implementation.

#### The Power of Method Name Conventions

Spring Data JPA follows a "convention over configuration" philosophy. By following specific naming patterns, you get fully functional database queries without writing a single line of SQL. This approach reduces bugs, improves readability, and makes repositories incredibly maintainable.

**How It Works**:
1. You define an interface extending `JpaRepository<Entity, IdType>`
2. You declare method signatures following Spring Data naming conventions
3. Spring automatically generates the implementation at runtime
4. You get full CRUD operations + custom queries for free

#### Repository Examples with Detailed Explanations

Using Spring Data JPA to create powerful, type-safe database access:

```java
// repository/UserRepository.java
// @Repository: Marks this as a Spring-managed repository bean
// Also enables Spring's exception translation (SQLException → DataAccessException)
@Repository

// extends JpaRepository<User, Long>:
//   - User: The entity this repository manages
//   - Long: The type of User's primary key (@Id field)
// This inheritance gives us ~15 methods for free: save(), findById(), findAll(), delete(), etc.
public interface UserRepository extends JpaRepository<User, Long> {

    // Method name query: Spring parses the method name to generate SQL
    // "findBy" + "Email" → SELECT * FROM users WHERE email = ?
    // Return type Optional<User> handles the case where no user found (no null checks needed)
    // 
    // Generated SQL:
    // SELECT * FROM users WHERE email = ?
    //
    // Usage example:
    // Optional<User> user = userRepository.findByEmail("john@example.com");
    // if (user.isPresent()) { ... }
    Optional<User> findByEmail(String email);

    // Method with multiple conditions: "Role" AND "Active" = True
    // "findBy" + "RoleAnd" + "ActiveTrue"
    // 
    // Generated SQL:
    // SELECT * FROM users WHERE role = ? AND active = true
    //
    // "ActiveTrue" is a special keyword - Spring recognizes True/False suffixes
    // No need to pass the active value, it's hardcoded to true
    //
    // Usage:
    // List<User> caregivers = userRepository.findByRoleAndActiveTrue(UserRole.CAREGIVER);
    List<User> findByRoleAndActiveTrue(UserRole role);

    // @Query: When method name queries aren't expressive enough, write JPQL
    // JPQL (Java Persistence Query Language): Object-oriented query language
    // Queries operate on entities, not tables ("User u" not "users u")
    // 
    // Why use @Query here? It's functionally identical to the method above!
    // This demonstrates how @Query works for more complex scenarios
    // 
    // @Param: Binds method parameter to query parameter
    // ":role" in query matches @Param("role") in method signature
    @Query("SELECT u FROM User u WHERE u.role = :role AND u.active = true")
    List<User> findActiveUsersByRole(@Param("role") UserRole role);

    // Boolean return type: Does a matching record exist?
    // More efficient than findByEmail() if you only need to check existence
    // 
    // Generated SQL:
    // SELECT EXISTS(SELECT 1 FROM users WHERE email = ?)
    //
    // This is a COUNT or EXISTS query, not a full SELECT
    // Returns true/false without loading the entire User object (performance optimization)
    //
    // Usage:
    // if (userRepository.existsByEmail("test@example.com")) {
    //   throw new EmailAlreadyExistsException();
    // }
    boolean existsByEmail(String email);
}

// repository/VitalSignRepository.java
// Repository for VitalSign entities - demonstrates more complex query patterns
@Repository
public interface VitalSignRepository extends JpaRepository<VitalSign, Long> {

    // Method name with nested property and sorting
    // "UserId" → navigates to VitalSign.user.id (foreign key)
    // "OrderBy" + "MeasurementTimeDesc" → ORDER BY measurement_time DESC
    // 
    // Generated SQL:
    // SELECT * FROM vital_signs WHERE user_id = ? ORDER BY measurement_time DESC
    //
    // Sorting is crucial in healthcare: most recent vitals first
    // Patient dashboard shows latest blood pressure at the top
    //
    // Usage:
    // List<VitalSign> vitals = vitalSignRepository.findByUserIdOrderByMeasurementTimeDesc(123L);
    // VitalSign mostRecent = vitals.get(0); // Most recent measurement
    List<VitalSign> findByUserIdOrderByMeasurementTimeDesc(Long userId);

    // Multiple conditions + sorting
    // Filter by both user AND vital type, then sort by time
    // 
    // Generated SQL:
    // SELECT * FROM vital_signs 
    // WHERE user_id = ? AND type = ? 
    // ORDER BY measurement_time DESC
    //
    // Example: Get all blood pressure readings for a specific patient
    // List<VitalSign> bpReadings = repo.findByUserIdAndTypeOrderByMeasurementTimeDesc(
    //     123L, "blood_pressure"
    // );
    List<VitalSign> findByUserIdAndTypeOrderByMeasurementTimeDesc(
        Long userId, String type);

    // @Query with date range: JPQL BETWEEN clause
    // This query couldn't be expressed with method naming alone (too complex)
    // 
    // "v.measurementTime BETWEEN :start AND :end" → SQL's BETWEEN operator
    // BETWEEN is inclusive: includes both start and end timestamps
    //
    // Why JPQL instead of method name? "findByUserIdAndMeasurementTimeBetween" works,
    // but @Query is clearer when queries get complex
    //
    // Usage:
    // LocalDateTime start = LocalDateTime.now().minusDays(7);
    // LocalDateTime end = LocalDateTime.now();
    // List<VitalSign> lastWeek = repo.findByUserIdAndDateRange(123L, start, end);
    @Query("SELECT v FROM VitalSign v WHERE v.user.id = :userId " +
           "AND v.measurementTime BETWEEN :start AND :end")
    List<VitalSign> findByUserIdAndDateRange(
        @Param("userId") Long userId,
        @Param("start") LocalDateTime start,
        @Param("end") LocalDateTime end);
}
```

#### Understanding Method Name Query Conventions

Spring Data JPA recognizes keywords in method names to build queries:

**Prefixes (Start of method name)**:
- `findBy...` → SELECT query
- `existsBy...` → EXISTS/COUNT query (returns boolean)
- `countBy...` → COUNT query (returns long)
- `deleteBy...` → DELETE query (returns void or int)

**Keywords (Conditions)**:
- `And` → SQL AND
- `Or` → SQL OR
- `Between` → SQL BETWEEN
- `LessThan`, `GreaterThan` → SQL < and >
- `Like` → SQL LIKE (wildcards)
- `IgnoreCase` → Case-insensitive comparison
- `OrderBy...Asc/Desc` → ORDER BY

**Examples**:
```java
// Find users by email OR username
Optional<User> findByEmailOrUsername(String email, String username);

// Find vitals with value greater than threshold
List<VitalSign> findByValueGreaterThan(Double threshold);

// Count users created after a date
long countByCreatedDateAfter(LocalDateTime date);

// Delete inactive users (returns number of deleted entities)
int deleteByActiveFalse();

// Find users with name containing string (case-insensitive)
List<User> findByFirstNameContainingIgnoreCase(String name);
```

#### When to Use @Query vs Method Names

**Use Method Names When**:
- Query is simple (1-3 conditions)
- Standard CRUD operations
- Readability is clear

**Use @Query When**:
- Complex joins across multiple tables
- Aggregate functions (COUNT, AVG, SUM)
- Subqueries or advanced SQL
- Method name would be too long/unclear

**Example of @Query Necessity**:
```java
// This would require an unreadably long method name:
// findByUserIdAndMeasurementTimeBetweenAndValueGreaterThanAndTypeLikeIgnoreCase

// Better as @Query:
@Query("SELECT v FROM VitalSign v WHERE v.user.id = :userId " +
       "AND v.measurementTime BETWEEN :start AND :end " +
       "AND v.value > :minValue " +
       "AND LOWER(v.type) LIKE LOWER(CONCAT('%', :typePattern, '%'))")
List<VitalSign> findComplexVitalCriteria(
    @Param("userId") Long userId,
    @Param("start") LocalDateTime start,
    @Param("end") LocalDateTime end,
    @Param("minValue") Double minValue,
    @Param("typePattern") String typePattern
);
```

#### Inherited Methods from JpaRepository

Every repository automatically gets these methods (no code needed):

```java
// Basic CRUD
save(User user)                    // Insert or update
saveAll(Iterable<User> users)      // Batch save
findById(Long id)                  // Find by primary key
findAll()                          // Get all entities
findAllById(Iterable<Long> ids)    // Get multiple by IDs
delete(User user)                  // Delete entity
deleteById(Long id)                // Delete by ID
deleteAll()                        // Delete all (use carefully!)
count()                            // Count all entities
existsById(Long id)                // Check if ID exists
```

#### Performance Considerations

**1. Lazy Loading (fetch = LAZY)**:
```java
@ManyToOne(fetch = FetchType.LAZY)
private User user;
```
- VitalSign query doesn't load User unless explicitly accessed
- Prevents N+1 query problem (loading 100 vitals wouldn't trigger 100 user queries)

**2. Pagination for Large Datasets**:
```java
// Instead of List<VitalSign>, use Page<VitalSign> for large results
Page<VitalSign> findByUserId(Long userId, Pageable pageable);

// Usage:
PageRequest pageRequest = PageRequest.of(0, 20); // Page 0, 20 items
Page<VitalSign> page = repo.findByUserId(123L, pageRequest);
List<VitalSign> vitals = page.getContent();
```

**3. Projection for Partial Data**:
```java
// Only select specific fields instead of entire entity
@Query("SELECT v.type, v.value, v.measurementTime FROM VitalSign v WHERE v.user.id = :userId")
List<Object[]> findVitalSummary(@Param("userId") Long userId);
```

This repository pattern, combined with JPA entities, provides a robust, type-safe, and efficient way to manage data in CareConnect while requiring minimal boilerplate code.



```java
// repository/UserRepository.java
@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    List<User> findByRoleAndActiveTrue(UserRole role);

    @Query("SELECT u FROM User u WHERE u.role = :role AND u.active = true")
    List<User> findActiveUsersByRole(@Param("role") UserRole role);

    boolean existsByEmail(String email);
}

// repository/VitalSignRepository.java
@Repository
public interface VitalSignRepository extends JpaRepository<VitalSign, Long> {

    List<VitalSign> findByUserIdOrderByMeasurementTimeDesc(Long userId);

    List<VitalSign> findByUserIdAndTypeOrderByMeasurementTimeDesc(
        Long userId, String type);

    @Query("SELECT v FROM VitalSign v WHERE v.user.id = :userId " +
           "AND v.measurementTime BETWEEN :start AND :end")
    List<VitalSign> findByUserIdAndDateRange(
        @Param("userId") Long userId,
        @Param("start") LocalDateTime start,
        @Param("end") LocalDateTime end);
}
```

### Service Layer: Implementing Business Logic and Orchestration

The Service Layer in CareConnect acts as the core of our business logic, sitting between the Controllers (which handle HTTP requests and responses) and the Repositories (which handle data access). This architectural separation is crucial in healthcare applications where business rules can be complex and must be consistently applied across different access points (REST API, WebSocket, scheduled jobs, etc.).

#### Core Responsibilities

**Orchestrating Complex Operations**: Business processes in healthcare often involve multiple steps. For example, recording a vital sign might require: validating the user exists, saving the measurement, checking for critical values, notifying caregivers if needed, and updating analytics. The service layer coordinates all these steps as a single, transactional unit of work.

**Enforcing Business Rules**: Validation goes beyond simple JSR-380 annotations. Services enforce domain-specific rules like "is this blood pressure reading within a critical range for *this specific patient* given their medical history?" These rules often require database queries or complex calculations.

**Applying Security Context**: Services ensure that a user can only access data they are authorized to see. Even if a controller is misconfigured, the service layer acts as a second line of defense by verifying permissions.

**Managing Transactions**: Using `@Transactional`, services ensure that either all database operations succeed or all fail together. In healthcare, partial data saves could lead to inconsistent medical records, so this all-or-nothing approach is essential.

#### Example: Recording a Vital Sign with Automated Alerts

This example demonstrates how the service layer orchestrates a seemingly simple operation (recording a blood pressure reading) into a multi-step process that maintains data integrity and patient safety:

```java
// service/HealthService.java
@Service
@Transactional // This entire method is a single transaction
public class HealthService {

    private final VitalSignRepository vitalSignRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;
    private final VitalSignAnalyzer vitalSignAnalyzer;
    
    private static final Logger log = LoggerFactory.getLogger(HealthService.class);

    public HealthService(VitalSignRepository vitalSignRepository,
                        UserRepository userRepository,
                        NotificationService notificationService,
                        VitalSignAnalyzer vitalSignAnalyzer) {
        this.vitalSignRepository = vitalSignRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
        this.vitalSignAnalyzer = vitalSignAnalyzer;
    }

    public VitalSignDTO recordVitalSign(Long userId, VitalSignDTO vitalSignDTO) {
        // 1. VALIDATE: First, ensure the user exists and is authorized
        //    This prevents orphaned vital signs and enforces data integrity
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException(
                    "User not found with id: " + userId));
        
        // Additional business rule: Only patients and caregivers can record vitals
        if (!user.canRecordVitalSigns()) {
            throw new UnauthorizedException("User is not authorized to record vital signs");
        }

        // 2. CONVERT: Map the incoming DTO to a JPA Entity
        //    DTOs protect our API from exposing internal entity structure
        VitalSign vitalSign = new VitalSign();
        vitalSign.setUser(user);
        vitalSign.setType(vitalSignDTO.getType());
        vitalSign.setValue(vitalSignDTO.getValue());
        vitalSign.setUnit(vitalSignDTO.getUnit());
        vitalSign.setNotes(vitalSignDTO.getNotes());
        vitalSign.setMeasurementTime(LocalDateTime.now());

        // 3. PERSIST: Save the entity to the database
        //    The transaction ensures this and all subsequent operations succeed together
        vitalSign = vitalSignRepository.save(vitalSign);
        
        log.info("Recorded vital sign for user {}: {} {}", 
                userId, vitalSign.getValue(), vitalSign.getUnit());

        // 4. PROCESS BUSINESS LOGIC: Check for critical alerts after saving
        //    This is a key piece of business logic that belongs in the service
        //    If this were in the controller, other entry points might miss the check
        checkForVitalSignAlerts(vitalSign);

        // 5. RETURN: Convert the saved entity back to a DTO for the response
        //    This prevents accidental exposure of Hibernate proxies or lazy-loaded data
        return convertToDTO(vitalSign);
    }

    /**
     * Analyzes a vital sign and sends alerts if critical thresholds are exceeded.
     * This method demonstrates separation of concerns: the service orchestrates,
     * while specialized components handle the complex medical logic.
     */
    private void checkForVitalSignAlerts(VitalSign vitalSign) {
        // Delegate the complex medical logic to a dedicated analyzer
        // This makes the code testable and allows medical rules to be updated
        // independently of the service layer
        AlertLevel alertLevel = vitalSignAnalyzer.analyzeVitalSign(vitalSign);
        
        if (alertLevel.isCritical()) {
            // Use the notification service to alert caregivers
            // This abstraction allows notifications via email, SMS, push, etc.
            notificationService.sendHealthAlert(
                vitalSign.getUser(),
                String.format("Critical %s reading: %s %s", 
                    vitalSign.getType(), 
                    vitalSign.getValue(),
                    vitalSign.getUnit()),
                AlertType.CRITICAL_HEALTH_ALERT,
                alertLevel
            );
            
            // Audit log for compliance - all critical events must be logged
            log.warn("CRITICAL ALERT generated for user {} - {} reading: {} {}",
                vitalSign.getUser().getId(),
                vitalSign.getType(),
                vitalSign.getValue(),
                vitalSign.getUnit());
        } else if (alertLevel.needsAttention()) {
            // Send lower-priority notification
            notificationService.sendHealthAlert(
                vitalSign.getUser(),
                String.format("%s reading outside normal range: %s %s", 
                    vitalSign.getType(), 
                    vitalSign.getValue(),
                    vitalSign.getUnit()),
                AlertType.HEALTH_ADVISORY,
                alertLevel
            );
        }
    }

    private VitalSignDTO convertToDTO(VitalSign vitalSign) {
        // Convert entity to DTO, ensuring we don't expose internal details
        return VitalSignDTO.builder()
            .id(vitalSign.getId())
            .type(vitalSign.getType())
            .value(vitalSign.getValue())
            .unit(vitalSign.getUnit())
            .notes(vitalSign.getNotes())
            .measurementTime(vitalSign.getMeasurementTime())
            .build();
    }
}
```

#### Why This Structure?

This method clearly separates concerns:
- The **repository** handles only data persistence and retrieval
- The **analyzer** encapsulates complex medical rules and thresholds
- The **notification service** handles the mechanics of sending alerts
- The **service** orchestrates all these components into a cohesive workflow

The `@Transactional` annotation is critical here. If the alert-sending logic fails (e.g., email server is down), the entire vital sign recording is rolled back. This ensures we never have a situation where a critical reading is recorded but caregivers aren't notified.

In healthcare applications, this transactional integrity is not just a nice-to-have—it's a regulatory requirement. The service layer is where we enforce these guarantees.

### Controller Layer

REST API endpoints:

```java
// controller/HealthController.java
@RestController
@RequestMapping("v1/api/health")
@PreAuthorize("hasRole('PATIENT') or hasRole('CAREGIVER')")
@Tag(name = "Health", description = "Health data management")
public class HealthController {

    private final HealthService healthService;

    public HealthController(HealthService healthService) {
        this.healthService = healthService;
    }

    @GetMapping("/vitals")
    @Operation(summary = "Get user's vital signs")
    public ResponseEntity<List<VitalSignDTO>> getVitalSigns(
            Authentication authentication) {

        Long userId = getUserIdFromAuthentication(authentication);
        List<VitalSignDTO> vitalSigns = healthService.getVitalSigns(userId);

        return ResponseEntity.ok(vitalSigns);
    }

    @PostMapping("/vitals")
    @Operation(summary = "Record a new vital sign")
    public ResponseEntity<VitalSignDTO> recordVitalSign(
            @Valid @RequestBody VitalSignDTO vitalSignDTO,
            Authentication authentication) {

        Long userId = getUserIdFromAuthentication(authentication);
        VitalSignDTO savedVitalSign = healthService.recordVitalSign(userId, vitalSignDTO);

        return ResponseEntity.status(HttpStatus.CREATED).body(savedVitalSign);
    }

    @GetMapping("/vitals/{type}")
    @Operation(summary = "Get vital signs by type")
    public ResponseEntity<List<VitalSignDTO>> getVitalSignsByType(
            @PathVariable String type,
            Authentication authentication) {

        Long userId = getUserIdFromAuthentication(authentication);
        List<VitalSignDTO> vitalSigns = healthService.getVitalSignsByType(userId, type);

        return ResponseEntity.ok(vitalSigns);
    }

    private Long getUserIdFromAuthentication(Authentication authentication) {
        UserPrincipal userPrincipal = (UserPrincipal) authentication.getPrincipal();
        return userPrincipal.getId();
    }
}
```

## Database Design

### Entity Relationship Diagram

```
Users                          VitalSigns
┌─────────────────────┐       ┌─────────────────────┐
│ id (PK)             │       │ id (PK)             │
│ email (UQ)          │       │ user_id (FK)        │
│ password            │       │ type                │
│ first_name          │       │ value               │
│ last_name           │       │ unit                │
│ role                │       │ notes               │
│ active              │       │ measurement_time    │
│ created_at          │       │ created_at          │
│ updated_at          │       │ updated_at          │
└─────────────────────┘       └─────────────────────┘
          │                            │
          └────────────1:N─────────────┘

CaregiverPatientLink          ChatMessages
┌─────────────────────┐       ┌─────────────────────┐
│ id (PK)             │       │ id (PK)             │
│ caregiver_id (FK)   │       │ sender_id (FK)      │
│ patient_id (FK)     │       │ receiver_id (FK)    │
│ status              │       │ content             │
│ created_at          │       │ message_type        │
│ updated_at          │       │ sent_at             │
└─────────────────────┘       └─────────────────────┘
```

### Database Schema

```sql
-- Users table
CREATE TABLE users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role ENUM('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER') NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Vital signs table
CREATE TABLE vital_signs (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    type VARCHAR(50) NOT NULL,
    value DECIMAL(10,2) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    notes TEXT,
    measurement_time DATETIME NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_vital_signs_user_id ON vital_signs(user_id);
CREATE INDEX idx_vital_signs_type ON vital_signs(type);
CREATE INDEX idx_vital_signs_measurement_time ON vital_signs(measurement_time);
```

## API Documentation

### OpenAPI Configuration

```java
// config/OpenApiConfig.java
@Configuration
@EnableWebSecurity
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("CareConnect API")
                .version("1.0.0")
                .description("Healthcare management platform API"))
            .addSecurityItem(new SecurityRequirement().addList("bearerAuth"))
            .components(new Components()
                .addSecuritySchemes("bearerAuth",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")));
    }
}
```

### RESTful API Endpoints

The CareConnect backend provides a comprehensive RESTful API with over 100 endpoints organized by functional domains. All endpoints follow consistent patterns with proper HTTP methods, status codes, and JSON responses.

#### Base URL and Versioning

All API endpoints are prefixed with `/v1/api/` (with some legacy endpoints at `/api/`). The backend runs on Spring Boot with embedded Tomcat.

```
Base URL: http://localhost:8080/v1/api
Production: https://your-domain.com/v1/api
```

#### Authentication & Authorization

Most endpoints require Bearer token authentication obtained through the login process:

```http
Authorization: Bearer <jwt-token>
```

**Public Endpoints (No Authentication Required):**
- All `/v1/api/auth/**` endpoints (registration, login, password reset)
- `/v1/api/emergency/**` endpoints (emergency PDF access)
- `/v1/api/public/**` endpoints
- Email verification and OAuth callbacks

#### Core API Endpoints by Domain

##### 1. Authentication (`/v1/api/auth`)

**Registration & Login**
```http
POST /v1/api/auth/register
Content-Type: application/json
{
  "email": "user@example.com",
  "password": "password123",
  "name": "John Doe",
  "role": "PATIENT"
}

POST /v1/api/auth/login
Content-Type: application/json
{
  "email": "user@example.com",
  "password": "password123"
}
Response: {
  "token": "jwt-token",
  "user": {...},
  "patientId": 123,
  "caregiverId": null
}
```

**Password Management**
```http
POST /v1/api/auth/password/forgot
POST /v1/api/auth/password/change
GET /v1/api/auth/password/reset?token=abc123
```

**OAuth & Third-Party Integration**
```http
GET /v1/api/auth/sso/google
POST /v1/api/auth/sso/alexa/code
POST /v1/api/auth/sso/alexa/token
```

##### 2. Patient Management (`/v1/api/patients`)

**Patient Profile**
```http
GET /v1/api/patients/{patientId}
PUT /v1/api/patients/{patientId}
GET /v1/api/patients/me  # Current patient's profile
GET /v1/api/patients/{patientId}/profile/enhanced  # With medical data
```

**Mood & Pain Tracking**
```http
POST /v1/api/patients/mood-pain-log
{
  "mood": 7,
  "pain": 3,
  "timestamp": "2024-01-15T10:30:00Z",
  "notes": "Feeling better today"
}

GET /v1/api/patients/mood-pain-log/range?startDate=2024-01-01&endDate=2024-01-31
GET /v1/api/patients/mood-pain-log/analytics?startDate=2024-01-01&endDate=2024-01-31
```

**Medication Management**
```http
GET /v1/api/patients/{patientId}/medications
POST /v1/api/patients/{patientId}/medications
DELETE /v1/api/patients/{patientId}/medications/{medicationId}  # Soft delete
```

**Family Member Relations**
```http
GET /v1/api/patients/{patientId}/family-members
POST /v1/api/patients/{patientId}/family-members
{
  "email": "family@example.com",
  "firstName": "Jane",
  "lastName": "Doe",
  "relationship": "daughter",
  "permissions": ["VIEW_PROFILE", "VIEW_VITALS"]
}
```

##### 3. Caregiver Operations (`/v1/api/caregivers`)

```http
GET /v1/api/caregivers/{caregiverId}/patients?email=patient@example.com&name=John
POST /v1/api/caregivers/{caregiverId}/patients
{
  "email": "newpatient@example.com",
  "firstName": "New",
  "lastName": "Patient",
  "dateOfBirth": "1990-01-01",
  "emergencyContactName": "Contact Name",
  "emergencyContactPhone": "555-0123"
}

POST /v1/api/caregivers/{caregiverId}/patients/add
{
  "email": "existing@example.com"
}
```

##### 4. Analytics & Vital Signs (`/v1/api/analytics`)

**Dashboard & Vitals**
```http
GET /v1/api/analytics/dashboard?patientId=123&days=30
GET /v1/api/analytics/vitals?patientId=123&days=7

POST /v1/api/analytics/vitals
{
  "patientId": 123,
  "vitalType": "BLOOD_PRESSURE",
  "systolic": 120,
  "diastolic": 80,
  "timestamp": "2024-01-15T10:30:00Z",
  "notes": "Morning reading"
}
```

**Data Export**
```http
GET /v1/api/analytics/export/vitals/csv?patientId=123&days=30
GET /v1/api/analytics/export/vitals/pdf?patientId=123&days=30
```

**Live Data Streaming**
```http
GET /v1/api/analytics/live?patientId=123
Accept: text/event-stream
# Returns Server-Sent Events stream
```

##### 5. Task Management

**Version 2 (Current)**
```http
GET /v2/api/tasks/patient/{patientId}
POST /v2/api/tasks/patient/{patientId}
{
  "title": "Take medication",
  "description": "Take morning pills",
  "dueDate": "2024-01-15T09:00:00Z",
  "priority": "HIGH",
  "completed": false
}

PUT /v2/api/tasks/{id}/complete
{
  "isComplete": true
}

DELETE /v2/api/tasks/{id}?deleteSeries=true  # For recurring tasks
```

##### 6. Messaging & Communication (`/v1/api/messages`)

```http
POST /v1/api/messages/send
{
  "senderId": 123,
  "receiverId": 456,
  "content": "How are you feeling today?",
  "messageType": "TEXT"
}

GET /v1/api/messages/conversation?user1=123&user2=456
GET /v1/api/messages/inbox/{userId}
```

##### 7. Notifications (`/v1/api/notifications`)

**Push Notifications**
```http
POST /v1/api/notifications/send
{
  "title": "Medication Reminder",
  "body": "Time to take your morning medication",
  "fcmTokens": ["fcm-token-1", "fcm-token-2"],
  "notificationType": "MEDICATION_REMINDER",
  "data": {
    "medicationId": "123",
    "patientId": "456"
  }
}
```

**Specialized Alerts**
```http
POST /v1/api/notifications/vital-alert/{patientId}?vitalType=BLOOD_PRESSURE&vitalValue=180/120&alertLevel=HIGH
POST /v1/api/notifications/emergency-alert/{patientId}?emergencyType=FALL_DETECTED&location=Living Room
POST /v1/api/notifications/medication-reminder/{patientId}?medicationName=Aspirin&dosage=100mg&scheduledTime=09:00
```

##### 8. File Management (`/v1/api/files`)

```http
POST /v1/api/files/upload
Content-Type: multipart/form-data
file: <binary-data>
category: "MEDICAL_RECORDS"
description: "Lab results from 2024-01-15"
patientId: 123

GET /v1/api/files/{fileId}/download
GET /v1/api/files/my-files?category=MEDICAL_RECORDS
GET /v1/api/files/patient/{patientId}?category=PRESCRIPTIONS
DELETE /v1/api/files/{fileId}
```

##### 9. Emergency Services (`/v1/api/emergency`)

**Public Emergency Access (No Authentication)**
```http
GET /v1/api/emergency/{emergencyId}.pdf
# Returns Vial of Life PDF with patient emergency information
# emergencyId format: VIAL123456

GET /v1/api/emergency/download/{emergencyId}.pdf
# Forces download instead of browser viewing
```

##### 10. Electronic Visit Verification (EVV) (`/v1/api/evv`)

```http
POST /v1/api/evv/participants
{
  "participantName": "John Doe",
  "participantId": "P123456",
  "serviceType": "PERSONAL_CARE",
  "authorizedHours": 40
}

POST /v1/api/evv/records
{
  "participantId": "P123456",
  "providerId": "PRV789",
  "serviceDate": "2024-01-15",
  "clockInTime": "09:00:00",
  "clockOutTime": "17:00:00",
  "serviceLocation": "123 Main St",
  "servicesProvided": ["PERSONAL_CARE", "MEAL_PREPARATION"],
  "gpsCoordinates": {
    "latitude": 38.9072,
    "longitude": -77.0369
  }
}

GET /v1/api/evv/records/search?participantId=P123456&startDate=2024-01-01&endDate=2024-01-31
```

##### 11. Alexa Integration (`/v1/api/alexa`)

```http
GET /v1/api/alexa/calendarTasks/get?filter=week
Authorization: Bearer <alexa-access-token>

POST /v1/api/alexa/calendarTasks/add
Authorization: Bearer <alexa-access-token>
{
  "name": "Doctor appointment",
  "description": "Annual checkup with Dr. Smith",
  "date": "2024-01-20",
  "timeOfDay": "MORNING",
  "priority": "HIGH"
}
```

##### 12. Subscription Management (`/v1/api/subscriptions`)

```http
GET /v1/api/subscriptions/plans
POST /v1/api/subscriptions/create?plan=premium&userId=123&amount=2999
GET /v1/api/subscriptions/user/{userId}/active
POST /v1/api/subscriptions/{id}/cancel
POST /v1/api/subscriptions/upgrade-or-downgrade?oldSubscriptionId=sub_123&newPriceId=price_456
```

#### Error Handling

All endpoints return consistent error responses:

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "status": 400,
  "error": "Bad Request",
  "message": "Validation failed for field 'email'",
  "path": "/v1/api/auth/register"
}
```

**Common HTTP Status Codes:**
- `200` - Success
- `201` - Created
- `400` - Bad Request (validation errors)
- `401` - Unauthorized (missing/invalid token)
- `403` - Forbidden (insufficient permissions)
- `404` - Not Found
- `409` - Conflict (duplicate resource)
- `500` - Internal Server Error

#### Rate Limiting

API endpoints implement rate limiting based on user role:
- **Public endpoints**: 100 requests per hour per IP
- **Authenticated users**: 1000 requests per hour per user
- **Emergency endpoints**: No rate limiting

#### Data Formats

**Date/Time**: ISO 8601 format (`2024-01-15T10:30:00Z`)
**Pagination**:
```json
{
  "content": [...],
  "pageable": {
    "page": 0,
    "size": 20,
    "sort": "createdAt,desc"
  },
  "totalElements": 100,
  "totalPages": 5
}
```

#### WebSocket Integration

Real-time communication endpoints at `/ws`:
- `/ws/notifications` - Real-time notifications
- `/ws/vitals` - Live vital signs updates
- `/ws/chat` - Messaging system

## Authentication & Security

### JWT Implementation

```java
// util/JwtUtil.java
@Component
public class JwtUtil {

    @Value("${jwt.secret}")
    private String jwtSecret;

    @Value("${jwt.expiration}")
    private long jwtExpiration;

    public String generateToken(UserDetails userDetails) {
        Map<String, Object> claims = new HashMap<>();
        return createToken(claims, userDetails.getUsername());
    }

    private String createToken(Map<String, Object> claims, String subject) {
        return Jwts.builder()
            .setClaims(claims)
            .setSubject(subject)
            .setIssuedAt(new Date(System.currentTimeMillis()))
            .setExpiration(new Date(System.currentTimeMillis() + jwtExpiration))
            .signWith(getSigningKey(), SignatureAlgorithm.HS256)
            .compact();
    }

    public Boolean validateToken(String token, UserDetails userDetails) {
        final String username = getUsernameFromToken(token);
        return (username.equals(userDetails.getUsername()) && !isTokenExpired(token));
    }

    private Key getSigningKey() {
        byte[] keyBytes = Decoders.BASE64.decode(jwtSecret);
        return Keys.hmacShaKeyFor(keyBytes);
    }
}
```

### JWT Authentication Filter

The CareConnect backend uses a custom JWT authentication filter that provides comprehensive token-based authentication with automatic token renewal and multi-source token resolution.

#### JwtAuthenticationFilter Implementation

```java
// security/JwtAuthenticationFilter.java
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthenticationFilter.class);
    private static final String COOKIE_NAME = "AUTH";

    // Paths excluded from JWT authentication
    private static final List<String> EXCLUDED_PATHS = Arrays.asList(
        "/swagger-ui",
        "/v3/api-docs",
        "/swagger-resources",
        "/webjars",
        "/v1/api/auth",           // Authentication endpoints
        "/api/v1/auth",
        "/v1/api/test",           // Test endpoints
        "/v1/api/caregivers",     // Public caregiver registration
        "/v1/api/subscriptions",  // Public subscription info
        "/v1/api/email-test",     // Email testing
        "/v1/api/emergency"       // Emergency PDF access (no auth required)
    );

    private final JwtTokenProvider jwt;
    private final UserDetailsService uds;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        return EXCLUDED_PATHS.stream().anyMatch(path::startsWith);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req,
                                    HttpServletResponse res,
                                    FilterChain chain)
            throws ServletException, IOException {

        String requestURI = req.getRequestURI();
        log.debug("Processing JWT authentication for: {}", requestURI);

        // 1. Resolve token from header or cookie
        String token = resolveToken(req);

        // 2. Validate token and build authentication
        if (token != null && jwt.validateToken(token)) {
            Claims claims = jwt.getClaims(token);
            String email = claims.getSubject();
            String role = claims.get("role", String.class);

            // Role-specific user loading for precise authentication
            UserDetails userDetails;
            if (role != null && uds instanceof UserDetailsServiceImpl) {
                userDetails = ((UserDetailsServiceImpl) uds)
                    .loadUserByEmailAndRole(email, role);
            } else {
                userDetails = uds.loadUserByUsername(email);
            }

            UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(
                    userDetails, null, userDetails.getAuthorities());
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(req));
            SecurityContextHolder.getContext().setAuthentication(auth);

            // 3. Silent token renewal (if < 5 minutes remaining)
            if (jwt.needsRenewal(claims)) {
                String renewed = jwt.refresh(claims);
                ResponseCookie cookie = ResponseCookie.from(COOKIE_NAME, renewed)
                    .httpOnly(true)
                    .secure(true)
                    .sameSite("Lax")
                    .path("/")
                    .maxAge(Duration.ofHours(3))  // 3-hour sliding window
                    .build();
                res.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
                log.debug("Token renewed for user: {}", email);
            }
        }

        chain.doFilter(req, res);
    }

    private String resolveToken(HttpServletRequest req) {
        // Check Bearer header first
        String header = req.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            return header.substring(7);
        }

        // Fallback to HttpOnly cookie
        if (req.getCookies() != null) {
            return Arrays.stream(req.getCookies())
                .filter(c -> COOKIE_NAME.equals(c.getName()))
                .findFirst()
                .map(Cookie::getValue)
                .orElse(null);
        }
        return null;
    }
}
```

#### Key Features

**Multi-Source Token Resolution:**
- Primary: `Authorization: Bearer <token>` header
- Fallback: HttpOnly `AUTH` cookie for web clients
- Secure cookie configuration (HttpOnly, Secure, SameSite)

**Path-Based Exclusions:**
- Public authentication endpoints (`/v1/api/auth/**`)
- Emergency access endpoints (`/v1/api/emergency/**`)
- API documentation (`/swagger-ui/**`, `/v3/api-docs/**`)
- Public registration endpoints

**Automatic Token Renewal:**
- Silent renewal when < 5 minutes remaining
- 3-hour sliding window maximum
- Maintains user session without interruption

**Role-Based Authentication:**
- Extracts role from JWT claims
- Role-specific user loading for multi-role scenarios
- Prevents authentication ambiguity

### Security Configuration

```java
// config/SecurityConfig.java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity(prePostEnabled = true)
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final JwtAuthenticationEntryPoint jwtAuthenticationEntryPoint;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf().disable()
            .sessionManagement().sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            .and()
            .authorizeHttpRequests(authz -> authz
                // Public endpoints
                .requestMatchers("/v1/api/auth/**").permitAll()
                .requestMatchers("/v1/api/emergency/**").permitAll()
                .requestMatchers("/v1/api/public/**").permitAll()
                .requestMatchers("/swagger-ui/**", "/v3/api-docs/**").permitAll()

                // Role-based endpoints
                .requestMatchers("/v1/api/patients/**").hasAnyRole("PATIENT", "CAREGIVER", "FAMILY_MEMBER")
                .requestMatchers("/v1/api/caregivers/**").hasAnyRole("CAREGIVER", "ADMIN")
                .requestMatchers("/v1/api/family-members/**").hasRole("FAMILY_MEMBER")
                .requestMatchers("/v1/api/admin/**").hasRole("ADMIN")

                // Default authentication required
                .anyRequest().authenticated())
            .exceptionHandling()
                .authenticationEntryPoint(jwtAuthenticationEntryPoint)
            .and()
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    @Bean
    public AuthenticationManager authenticationManager(
            AuthenticationConfiguration config) throws Exception {
        return config.getAuthenticationManager();
    }
}
```

### JWT Token Provider

```java
// security/JwtTokenProvider.java
@Component
public class JwtTokenProvider {

    @Value("${jwt.secret}")
    private String jwtSecret;

    @Value("${jwt.expiration:3600000}") // 1 hour default
    private long jwtExpiration;

    private static final long RENEWAL_THRESHOLD = 5 * 60 * 1000; // 5 minutes

    public String generateToken(UserDetails userDetails, String role) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("role", role);
        claims.put("authorities", userDetails.getAuthorities());

        return createToken(claims, userDetails.getUsername());
    }

    private String createToken(Map<String, Object> claims, String subject) {
        Date now = new Date();
        Date validity = new Date(now.getTime() + jwtExpiration);

        return Jwts.builder()
            .setClaims(claims)
            .setSubject(subject)
            .setIssuedAt(now)
            .setExpiration(validity)
            .signWith(getSigningKey(), SignatureAlgorithm.HS256)
            .compact();
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parserBuilder()
                .setSigningKey(getSigningKey())
                .build()
                .parseClaimsJws(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            log.debug("Invalid JWT token: {}", e.getMessage());
            return false;
        }
    }

    public Claims getClaims(String token) {
        return Jwts.parserBuilder()
            .setSigningKey(getSigningKey())
            .build()
            .parseClaimsJws(token)
            .getBody();
    }

    public boolean needsRenewal(Claims claims) {
        Date expiration = claims.getExpiration();
        long timeUntilExpiry = expiration.getTime() - System.currentTimeMillis();
        return timeUntilExpiry < RENEWAL_THRESHOLD;
    }

    public String refresh(Claims claims) {
        // Create new token with extended expiration
        Map<String, Object> newClaims = new HashMap<>(claims);
        return createToken(newClaims, claims.getSubject());
    }

    private Key getSigningKey() {
        byte[] keyBytes = Decoders.BASE64.decode(jwtSecret);
        return Keys.hmacShaKeyFor(keyBytes);
    }
}
```

### User Details Service Implementation

```java
// security/UserDetailsServiceImpl.java
@Service
@RequiredArgsConstructor
public class UserDetailsServiceImpl implements UserDetailsService {

    private final UserRepository userRepository;

    @Override
    public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
        User user = userRepository.findByEmail(email)
            .orElseThrow(() -> new UsernameNotFoundException("User not found: " + email));

        return UserPrincipal.create(user);
    }

    // Role-specific loading for multi-role scenarios
    public UserDetails loadUserByEmailAndRole(String email, String role)
            throws UsernameNotFoundException {
        User user = userRepository.findByEmailAndRole(email, UserRole.valueOf(role))
            .orElseThrow(() -> new UsernameNotFoundException(
                "User not found with email: " + email + " and role: " + role));

        return UserPrincipal.create(user);
    }
}

// security/UserPrincipal.java
@Getter
@AllArgsConstructor
public class UserPrincipal implements UserDetails {

    private Long id;
    private String email;
    private String password;
    private Collection<? extends GrantedAuthority> authorities;
    private boolean enabled;

    public static UserPrincipal create(User user) {
        List<GrantedAuthority> authorities = List.of(
            new SimpleGrantedAuthority("ROLE_" + user.getRole().name())
        );

        return new UserPrincipal(
            user.getId(),
            user.getEmail(),
            user.getPassword(),
            authorities,
            user.getActive()
        );
    }

    @Override
    public String getUsername() { return email; }

    @Override
    public boolean isAccountNonExpired() { return true; }

    @Override
    public boolean isAccountNonLocked() { return true; }

    @Override
    public boolean isCredentialsNonExpired() { return true; }

    @Override
    public boolean isEnabled() { return enabled; }
}
```

### Security Features

**Password Security:**
- BCrypt hashing with strength 12
- Minimum 8 characters with complexity requirements
- Password history prevention (last 5 passwords)

**Session Management:**
- Stateless JWT-based authentication
- Automatic token renewal for active sessions
- Secure cookie storage for web clients

**CORS Configuration:**
```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration configuration = new CorsConfiguration();
    configuration.setAllowedOriginPatterns(List.of("*"));
    configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
    configuration.setAllowedHeaders(List.of("*"));
    configuration.setAllowCredentials(true);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", configuration);
    return source;
}
```

**Rate Limiting:**
- API rate limiting based on user role and endpoint
- Brute force protection for authentication endpoints
- Emergency endpoint exemption from rate limits

## Real-time Communication with WebSocket

CareConnect implements a comprehensive WebSocket-based real-time communication system. This system is specifically designed for healthcare applications where timely information delivery can be critical to patient safety. The system uses a **dual-mode architecture** that automatically switches between local development (embedded WebSocket server) and AWS production (API Gateway WebSocket) environments.

### Why WebSocket for Healthcare?

Healthcare scenarios demand real-time communication in ways that traditional REST APIs cannot satisfy:

**Critical Alerts**: When a patient's blood pressure reading is dangerously high, the caregiver needs immediate notification—not whenever they next refresh the dashboard. A 5-minute delay in notification could be the difference between timely intervention and a medical emergency.

**Medication Reminders**: Patients need timely reminders to take medications. WebSocket push notifications are more reliable than polling, especially when the app is backgrounded.

**Communication**: Video calls, text messaging, and emergency calls require persistent connections. Establishing a new HTTP connection for every message would be slow and wasteful.

**Vital Signs Monitoring**: Real-time streaming of vital signs data (from connected devices like blood pressure monitors) requires continuous data flow, not request-response cycles.

**Audit Requirements**: Healthcare regulations often require real-time audit logging. WebSocket connections can stream audit events as they occur, rather than batching them.

While Server-Sent Events (SSE) could handle some use cases, WebSocket's bidirectional nature allows clients to also send data efficiently (like acknowledging alerts or sending heartbeats).

### Architecture Overview

CareConnect provides three main WebSocket channels, each serving distinct purposes:

**`/ws/careconnect`** - Primary healthcare communications channel
- AI notifications (health risk assessments, recommendations)
- Vital signs alerts (abnormal readings requiring attention)
- Medication reminders (scheduled notifications)
- Mood/pain log updates (real-time patient self-reporting)
- Emergency alerts (critical patient situations)

**`/ws/calls`** - Call management and notifications
- Video call initiation and coordination
- Audio call signaling
- SMS notifications (text message delivery)
- Call status updates

**`/ws/notifications`** - General notification delivery
- System notifications
- Administrative messages
- Low-priority updates

This separation allows different Quality of Service levels: emergency alerts on `/ws/careconnect` get highest priority, while general notifications can be throttled during high load.

### Dual-Mode Configuration: Development vs Production

CareConnect's WebSocket system adapts automatically to its environment:

**Development Mode**: Uses Spring Boot's embedded WebSocket server
- Runs on same port as REST API (8080)
- Simple configuration, easy debugging
- Full WebSocket features including SockJS fallback
- Perfect for local development and testing

**Production Mode**: Uses AWS API Gateway WebSocket
- Scales automatically with load
- Integrates with AWS Lambda for message processing
- Global distribution via CloudFront
- Handles connection persistence and reconnection

This dual-mode approach means developers can work locally without AWS credentials, while production benefits from enterprise-grade infrastructure.

#### Configuration Detection

```java
// config/WebSocketModeConfig.java
@Configuration
@ConditionalOnProperty(
    name = "careconnect.websocket.enabled", 
    havingValue = "true", 
    matchIfMissing = true
)
public class WebSocketModeConfig {

    /**
     * Local WebSocket configuration - used when AWS endpoint is not defined.
     * This is the default for development environments.
     */
    @Bean
    @ConditionalOnMissingBean(name = "awsWebSocketApiEndpoint")
    public WebSocketConfig localWebSocketConfig() {
        return new WebSocketConfig(); // Embedded Spring WebSocket
    }

    /**
     * AWS WebSocket configuration - used when AWS endpoint is defined.
     * This activates in production when AWS_WEBSOCKET_API_ENDPOINT is set.
     */
    @Bean
    @ConditionalOnBean(name = "awsWebSocketApiEndpoint")
    public AwsWebSocketService awsWebSocketService() {
        return new AwsWebSocketService(); // AWS API Gateway client
    }
}
```

**How it works**: Spring checks for the presence of `awsWebSocketApiEndpoint` bean (defined when `AWS_WEBSOCKET_API_ENDPOINT` environment variable is set). If present, uses AWS mode; otherwise, uses local mode. This is completely transparent to application code.

### Local Development WebSocket Configuration

```java
// config/WebSocketConfig.java
@Configuration
@EnableWebSocket
@Slf4j
public class WebSocketConfig implements WebSocketConfigurer {

    @Value("${careconnect.websocket.allowed-origins}")
    private String allowedOrigins;

    private final CareConnectWebSocketHandler careConnectHandler;
    private final CallNotificationHandler callHandler;
    private final NotificationWebSocketHandler notificationHandler;

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        // Parse allowed origins from configuration
        String[] origins = allowedOrigins.split(",");

        // Main healthcare WebSocket with SockJS fallback
        registry.addHandler(careConnectHandler, "/ws/careconnect")
                .setAllowedOrigins(origins)
                .withSockJS();  // Enables fallback for browsers without WebSocket

        // Call management WebSocket with SockJS fallback
        registry.addHandler(callHandler, "/ws/calls")
                .setAllowedOrigins(origins)
                .withSockJS();

        // Basic notifications (no SockJS - pure WebSocket only)
        registry.addHandler(notificationHandler, "/ws/notifications")
                .setAllowedOrigins(origins);
    }
}
```

#### Why SockJS Fallback?

SockJS provides automatic fallback to HTTP long-polling when WebSocket is unavailable. This is crucial in healthcare settings where:
- Corporate firewalls might block WebSocket connections
- Some hospital networks use outdated proxies incompatible with WebSocket
- Mobile networks occasionally have issues with persistent connections

With SockJS, the application automatically degrades gracefully: tries WebSocket first, falls back to HTTP streaming, then long-polling if needed. The application code remains identical—SockJS handles the complexity.

### WebSocket Handler: Healthcare Communications

The main healthcare WebSocket handler manages patient-critical communications:

```java
@Component
@Slf4j
public class CareConnectWebSocketHandler extends TextWebSocketHandler {

    private final JwtTokenProvider jwtTokenProvider;
    private final WebSocketConnectionService connectionService;
    
    // Thread-safe map of user IDs to active WebSocket sessions
    private final Map<Long, WebSocketSession> userSessions = new ConcurrentHashMap<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        log.info("WebSocket connection established: {}", session.getId());
        
        // Track when connection was established (for timeout detection)
        session.getAttributes().put("connectionTime", System.currentTimeMillis());

        // Send welcome message to client
        sendMessage(session, Map.of(
            "type", "connection-established",
            "message", "WebSocket connection successful",
            "sessionId", session.getId()
        ));
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) 
            throws Exception {
        try {
            // Parse incoming message as JSON
            Map<String, Object> payload = objectMapper.readValue(
                message.getPayload(), 
                Map.class
            );
            String messageType = (String) payload.get("type");

            // Route message to appropriate handler based on type
            switch (messageType) {
                case "authenticate":
                    // Client sends JWT token to authenticate the connection
                    handleAuthentication(session, payload);
                    break;
                    
                case "heartbeat":
                    // Client sends periodic heartbeat to keep connection alive
                    handleHeartbeat(session);
                    break;
                    
                case "ai-chat-notification":
                    // AI-generated health recommendations or alerts
                    handleAIChatNotification(session, payload);
                    break;
                    
                case "mood-pain-log-update":
                    // Patient reported mood/pain data in real-time
                    handleMoodPainLogUpdate(session, payload);
                    break;
                    
                case "medication-reminder":
                    // Scheduled medication reminder needs to be sent
                    handleMedicationReminder(session, payload);
                    break;
                    
                case "vital-signs-alert":
                    // Abnormal vital sign detected, alert caregivers
                    handleVitalSignsAlert(session, payload);
                    break;
                    
                case "emergency-alert":
                    // Critical patient emergency, highest priority
                    handleEmergencyAlert(session, payload);
                    break;
                    
                default:
                    log.warn("Unknown message type received: {}", messageType);
                    sendErrorMessage(session, "Unknown message type: " + messageType);
            }
        } catch (Exception e) {
            log.error("Error handling WebSocket message", e);
            sendErrorMessage(session, "Invalid message format");
        }
    }

    /**
     * Handles client authentication over WebSocket.
     * Unlike REST APIs where auth happens per-request, WebSocket connections
     * authenticate once when established, then remain authenticated.
     */
    private void handleAuthentication(WebSocketSession session, Map<String, Object> payload) {
        try {
            String token = (String) payload.get("token");
            Long userId = getLongValue(payload, "userId");

            if (jwtTokenProvider.validateToken(token)) {
                // Token is valid - extract user information
                Claims claims = jwtTokenProvider.getClaims(token);
                String email = claims.getSubject();
                String role = claims.get("role", String.class);

                // Store user info in session attributes
                // These persist for the lifetime of the WebSocket connection
                session.getAttributes().put("userId", userId);
                session.getAttributes().put("email", email);
                session.getAttributes().put("role", role);
                session.getAttributes().put("authenticated", true);

                // Map user ID to this session for targeted messaging
                // When we need to send alert to user 123, we look up their session here
                userSessions.put(userId, session);

                // Persist connection to database for audit trail and reconnection
                connectionService.saveConnection(
                    session.getId(), 
                    email, 
                    userId, 
                    "authenticated"
                );

                // Confirm successful authentication to client
                sendMessage(session, Map.of(
                    "type", "authentication-success",
                    "userId", userId,
                    "email", email,
                    "role", role
                ));

                log.info("User {} authenticated via WebSocket", email);
            } else {
                // Invalid token - reject authentication
                sendMessage(session, Map.of(
                    "type", "authentication-error",
                    "message", "Invalid token"
                ));
                
                // Close connection after authentication failure
                session.close(CloseStatus.POLICY_VIOLATION);
            }
        } catch (Exception e) {
            log.error("Authentication error", e);
            sendErrorMessage(session, "Authentication failed");
        }
    }

    /**
     * Handles emergency alerts - highest priority healthcare notifications.
     * These bypass normal throttling and are delivered immediately to all
     * authorized recipients (caregivers and family members).
     */
    private void handleEmergencyAlert(WebSocketSession session, Map<String, Object> payload) {
        Long patientId = getLongValue(payload, "patientId");
        String alertType = (String) payload.get("alertType");
        String message = (String) payload.get("message");

        // Construct alert payload
        Map<String, Object> alert = Map.of(
            "type", "emergency-alert",
            "patientId", patientId,
            "alertType", alertType,
            "message", message,
            "timestamp", System.currentTimeMillis(),
            "priority", "HIGH"
        );

        // Broadcast to all caregivers and family members linked to this patient
        // This uses a specialized method that queries database for authorized users
        // and sends to all their active WebSocket sessions
        broadcastToUsersByRole(
            patientId, 
            "emergency-alert", 
            alert,
            List.of("CAREGIVER", "FAMILY_MEMBER")
        );

        // Audit log - all emergency alerts must be logged for compliance
        log.warn("🚨 EMERGENCY ALERT sent for patient {}: {} - {}", 
            patientId, alertType, message);
            
        // Could also trigger additional actions:
        // - Send SMS to emergency contact
        // - Create database record for audit trail
        // - Trigger automated escalation if no acknowledgment within X minutes
    }
    
    private void sendMessage(WebSocketSession session, Map<String, Object> message) 
            throws Exception {
        if (session.isOpen()) {
            String json = objectMapper.writeValueAsString(message);
            session.sendMessage(new TextMessage(json));
        }
    }
}
```

#### Key Architectural Decisions

**Stateful Connections**: Unlike REST's stateless nature, WebSocket connections are stateful. Once a user authenticates, their connection remains authenticated until they disconnect or their token expires. This eliminates the overhead of validating JWT on every message.

**User Session Mapping**: The `userSessions` map enables targeted messaging. When a vital sign alert needs to reach a specific caregiver, we look up their session and send directly to them, rather than broadcasting to everyone.

**Message Type Routing**: The `handleTextMessage` switch statement acts as a message router. As new real-time features are added, they get a new message type and handler method. This scales much better than monolithic message processing.

**Audit Logging**: Every significant event (authentication, emergency alerts) is logged. In healthcare, this audit trail is not optional—it's a regulatory requirement for demonstrating compliance with HIPAA and other regulations.

**Error Resilience**: Notice how exceptions are caught and transformed into error messages sent back to the client. A crashed WebSocket handler would drop all active connections—unacceptable in a healthcare app where those connections might be monitoring critical patients.

### Connection Lifecycle and Management

**Connection Establishment**:
1. Client opens WebSocket connection to `/ws/careconnect`
2. Server accepts, assigns session ID
3. Client sends `authenticate` message with JWT
4. Server validates token, stores user info in session
5. Connection is now ready for bidirectional messaging

**Active Connection**:
- Client sends periodic heartbeats (every 30 seconds) to prevent timeout
- Server can send messages anytime (alerts, notifications)
- Client can send messages anytime (requests, updates)
- Connection remains open for hours or days

**Connection Termination**:
- Client explicitly closes (app backgrounded, user logs out)
- Network interruption (mobile signal loss, WiFi disconnect)
- Server timeout (no heartbeat for 5 minutes)
- Server restart (all connections dropped, clients must reconnect)

**Reconnection Strategy**: Clients implement exponential backoff reconnection:
```dart
// Flutter client reconnection logic
int retryCount = 0;
while (retryCount < 5 && !connected) {
  await Future.delayed(Duration(seconds: math.pow(2, retryCount).toInt()));
  try {
    await connect();
    retryCount = 0; // Reset on success
  } catch (e) {
    retryCount++;
  }
}
```

This prevents overwhelming the server with reconnection attempts while ensuring clients eventually reconnect.

#### CallNotificationHandler - Video/Audio Calls

```java
@Component
@Slf4j
public class CallNotificationHandler extends TextWebSocketHandler {

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        Map<String, Object> payload = objectMapper.readValue(message.getPayload(), Map.class);
        String messageType = (String) payload.get("type");

        switch (messageType) {
            case "send-video-call-invitation":
                handleVideoCallInvitation(session, payload);
                break;
            case "accept-call":
                handleAcceptCall(session, payload);
                break;
            case "decline-call":
                handleDeclineCall(session, payload);
                break;
            case "end-call":
                handleEndCall(session, payload);
                break;
            case "send-sms-notification":
                handleSMSNotification(session, payload);
                break;
        }
    }

    private void handleVideoCallInvitation(WebSocketSession session, Map<String, Object> payload) {
        String fromUserId = (String) payload.get("fromUserId");
        String toUserId = (String) payload.get("toUserId");
        String callType = (String) payload.get("callType"); // "video" or "audio"
        String roomId = (String) payload.get("roomId");

        // Find recipient session and send invitation
        WebSocketSession recipientSession = findSessionByUserId(toUserId);
        if (recipientSession != null && recipientSession.isOpen()) {
            sendMessage(recipientSession, Map.of(
                "type", "incoming-call",
                "fromUserId", fromUserId,
                "callType", callType,
                "roomId", roomId,
                "timestamp", System.currentTimeMillis()
            ));
            log.info("Call invitation sent from {} to {}", fromUserId, toUserId);
        }
    }
}
```

### Security Implementation

#### JWT Authentication

```java
// WebSocket authentication check
private void handleAuthentication(WebSocketSession session, Map<String, Object> payload) {
    String token = (String) payload.get("token");
    if (jwtTokenProvider.validateToken(token)) {
        Claims claims = jwtTokenProvider.getClaims(token);
        String email = claims.getSubject();
        String role = claims.get("role", String.class);

        // Store authenticated user info
        session.getAttributes().put("authenticated", true);
        session.getAttributes().put("email", email);
        session.getAttributes().put("role", role);

        userSessions.put(userId, session);
        connectionService.saveConnection(session.getId(), email, userId, "authenticated");
    }
}
```

#### CORS Configuration

```properties
# application.properties
careconnect.websocket.allowed-origins=http://localhost:*,https://*.careconnect.com
careconnect.websocket.connection-ttl-minutes=30
```

### Connection Management

#### WebSocket Connection Entity

```java
// model/WebSocketConnection.java
@Entity
@Table(name = "websocket_connections")
public class WebSocketConnection {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true)
    private String connectionId;

    @Column(nullable = false)
    private String userEmail;

    private Long userId;

    @Enumerated(EnumType.STRING)
    private SubscriptionType subscriptionType; // email-verification, authenticated, notifications

    @Enumerated(EnumType.STRING)
    private ConnectionType connectionType; // LOCAL, AWS

    private LocalDateTime connectedAt;
    private LocalDateTime lastActivityAt;
    private LocalDateTime expiresAt;
    private Boolean isActive = true;
}
```

#### Connection Service

```java
// service/WebSocketConnectionService.java
@Service
@Transactional
public class WebSocketConnectionService {

    public void saveConnection(String connectionId, String email, Long userId, String subscriptionType) {
        WebSocketConnection connection = new WebSocketConnection();
        connection.setConnectionId(connectionId);
        connection.setUserEmail(email);
        connection.setUserId(userId);
        connection.setSubscriptionType(SubscriptionType.valueOf(subscriptionType.toUpperCase()));
        connection.setConnectionType(detectConnectionType());
        connection.setConnectedAt(LocalDateTime.now());
        connection.setExpiresAt(LocalDateTime.now().plusMinutes(getConnectionTTL()));
        connection.setIsActive(true);

        repository.save(connection);
    }

    @Scheduled(fixedRate = 300000) // Every 5 minutes
    public void cleanupExpiredConnections() {
        List<WebSocketConnection> expired = repository.findExpiredConnections(LocalDateTime.now());
        expired.forEach(conn -> {
            conn.setIsActive(false);
            repository.save(conn);
        });
        log.info("Cleaned up {} expired WebSocket connections", expired.size());
    }
}
```

### REST API Integration

#### WebSocket Controller

```java
// controller/WebSocketController.java
@RestController
@RequestMapping("v1/api/websocket")
@PreAuthorize("hasAnyRole('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER', 'ADMIN')")
public class WebSocketController {

    @PostMapping("/call-invitation")
    public ResponseEntity<String> sendCallInvitation(@RequestBody CallInvitationRequest request) {
        WebSocketSession recipientSession = webSocketHandler.getSessionByUserId(request.getToUserId());
        if (recipientSession != null && recipientSession.isOpen()) {
            webSocketHandler.sendMessage(recipientSession, Map.of(
                "type", "incoming-call",
                "fromUserId", request.getFromUserId(),
                "callType", request.getCallType(),
                "roomId", request.getRoomId()
            ));
            return ResponseEntity.ok("Call invitation sent");
        }
        return ResponseEntity.status(404).body("User not online");
    }

    @PostMapping("/medication-reminder")
    @PreAuthorize("hasAnyRole('CAREGIVER', 'ADMIN')")
    public ResponseEntity<String> sendMedicationReminder(@RequestBody MedicationReminderRequest request) {
        broadcastToPatient(request.getPatientId(), "medication-reminder", Map.of(
            "medicationName", request.getMedicationName(),
            "dosage", request.getDosage(),
            "timeToTake", request.getTimeToTake(),
            "instructions", request.getInstructions()
        ));
        return ResponseEntity.ok("Medication reminder sent");
    }

    @PostMapping("/emergency-alert")
    @PreAuthorize("hasAnyRole('PATIENT', 'CAREGIVER', 'ADMIN')")
    public ResponseEntity<String> sendEmergencyAlert(@RequestBody EmergencyAlertRequest request) {
        // High-priority emergency broadcast
        broadcastToUsersByRole(request.getPatientId(), "emergency-alert", Map.of(
            "alertType", request.getAlertType(),
            "message", request.getMessage(),
            "location", request.getLocation(),
            "priority", "CRITICAL"
        ), List.of("CAREGIVER", "FAMILY_MEMBER", "ADMIN"));

        return ResponseEntity.ok("Emergency alert broadcasted");
    }

    @GetMapping("/online-users")
    @PreAuthorize("hasAnyRole('CAREGIVER', 'ADMIN')")
    public ResponseEntity<List<OnlineUserInfo>> getOnlineUsers() {
        List<OnlineUserInfo> onlineUsers = webSocketHandler.getOnlineUsers();
        return ResponseEntity.ok(onlineUsers);
    }
}
```

### Client-Side Integration (Flutter)

#### WebSocket Service

```dart
// services/websocket_backend_service.dart
class CareConnectWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect() async {
    try {
      final wsUrl = _getWebSocketUrl();
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _streamSubscription = _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _messageController.add(data);
          _handleMessage(data);
        },
        onError: (error) => _handleError(error),
        onDone: () => _handleDisconnection(),
      );

      // Authenticate after connection
      await _authenticate();

    } catch (e) {
      throw WebSocketException('Connection failed: $e');
    }
  }

  Future<void> _authenticate() async {
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();

    final authMessage = {
      'type': 'authenticate',
      'token': token,
      'userId': userId,
    };

    _channel?.sink.add(jsonEncode(authMessage));
  }

  void sendMoodPainLog(int mood, int pain, String notes) {
    final message = {
      'type': 'mood-pain-log-update',
      'mood': mood,
      'pain': pain,
      'notes': notes,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _channel?.sink.add(jsonEncode(message));
  }

  void _handleMessage(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'authentication-success':
        _onAuthenticationSuccess(data);
        break;
      case 'incoming-call':
        _showIncomingCallDialog(data);
        break;
      case 'medication-reminder':
        _showMedicationReminder(data);
        break;
      case 'emergency-alert':
        _showEmergencyAlert(data);
        break;
      case 'ai-chat-notification':
        _handleAIChatResponse(data);
        break;
    }
  }
}
```

### AWS Integration

#### AWS WebSocket Service

```java
// service/AwsWebSocketService.java
@Service
@ConditionalOnProperty(name = "careconnect.websocket.mode", havingValue = "aws")
public class AwsWebSocketService {

    @Value("${careconnect.websocket.aws.api-gateway-endpoint}")
    private String apiGatewayEndpoint;

    private final AmazonApiGatewayManagementApiClientBuilder clientBuilder;

    public void sendMessageToConnection(String connectionId, Object message) {
        try {
            AmazonApiGatewayManagementApi client = clientBuilder
                .withEndpointConfiguration(new EndpointConfiguration(apiGatewayEndpoint, "us-east-1"))
                .build();

            PostToConnectionRequest request = new PostToConnectionRequest()
                .withConnectionId(connectionId)
                .withData(ByteBuffer.wrap(objectMapper.writeValueAsBytes(message)));

            client.postToConnection(request);
        } catch (Exception e) {
            log.error("Failed to send message to AWS WebSocket connection {}", connectionId, e);
        }
    }

    public void broadcastToAllConnections(Object message) {
        List<WebSocketConnection> activeConnections = connectionRepository.findActiveAWSConnections();

        activeConnections.parallelStream().forEach(conn ->
            sendMessageToConnection(conn.getConnectionId(), message)
        );
    }
}
```

### Healthcare-Specific Message Types

The system supports specialized healthcare message types:

```java
// Healthcare-specific WebSocket messages
public enum HealthcareMessageType {
    AI_CHAT_NOTIFICATION,           // AI assistant responses
    MOOD_PAIN_LOG_UPDATE,          // Patient mood/pain tracking
    MEDICATION_REMINDER,           // Medication schedules
    VITAL_SIGNS_ALERT,            // Critical health alerts
    EMERGENCY_ALERT,              // Emergency SOS calls
    FAMILY_MEMBER_REQUEST,        // Family connection requests
    APPOINTMENT_REMINDER,         // Healthcare appointments
    FALL_DETECTION_ALERT,         // Fall detection from IoT devices
    MEDICATION_ADHERENCE_UPDATE,  // Medication compliance tracking
    HEALTH_GOAL_PROGRESS,         // Patient health goal updates
}
```

This comprehensive WebSocket implementation provides real-time communication capabilities specifically tailored for healthcare applications, with robust security, scalable architecture, and seamless integration between development and production environments.

## AI Integration

CareConnect integrates advanced AI capabilities using **DeepSeek** as the primary AI provider through **LangChain4j** and **Spring AI** frameworks. The system provides healthcare-focused AI chat assistance, document processing, and medical data analysis.

### Architecture Overview

The AI integration follows a dual-framework approach:
- **LangChain4j**: Primary AI framework for chat functionality and memory management
- **Spring AI**: Structured data extraction and document processing
- **DeepSeek**: Cost-effective AI provider with OpenAI-compatible API
- **Security Layer**: Comprehensive input/output sanitization and governance controls

### AI Configuration

#### Main Configuration Class

```java
// config/AIChatServiceConfig.java
@Configuration
@ConditionalOnProperty(name = "careconnect.deepseek.enabled", havingValue = "true", matchIfMissing = true)
public class AIChatServiceConfig {

    @Value("${deepseek.api.key}")
    private String deepSeekApiKey;

    @Value("${deepseek.api.url:https://api.deepseek.com/v1}")
    private String deepSeekApiUrl;

    @Bean
    public ChatModel chatModel() {
        return OpenAiChatModel.builder()
            .apiKey(deepSeekApiKey)
            .baseUrl(deepSeekApiUrl)
            .modelName("deepseek-chat")
            .temperature(0.7)
            .maxTokens(2048)
            .build();
    }

    @Bean
    public SpringAIChatModel springAIChatModel() {
        return new OpenAiChatModel(
            OpenAiApi.builder()
                .apiKey(deepSeekApiKey)
                .baseUrl(deepSeekApiUrl)
                .build()
        );
    }
}
```

#### Configuration Properties

```properties
# AI Service Configuration
ai.model.provider=deepseek
deepseek.api.key=${DEEPSEEK_API_KEY:your-api-key}
deepseek.api.url=https://api.deepseek.com/v1
careconnect.deepseek.enabled=true

# Spring AI Configuration
spring.ai.openai.api-key=${DEEPSEEK_API_KEY}
spring.ai.openai.base-url=https://api.deepseek.com
spring.ai.openai.chat.options.model=deepseek-chat
spring.ai.openai.chat.options.temperature=0.7
spring.ai.openai.chat.options.max-tokens=2048
```

### Core AI Services

#### DefaultAIChatService - Main Chat Implementation

```java
// service/DefaultAIChatService.java
@Service
@ConditionalOnProperty(name = "careconnect.deepseek.enabled", havingValue = "true", matchIfMissing = true)
public class DefaultAIChatService implements AIChatService {

    private final ChatModel chatModel;
    private final ChatMemoryFactory chatMemoryFactory;
    private final InputSanitizationService inputSanitizationService;
    private final ResponseSanitizationService responseSanitizationService;
    private final LangChainGovernanceService governanceService;

    public AiChatResponse sendMessage(Long userId, String message, Long patientId) {
        // Governance checks
        governanceService.checkRateLimit(userId);
        governanceService.validateMessageLength(message);

        // Sanitize input
        String sanitizedMessage = inputSanitizationService.sanitize(message);

        // Build context with medical data
        String medicalContext = buildMedicalContext(patientId);

        // Create AI chain with memory
        ConversationalRetrievalChain chain = ConversationalRetrievalChain.builder()
            .chatModel(chatModel)
            .chatMemory(chatMemoryFactory.createMemory(userId))
            .systemPrompt(buildSystemPrompt(medicalContext))
            .build();

        // Generate response
        String aiResponse = chain.execute(sanitizedMessage);

        // Sanitize response
        String sanitizedResponse = responseSanitizationService.sanitize(aiResponse);

        // Save conversation
        return saveChatMessage(userId, patientId, sanitizedMessage, sanitizedResponse);
    }

    private String buildMedicalContext(Long patientId) {
        PatientMedicalData medicalData = medicalDataService.getPatientData(patientId);

        StringBuilder context = new StringBuilder();
        context.append("Patient Medical Context:\n");

        if (medicalData.hasVitals()) {
            context.append("Recent Vitals: ").append(medicalData.getVitalsSummary()).append("\n");
        }

        if (medicalData.hasMedications()) {
            context.append("Current Medications: ").append(medicalData.getMedicationsList()).append("\n");
        }

        if (medicalData.hasAllergies()) {
            context.append("Known Allergies: ").append(medicalData.getAllergiesList()).append("\n");
        }

        return context.toString();
    }

    private String buildSystemPrompt(String medicalContext) {
        return """
            You are a healthcare assistant for CareConnect. Guidelines:
            1. Provide information and support, never diagnose or prescribe
            2. Encourage users to consult healthcare professionals for medical decisions
            3. Use the provided medical context to give relevant, personalized responses
            4. Be empathetic, professional, and clear
            5. If unsure about medical information, recommend consulting a doctor

            %s
            """.formatted(medicalContext);
    }
}
```

#### LlmExtractionService - Document Processing

```java
// service/invoice/LlmExtractionService.java
@Service
@ConditionalOnProperty(name = "careconnect.deepseek.enabled", havingValue = "true", matchIfMissing = true)
public class LlmExtractionService {

    private final ChatModel chatModel; // Spring AI ChatModel

    public InvoiceData extractInvoiceData(String rawInvoiceText) {
        String extractionPrompt = """
            Extract structured data from this healthcare invoice. Return JSON with:
            - provider: {name, address, phone, email, taxId}
            - patient: {name, address, phone, email, dateOfBirth, patientId}
            - services: [{code, description, quantity, unitPrice, totalPrice, date}]
            - payments: [{method, amount, date, confirmationNumber}]
            - totals: {subtotal, tax, discount, totalAmount, amountDue}
            - dates: {serviceDate, dueDate, issueDate}
            - aiSummary: Brief summary of the invoice
            - recommendedActions: Array of patient action recommendations

            Invoice text:
            %s
            """.formatted(rawInvoiceText);

        ChatResponse response = chatModel.call(new Prompt(extractionPrompt));
        String jsonResponse = response.getResult().getOutput().getContent();

        try {
            return objectMapper.readValue(jsonResponse, InvoiceData.class);
        } catch (JsonProcessingException e) {
            throw new AIProcessingException("Failed to parse AI response: " + e.getMessage());
        }
    }

    public String generateInvoiceSummary(InvoiceData invoiceData) {
        String summaryPrompt = """
            Create a patient-friendly summary of this healthcare invoice:

            Provider: %s
            Services: %s
            Total Amount: $%.2f
            Due Date: %s

            Include:
            1. What services were provided
            2. Payment amount and due date
            3. Any action items for the patient
            4. Payment options if applicable
            """.formatted(
                invoiceData.getProvider().getName(),
                invoiceData.getServicesDescription(),
                invoiceData.getTotals().getTotalAmount(),
                invoiceData.getDates().getDueDate()
            );

        ChatResponse response = chatModel.call(new Prompt(summaryPrompt));
        return response.getResult().getOutput().getContent();
    }
}
```

### Chat Memory Management

#### ChatMemoryFactory

```java
// service/memory/ChatMemoryFactory.java
@Service
public class ChatMemoryFactory {

    @Value("${ai.chat.memory.timeout:900}") // 15 minutes
    private long memoryTimeoutSeconds;

    @Value("${ai.chat.memory.max-messages:15}")
    private int maxMessages;

    public ChatMemory createMemory(Long userId) {
        return MessageWindowChatMemory.builder()
            .id(userId)
            .maxMessages(maxMessages)
            .chatMemoryStore(createMemoryStore(userId))
            .build();
    }

    private ChatMemoryStore createMemoryStore(Long userId) {
        return new DatabaseChatMemoryStore(userId, memoryTimeoutSeconds);
    }
}

// Custom database-backed memory store
public class DatabaseChatMemoryStore implements ChatMemoryStore {

    private final ChatMessageRepository chatMessageRepository;
    private final Long userId;
    private final long timeoutSeconds;

    @Override
    public List<ChatMessage> getMessages(Object memoryId) {
        LocalDateTime cutoff = LocalDateTime.now().minusSeconds(timeoutSeconds);

        return chatMessageRepository
            .findByUserIdAndCreatedAtAfterOrderByCreatedAt(userId, cutoff)
            .stream()
            .map(this::convertToLangChainMessage)
            .collect(Collectors.toList());
    }

    @Override
    public void updateMessages(Object memoryId, List<ChatMessage> messages) {
        // Save new messages to database
        messages.forEach(message -> {
            if (!messageExists(message)) {
                saveChatMessage(message);
            }
        });
    }
}
```

### Security and Governance

#### LangChainGovernanceService

```java
// service/LangChainGovernanceService.java
@Service
public class LangChainGovernanceService {

    private static final int MAX_REQUESTS_PER_MINUTE = 10;
    private static final int MAX_REQUESTS_PER_HOUR = 60;
    private static final int MAX_MESSAGE_LENGTH = 4000;

    private final RedisTemplate<String, Object> redisTemplate;

    public void checkRateLimit(Long userId) {
        String minuteKey = "rate_limit:user:" + userId + ":minute:" +
                          (System.currentTimeMillis() / 60000);
        String hourKey = "rate_limit:user:" + userId + ":hour:" +
                        (System.currentTimeMillis() / 3600000);

        Long minuteCount = redisTemplate.opsForValue().increment(minuteKey);
        if (minuteCount == 1) {
            redisTemplate.expire(minuteKey, Duration.ofMinutes(1));
        }

        Long hourCount = redisTemplate.opsForValue().increment(hourKey);
        if (hourCount == 1) {
            redisTemplate.expire(hourKey, Duration.ofHours(1));
        }

        if (minuteCount > MAX_REQUESTS_PER_MINUTE) {
            throw new RateLimitExceededException("Too many requests per minute");
        }

        if (hourCount > MAX_REQUESTS_PER_HOUR) {
            throw new RateLimitExceededException("Too many requests per hour");
        }
    }

    public void validateMessageLength(String message) {
        if (message.length() > MAX_MESSAGE_LENGTH) {
            throw new MessageTooLongException(
                "Message exceeds maximum length of " + MAX_MESSAGE_LENGTH + " characters"
            );
        }
    }

    public void auditAIInteraction(Long userId, String input, String output,
                                  String model, Long tokens) {
        AiInteractionAudit audit = AiInteractionAudit.builder()
            .userId(userId)
            .input(input)
            .output(output)
            .model(model)
            .tokensUsed(tokens)
            .timestamp(LocalDateTime.now())
            .build();

        auditRepository.save(audit);
    }
}
```

#### Input/Output Sanitization

```java
// service/InputSanitizationService.java
@Service
public class InputSanitizationService {

    private static final List<String> BLOCKED_PATTERNS = List.of(
        "(?i).*diagnose.*",
        "(?i).*prescribe.*medication.*",
        "(?i).*medical advice.*",
        "(?i).*ignore.*previous.*instructions.*"
    );

    public String sanitize(String input) {
        // Remove potentially harmful patterns
        String sanitized = input;

        for (String pattern : BLOCKED_PATTERNS) {
            sanitized = sanitized.replaceAll(pattern, "[FILTERED]");
        }

        // Limit length
        if (sanitized.length() > 4000) {
            sanitized = sanitized.substring(0, 4000) + "...";
        }

        // Basic XSS protection
        sanitized = StringEscapeUtils.escapeHtml4(sanitized);

        return sanitized;
    }
}

// service/ResponseSanitizationService.java
@Service
public class ResponseSanitizationService {

    private static final List<String> MEDICAL_DISCLAIMERS = List.of(
        "Please consult with your healthcare provider",
        "This is not medical advice",
        "Always verify with a medical professional"
    );

    public String sanitize(String aiResponse) {
        // Add medical disclaimers if response contains medical terms
        if (containsMedicalTerms(aiResponse)) {
            aiResponse += "\n\n⚠️ " + getRandomDisclaimer();
        }

        // Remove any potential harmful content
        aiResponse = removePotentiallyHarmfulContent(aiResponse);

        return aiResponse;
    }

    private boolean containsMedicalTerms(String response) {
        return response.toLowerCase().matches(
            ".*(symptom|treatment|medication|diagnosis|dosage|prescription).*"
        );
    }
}
```

### User AI Configuration

#### UserAIConfig Entity

```java
// model/UserAIConfig.java
@Entity
@Table(name = "user_ai_config")
public class UserAIConfig {

    @Id
    private Long userId;

    @Column(name = "ai_provider")
    @Enumerated(EnumType.STRING)
    private AIProvider aiProvider = AIProvider.DEEPSEEK;

    @Column(name = "model_name")
    private String modelName = "deepseek-chat";

    @Column(name = "include_vitals")
    private Boolean includeVitals = true;

    @Column(name = "include_medications")
    private Boolean includeMedications = true;

    @Column(name = "include_notes")
    private Boolean includeNotes = false;

    @Column(name = "include_allergies")
    private Boolean includeAllergies = true;

    @Column(name = "max_tokens")
    private Integer maxTokens = 2048;

    @Column(name = "temperature")
    private Double temperature = 0.7;

    @Column(name = "conversation_history_limit")
    private Integer conversationHistoryLimit = 10;

    @Column(name = "custom_system_prompt")
    private String customSystemPrompt;

    // Default configurations for different user types
    public static UserAIConfig defaultPatientConfig(Long userId) {
        UserAIConfig config = new UserAIConfig();
        config.setUserId(userId);
        config.setCustomSystemPrompt(DEFAULT_PATIENT_PROMPT);
        return config;
    }

    public static UserAIConfig defaultCaregiverConfig(Long userId) {
        UserAIConfig config = new UserAIConfig();
        config.setUserId(userId);
        config.setIncludeNotes(true);
        config.setConversationHistoryLimit(20);
        config.setCustomSystemPrompt(DEFAULT_CAREGIVER_PROMPT);
        return config;
    }

    private static final String DEFAULT_PATIENT_PROMPT = """
        You are a helpful healthcare assistant. Provide information and support
        while encouraging consultation with healthcare professionals for medical decisions.
        Be empathetic, clear, and never provide diagnostic or prescriptive advice.
        """;

    private static final String DEFAULT_CAREGIVER_PROMPT = """
        You are an AI assistant for healthcare professionals. Provide clinical
        insights and information while emphasizing professional judgment.
        Include relevant patient data context in your responses.
        """;
}
```

### API Endpoints

#### AIChatController

```java
// controller/AIChatController.java
@RestController
@RequestMapping("/v1/api/ai-chat")
@PreAuthorize("hasRole('PATIENT') or hasRole('CAREGIVER')")
public class AIChatController {

    private final AIChatService aiChatService;
    private final UserAIConfigService configService;

    @PostMapping("/chat")
    @Operation(summary = "Send message to AI assistant")
    public ResponseEntity<AiChatResponse> sendMessage(
            @Valid @RequestBody AiChatRequest request,
            Authentication authentication) {

        Long userId = getUserId(authentication);
        AiChatResponse response = aiChatService.sendMessage(
            userId, request.getMessage(), request.getPatientId());

        return ResponseEntity.ok(response);
    }

    @GetMapping("/conversations/{patientId}")
    @Operation(summary = "Get patient conversations")
    public ResponseEntity<List<ChatConversationResponse>> getConversations(
            @PathVariable Long patientId,
            Authentication authentication) {

        Long userId = getUserId(authentication);
        // Verify access to patient data
        patientAccessService.verifyAccess(userId, patientId);

        List<ChatConversationResponse> conversations =
            aiChatService.getConversations(patientId);

        return ResponseEntity.ok(conversations);
    }

    @GetMapping("/config")
    @Operation(summary = "Get AI configuration")
    public ResponseEntity<UserAIConfig> getConfig(Authentication authentication) {
        Long userId = getUserId(authentication);
        UserAIConfig config = configService.getUserConfig(userId);
        return ResponseEntity.ok(config);
    }

    @PostMapping("/config")
    @Operation(summary = "Update AI configuration")
    public ResponseEntity<UserAIConfig> updateConfig(
            @Valid @RequestBody UserAIConfig config,
            Authentication authentication) {

        Long userId = getUserId(authentication);
        config.setUserId(userId);
        UserAIConfig savedConfig = configService.saveConfig(config);

        return ResponseEntity.ok(savedConfig);
    }
}
```

### Database Schema

#### AI-Related Tables

```sql
-- User AI Configuration
CREATE TABLE user_ai_config (
    user_id BIGINT PRIMARY KEY,
    ai_provider VARCHAR(50) DEFAULT 'DEEPSEEK',
    model_name VARCHAR(100) DEFAULT 'deepseek-chat',
    include_vitals BOOLEAN DEFAULT TRUE,
    include_medications BOOLEAN DEFAULT TRUE,
    include_notes BOOLEAN DEFAULT FALSE,
    include_allergies BOOLEAN DEFAULT TRUE,
    max_tokens INTEGER DEFAULT 2048,
    temperature DECIMAL(3,2) DEFAULT 0.70,
    conversation_history_limit INTEGER DEFAULT 10,
    custom_system_prompt TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Chat Conversations
CREATE TABLE chat_conversations (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    patient_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    title VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Chat Messages
CREATE TABLE chat_messages (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    conversation_id BIGINT NOT NULL,
    message_type ENUM('USER', 'AI') NOT NULL,
    content TEXT NOT NULL,
    tokens_used INTEGER,
    model_used VARCHAR(100),
    processing_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE
);

-- AI Interaction Audit
CREATE TABLE ai_interaction_audit (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    input_text TEXT,
    output_text TEXT,
    model_used VARCHAR(100),
    tokens_used INTEGER,
    processing_time_ms INTEGER,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX idx_chat_conversations_patient_user ON chat_conversations(patient_id, user_id);
CREATE INDEX idx_chat_messages_conversation_created ON chat_messages(conversation_id, created_at);
CREATE INDEX idx_ai_audit_user_timestamp ON ai_interaction_audit(user_id, timestamp);
```

### Development and Testing

#### Mock AI Service for Development

```java
// service/MockAIChatService.java
@Service
@Profile("dev")
@ConditionalOnProperty(name = "careconnect.deepseek.enabled", havingValue = "false")
public class MockAIChatService implements AIChatService {

    @Override
    public AiChatResponse sendMessage(Long userId, String message, Long patientId) {
        // Simulate processing time
        try {
            Thread.sleep(1000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        String mockResponse = generateMockResponse(message);

        return AiChatResponse.builder()
            .response(mockResponse)
            .tokensUsed(calculateMockTokens(message, mockResponse))
            .model("mock-model")
            .processingTimeMs(1000L)
            .build();
    }

    private String generateMockResponse(String message) {
        if (message.toLowerCase().contains("pain")) {
            return "I understand you're experiencing pain. Please describe your pain level on a scale of 1-10 and consider speaking with your healthcare provider if it persists.";
        } else if (message.toLowerCase().contains("medication")) {
            return "For medication questions, please consult with your pharmacist or healthcare provider. They can provide the most accurate and safe guidance for your specific situation.";
        } else {
            return "Thank you for your message. I'm here to provide general health information and support. For specific medical advice, please consult with your healthcare provider.";
        }
    }
}
```

The CareConnect AI integration provides a comprehensive, healthcare-focused AI solution with robust security, flexible configuration, and production-ready features for both patient support and clinical assistance.

## Device Integration

### Wearable Device Integration

Current semester implementation centers on explicit source/metric scope definition and mapping to existing persisted entities.

- Frontend entrypoint: `frontend/lib/features/integrations/presentation/pages/wearables_screen.dart`
- Persisted wearable model: `backend/core/src/main/java/com/careconnect/model/WearableMetric.java`
- Manual vital sample model: `backend/core/src/main/java/com/careconnect/model/VitalSample.java`
- Wearable metric repository queries: `backend/core/src/main/java/com/careconnect/repository/WearableMetricRepository.java`

For the semester source-by-source matrix and placeholder policy, see:

- `docs/spring2026_guides/WEARABLE_METRICS_SOURCE_MATRIX.md`

## USPS Integration

CareConnect integrates with the USPS Informed Delivery service to help patients and caregivers track incoming mail and packages. This feature is particularly valuable for elderly patients who may miss important medical correspondence or medication deliveries.

### Architecture Overview

The USPS integration provides:
- **Mail Digest Retrieval**: Fetches daily mail summaries from USPS Informed Delivery
- **Multi-Provider Support**: Works with Gmail and Outlook for USPS email parsing
- **Caching Layer**: Reduces API calls with intelligent caching
- **Mock Fallback**: Provides test data when email integration is unavailable

**Note**: This integration currently requires Google OAuth authentication for Gmail access, which is still pending configuration.

### Backend Implementation

#### USPSDigestService - Core Service

```java
// service/USPSDigestService.java
@Service
@RequiredArgsConstructor
public class USPSDigestService {
    private final EmailCredentialRepo credRepo;
    private final USPSDigestCacheRepo cacheRepo;
    private final GmailClient gmailClient;
    private final OutlookClient outlookClient;
    private final GmailParser gmailParser;
    private final OutlookParser outlookParser;

    public Optional<USPSDigest> latestForUser(String userId) {
        // 1. Check cache first (6-hour TTL)
        var cached = cacheRepo.findFirstByUserIdAndExpiresAtAfterOrderByDigestDateDesc(userId, Instant.now());
        if (cached.isPresent()) {
            try {
                return Optional.of(objectMapper.readValue(cached.get().getPayloadJson(), USPSDigest.class));
            } catch (Exception ignored) {}
        }

        // 2. Try Gmail integration
        var gmail = credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL);
        if (gmail.isPresent()) {
            var accessToken = decrypt(gmail.get().getAccessTokenEnc());
            var rawDigest = gmailClient.fetchLatestDigest(accessToken);
            if (rawDigest.isPresent()) {
                var digest = gmailParser.toDomain(rawDigest.get());
                cache(userId, digest);
                return Optional.of(digest);
            }
        }

        // 3. Try Outlook integration
        var outlook = credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.OUTLOOK);
        if (outlook.isPresent()) {
            var accessToken = decrypt(outlook.get().getAccessTokenEnc());
            var rawDigest = outlookClient.fetchLatestDigest(accessToken);
            if (rawDigest.isPresent()) {
                var digest = outlookParser.toDomain(rawDigest.get());
                cache(userId, digest);
                return Optional.of(digest);
            }
        }

        // 4. Mock fallback for testing and demonstration
        var mockDigest = mockDigest();
        cache(userId, mockDigest);
        return Optional.of(mockDigest);
    }

    private void cache(String userId, USPSDigest digest) {
        try {
            var cache = new USPSDigestCache();
            cache.setUserId(userId);
            cache.setDigestDate(digest.digestDate() != null ? digest.digestDate().toInstant() : Instant.now());
            cache.setPayloadJson(objectMapper.writeValueAsString(digest));
            cache.setExpiresAt(Instant.now().plus(Duration.ofHours(6))); // 6-hour cache
            cacheRepo.save(cache);
        } catch (Exception ignored) {
            // Cache failure should not affect main functionality
        }
    }

    private USPSDigest mockDigest() {
        var now = OffsetDateTime.now(ZoneOffset.UTC);
        var packageItem = new PackageItem(
            "9400100000000000000000",
            now.plusDays(1).toString(),
            ActionLinks.defaults("https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=9400100000000000000000")
        );
        var mailPiece = new MailPiece(
            "m-1",
            "ACME Bank",
            "Monthly statement",
            "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0nNDAnIGhlaWdodD0nMjAnIHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Zyc+PHJlY3Qgd2lkdGg9JzQwJyBoZWlnaHQ9JzIwJyBmaWxsPSIjZGRkIi8+PC9zdmc+",
            now.toString(),
            ActionLinks.defaults(null)
        );
        return new USPSDigest(now, List.of(mailPiece), List.of(packageItem));
    }
}
```

#### USPS REST Controller

```java
// controller/USPSController.java
@RestController
@RequestMapping("/v1/api/usps")
@RequiredArgsConstructor
public class USPSController {

    private final USPSDigestService service;

    @GetMapping("/mail")
    public ResponseEntity<USPSDigest> getDigest(@AuthenticationPrincipal Jwt jwt) {
        var userId = jwt != null ? jwt.getSubject() : "demo-user"; // Fallback for testing
        var digest = service.latestForUser(userId)
            .orElseGet(() -> new USPSDigest(null, List.of(), List.of()));
        return ResponseEntity.ok(digest);
    }
}
```

#### Data Models

```java
// model/USPSDigest.java
public record USPSDigest(
    OffsetDateTime digestDate,
    List<MailPiece> mailPieces,
    List<PackageItem> packages
) {}

// model/MailPiece.java
public record MailPiece(
    String id,
    String sender,
    String subject,
    String imageUrl,
    String deliveryDate,
    ActionLinks actionLinks
) {}

// model/PackageItem.java
public record PackageItem(
    String trackingNumber,
    String expectedDelivery,
    ActionLinks actionLinks
) {}

// model/ActionLinks.java
public record ActionLinks(
    String trackingUrl,
    String detailsUrl
) {
    public static ActionLinks defaults(String trackingUrl) {
        return new ActionLinks(trackingUrl, null);
    }
}
```

### Frontend Implementation

#### InformedDeliveryService - API Client

```dart
// services/informed_delivery_service.dart
class InformedDeliveryService {
  static Future<Map<String, dynamic>> fetchInformedDelivery() async {
    final headers = await AuthTokenManager.getAuthHeaders();

    final response = await http.get(
      Uri.parse('${ApiConstants.informedDelivery}/mail'),
      headers: headers,
    );

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception("Not authorized. Please log in again.");
    } else {
      throw Exception("Failed to fetch informed delivery data: ${response.statusCode}");
    }
  }
}

// API Constants
class ApiConstants {
  static final String _host = getBackendBaseUrl();
  static final String informedDelivery = '$_host/v1/api/usps';
}
```

#### Frontend Display Integration

```dart
// features/informed_delivery/informed_delivery_screen.dart
class InformedDeliveryScreen extends StatefulWidget {
  @override
  _InformedDeliveryScreenState createState() => _InformedDeliveryScreenState();
}

class _InformedDeliveryScreenState extends State<InformedDeliveryScreen> {
  Map<String, dynamic>? digestData;
  bool isLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadInformedDelivery();
  }

  Future<void> loadInformedDelivery() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final data = await InformedDeliveryService.fetchInformedDelivery();
      setState(() {
        digestData = data;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mail & Packages'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: isLoading
        ? Center(child: CircularProgressIndicator())
        : error != null
          ? Center(child: Text('Error: $error'))
          : buildDigestContent(),
    );
  }

  Widget buildDigestContent() {
    if (digestData == null) return Center(child: Text('No data available'));

    return RefreshIndicator(
      onRefresh: loadInformedDelivery,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildMailPiecesSection(),
              SizedBox(height: 20),
              buildPackagesSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildMailPiecesSection() {
    final mailPieces = digestData!['mailPieces'] as List<dynamic>? ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today\'s Mail', style: Theme.of(context).textTheme.headline6),
            SizedBox(height: 10),
            ...mailPieces.map((mail) => buildMailItem(mail)).toList(),
            if (mailPieces.isEmpty) Text('No mail expected today'),
          ],
        ),
      ),
    );
  }

  Widget buildPackagesSection() {
    final packages = digestData!['packages'] as List<dynamic>? ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Package Tracking', style: Theme.of(context).textTheme.headline6),
            SizedBox(height: 10),
            ...packages.map((pkg) => buildPackageItem(pkg)).toList(),
            if (packages.isEmpty) Text('No packages being tracked'),
          ],
        ),
      ),
    );
  }
}
```

### Database Schema

```sql
-- USPS Digest Cache Table
CREATE TABLE usps_digest_cache (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id VARCHAR(255) NOT NULL,
    digest_date TIMESTAMP NOT NULL,
    payload_json TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_user_expires (user_id, expires_at),
    INDEX idx_user_digest_date (user_id, digest_date DESC)
);

-- Email Credentials for OAuth Integration
CREATE TABLE email_credentials (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id VARCHAR(255) NOT NULL,
    provider ENUM('GMAIL', 'OUTLOOK') NOT NULL,
    access_token_enc TEXT NOT NULL,
    refresh_token_enc TEXT,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_user_provider (user_id, provider),
    INDEX idx_expires_at (expires_at)
);
```

### Configuration

#### Application Properties

```properties
# USPS Integration Settings
careconnect.usps.enabled=true
careconnect.usps.cache.ttl-hours=6
careconnect.usps.mock.enabled=${USPS_MOCK_MODE:true}

# Email Integration (Pending Google OAuth Setup)
careconnect.email.gmail.client-id=${GMAIL_CLIENT_ID:}
careconnect.email.gmail.client-secret=${GMAIL_CLIENT_SECRET:}
careconnect.email.outlook.client-id=${OUTLOOK_CLIENT_ID:}
careconnect.email.outlook.client-secret=${OUTLOOK_CLIENT_SECRET:}

# Encryption for stored credentials
careconnect.encryption.key=${ENCRYPTION_KEY:default-dev-key}
```

### Security Considerations

- **OAuth Integration**: Requires secure storage of email access tokens
- **Token Encryption**: Email credentials are encrypted at rest
- **Cache Security**: Digest data cached with user-specific keys
- **Rate Limiting**: Prevents excessive API calls to email providers

### Known Limitations

1. **Google OAuth Pending**: Gmail integration requires Google OAuth 2.0 setup
2. **Mock Data**: Currently uses mock data when email integration unavailable
3. **Email Parsing**: Depends on USPS email format consistency
4. **Cache Invalidation**: Manual refresh required for real-time updates

### Future Enhancements

- **Push Notifications**: Alert users of important mail/packages
- **OCR Integration**: Extract text from mail piece images
- **Smart Filtering**: Categorize mail by medical/financial importance
- **Medication Delivery Tracking**: Special handling for pharmacy deliveries

## Vial of Life Integration

CareConnect includes a comprehensive Vial of Life PDF generation system designed for emergency medical situations. The system creates professionally formatted emergency information documents that can be accessed by first responders via QR codes or emergency IDs.

### Architecture Overview

The Vial of Life integration provides:
- **Emergency PDF Generation**: Creates standardized emergency medical information forms
- **Patient Data Integration**: Automatically populates patient medical data
- **QR Code Access**: Public emergency access without authentication
- **Professional Formatting**: Medical-grade PDF layouts with clear typography
- **Emergency Contact Integration**: Includes family member and caregiver contacts

### Backend Implementation

#### VialOfLifePdfService - Core PDF Generation

```java
// service/VialOfLifePdfService.java
@Service
public class VialOfLifePdfService {

    private static final Logger logger = LoggerFactory.getLogger(VialOfLifePdfService.class);

    @Autowired
    private PatientService patientService;

    @Autowired
    private MedicationService medicationService;

    @Autowired
    private FamilyMemberService familyMemberService;

    /**
     * Generate a pre-filled Vial of Life PDF for a patient
     */
    public byte[] generateVialOfLifePdf(String emergencyId) throws Exception {
        logger.info("Generating Vial of Life PDF for emergency ID: {}", emergencyId);

        // Extract patient ID from emergency ID format: VIAL123456
        Long patientId = extractPatientIdFromEmergencyId(emergencyId);

        // Gather patient information
        Optional<PatientProfileDTO> patientProfile = patientService.getPatientProfile(patientId);
        if (patientProfile.isEmpty()) {
            throw new IllegalArgumentException("Patient not found for emergency ID: " + emergencyId);
        }

        // Get additional medical data
        List<MedicationDTO> medications = medicationService.getAllMedicationsForPatient(patientId);
        List<FamilyMemberLinkResponse> emergencyContacts = familyMemberService.getFamilyMembersByPatientId(patientId);

        return createProfessionalEmergencyPdf(patientProfile.get(), medications, emergencyContacts);
    }

    /**
     * Create professional emergency PDF document using Apache PDFBox
     */
    private byte[] createProfessionalEmergencyPdf(PatientProfileDTO patient,
                                                 List<MedicationDTO> medications,
                                                 List<FamilyMemberLinkResponse> emergencyContacts) throws IOException {

        ByteArrayOutputStream baos = new ByteArrayOutputStream();

        try (PDDocument document = new PDDocument()) {
            PDPage page = new PDPage();
            document.addPage(page);

            try (PDPageContentStream contentStream = new PDPageContentStream(document, page)) {
                float pageWidth = page.getMediaBox().getWidth();
                float pageHeight = page.getMediaBox().getHeight();
                float margin = 50;
                float yPosition = pageHeight - margin;

                // Draw medical cross header
                drawRedCrossHeader(contentStream, pageWidth, yPosition);
                yPosition -= 80;

                // Document title
                drawTitle(contentStream, pageWidth, yPosition);
                yPosition -= 50;

                // Patient Information Section
                yPosition = drawPatientInfoSection(contentStream, patient, margin, yPosition);
                yPosition -= 30;

                // Critical Medical Information Section
                yPosition = drawMedicalInfoSection(contentStream, patient, medications, margin, yPosition);
                yPosition -= 30;

                // Emergency Contacts Section
                yPosition = drawEmergencyContactsSection(contentStream, emergencyContacts, margin, yPosition);
                yPosition -= 40;

                // Professional footer
                drawFooter(contentStream, pageWidth, yPosition);
            }

            document.save(baos);
        }

        return baos.toByteArray();
    }

    /**
     * Draw red cross medical symbol header
     */
    private void drawRedCrossHeader(PDPageContentStream contentStream, float pageWidth, float yPosition) throws IOException {
        float crossSize = 40;
        float crossX = pageWidth / 2 - crossSize / 2;
        float crossY = yPosition - crossSize;

        // Draw red medical cross
        contentStream.setNonStrokingColor(Color.RED);
        contentStream.addRect(crossX - 5, crossY + crossSize/3, crossSize + 10, crossSize/3);
        contentStream.fill();
        contentStream.addRect(crossX + crossSize/3, crossY - 5, crossSize/3, crossSize + 10);
        contentStream.fill();
        contentStream.setNonStrokingColor(Color.BLACK);

        // Header text
        contentStream.beginText();
        contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD), 18);
        String headerText = "EMERGENCY MEDICAL INFORMATION";
        float textWidth = new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD).getStringWidth(headerText) / 1000 * 18;
        contentStream.newLineAtOffset((pageWidth - textWidth) / 2, crossY - 25);
        contentStream.showText(headerText);
        contentStream.endText();
    }

    /**
     * Draw patient information section with clean formatting
     */
    private float drawPatientInfoSection(PDPageContentStream contentStream, PatientProfileDTO patient, float margin, float yPosition) throws IOException {
        drawSectionTitle(contentStream, "PATIENT INFORMATION", margin, yPosition);
        yPosition -= 25;

        yPosition = drawInfoLine(contentStream, "Name:", patient.firstName() + " " + patient.lastName(), margin, yPosition);

        if (patient.dob() != null) {
            try {
                LocalDate dobDate = LocalDate.parse(patient.dob());
                int age = Period.between(dobDate, LocalDate.now()).getYears();
                yPosition = drawInfoLine(contentStream, "Date of Birth:", patient.dob() + " (Age: " + age + ")", margin, yPosition);
            } catch (Exception e) {
                yPosition = drawInfoLine(contentStream, "Date of Birth:", patient.dob(), margin, yPosition);
            }
        }

        if (patient.gender() != null) {
            yPosition = drawInfoLine(contentStream, "Gender:", patient.gender().toString(), margin, yPosition);
        }

        if (patient.phone() != null) {
            yPosition = drawInfoLine(contentStream, "Phone:", patient.phone(), margin, yPosition);
        }

        return yPosition;
    }

    /**
     * Draw critical medical information with highlighted allergies
     */
    private float drawMedicalInfoSection(PDPageContentStream contentStream, PatientProfileDTO patient, List<MedicationDTO> medications, float margin, float yPosition) throws IOException {
        drawSectionTitle(contentStream, "CRITICAL MEDICAL INFORMATION", margin, yPosition);
        yPosition -= 25;

        // Critical Allergies (highlighted in red)
        if (patient.allergies() != null && !patient.allergies().isEmpty()) {
            contentStream.beginText();
            contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD), 11);
            contentStream.setNonStrokingColor(Color.RED);
            contentStream.newLineAtOffset(margin, yPosition);
            contentStream.showText("CRITICAL ALLERGIES:");
            contentStream.endText();
            contentStream.setNonStrokingColor(Color.BLACK);
            yPosition -= 18;

            for (var allergy : patient.allergies()) {
                String allergyText = "• " + allergy.allergen();
                if (allergy.severity() != null) {
                    allergyText += " [" + allergy.severity().toString() + "]";
                }
                if (allergy.reaction() != null) {
                    allergyText += " - " + allergy.reaction();
                }
                yPosition = drawBulletPoint(contentStream, allergyText, margin + 10, yPosition);
            }
            yPosition -= 10;
        }

        // Current Active Medications
        if (medications != null && !medications.isEmpty()) {
            List<MedicationDTO> activeMeds = medications.stream()
                .filter(MedicationDTO::isActive)
                .toList();

            if (!activeMeds.isEmpty()) {
                yPosition = drawInfoLine(contentStream, "Current Medications:", "", margin, yPosition);
                yPosition -= 5;

                for (MedicationDTO med : activeMeds) {
                    String medText = "• " + med.medicationName();
                    if (med.dosage() != null) {
                        medText += " - " + med.dosage();
                    }
                    if (med.frequency() != null) {
                        medText += " (" + med.frequency() + ")";
                    }
                    yPosition = drawBulletPoint(contentStream, medText, margin + 10, yPosition);
                }
            }
        }

        return yPosition;
    }

    /**
     * Draw emergency contacts section
     */
    private float drawEmergencyContactsSection(PDPageContentStream contentStream, List<FamilyMemberLinkResponse> emergencyContacts, float margin, float yPosition) throws IOException {
        drawSectionTitle(contentStream, "EMERGENCY CONTACTS", margin, yPosition);
        yPosition -= 25;

        if (emergencyContacts != null && !emergencyContacts.isEmpty()) {
            for (FamilyMemberLinkResponse contact : emergencyContacts) {
                String contactText = contact.familyMemberName();
                if (contact.relationship() != null) {
                    contactText += " (" + contact.relationship() + ")";
                }
                yPosition = drawInfoLine(contentStream, "Contact:", contactText, margin, yPosition);

                if (contact.familyMemberEmail() != null) {
                    yPosition = drawInfoLine(contentStream, "Email:", contact.familyMemberEmail(), margin, yPosition);
                }
                yPosition -= 5;
            }
        } else {
            yPosition = drawInfoLine(contentStream, "", "No emergency contacts on file", margin, yPosition);
        }

        return yPosition;
    }

    /**
     * Draw professional footer with generation info
     */
    private void drawFooter(PDPageContentStream contentStream, float pageWidth, float yPosition) throws IOException {
        // Draw separator line
        contentStream.setStrokingColor(Color.GRAY);
        contentStream.moveTo(50, yPosition + 10);
        contentStream.lineTo(pageWidth - 50, yPosition + 10);
        contentStream.stroke();

        // Footer information
        contentStream.beginText();
        contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA), 9);
        contentStream.setNonStrokingColor(Color.GRAY);
        contentStream.newLineAtOffset(50, yPosition - 10);
        contentStream.showText("This document contains confidential medical information.");
        contentStream.endText();

        contentStream.beginText();
        contentStream.newLineAtOffset(50, yPosition - 25);
        contentStream.showText("Generated by CareConnect Emergency Information System - For medical emergencies, contact 911 immediately.");
        contentStream.endText();

        // Generation timestamp
        contentStream.beginText();
        contentStream.newLineAtOffset(pageWidth - 200, yPosition - 10);
        contentStream.showText("Generated: " + LocalDate.now().format(DateTimeFormatter.ofPattern("MM/dd/yyyy")));
        contentStream.endText();

        contentStream.setNonStrokingColor(Color.BLACK);
    }

    /**
     * Helper method to draw section titles with background
     */
    private void drawSectionTitle(PDPageContentStream contentStream, String title, float margin, float yPosition) throws IOException {
        // Background rectangle for section title
        contentStream.setNonStrokingColor(new Color(240, 240, 240));
        contentStream.addRect(margin - 5, yPosition - 15, 500, 20);
        contentStream.fill();

        // Title text
        contentStream.beginText();
        contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD), 12);
        contentStream.setNonStrokingColor(Color.BLACK);
        contentStream.newLineAtOffset(margin, yPosition - 12);
        contentStream.showText(title);
        contentStream.endText();
    }

    /**
     * Helper method for formatting information lines
     */
    private float drawInfoLine(PDPageContentStream contentStream, String label, String value, float margin, float yPosition) throws IOException {
        contentStream.beginText();
        contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD), 10);
        contentStream.newLineAtOffset(margin, yPosition);
        contentStream.showText(label);
        contentStream.endText();

        if (!value.isEmpty()) {
            contentStream.beginText();
            contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA), 10);
            contentStream.newLineAtOffset(margin + 100, yPosition);
            contentStream.showText(value);
            contentStream.endText();
        }

        return yPosition - 18;
    }

    /**
     * Helper method for bullet point formatting
     */
    private float drawBulletPoint(PDPageContentStream contentStream, String text, float margin, float yPosition) throws IOException {
        contentStream.beginText();
        contentStream.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA), 10);
        contentStream.newLineAtOffset(margin, yPosition);
        contentStream.showText(text);
        contentStream.endText();

        return yPosition - 15;
    }

    /**
     * Extract patient ID from emergency ID format: VIAL123456
     */
    private Long extractPatientIdFromEmergencyId(String emergencyId) {
        try {
            if (emergencyId.startsWith("VIAL")) {
                String idPart = emergencyId.substring(4);
                return Long.parseLong(idPart);
            }
        } catch (NumberFormatException e) {
            logger.error("Could not parse patient ID from emergency ID: {}", emergencyId);
        }

        throw new IllegalArgumentException("Invalid emergency ID format: " + emergencyId);
    }
}
```

#### Emergency Controller - Public Access

```java
// controller/EmergencyController.java
@RestController
@RequestMapping("/v1/api/emergency")
@Tag(name = "Emergency Information", description = "Emergency medical information and Vial of Life PDF generation")
public class EmergencyController {

    private static final Logger logger = LoggerFactory.getLogger(EmergencyController.class);

    @Autowired
    private VialOfLifePdfService vialOfLifePdfService;

    /**
     * Generate and serve Vial of Life PDF for emergency use (PUBLIC ACCESS)
     */
    @GetMapping("/{emergencyId}.pdf")
    @Operation(
        summary = "🚨 Get Emergency PDF",
        description = """
            Generate a pre-filled Vial of Life PDF document for emergency responders.

            This endpoint is designed to be accessed via QR codes in emergency situations.
            It returns an official Vial of Life form pre-populated with the patient's:
            - Basic information (name, DOB, blood type)
            - Critical allergies and medical conditions
            - Current medications
            - Emergency contact information

            **Security Note:** This endpoint uses emergency ID tokens for access control.
            """,
        tags = {"Emergency Information", "🚨 Emergency Response"}
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "PDF generated and returned successfully"),
        @ApiResponse(responseCode = "404", description = "Patient not found for emergency ID"),
        @ApiResponse(responseCode = "500", description = "Error generating PDF")
    })
    public ResponseEntity<byte[]> getEmergencyPdf(
            @Parameter(description = "Emergency ID (format: VIAL123456)", example = "VIAL123456")
            @PathVariable String emergencyId) {

        try {
            logger.info("🚨 Emergency PDF request for ID: {}", emergencyId);

            // Generate PDF
            byte[] pdfBytes = vialOfLifePdfService.generateVialOfLifePdf(emergencyId);

            // Set response headers for PDF
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_PDF);
            headers.setContentDisposition(ContentDisposition.inline()
                .filename("vial_of_life_" + emergencyId + ".pdf")
                .build());
            headers.setContentLength(pdfBytes.length);
            headers.setCacheControl("no-cache, no-store, must-revalidate");

            logger.info("✅ Emergency PDF generated successfully for: {}", emergencyId);
            return new ResponseEntity<>(pdfBytes, headers, HttpStatus.OK);

        } catch (IllegalArgumentException e) {
            logger.error("❌ Invalid emergency ID: {}", emergencyId);
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            logger.error("💥 Error generating emergency PDF for ID: {}", emergencyId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Force download version of emergency PDF
     */
    @GetMapping("/download/{emergencyId}.pdf")
    @Operation(summary = "Download Emergency PDF", description = "Force download of Vial of Life PDF")
    public ResponseEntity<byte[]> downloadEmergencyPdf(@PathVariable String emergencyId) {

        try {
            byte[] pdfBytes = vialOfLifePdfService.generateVialOfLifePdf(emergencyId);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
            headers.setContentDisposition(ContentDisposition.attachment()
                .filename("vial_of_life_" + emergencyId + ".pdf")
                .build());

            return new ResponseEntity<>(pdfBytes, headers, HttpStatus.OK);

        } catch (Exception e) {
            logger.error("Error generating downloadable emergency PDF", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
```

### Security Configuration

#### Public Emergency Access

```java
// Emergency endpoints are configured as permitAll() in SecurityConfig
.requestMatchers("/v1/api/emergency/**").permitAll()  // No authentication required

// JWT Authentication Filter excludes emergency endpoints
private static final List<String> EXCLUDED_PATHS = Arrays.asList(
    "/v1/api/emergency"  // Emergency PDF access (no auth required)
);
```

### Emergency ID Format

- **Format**: `VIAL{patientId}` (e.g., `VIAL123456`)
- **Usage**: Embedded in QR codes for first responder access
- **Security**: Emergency IDs are not sensitive but provide controlled access

### QR Code Integration

```java
// QR Code generation for emergency access
public String generateEmergencyQRCode(Long patientId) {
    String emergencyId = "VIAL" + patientId;
    String emergencyUrl = baseUrl + "/v1/api/emergency/" + emergencyId + ".pdf";

    // Generate QR code pointing to emergency PDF
    return qrCodeService.generateQRCode(emergencyUrl);
}
```

### PDF Features

#### Professional Medical Formatting
- **Red Cross Header**: Medical symbol for easy identification
- **Clear Typography**: High-contrast fonts for readability
- **Structured Sections**: Patient info, medical data, emergency contacts
- **Critical Allergies**: Highlighted in red for immediate attention
- **Generation Timestamp**: Shows when document was created

#### Information Included
- **Patient Demographics**: Name, DOB, age, gender, phone
- **Critical Medical Data**: Allergies with severity levels
- **Current Medications**: Active medications with dosage and frequency
- **Emergency Contacts**: Family members and caregivers with contact info
- **Legal Footer**: Confidentiality notice and system attribution

### Dependencies

#### Maven Dependencies
```xml
<!-- Apache PDFBox for PDF generation -->
<dependency>
    <groupId>org.apache.pdfbox</groupId>
    <artifactId>pdfbox</artifactId>
    <version>3.0.0</version>
</dependency>
```

### Configuration Properties

```properties
# Vial of Life Configuration
careconnect.vial.enabled=true
careconnect.vial.base-url=${BASE_URL:http://localhost:8080}

# PDF Generation Settings
careconnect.pdf.cache.enabled=false  # Always generate fresh for emergencies
careconnect.pdf.quality=high
```

### Error Handling

```java
// Comprehensive error handling for emergency situations
@ExceptionHandler(IllegalArgumentException.class)
public ResponseEntity<String> handleInvalidEmergencyId(IllegalArgumentException e) {
    logger.warn("Invalid emergency ID provided: {}", e.getMessage());
    return ResponseEntity.status(HttpStatus.NOT_FOUND)
        .body("Emergency information not found");
}

@ExceptionHandler(Exception.class)
public ResponseEntity<String> handlePdfGenerationError(Exception e) {
    logger.error("PDF generation failed", e);
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
        .body("Emergency PDF temporarily unavailable");
}
```

### Usage Example

#### Emergency Access URL
```
https://careconnect.example.com/v1/api/emergency/VIAL123456.pdf
```

#### QR Code Integration
First responders scan QR code → Instantly access patient's critical medical information → Make informed emergency decisions

### Future Enhancements

- **Multi-language Support**: Emergency PDFs in multiple languages
- **Photo Integration**: Include patient photo for identification
- **Medical Conditions**: Add chronic conditions and recent procedures
- **Insurance Information**: Include insurance details for billing
- **Advanced Care Directives**: Include DNR and other care preferences
- **Digital Signature**: Cryptographic verification of document authenticity

## File Upload & Management

### File Upload Service

```java
// service/FileUploadService.java
@Service
public class FileUploadService {

    @Value("${app.upload.dir}")
    private String uploadDir;

    private final UserFileRepository userFileRepository;

    public UserFileDTO uploadFile(MultipartFile file, Long userId, String category) {
        validateFile(file);

        String fileName = generateUniqueFileName(file.getOriginalFilename());
        String filePath = uploadDir + "/" + userId + "/" + category + "/" + fileName;

        try {
            // Create directory if not exists
            Files.createDirectories(Paths.get(filePath).getParent());

            // Save file
            Files.copy(file.getInputStream(), Paths.get(filePath));

            // Save metadata to database
            UserFile userFile = new UserFile();
            userFile.setUserId(userId);
            userFile.setFileName(file.getOriginalFilename());
            userFile.setFilePath(filePath);
            userFile.setFileSize(file.getSize());
            userFile.setContentType(file.getContentType());
            userFile.setCategory(category);

            userFile = userFileRepository.save(userFile);

            return convertToDTO(userFile);

        } catch (IOException e) {
            throw new FileStorageException("Could not store file " + fileName, e);
        }
    }

    private void validateFile(MultipartFile file) {
        if (file.isEmpty()) {
            throw new FileStorageException("Cannot store empty file");
        }

        // Check file size (10MB limit)
        if (file.getSize() > 10 * 1024 * 1024) {
            throw new FileStorageException("File size exceeds 10MB limit");
        }

        // Check file type
        String contentType = file.getContentType();
        if (!isAllowedContentType(contentType)) {
            throw new FileStorageException("File type not allowed: " + contentType);
        }
    }
}
```

### Frontend File Upload

```dart
// services/file_upload_service.dart
class FileUploadService {
  final ApiClient _apiClient;

  Future<UploadedFile> uploadFile(File file, String category) async {
    try {
      String fileName = path.basename(file.path);

      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
        'category': category,
      });

      final response = await _apiClient.post(
        '/api/files/upload',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
        ),
        onSendProgress: (sent, total) {
          // Update upload progress
          double progress = sent / total;
          _uploadProgressController.add(progress);
        },
      );

      return UploadedFile.fromJson(response.data);
    } catch (e) {
      throw FileUploadException('Upload failed: $e');
    }
  }

  Future<List<UploadedFile>> getUserFiles(String? category) async {
    try {
      final response = await _apiClient.get(
        '/api/files',
        queryParameters: category != null ? {'category': category} : null,
      );

      return (response.data as List)
          .map((json) => UploadedFile.fromJson(json))
          .toList();
    } catch (e) {
      throw FileUploadException('Failed to fetch files: $e');
    }
  }
}
```

## Testing Strategies

### Unit Testing (Flutter)

```dart
// test/services/health_service_test.dart
void main() {
  group('HealthService', () {
    late HealthService healthService;
    late MockApiClient mockApiClient;

    setUp(() {
      mockApiClient = MockApiClient();
      healthService = HealthService(mockApiClient);
    });

    test('should fetch vital signs successfully', () async {
      // Arrange
      final mockResponse = [
        {'id': '1', 'type': 'blood_pressure', 'value': 120.0, 'unit': 'mmHg'}
      ];
      when(mockApiClient.get('/api/health/vitals'))
          .thenAnswer((_) async => Response(data: mockResponse, statusCode: 200));

      // Act
      final result = await healthService.getVitalSigns();

      // Assert
      expect(result, isA<List<VitalSign>>());
      expect(result.length, equals(1));
      expect(result.first.type, equals('blood_pressure'));
    });

    test('should throw exception on network error', () async {
      // Arrange
      when(mockApiClient.get('/api/health/vitals'))
          .thenThrow(DioException(requestOptions: RequestOptions()));

      // Act & Assert
      expect(() => healthService.getVitalSigns(),
             throwsA(isA<HealthException>()));
    });
  });
}
```

### Integration Testing (Spring Boot)

```java
// test/integration/HealthControllerIntegrationTest.java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.ANY)
@Transactional
class HealthControllerIntegrationTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JwtUtil jwtUtil;

    private String jwtToken;
    private User testUser;

    @BeforeEach
    void setUp() {
        testUser = createTestUser();
        userRepository.save(testUser);
        jwtToken = jwtUtil.generateToken(new UserPrincipal(testUser));
    }

    @Test
    void shouldReturnVitalSignsForAuthenticatedUser() {
        // Arrange
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(jwtToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // Act
        ResponseEntity<List> response = restTemplate.exchange(
            "/api/health/vitals",
            HttpMethod.GET,
            entity,
            List.class
        );

        // Assert
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
    }

    @Test
    void shouldCreateVitalSignSuccessfully() {
        // Arrange
        VitalSignDTO vitalSign = VitalSignDTO.builder()
            .type("blood_pressure")
            .value(120.0)
            .unit("mmHg")
            .build();

        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(jwtToken);
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<VitalSignDTO> entity = new HttpEntity<>(vitalSign, headers);

        // Act
        ResponseEntity<VitalSignDTO> response = restTemplate.exchange(
            "/api/health/vitals",
            HttpMethod.POST,
            entity,
            VitalSignDTO.class
        );

        // Assert
        assertEquals(HttpStatus.CREATED, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("blood_pressure", response.getBody().getType());
    }
}
```

### End-to-End Testing

```dart
// integration_test/app_test.dart
void main() {
  group('CareConnect E2E Tests', () {
    testWidgets('complete user journey', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Login flow
      await tester.enterText(find.byKey(Key('email_field')), 'test@example.com');
      await tester.enterText(find.byKey(Key('password_field')), 'password123');
      await tester.tap(find.byKey(Key('login_button')));
      await tester.pumpAndSettle();

      // Verify dashboard is loaded
      expect(find.text('Dashboard'), findsOneWidget);

      // Navigate to health section
      await tester.tap(find.byKey(Key('health_tab')));
      await tester.pumpAndSettle();

      // Record vital sign
      await tester.tap(find.byKey(Key('add_vital_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(Key('vital_value')), '120');
      await tester.tap(find.byKey(Key('save_vital_button')));
      await tester.pumpAndSettle();

      // Verify vital sign was saved
      expect(find.text('120'), findsOneWidget);
    });
  });
}
```

## Performance Optimization

Performance is critical in healthcare applications where delays can affect patient care. CareConnect employs multiple optimization strategies across the frontend, backend, and database layers to ensure responsive user experiences even under heavy load. This section covers practical performance patterns we've implemented and why they matter.

### Frontend Optimization: Efficient Data Loading and Rendering

Flutter applications can handle thousands of list items efficiently if properly optimized. However, loading all data at once wastes memory and slows initial render time. CareConnect uses lazy loading (pagination) to load data incrementally as users scroll, providing instant initial load times while still allowing access to complete datasets.

#### Infinite Scroll Pattern with Pagination

The infinite scroll pattern loads a small initial dataset (e.g., 20 items) and fetches more as the user scrolls to the bottom. This provides:
- **Fast Initial Load**: Only 20 items loaded, so app feels instant
- **Memory Efficiency**: Old items can be garbage collected as list grows
- **Seamless UX**: No "load more" buttons, natural scrolling experience
- **Backend Efficiency**: Smaller queries, less database load

**Implementation with Detailed Explanation**:

```dart
// Lazy loading and performance optimizations
// This widget demonstrates infinite scroll for vital signs history
// Pattern is reusable for any large list (messages, medications, appointments)
class OptimizedListView extends StatefulWidget {
  @override
  _OptimizedListViewState createState() => _OptimizedListViewState();
}

class _OptimizedListViewState extends State<OptimizedListView> {
  // ScrollController: Detects when user has scrolled to bottom
  // We listen to this to know when to fetch more data
  final ScrollController _scrollController = ScrollController();
  
  // Local state: List of vitals loaded so far
  // Starts empty, grows as user scrolls
  final List<VitalSign> _vitalSigns = [];
  
  // Loading state: Prevents duplicate API calls while fetching
  // If true, we're already fetching next page, don't trigger another
  bool _isLoading = false;
  
  // Pagination state (not shown but assumed):
  // int _currentPage = 0;
  // bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
    // Load first page of data when widget initializes
    _loadInitialData();
    
    // Add scroll listener: Triggers when user scrolls
    // This is the heart of infinite scroll - detects when to load more
    _scrollController.addListener(_onScroll);
  }

  /// Scroll listener: Called every time user scrolls
  /// Checks if user has reached the bottom of the list
  void _onScroll() {
    // pixels: Current scroll position
    // maxScrollExtent: Maximum scroll position (bottom of list)
    // When these are equal, user has scrolled to the very bottom
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      // User reached bottom → fetch next page
      _loadMoreData();
    }
  }
  
  /// Load initial page of data (called once on widget creation)
  /// 
  /// This method would typically:
  /// 1. Set _isLoading = true
  /// 2. Call API: healthService.getVitalSigns(page: 0, pageSize: 20)
  /// 3. Add results to _vitalSigns list
  /// 4. Call setState() to trigger rebuild
  /// 5. Set _isLoading = false
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    try {
      // Fetch first 20 vitals from API
      final vitals = await _healthService.getVitalSigns(page: 0, pageSize: 20);
      
      setState(() {
        _vitalSigns.addAll(vitals);
        _isLoading = false;
      });
    } catch (e) {
      // Handle error (show snackbar, etc.)
      setState(() => _isLoading = false);
    }
  }
  
  /// Load next page of data (called when user scrolls to bottom)
  /// 
  /// Includes guard clause to prevent duplicate API calls:
  /// - If already loading, don't start another request
  /// - If no more data available, don't make unnecessary API call
  Future<void> _loadMoreData() async {
    // Guard: Don't start loading if already loading
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Fetch next page (page number tracks which page we're on)
      final vitals = await _healthService.getVitalSigns(
        page: _currentPage + 1, 
        pageSize: 20
      );
      
      setState(() {
        if (vitals.isEmpty) {
          // No more data from API, we've reached the end
          _hasMoreData = false;
        } else {
          // Add new vitals to existing list
          _vitalSigns.addAll(vitals);
          _currentPage++;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  void dispose() {
    // Clean up: Remove listener to prevent memory leaks
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ListView.builder: Only builds visible items (critical for performance)
    // If you have 10,000 items but only 10 fit on screen, only 10 widgets are built
    // As user scrolls, Flutter builds new items and disposes old ones
    return ListView.builder(
      controller: _scrollController,  // Attach our scroll listener
      
      // Item count: Number of vitals + 1 loading indicator (if loading)
      // Example: 20 vitals + 1 spinner = 21 total items
      itemCount: _vitalSigns.length + (_isLoading ? 1 : 0),
      
      // itemBuilder: Called for each visible item
      // Flutter only calls this for items that need to be displayed
      // index: Position in list (0 to itemCount - 1)
      itemBuilder: (context, index) {
        // Last item: Show loading spinner while fetching
        if (index == _vitalSigns.length) {
          return Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Regular item: Show vital sign data
        final vital = _vitalSigns[index];
        
        return ListTile(
          // key: Helps Flutter identify widgets across rebuilds
          // Without this, Flutter might rebuild the wrong items
          // ValueKey uses the unique ID to track each vital
          key: ValueKey(vital.id),
          
          title: Text(vital.type),  // "Blood Pressure"
          subtitle: Text('${vital.value} ${vital.unit}'),  // "120 mmHg"
          trailing: Text(
            // Format timestamp: "2 hours ago"
            _formatTimestamp(vital.timestamp),
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        );
      },
    );
  }
}
```

#### Why This Pattern Improves Performance

**Memory Efficiency**:
- Without pagination: Loading 10,000 vitals = ~10MB of RAM
- With pagination: Loading 20 vitals at a time = ~20KB of RAM
- Old items off-screen can be garbage collected

**Initial Load Speed**:
- Without pagination: Wait for all 10,000 vitals to load (10+ seconds)
- With pagination: Load 20 vitals instantly (<1 second)

**Network Efficiency**:
- Without pagination: 10,000 vitals in one giant JSON payload
- With pagination: Small, incremental requests that complete quickly

**User Experience**:
- Instant perceived performance (data appears immediately)
- Natural scrolling behavior (no pagination buttons to click)
- Works well even with slow network connections

#### Additional Flutter Performance Optimizations

**1. const Constructors for Immutable Widgets**:
```dart
// BAD: Widget rebuilds every time parent rebuilds
Widget build(BuildContext context) {
  return Text('Hello');
}

// GOOD: Widget is const, Flutter reuses existing instance
Widget build(BuildContext context) {
  return const Text('Hello');  // Marked as const
}
```
Using `const` tells Flutter "this widget never changes," allowing it to skip rebuilding entirely.

**2. RepaintBoundary for Complex Widgets**:
```dart
// Wrap expensive widgets in RepaintBoundary to isolate repaints
RepaintBoundary(
  child: ComplexChart(data: vitalSignsData),
)
```
This prevents the chart from being repainted when other parts of the screen change.

**3. AutomaticKeepAliveClientMixin for Tab Views**:
```dart
// Prevents tabs from rebuilding when switching between them
class HealthTab extends StatefulWidget {
  @override
  _HealthTabState createState() => _HealthTabState();
}

class _HealthTabState extends State<HealthTab> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;  // Keep this tab's state alive
  
  @override
  Widget build(BuildContext context) {
    super.build(context);  // Required by mixin
    return HealthContent();
  }
}
```

### Backend Optimization: Caching with Redis

Repeatedly querying the database for the same data wastes resources and slows response time. Redis is an in-memory cache that stores frequently accessed data, providing sub-millisecond response times. CareConnect uses Spring's caching abstraction with Redis to transparently cache expensive database queries.

#### How Caching Works in CareConnect

**The Flow Without Caching**:
1. Request arrives: "Get vitals for user 123"
2. Service queries database: SELECT * FROM vital_signs WHERE user_id = 123
3. Database processes query (~50ms)
4. Return results to client

**With Caching**:
1. First request: Query database, store result in Redis (cache miss)
2. Subsequent requests: Return from Redis (~1ms), skip database entirely (cache hit)
3. Cache expires after 10 minutes or when data changes

**Cache Hit Rate**: In production, vitals are read much more often than written. A good cache hit rate is 80%+, meaning 80% of requests never touch the database.

**Implementation with Detailed Explanation**:

```java
// Caching configuration
// @EnableCaching: Activates Spring's caching infrastructure
// This annotation scans for @Cacheable, @CacheEvict annotations
@Configuration
@EnableCaching
public class CacheConfig {

    /// Creates the cache manager that handles all caching operations
    /// Redis is chosen over simple in-memory cache because:
    /// - Shared across multiple backend instances (horizontal scaling)
    /// - Survives application restarts
    /// - Supports TTL (time-to-live) for automatic expiration
    @Bean
    public CacheManager cacheManager() {
        RedisCacheManager.Builder builder = RedisCacheManager
            .RedisCacheManagerBuilder
            // Connect to Redis instance (configured in application.properties)
            .fromConnectionFactory(redisConnectionFactory())
            // Set default cache configuration: 10 minute TTL
            .cacheDefaults(cacheConfiguration(Duration.ofMinutes(10)));

        return builder.build();
    }

    /// Configure how data is stored in Redis
    /// 
    /// Key decisions:
    /// - TTL (time-to-live): How long cached data remains valid
    /// - Serialization: How Java objects convert to/from Redis format
    /// - Null value caching: Should we cache NULL results?
    private RedisCacheConfiguration cacheConfiguration(Duration ttl) {
        return RedisCacheConfiguration.defaultCacheConfig()
            // entryTtl: Cache entries expire after this duration
            // After 10 minutes, entry is automatically removed
            // This ensures users see fresh data without explicit cache invalidation
            .entryTtl(ttl)
            
            // disableCachingNullValues: Don't cache NULL query results
            // Why? If user has no vitals, we don't want to cache that for 10 minutes
            // The next time they record a vital, query should reflect it immediately
            .disableCachingNullValues()
            
            // serializeKeysWith: How cache keys are stored
            // Keys are strings like "user_vitals::123"
            // StringRedisSerializer stores them as plain strings in Redis
            .serializeKeysWith(RedisSerializationContext.SerializationPair
                .fromSerializer(new StringRedisSerializer()))
                
            // serializeValuesWith: How cache values (the actual data) are stored
            // GenericJackson2JsonRedisSerializer converts Java objects to JSON
            // Stored as JSON in Redis, human-readable for debugging
            .serializeValuesWith(RedisSerializationContext.SerializationPair
                .fromSerializer(new GenericJackson2JsonRedisSerializer()));
    }
}

// Service with caching
// This service demonstrates Spring's declarative caching
// No manual cache management code needed - annotations handle everything
@Service
public class CachedHealthService {

    /// @Cacheable: Cache the result of this method
    /// 
    /// How it works:
    /// 1. Spring intercepts the method call
    /// 2. Checks if result exists in cache for this userId
    /// 3. If YES (cache hit): Return cached result, skip method execution
    /// 4. If NO (cache miss): Execute method, store result in cache, return it
    /// 
    /// Parameters:
    /// - value: Cache name ("user_vitals")
    /// - key: Cache key expression ("#userId" uses method parameter)
    ///   Full cache key: "user_vitals::123" for userId=123
    /// 
    /// Example flow:
    /// Request 1 (userId=123): Cache miss → Query DB → Store in cache → Return
    /// Request 2 (userId=123): Cache hit → Return from Redis (1ms)
    /// Request 3 (userId=456): Cache miss → Query DB → Store in cache → Return
    @Cacheable(value = "user_vitals", key = "#userId")
    public List<VitalSignDTO> getVitalSigns(Long userId) {
        // This code only executes on cache miss
        // On cache hit, Spring returns cached result without calling this method
        
        // Expensive database query (50ms+)
        return healthRepository.findByUserIdOrderByMeasurementTimeDesc(userId)
            .stream()
            .map(this::convertToDTO)  // Convert entities to DTOs
            .collect(Collectors.toList());
    }

    /// @CacheEvict: Remove cached data when it becomes stale
    /// 
    /// Why evict? When new vital is recorded, cached data is outdated
    /// We must remove the old cache so next getVitalSigns() fetches fresh data
    /// 
    /// Parameters:
    /// - value: Which cache to evict from ("user_vitals")
    /// - key: Which specific entry to evict ("#userId")
    /// 
    /// Example flow:
    /// 1. User 123's vitals are cached
    /// 2. User records new vital → this method called
    /// 3. Cache entry "user_vitals::123" removed from Redis
    /// 4. Next getVitalSigns(123) will be cache miss, fetching fresh data
    @CacheEvict(value = "user_vitals", key = "#userId")
    public VitalSignDTO recordVitalSign(Long userId, VitalSignDTO vitalSign) {
        // Cache is invalidated BEFORE this method executes
        // This ensures the cache doesn't contain stale data
        
        // Save the new vital sign to database
        return saveVitalSign(userId, vitalSign);
    }
}
```

#### Cache Performance Impact

**Metrics from production**:
- Database query time: 50-100ms
- Redis cache retrieval: 1-2ms
- **Speedup: 50-100x faster** for cached queries

**Cache hit rate**: ~85% for vital signs (frequently read, infrequently updated)

**Cost savings**: Reduced database load means smaller database instance needed

#### Caching Strategies in CareConnect

| Data Type | Cache Strategy | TTL | Rationale |
|-----------|---------------|-----|-----------|
| User vitals | Cache + evict on write | 10 min | Read-heavy, updated occasionally |
| User profile | Cache + evict on write | 30 min | Rarely changes |
| Medication list | Cache + evict on write | 5 min | Important to be up-to-date |
| Static data (lists of vital types) | Cache only | 24 hours | Never changes |
| Real-time data (WebSocket messages) | No cache | N/A | Must be real-time |



```dart
// Lazy loading and performance optimizations
class OptimizedListView extends StatefulWidget {
  @override
  _OptimizedListViewState createState() => _OptimizedListViewState();
}

class _OptimizedListViewState extends State<OptimizedListView> {
  final ScrollController _scrollController = ScrollController();
  final List<VitalSign> _vitalSigns = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      _loadMoreData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _vitalSigns.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _vitalSigns.length) {
          return CircularProgressIndicator();
        }

        return ListTile(
          key: ValueKey(_vitalSigns[index].id),
          title: Text(_vitalSigns[index].type),
          subtitle: Text('${_vitalSigns[index].value} ${_vitalSigns[index].unit}'),
        );
      },
    );
  }
}
```

### Backend Optimization

```java
// Caching configuration
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public CacheManager cacheManager() {
        RedisCacheManager.Builder builder = RedisCacheManager
            .RedisCacheManagerBuilder
            .fromConnectionFactory(redisConnectionFactory())
            .cacheDefaults(cacheConfiguration(Duration.ofMinutes(10)));

        return builder.build();
    }

    private RedisCacheConfiguration cacheConfiguration(Duration ttl) {
        return RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(ttl)
            .disableCachingNullValues()
            .serializeKeysWith(RedisSerializationContext.SerializationPair
                .fromSerializer(new StringRedisSerializer()))
            .serializeValuesWith(RedisSerializationContext.SerializationPair
                .fromSerializer(new GenericJackson2JsonRedisSerializer()));
    }
}

// Service with caching
@Service
public class CachedHealthService {

    @Cacheable(value = "user_vitals", key = "#userId")
    public List<VitalSignDTO> getVitalSigns(Long userId) {
        // Database query is cached
        return healthRepository.findByUserIdOrderByMeasurementTimeDesc(userId)
            .stream()
            .map(this::convertToDTO)
            .collect(Collectors.toList());
    }

    @CacheEvict(value = "user_vitals", key = "#userId")
    public VitalSignDTO recordVitalSign(Long userId, VitalSignDTO vitalSign) {
        // Cache is invalidated when new data is added
        return saveVitalSign(userId, vitalSign);
    }
}
```

### Database Optimization: Indexes and Partitioning

Database performance is critical in healthcare applications where queries must return results quickly even with millions of records. PostgreSQL provides powerful optimization features—indexes and partitioning—that dramatically improve query performance when used correctly. However, these features require understanding of how queries actually execute.

#### Understanding Database Indexes

An index is like a book's index: instead of reading every page to find "blood pressure," you check the index which tells you exactly which pages to read. Similarly, database indexes let PostgreSQL find rows without scanning the entire table.

**Without Index**: `SELECT * FROM vital_signs WHERE user_id = 123`
- PostgreSQL scans ALL rows (1 million+) to find user 123's vitals
- Takes seconds, gets slower as table grows

**With Index**: Same query with index on `user_id`
- PostgreSQL uses index to jump directly to user 123's rows
- Returns in milliseconds, performance stays constant even with growth

**The Trade-Off**:
- **Benefit**: Dramatically faster queries (100x+ improvement)
- **Cost**: Slower writes (every INSERT updates the index), more disk space

**Rule of Thumb**: Index columns used in WHERE clauses, JOIN conditions, and ORDER BY clauses of frequent queries.

#### Strategic Index Design for CareConnect

Our indexes are designed based on actual query patterns observed in the application. Each index targets specific, frequently-executed queries that were identified through performance profiling:

```sql
-- Optimized indexes for common queries

-- Index 1: Composite index for vital signs queries
-- Covers the most common query pattern: "Get all vitals of a specific type for a user, ordered by time"
-- Example query: SELECT * FROM vital_signs 
--                WHERE user_id = 123 AND type = 'blood_pressure' 
--                ORDER BY measurement_time DESC
--
-- Why composite (user_id, type, measurement_time)?
-- - user_id first: Narrows down to one user's data (most selective)
-- - type second: Further filters to specific vital type
-- - measurement_time DESC: Ordering by index column is free (no separate sort step)
--
-- Query execution with this index:
-- 1. Jump to user_id = 123 section of index
-- 2. Filter to type = 'blood_pressure' rows
-- 3. Results already sorted by measurement_time DESC (no extra sort!)
-- Query time: <1ms even with millions of vitals
--
-- Without this index:
-- 1. Sequential scan of entire table (millions of rows)
-- 2. Filter by user_id and type
-- 3. Sort results by measurement_time (expensive!)
-- Query time: 500ms+
CREATE INDEX idx_vital_signs_user_type_time ON vital_signs(user_id, type, measurement_time DESC);

-- Index 2: Users by role and active status
-- Covers admin queries: "Find all active caregivers" or "Find all active patients"
-- Example query: SELECT * FROM users WHERE role = 'CAREGIVER' AND active = true
--
-- Why needed?
-- - Admin dashboard shows user lists filtered by role and status
-- - Login system checks if user exists and is active
-- - Notification system finds all active caregivers for a patient
--
-- Column order matters:
-- - (role, active) is correct: role has higher cardinality (4-5 distinct values)
-- - (active, role) would be wrong: active is boolean (only 2 values, low selectivity)
--
-- Performance impact:
-- - With index: Find all active caregivers in 1ms
-- - Without index: Scan all users (could be 100,000+), takes 100ms+
CREATE INDEX idx_users_role_active ON users(role, active);

-- Index 3: Messages by conversation, ordered by time
-- Covers messaging queries: "Load recent messages for a conversation"
-- Example query: SELECT * FROM messages 
--                WHERE conversation_id = 456 
--                ORDER BY sent_at DESC 
--                LIMIT 50
--
-- Why DESC in index?
-- - We always want newest messages first (DESC order)
-- - Index stores data pre-sorted in DESC order
-- - PostgreSQL can read index forward without additional sorting
--
-- Real-world impact:
-- - Healthcare conversations can have 1000+ messages
-- - Loading latest 50 messages is near-instant with this index
-- - Without index: Load all 1000+ messages, sort them, take top 50 (wasteful!)
CREATE INDEX idx_messages_conversation_time ON messages(conversation_id, sent_at DESC);
```

#### Index Design Principles Applied

**1. Composite Index Column Order**:
```sql
-- GOOD: More selective column first
CREATE INDEX idx_user_email ON users(email, active);
-- email is unique (high selectivity)
-- active is boolean (low selectivity)

-- BAD: Less selective column first
CREATE INDEX idx_active_email ON users(active, email);
-- active only has 2 values, not selective
```

**2. Covering Indexes** (includes all columns needed by query):
```sql
-- Query: SELECT type, value, unit FROM vital_signs WHERE user_id = 123
-- Index covers user_id (WHERE), type, value, unit (SELECT)
CREATE INDEX idx_vitals_covering ON vital_signs(user_id, type, value, unit);
-- PostgreSQL can answer query entirely from index (index-only scan)
-- Never needs to access table data at all!
```

**3. Partial Indexes** (indexes only relevant rows):
```sql
-- We only care about active users in most queries
-- No point indexing inactive users (saves 20% space)
CREATE INDEX idx_active_users ON users(role) WHERE active = true;
-- Smaller index → fits in RAM → faster queries
```

#### Table Partitioning for Large Datasets

As vital signs accumulate (millions per year), a single table becomes unwieldy. PostgreSQL's partitioning feature splits a large table into smaller, manageable pieces based on a column value (like year). Queries that filter by the partition key only scan the relevant partition, dramatically improving performance.

**How Partitioning Works**:
- Main table (`vital_signs`) is a "parent" that defines structure
- Partition tables (p2023, p2024, etc.) are "children" that hold actual data
- PostgreSQL automatically routes INSERTs to the correct partition
- Queries that filter by year only scan that year's partition

**Real-World Benefit**:
- Query: "Find vitals from 2024" (assuming 10 million vitals total)
- Without partitioning: Scan all 10 million vitals, filter by year
- With partitioning: Only scan p2024 partition (2 million vitals), skip other 8 million
- **5x faster**

**Partitioning Strategy for CareConnect**:

```sql
-- Partitioning for large tables
-- Partition by YEAR(measurement_time) because:
-- 1. Vitals accumulate over time (millions per year)
-- 2. Most queries filter by date range ("last 30 days", "this year")
-- 3. Old data (2-3 years old) rarely accessed → can be archived or moved to slower storage
ALTER TABLE vital_signs PARTITION BY RANGE (YEAR(measurement_time)) (
    -- Partition for 2023 data
    -- Holds all vitals where YEAR(measurement_time) < 2024
    PARTITION p2023 VALUES LESS THAN (2024),
    
    -- Partition for 2024 data
    -- Holds all vitals where YEAR(measurement_time) >= 2024 AND < 2025
    PARTITION p2024 VALUES LESS THAN (2025),
    
    -- Partition for 2025 data
    PARTITION p2025 VALUES LESS THAN (2026),
    
    -- Catch-all partition for future years
    -- PostgreSQL requires this to prevent "no partition found" errors
    -- Future years (2026+) go here until we create specific partitions
    PARTITION pmax VALUES LESS THAN MAXVALUE
);
```

#### Partition Maintenance Strategy

**Yearly Routine** (January each year):
```sql
-- Create next year's partition (e.g., in January 2026)
ALTER TABLE vital_signs ADD PARTITION p2026 VALUES LESS THAN (2027);

-- Archive old data (e.g., 2023 data is 3+ years old)
-- Option 1: Move to archive table (rarely queried, but kept for compliance)
CREATE TABLE vital_signs_archive PARTITION OF vital_signs FOR VALUES FROM (2020) TO (2024);

-- Option 2: Detach partition entirely (for backup or deletion)
ALTER TABLE vital_signs DETACH PARTITION p2023;
-- Now p2023 is a standalone table, can be backed up to S3 and dropped
```

**Benefits of This Approach**:
- **Performance**: Queries scan only relevant year's data
- **Maintenance**: Can VACUUM, REINDEX individual partitions without locking entire table
- **Archival**: Easy to move old data to cheaper storage (S3, tape backup)
- **Compliance**: HIPAA requires 7 years of data retention, partitioning makes this manageable

#### Monitoring Index Usage

Not all indexes are useful—unused indexes waste space and slow down writes. PostgreSQL tracks index usage statistics to identify unused indexes:

```sql
-- Find unused indexes (candidates for deletion)
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,  -- Number of times index was scanned (used)
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0  -- Never used
ORDER BY pg_relation_size(indexrelid) DESC;

-- Output example:
-- tablename | indexname | idx_scan | index_size
-- messages  | idx_msg_status | 0 | 120 MB
-- → This index takes 120MB but is never used, safe to drop
```

#### Index Best Practices for Healthcare Data

1. **Index Foreign Keys**: Always index columns used in JOINs (e.g., `user_id` in `vital_signs`)
2. **Index Date Ranges**: Healthcare queries often filter by date ("last 30 days"), index timestamp columns
3. **Avoid Over-Indexing**: Each index slows down INSERTs/UPDATEs, limit to truly necessary indexes
4. **Use Partial Indexes**: If 90% of queries filter by `active = true`, create partial index on active rows only
5. **Monitor Query Performance**: Use `EXPLAIN ANALYZE` to see if indexes are actually used

**Example of Query Analysis**:
```sql
-- Check if query uses our index
EXPLAIN ANALYZE 
SELECT * FROM vital_signs 
WHERE user_id = 123 AND type = 'blood_pressure' 
ORDER BY measurement_time DESC;

-- Good output:
-- Index Scan using idx_vital_signs_user_type_time (cost=0.42..8.44 rows=1 width=100)
-- → Query uses our index, execution time <1ms

-- Bad output:
-- Seq Scan on vital_signs (cost=0.00..1000000 rows=1000000 width=100)
-- → Query scans entire table, execution time 500ms+, needs index!
```

By strategically designing indexes and partitions, CareConnect maintains sub-10ms query times even with millions of records, ensuring a responsive user experience critical for healthcare workflows.



## Deployment Pipeline

### GitHub Actions CI/CD

```yaml
# .github/workflows/ci-cd.yml
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test-frontend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend

    steps:
    - uses: actions/checkout@v3
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.9.2'

    - name: Install dependencies
      run: flutter pub get

    - name: Run tests
      run: flutter test

    - name: Build web
      run: flutter build web

  test-backend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend/core

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_USER: careconnect
          POSTGRES_DB: careconnect_test
        options: --health-cmd="pg_isready" --health-interval=10s --health-timeout=5s --health-retries=3

    steps:
    - uses: actions/checkout@v3
    - uses: actions/setup-java@v3
      with:
        java-version: '17'
        distribution: 'adopt'

    - name: Cache Maven packages
      uses: actions/cache@v3
      with:
        path: ~/.m2
        key: ${{ runner.os }}-m2-${{ hashFiles('**/pom.xml') }}

    - name: Run tests
      run: ./mvnw test
      env:
        SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/careconnect_test
        SPRING_DATASOURCE_USERNAME: careconnect
        SPRING_DATASOURCE_PASSWORD: test

  deploy-staging:
    needs: [test-frontend, test-backend]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'

    steps:
    - uses: actions/checkout@v3

    - name: Deploy to staging
      run: |
        # Deploy backend to staging
        docker build -t careconnect-backend:staging backend/core
        docker push ${{ secrets.ECR_REGISTRY }}/careconnect-backend:staging

        # Deploy frontend to staging
        cd frontend
        flutter build web
        aws s3 sync build/web s3://${{ secrets.STAGING_BUCKET }}

  deploy-production:
    needs: [test-frontend, test-backend]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
    - uses: actions/checkout@v3

    - name: Deploy to production
      run: |
        # Production deployment with blue-green strategy
        ./scripts/deploy-production.sh
```

### Docker Configuration

```dockerfile
# backend/core/Dockerfile
FROM openjdk:17-jdk-slim

WORKDIR /app

COPY pom.xml .
COPY mvnw .
COPY .mvn .mvn
RUN ./mvnw dependency:go-offline

COPY src src
RUN ./mvnw package -DskipTests

EXPOSE 8080

CMD ["java", "-jar", "target/careconnect-backend-1.0.0.jar"]
```

### Terraform Infrastructure

```hcl
# terraform_aws/main.tf
provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "./modules/vpc"

  environment = var.environment
  cidr_block = var.vpc_cidr
}

module "rds" {
  source = "./modules/rds"

  environment = var.environment
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  db_name = var.db_name
  db_username = var.db_username
  db_password = var.db_password
}

module "ecs" {
  source = "./modules/ecs"

  environment = var.environment
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  backend_image = var.backend_image
  db_host = module.rds.db_endpoint
}
```

## Monitoring & Logging

### Application Monitoring

```java
// config/MonitoringConfig.java
@Configuration
public class MonitoringConfig {

    @Bean
    public MeterRegistry meterRegistry() {
        return new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
    }

    @Bean
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }
}

// Custom metrics
@Service
public class MetricsService {

    private final Counter userLoginCounter;
    private final Timer apiResponseTimer;

    public MetricsService(MeterRegistry meterRegistry) {
        this.userLoginCounter = Counter.builder("user.login.count")
            .description("Number of user logins")
            .register(meterRegistry);

        this.apiResponseTimer = Timer.builder("api.response.time")
            .description("API response time")
            .register(meterRegistry);
    }

    public void recordLogin() {
        userLoginCounter.increment();
    }

    public void recordApiResponse(Duration duration) {
        apiResponseTimer.record(duration);
    }
}
```

### Logging Configuration

```yaml
# backend/core/src/main/resources/logback-spring.xml
<configuration>
    <springProfile name="!prod">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="CONSOLE" />
        </root>
    </springProfile>

    <springProfile name="prod">
        <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
            <file>/app/logs/careconnect.log</file>
            <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
                <fileNamePattern>/app/logs/careconnect.%d{yyyy-MM-dd}.log</fileNamePattern>
                <maxHistory>30</maxHistory>
            </rollingPolicy>
            <encoder class="net.logstash.logback.encoder.LoggingEventCompositeJsonEncoder">
                <providers>
                    <timestamp />
                    <logLevel />
                    <loggerName />
                    <message />
                    <mdc />
                    <stackTrace />
                </providers>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="FILE" />
        </root>
    </springProfile>
</configuration>
```

## Code Standards & Best Practices

### Flutter Code Standards

```dart
// Good example - following naming conventions and structure
class HealthDataProvider extends ChangeNotifier {
  final HealthService _healthService;
  final List<VitalSign> _vitalSigns = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<VitalSign> get vitalSigns => List.unmodifiable(_vitalSigns);
  bool get isLoading => _isLoading;
  String? get error => _error;

  HealthDataProvider(this._healthService);

  Future<void> loadVitalSigns() async {
    _setLoading(true);
    _clearError();

    try {
      final signs = await _healthService.getVitalSigns();
      _vitalSigns.clear();
      _vitalSigns.addAll(signs);
    } catch (e) {
      _setError('Failed to load vital signs: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() => _setError(null);
}
```

### Java Code Standards

```java
// Good example - following SOLID principles and clean code
@Service
@Transactional
public class HealthServiceImpl implements HealthService {

    private static final Logger log = LoggerFactory.getLogger(HealthServiceImpl.class);

    private final VitalSignRepository vitalSignRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;
    private final VitalSignValidator vitalSignValidator;

    public HealthServiceImpl(
            VitalSignRepository vitalSignRepository,
            UserRepository userRepository,
            NotificationService notificationService,
            VitalSignValidator vitalSignValidator) {
        this.vitalSignRepository = vitalSignRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
        this.vitalSignValidator = vitalSignValidator;
    }

    @Override
    @Cacheable(value = "user_vitals", key = "#userId")
    public List<VitalSignDTO> getVitalSigns(Long userId) {
        log.debug("Fetching vital signs for user: {}", userId);

        List<VitalSign> vitalSigns = vitalSignRepository
            .findByUserIdOrderByMeasurementTimeDesc(userId);

        return vitalSigns.stream()
            .map(VitalSignMapper::toDTO)
            .collect(Collectors.toList());
    }

    @Override
    @CacheEvict(value = "user_vitals", key = "#userId")
    public VitalSignDTO recordVitalSign(Long userId, VitalSignRequest request) {
        log.info("Recording vital sign for user: {}", userId);

        // Validate input
        vitalSignValidator.validate(request);

        // Get user
        User user = userRepository.findById(userId)
            .orElseThrow(() -> new UserNotFoundException(userId));

        // Create and save vital sign
        VitalSign vitalSign = VitalSignMapper.fromRequest(request, user);
        vitalSign = vitalSignRepository.save(vitalSign);

        // Process alerts
        processVitalSignAlerts(vitalSign);

        log.info("Successfully recorded vital sign: {}", vitalSign.getId());
        return VitalSignMapper.toDTO(vitalSign);
    }

    private void processVitalSignAlerts(VitalSign vitalSign) {
        if (VitalSignAnalyzer.isAbnormal(vitalSign)) {
            notificationService.sendHealthAlert(vitalSign);
        }
    }
}
```

### Git Commit Standards

```
feat: add vital signs tracking functionality
fix: resolve authentication token refresh issue
docs: update API documentation for health endpoints
style: format code according to style guide
refactor: extract common validation logic
test: add unit tests for health service
chore: update dependencies to latest versions

# Breaking changes
BREAKING CHANGE: change API response format for vital signs endpoint
```

## Contributing Guidelines

### Development Workflow

1. **Fork and Clone**: Fork the repository and clone your fork
2. **Branch**: Create a feature branch from `develop`
3. **Develop**: Make your changes following code standards
4. **Test**: Write and run tests for your changes
5. **Commit**: Make atomic commits with clear messages
6. **Push**: Push your branch to your fork
7. **PR**: Create a pull request to `develop` branch

### Code Review Process

```markdown
## Pull Request Checklist

- [ ] Code follows the established style guide
- [ ] All tests pass
- [ ] New functionality has adequate test coverage
- [ ] Documentation is updated if needed
- [ ] No breaking changes without proper migration
- [ ] Security implications are considered
- [ ] Performance impact is acceptable
```

### Setting Up Development Environment

```bash
# Clone repository
git clone https://github.com/your-org/careconnect2025.git
cd careconnect2025

# Setup frontend
cd frontend
flutter pub get
flutter doctor

# Setup backend
cd ../backend/core
./mvnw clean install

# Setup database
psql -U postgres < scripts/init-db.sql

# Run tests
flutter test  # Frontend
./mvnw test   # Backend
```

## Troubleshooting

This section provides systematic approaches to resolving common issues in the CareConnect platform. Each issue is structured as: **Problem** → **Root Causes** → **Step-by-Step Resolution**, allowing you to quickly identify and fix issues while understanding why they occurred.

### Common Development Issues

#### Configuration Problems

##### Problem: Environment Variable Issues

**Symptoms**: Application fails to start with errors like "JWT secret not configured" or "API key missing". Services that depend on external APIs (AI, Stripe, AWS) fail to initialize.

**Root Causes**:
This typically occurs when environment variables are not properly set in your development environment. The application expects certain sensitive configuration values to be provided externally (not hardcoded) for security reasons. Common scenarios include:
- Variables set in one terminal session but not persisted
- Variables set in IDE configuration but not in terminal environment
- Incorrect variable names (typos or case sensitivity issues)
- Variables not exported in shell startup files

**Systematic Resolution Steps**:

1. **Verify Current Environment**: First, check which variables are actually set in your environment:
```bash
# Check all required environment variables at once
echo "JWT Secret: $SECURITY_JWT_SECRET"
echo "DeepSeek API Key: $DEEPSEEK_API_KEY"
echo "Stripe Secret: $STRIPE_SECRET_KEY"
echo "Database URL: $JDBC_URI"
```
Any variable showing blank means it's not set in your current environment.

2. **Set Variables for Current Session**: For immediate testing, export variables in your terminal:
```bash
export SECURITY_JWT_SECRET="your-jwt-secret-key-at-least-32-chars"
export DEEPSEEK_API_KEY="your-deepseek-api-key"
export STRIPE_SECRET_KEY="your-stripe-secret-key"
export JDBC_URI="jdbc:postgresql://localhost:5432/careconnect"
```
These will only last for the current terminal session.

3. **Persist Variables Permanently**: Add these to your shell configuration file for persistence:
```bash
# For bash users (~/.bashrc or ~/.bash_profile)
echo 'export SECURITY_JWT_SECRET="your-secret"' >> ~/.bashrc
source ~/.bashrc

# For zsh users (~/.zshrc)
echo 'export SECURITY_JWT_SECRET="your-secret"' >> ~/.zshrc
source ~/.zshrc
```

4. **Configure IDE Environment**: If running from an IDE, configure the run configuration:
- **IntelliJ IDEA**: Run → Edit Configurations → Environment Variables
- **VS Code**: Add to `.vscode/launch.json` or use `.env` file with appropriate plugin

5. **Verify Application Startup**: After setting variables, restart your application and check the logs for successful initialization of services that depend on these variables.

**Prevention**: Create a `.env.example` file in the repository documenting all required environment variables. New developers can copy this to `.env` and fill in their values.

##### Problem: Profile-Specific Configuration Issues

**Symptoms**: Application behavior differs between environments. Database schema updates fail in production. Flyway migrations conflict with JPA auto-generation.

**Root Causes**:
Spring Boot uses profiles to manage environment-specific configuration. Issues arise when:
- Development profile uses `spring.jpa.hibernate.ddl-auto=update` which auto-generates schema changes
- Flyway is disabled in development but enabled in production (or vice versa)
- Configuration properties conflict between profiles
- Active profile is not what you expect (e.g., running with `default` when you meant `dev`)

**Systematic Resolution Steps**:

1. **Identify Active Profile**: Check which profile Spring Boot is actually using:
```bash
# Check application logs on startup for:
# "The following profiles are active: dev"

# Or explicitly check:
java -jar your-app.jar --spring.profiles.active=dev

# Or via environment variable:
export SPRING_PROFILES_ACTIVE=dev
```

2. **Understand Profile Hierarchy**: Spring Boot loads configuration in this order (later overrides earlier):
   - `application.properties` (base configuration, always loaded)
   - `application-{profile}.properties` (profile-specific overrides)
   - Environment variables (highest priority)

3. **Review Development vs Production Settings**: Common configuration that should differ:
```properties
# application-dev.properties (Development)
spring.jpa.hibernate.ddl-auto=update      # Auto-generate schema changes
spring.flyway.enabled=false               # Disabled due to circular dependencies
spring.jpa.show-sql=true                  # Show SQL for debugging
logging.level.com.careconnect=DEBUG       # Verbose logging

# application-prod.properties (Production)
spring.jpa.hibernate.ddl-auto=validate    # Never auto-modify production schema
spring.flyway.enabled=true                # Use Flyway for controlled migrations
spring.jpa.show-sql=false                 # Don't log SQL in production
logging.level.com.careconnect=INFO        # Production logging level
```

4. **Fix Flyway/JPA Conflicts**: Currently, CareConnect has Flyway disabled in development due to circular dependency issues. To manually apply migrations:
```bash
# Check current database schema
psql -h localhost -U careconnect -d careconnect -c "\dt"

# Manually apply specific migration
psql -h localhost -U careconnect -d careconnect -f src/main/resources/db/migration/V22__create_ai_chat_tables.sql

# Verify migration was applied
psql -h localhost -U careconnect -d careconnect -c "SELECT * FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;"
```

5. **Validate Profile Loading**: Add logging to confirm correct profile is loaded:
```properties
# Add to application.properties
logging.level.org.springframework.core.env=DEBUG
```
This will log which property files are being loaded and in what order.

**Why This Happens**: Flyway and JPA DDL auto-generation both try to manage database schema, leading to conflicts. In CareConnect, we've temporarily disabled Flyway in development to avoid circular dependencies, but this is a technical debt that should be resolved by fixing the circular dependencies and re-enabling Flyway.

#### Flutter Build Issues

##### Problem: Unexpected Build Failures or Dependency Conflicts

**Symptoms**: `flutter build` or `flutter run` fails with errors about missing packages, version conflicts, or corrupted cache. Tests that previously passed now fail inexplicably.

**Root Causes**:
Flutter's build system aggressively caches dependencies and build artifacts for performance. While this usually helps, it can cause issues when:
- Package versions change in `pubspec.yaml` but cached versions persist
- Build artifacts become corrupted (often after git operations or Flutter SDK updates)
- Multiple Flutter projects on your system create conflicting cached state
- Flutter SDK is updated but local caches aren't refreshed

**Systematic Resolution Steps**:

1. **Level 1: Refresh Dependency Cache** (Solves ~80% of issues)
   ```bash
   # Delete the build folder (contains compiled artifacts)
   flutter clean

   # Repair the Pub cache (where packages are stored)
   flutter pub cache repair

   # Re-fetch all dependencies for this project
   flutter pub get
   ```
   **What this does**: `flutter clean` removes all compiled artifacts, forcing a fresh build. `pub cache repair` checks the integrity of all cached packages and re-downloads any that are corrupted. `pub get` updates the project's dependency resolution.

2. **Level 2: Upgrade SDK and Dependencies** (If Level 1 doesn't resolve)
   ```bash
   # Ensure you're on the stable channel (not dev or beta)
   flutter channel stable

   # Upgrade the Flutter SDK itself to the latest stable version
   flutter upgrade

   # Check which dependencies are outdated
   flutter pub outdated

   # Upgrade dependencies to latest compatible versions
   flutter pub upgrade
   ```
   **Important**: After `flutter upgrade`, run `flutter doctor -v` to ensure all components (Android toolchain, iOS toolchain, etc.) are properly configured.

3. **Level 3: Resolve Dependency Conflicts** (For persistent version conflicts)
   ```bash
   # Visualize the dependency tree to find conflicts
   flutter pub deps --style=tree
   ```
   Look for the same package appearing multiple times with different versions. Example output:
   ```
   ├── http 0.13.5
   └── some_package 1.0.0
       └── http 0.13.4  ← Conflict! Two versions of http
   ```
   
   **Resolution**: Use `dependency_overrides` in `pubspec.yaml` (use sparingly, only as last resort):
   ```yaml
   dependency_overrides:
     http: ^0.13.5  # Force all packages to use this version
   ```

4. **Level 4: IDE Synchronization** (If builds work in terminal but not IDE)
   
   **VS Code**:
   ```
   - Open Command Palette (Cmd/Ctrl+Shift+P)
   - Run: "Dart: Restart Analysis Server"
   - If issue persists: Reload window (Cmd/Ctrl+R)
   ```
   
   **Android Studio**:
   ```
   - File > Invalidate Caches / Restart...
   - Select "Invalidate and Restart"
   ```
   
   **What this does**: IDEs maintain their own analysis of your Dart code. Sometimes this gets out of sync with actual files, causing phantom errors.

5. **Level 5: Verify Exact Package Versions** (For reproducible team builds)
   
   Check the project's `pubspec.yaml` and ensure you're using the exact versions specified:
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     provider: ^6.0.5      # Ensure your version matches team's version
     dio: ^5.3.2
     go_router: ^10.1.0
   ```
   
   The `pubspec.lock` file (committed to git) records exact versions. If your `pubspec.lock` differs from the team's, you might get different behavior.

**Prevention**: 
- Commit `pubspec.lock` to version control so all team members use identical package versions
- Document the Flutter version the project uses in README: "This project requires Flutter 3.9.2 or later"
- Run `flutter doctor` regularly to catch environment issues early
- When changing dependencies, run tests before committing to catch incompatibilities

**When to Escalate**: If none of these steps resolve the issue, the problem may be:
- A genuine bug in a package (check package's GitHub issues)
- Incompatibility with your specific OS/environment (check Flutter GitHub issues)
- Project-specific configuration issue (consult the team lead)

#### Backend Compilation Issues

##### Problem: Maven Dependencies Not Resolving

**Symptoms**: Maven build fails with "Could not resolve dependencies" errors. Compile phase fails with "package does not exist" errors even though dependencies are declared in `pom.xml`. Spring Boot application fails to start due to missing beans.

**Root Causes**:
Maven maintains a local repository cache (`~/.m2/repository`) where it stores downloaded dependencies. Issues occur when:
- The local repository becomes corrupted (incomplete downloads, disk errors)
- A SNAPSHOT dependency was cached but the remote version has updated
- Maven's metadata files become inconsistent
- Network issues interrupted dependency downloads
- Corporate proxies or firewalls block Maven Central or Spring repositories

**Systematic Resolution Steps**:

1. **Clean Build Artifacts**: Start by removing compiled code to force a fresh build:
   ```bash
   # Clean all compiled artifacts and target directory
   ./mvnw clean
   
   # Verify target directory is gone
   ls -la target  # Should show "No such file or directory"
   ```

2. **Purge Local Maven Repository** (Nuclear option, but often necessary):
   ```bash
   # Remove entire local Maven cache
   # WARNING: This deletes ALL cached dependencies, not just for this project
   rm -rf ~/.m2/repository
   
   # Re-download all dependencies
   ./mvnw dependency:resolve
   
   # Attempt compilation
   ./mvnw clean compile
   ```
   **What this does**: Completely removes Maven's local cache and forces it to re-download every dependency. This fixes corruption but requires a full re-download (can take several minutes on slow connections).

3. **Verify Java Version** (Spring Boot 3.4.5 has specific requirements):
   ```bash
   # Check current Java version
   java -version
   
   # Must show Java 17 or higher for Spring Boot 3.4.5
   # If not:
   # - macOS: brew install openjdk@17 && sudo ln -sfn $(brew --prefix openjdk@17)/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk
   # - Linux: sudo apt install openjdk-17-jdk
   # - Windows: Download from https://adoptium.net/
   
   # Verify JAVA_HOME points to Java 17
   echo $JAVA_HOME
   
   # Set JAVA_HOME if needed
   export JAVA_HOME=/path/to/java17
   ```
   **Why this matters**: Spring Boot 3.x requires Java 17 as a minimum. Using Java 11 or older will cause cryptic compilation errors because certain language features and APIs don't exist in older versions.

4. **Diagnose Circular Dependencies**:
   ```bash
   # Compile and watch for circular dependency errors
   ./mvnw compile 2>&1 | grep -i circular
   
   # If circular dependencies found, analyze with:
   ./mvnw dependency:tree -Dverbose=true
   ```
   **Understanding Circular Dependencies**: A circular dependency occurs when Bean A depends on Bean B, which depends on Bean C, which depends on Bean A. Spring can sometimes resolve these with lazy initialization, but it's better to refactor the code to break the circle.
   
   **Common CareConnect Circular Dependency**: The Flyway/Spring AI circular dependency currently requires Flyway to be disabled in development. This should be resolved by:
   - Moving database initialization to a separate configuration
   - Using `@Lazy` annotation on one side of the dependency
   - Refactoring to introduce an interface that breaks the circle

5. **Check Spring AI Milestone Versions** (CareConnect-specific issue):
   ```bash
   # Spring AI is in milestone releases, which requires special repository configuration
   # Verify dependency tree for Spring AI conflicts
   ./mvnw dependency:tree | grep spring-ai
   
   # Should show consistent versions across all spring-ai-* artifacts
   ```
   
   Ensure your `pom.xml` includes the Spring milestones repository:
   ```xml
   <repositories>
       <repository>
           <id>spring-milestones</id>
           <name>Spring Milestones</name>
           <url>https://repo.spring.io/milestone</url>
           <snapshots>
               <enabled>false</enabled>
           </snapshots>
       </repository>
   </repositories>
   ```

6. **Force Maven to Update All Dependencies**:
   ```bash
   # Force update of all SNAPSHOT and release dependencies
   ./mvnw clean install -U
   
   # The -U flag forces Maven to check for updated versions
   ```

**Prevention**:
- Commit `maven-wrapper.properties` to ensure all developers use the same Maven version
- Document required Java version in README
- Use Maven Enforcer Plugin to fail builds with wrong Java version:
  ```xml
  <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-enforcer-plugin</artifactId>
      <executions>
          <execution>
              <goals>
                  <goal>enforce</goal>
              </goals>
              <configuration>
                  <rules>
                      <requireJavaVersion>
                          <version>[17,)</version>
                      </requireJavaVersion>
                  </rules>
              </configuration>
          </execution>
      </executions>
  </plugin>
  ```

**When to Escalate**: If these steps don't resolve the issue:
- Check if your network has proxy requirements (`~/.m2/settings.xml` proxy configuration)
- Verify you can reach Maven Central: `curl https://repo.maven.apache.org/maven2/`
- Check if a specific dependency is actually available at the version specified
- Consult the team's build server logs to see if it's a local-only issue

#### Database Connection Issues

##### Problem: PostgreSQL Connection Failures

**Symptoms**: Application startup fails with "Connection refused" or "Connection timeout" errors. Intermittent "Too many connections" errors during load. Operations hang without returning results.

**Root Causes**:
Database connection issues in CareConnect typically stem from:
- PostgreSQL server not running or not accessible
- Connection pool exhausted (HikariCP runs out of connections)
- Network connectivity issues (firewall, DNS resolution)
- Incorrect connection string or credentials
- PostgreSQL configured to accept too few connections
- Long-running transactions holding connections without releasing them

**Systematic Resolution Steps**:

1. **Verify PostgreSQL Server Status**:
   ```bash
   # Check if PostgreSQL is running
   pg_isready -h localhost -p 5432
   # Expected: "localhost:5432 - accepting connections"
   
   # If using Docker:
   docker ps | grep postgres
   # Should show a running postgres container
   
   # If not running, start it:
   # Docker: docker-compose up -d postgres
   # macOS: brew services start postgresql
   # Linux: sudo systemctl start postgresql
   ```

2. **Test Direct Connection** (bypasses application, tests database itself):
   ```bash
   # Connect with psql client
   psql -h localhost -p 5432 -U careconnect -d careconnect
   
   # If successful, you'll see: careconnect=#
   
   # Check PostgreSQL version and basic health
   SELECT version();
   SELECT now();  # Should return current timestamp
   ```
   
   **If this fails**: The problem is with PostgreSQL itself, not the application. Check:
   - Credentials in your environment match PostgreSQL's configured users
   - `pg_hba.conf` allows connections from localhost
   - PostgreSQL is listening on the right port (check `postgresql.conf`)

3. **Diagnose Connection Pool Issues**:
   ```sql
   -- Inside psql, check current connection usage
   SELECT 
       count(*) as total_connections,
       count(*) FILTER (WHERE state = 'active') as active,
       count(*) FILTER (WHERE state = 'idle') as idle,
       count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction
   FROM pg_stat_activity 
   WHERE datname = 'careconnect';
   
   -- Check max_connections setting
   SHOW max_connections;
   
   -- If close to max, you have a connection leak
   ```
   
   **Understanding the Results**:
   - **Active**: Currently executing queries (normal)
   - **Idle**: Connected but not doing anything (normal for connection pool)
   - **Idle in transaction**: Connected, started a transaction, but not committing/rolling back (BAD - indicates a bug)
   
   If "idle in transaction" is high, you have a connection leak. Transactions are starting but not finishing, holding connections hostage.

4. **Tune HikariCP Connection Pool** (if pool exhaustion detected):
   
   CareConnect uses HikariCP as its connection pool. Tuning it properly is crucial for stability:
   
   ```properties
   # In application.properties or application-dev.properties
   
   # Maximum number of connections in the pool
   # Rule of thumb: (2 * number_of_cores) + number_of_disks
   # For a 4-core machine with SSD: (2*4)+1 = 9, round up to 10
   spring.datasource.hikari.maximum-pool-size=10
   
   # Minimum number of idle connections maintained
   # Keep this lower to avoid wasting resources
   spring.datasource.hikari.minimum-idle=5
   
   # Maximum time to wait for a connection from pool (milliseconds)
   # 20 seconds is reasonable; if you hit this, you have a connection leak
   spring.datasource.hikari.connection-timeout=20000
   
   # Maximum time a connection can sit idle before being closed
   # 5 minutes prevents stale connections
   spring.datasource.hikari.idle-timeout=300000
   
   # Maximum lifetime of a connection (milliseconds)
   # 30 minutes forces periodic recycling, preventing stale connections
   spring.datasource.hikari.max-lifetime=1800000
   
   # Enable leak detection (development only, has performance cost)
   spring.datasource.hikari.leak-detection-threshold=60000
   ```
   
   **What each setting does**:
   - `maximum-pool-size`: Too low = connections exhausted under load; too high = wastes resources and can overwhelm PostgreSQL
   - `connection-timeout`: How long to wait for a connection before giving up. If you hit this regularly, increase pool size or fix connection leaks
   - `leak-detection-threshold`: If enabled, HikariCP will log a warning if a connection is held longer than this threshold, helping identify leaks

5. **Identify and Kill Problematic Connections** (emergency measure):
   ```sql
   -- Find long-running or blocked queries
   SELECT 
       pid,
       usename,
       application_name,
       state,
       query,
       now() - state_change as duration
   FROM pg_stat_activity
   WHERE state != 'idle'
     AND now() - state_change > interval '5 minutes'
   ORDER BY duration DESC;
   
   -- If you find a stuck query, you can terminate it:
   SELECT pg_terminate_backend(12345);  -- Replace 12345 with actual pid
   
   -- To terminate all idle in transaction connections (use carefully!):
   SELECT pg_terminate_backend(pid) 
   FROM pg_stat_activity 
   WHERE state = 'idle in transaction' 
     AND now() - state_change > interval '10 minutes';
   ```
   
   **Warning**: Terminating connections forcefully will roll back any in-progress transactions. Only do this when connections are truly stuck, not just slow.

6. **Increase PostgreSQL's max_connections** (if legitimately need more connections):
   ```sql
   -- Check current setting
   SHOW max_connections;  -- Default is often 100
   
   -- To increase (requires PostgreSQL restart):
   -- Edit postgresql.conf:
   max_connections = 200
   
   -- Then restart PostgreSQL:
   -- Docker: docker-compose restart postgres
   -- macOS: brew services restart postgresql
   -- Linux: sudo systemctl restart postgresql
   ```
   
   **Caveat**: Each connection consumes memory. Blindly increasing max_connections can cause PostgreSQL to run out of memory. Better to fix connection leaks or use connection pooling (which CareConnect already does with HikariCP).

7. **Enable Connection Pool Logging** (to debug pool behavior):
   ```properties
   # Add to application.properties
   logging.level.com.zaxxer.hikari=DEBUG
   logging.level.com.zaxxer.hikari.HikariConfig=DEBUG
   ```
   
   This will log every connection acquisition and release, helping you spot:
   - Connections not being returned to pool
   - Pool exhaustion events
   - Configuration issues

**Prevention**:
- Always use `@Transactional` on service methods to ensure transactions complete
- Avoid manual transaction management unless absolutely necessary
- Use try-with-resources when manually managing connections (rare in Spring Boot)
- Monitor connection pool metrics in production (HikariCP exposes JMX metrics)
- Set up alerts when idle in transaction connections exceed a threshold

**Common Anti-Patterns to Avoid**:
```java
// BAD: Opening connection manually (should use JPA/repositories)
Connection conn = DriverManager.getConnection(url);
// ... use connection ...
// Forgot to close! Connection leak!

// GOOD: Let Spring manage connections
@Service
@Transactional
public class MyService {
    @Autowired
    private MyRepository repo;
    
    public void doWork() {
        repo.save(entity);
        // Connection automatically returned to pool when method completes
    }
}
```

### Authentication & Security Issues

#### JWT Token Problems

**Invalid Token Handling**
```java
// Common JWT issues in JwtAuthenticationFilter
if (token != null && jwt.validateToken(token)) {
    // Token is valid
} else {
    if (token != null) {
        log.warn("Invalid token provided");  // Check token expiration
    } else {
        log.debug("No token found in request");  // Missing Authorization header
    }
}
```

**Token Debugging**
```bash
# Decode JWT token (for debugging only)
echo "your-jwt-token" | cut -d. -f2 | base64 --decode | jq .

# Check token expiration
curl -H "Authorization: Bearer your-token" http://localhost:8080/v1/api/auth/validate
```

#### Password Reset Issues

**Reset Token Problems**
```java
// From UserPasswordService - token validation
boolean validateToken(String token, String email) {
    // Check both raw token and Base64 encoded versions
    // Common issue: Base64 encoding mismatches
}
```

#### OAuth Integration Issues

**Google OAuth Configuration**
```properties
# Development uses mock credentials - update for production
spring.security.oauth2.client.registration.google.client-id=your-real-client-id
spring.security.oauth2.client.registration.google.client-secret=your-real-client-secret
```

### WebSocket Connection Issues

#### Connection Management Problems

**Authentication Failures**
```java
// Common WebSocket authentication issues
private void handleAuthentication(WebSocketSession session, Map<String, Object> payload) {
    String token = (String) payload.get("token");
    if (jwtTokenProvider.validateToken(token)) {
        // Store authenticated user info
        session.getAttributes().put("authenticated", true);
    } else {
        // Authentication failed - connection will be closed
        sendMessage(session, Map.of("type", "authentication-error", "message", "Invalid token"));
    }
}
```

**Connection Cleanup Issues**
```java
// WebSocket transport errors may not properly clean up sessions
@Scheduled(fixedRate = 300000) // Every 5 minutes
public void cleanupExpiredConnections() {
    List<WebSocketConnection> expired = repository.findExpiredConnections(LocalDateTime.now());
    expired.forEach(conn -> conn.setIsActive(false));
}
```

**Client-Side Connection Issues**
```dart
// Flutter WebSocket reconnection logic
Future<void> _handleDisconnection() async {
  // Implement exponential backoff
  int retryCount = 0;
  while (retryCount < 5) {
    await Future.delayed(Duration(seconds: math.pow(2, retryCount).toInt()));
    try {
      await connect();
      break;
    } catch (e) {
      retryCount++;
    }
  }
}
```

### AI Service Integration Issues

#### DeepSeek API Problems

**API Key Configuration**
```java
// DeepSeekService initialization
if (apiKey == null || apiKey.trim().isEmpty()) {
    throw new IllegalStateException("DeepSeek API key is not configured");
}
```

**Network Timeout Issues**
```properties
# Increase timeout for AI API calls
careconnect.ai.timeout.connection=30000
careconnect.ai.timeout.read=60000
```

**JSON Parsing Failures**
```java
// AI response parsing errors
try {
    TaskDtoV2 aiTask = objectMapper.readValue(aiContent, TaskDtoV2.class);
    if (aiTask == null || aiTask.getName() == null) {
        log.error("Invalid AI Task generated: {}", aiTask);
        return; // Skip invalid AI responses
    }
} catch (JsonProcessingException e) {
    log.error("Error parsing AI response: {}", e.getMessage());
}
```

#### LangChain4j Integration Issues

**Memory Management Problems**
```properties
# Chat memory configuration issues
careconnect.chat.memory.default-max-messages=20
careconnect.chat.memory.premium-max-messages=50
careconnect.chat.memory.auto-cleanup=true
```

**Model Configuration Errors**
```java
// Model initialization
@Bean
public ChatLanguageModel deepSeekChatModel() {
    return OpenAiChatModel.builder()
        .baseUrl("https://api.deepseek.com/v1")
        .apiKey(deepSeekApiKey)
        .modelName("deepseek-chat")
        .temperature(0.7)
        .timeout(Duration.ofSeconds(60))
        .maxRetries(3)  // Add retry logic
        .build();
}
```

### Third-Party Integration Issues

#### Stripe Integration Problems

**Price ID Conversion Issues**
```java
// Common Stripe issues in StripeService
private String convertPlanIdToPriceId(String planId) {
    // Complex price ID mapping - ensure all plans are configured
    switch (planId.toLowerCase()) {
        case "basic": return "price_basic_monthly";
        case "premium": return "price_premium_monthly";
        default:
            log.error("Unknown plan ID: {}", planId);
            throw new AppException(HttpStatus.BAD_REQUEST, "Invalid plan ID");
    }
}
```

**Webhook Validation**
```java
// Stripe webhook signature validation
try {
    Webhook.constructEvent(payload, sigHeader, endpointSecret);
} catch (SignatureVerificationException e) {
    log.error("Invalid Stripe webhook signature");
    throw new AppException(HttpStatus.BAD_REQUEST, "Invalid signature");
}
```

#### AWS Integration Issues

**S3 Configuration Problems**
```properties
# Environment-specific S3 configuration
cloud.aws.s3.bucket=${AWS_S3_BUCKET_NAME:careconnect-dev}
cloud.aws.credentials.access-key=${AWS_ACCESS_KEY_ID}
cloud.aws.credentials.secret-key=${AWS_SECRET_ACCESS_KEY}
```

**WebSocket API Gateway Issues**
```java
// AWS WebSocket connection management
public void sendMessageToConnection(String connectionId, Object message) {
    try {
        AmazonApiGatewayManagementApi client = clientBuilder
            .withEndpointConfiguration(new EndpointConfiguration(apiGatewayEndpoint, "us-east-1"))
            .build();
        // Handle ConnectionGoneException for disconnected clients
    } catch (GoneException e) {
        log.info("Connection {} is no longer available", connectionId);
        connectionService.markConnectionInactive(connectionId);
    }
}
```

### Performance Issues

#### Database Performance Problems

**Slow Queries**
```sql
-- Enable PostgreSQL query logging
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_min_duration_statement = 1000; -- Log queries > 1 second

-- Check slow queries
SELECT query, mean_exec_time, total_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC LIMIT 10;
```

**Connection Pool Exhaustion**
```properties
# Monitor and tune HikariCP settings
spring.datasource.hikari.maximum-pool-size=20
spring.datasource.hikari.leak-detection-threshold=60000
logging.level.com.zaxxer.hikari=DEBUG
```

#### Memory Issues

**JVM Memory Tuning**
```bash
# Production JVM settings
java -Xms2g -Xmx4g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 \
     -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/app/ \
     -jar careconnect-backend.jar
```

**Flutter Memory Optimization**
```dart
// Optimize image loading and caching
class OptimizedImageWidget extends StatelessWidget {
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      memCacheWidth: 300,
      memCacheHeight: 300,
      placeholder: (context, url) => CircularProgressIndicator(),
      errorWidget: (context, url, error) => Icon(Icons.error),
      // Implement image compression
      imageBuilder: (context, imageProvider) => Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: imageProvider,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
```

### Development Environment Issues

#### Docker and Containerization

**Database Container Issues**
```bash
# PostgreSQL container troubleshooting
docker logs careconnect-postgres
docker exec -it careconnect-postgres psql -U careconnect -d careconnect

# Reset database container
docker-compose down -v
docker-compose up -d postgres
```

**Port Conflicts**
```bash
# Check for port conflicts
lsof -i :8080  # Backend port
lsof -i :3000  # Frontend port
lsof -i :5432  # PostgreSQL port

# Kill conflicting processes
kill -9 <PID>
```

#### IDE and Tooling Issues

**IntelliJ IDEA Configuration**
```bash
# Clear IntelliJ caches
rm -rf ~/.IntelliJIdea*/system/caches
rm -rf ~/.IntelliJIdea*/system/index

# Reimport Maven project
mvn idea:idea
```

**VS Code Flutter Issues**
```json
// .vscode/settings.json
{
  "dart.flutterSdkPath": "/path/to/flutter",
  "dart.debugExternalPackageLibraries": true,
  "dart.debugSdkLibraries": true
}
```

### Deployment Issues

#### Production Deployment Problems

**Environment Configuration**
```bash
# Check all required environment variables for production
required_vars=(
  "SECURITY_JWT_SECRET"
  "DEEPSEEK_API_KEY"
  "STRIPE_SECRET_KEY"
  "AWS_ACCESS_KEY_ID"
  "AWS_SECRET_ACCESS_KEY"
  "DATABASE_URL"
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Missing required environment variable: $var"
  fi
done
```

**Health Check Failures**
```bash
# Test application health endpoints
curl -f http://localhost:8080/actuator/health || exit 1
curl -f http://localhost:8080/actuator/db || exit 1
```

#### Monitoring and Debugging

**Application Metrics**
```properties
# Enable actuator endpoints for monitoring
management.endpoints.web.exposure.include=health,info,metrics,prometheus
management.endpoint.health.show-details=always
```

**Logging Configuration**
```properties
# Production logging configuration
logging.level.org.springframework.security=INFO
logging.level.com.careconnect=INFO
logging.level.org.hibernate.SQL=WARN
logging.pattern.file=%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n
```

**Error Tracking**
```java
// Structured error logging
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGenericException(Exception e) {
        log.error("Unhandled exception occurred", e);
        ErrorResponse error = new ErrorResponse(
            "INTERNAL_ERROR",
            "An unexpected error occurred",
            System.currentTimeMillis()
        );
        return ResponseEntity.status(500).body(error);
    }
}
```

This comprehensive troubleshooting guide covers the most common issues encountered in the CareConnect platform, providing practical solutions and debugging strategies for developers.

---

*This guide covers the essential aspects of developing with the CareConnect platform. For specific implementation details, refer to the code comments and additional documentation in the respective modules.*

*Last Updated: October 2025*
*Version: 2025.1.0*