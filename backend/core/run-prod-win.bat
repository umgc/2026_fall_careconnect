@echo off
setlocal enabledelayedexpansion
REM ================================
REM CareConnect Backend Development Startup Script - Windows
REM ================================

echo CareConnect Backend - Windows Development Setup
echo Loading environment variables...

REM Validate Java version (project requires JDK 17)
where javac >nul 2>&1
if errorlevel 1 (
    echo Error: javac was not found on PATH.
    echo Install JDK 17 and set JAVA_HOME/PATH, then retry.
    pause
    exit /b 1
)

for /f "tokens=2 delims=. " %%v in ('javac -version 2^>^&1') do set "JAVA_MAJOR=%%v"
if not "%JAVA_MAJOR%" GEQ "17" (
    echo Error: Detected JDK %JAVA_MAJOR%, but this project requires JDK 17.
    echo Current compiler:
    javac -version
    echo Please install/select JDK 17 and try again.
    pause
    exit /b 1
)

REM Check if .env file exists
if not exist ".env" (
    echo Error: .env file not found in current directory
    echo Please create a .env file based on the provided template
    pause
    exit /b 1
)

REM Load environment variables from .env file
for /f "usebackq tokens=1* delims==" %%a in (".env") do (
    set "line=%%a"
    if not "!line!"=="" (
        if not "!line:~0,1!"=="#" (
            set "%%a=%%b"
        )
    )
)

echo Environment variables loaded successfully!
echo Database: %JDBC_URI%

REM Verify critical variables are set
set "missing_vars="
if "%JDBC_URI%"=="" set "missing_vars=%missing_vars% JDBC_URI"
if "%DB_USER%"=="" set "missing_vars=%missing_vars% DB_USER"
if "%DB_PASSWORD%"=="" set "missing_vars=%missing_vars% DB_PASSWORD"
if "%SECURITY_JWT_SECRET%"=="" set "missing_vars=%missing_vars% SECURITY_JWT_SECRET"
if "%FIREBASE_PROJECT_ID%"=="" set "missing_vars=%missing_vars% FIREBASE_PROJECT_ID"
if "%FIREBASE_SENDER_ID%"=="" set "missing_vars=%missing_vars% FIREBASE_SENDER_ID"

if not "%missing_vars%"=="" (
    echo Warning: The following critical environment variables are not set:
    echo %missing_vars%
    echo Please update your .env file with the required values
)

echo Starting CareConnect Backend in Development Mode...
echo ==========================================

REM Check if Docker Desktop is running (Windows specific)
docker info >nul 2>&1
if errorlevel 1 (
    echo Error: Docker Desktop is not running.
    echo Please start Docker Desktop from the Start Menu or Desktop
    set /p "choice=Would you like to try starting Docker Desktop? (y/n): "
    if /i "!choice!"=="y" (
        echo Starting Docker Desktop...
        start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        echo Waiting for Docker Desktop to start...
        C:\Windows\System32\timeout.exe /t 20 /nobreak >nul
        REM Retry docker info
        docker info >nul 2>&1
        if errorlevel 1 (
            echo Docker Desktop is still not ready. Please start it manually and try again.
            pause
            exit /b 1
        )
    ) else (
        exit /b 1
    )
)

REM Check if PostgreSQL container is running - FIXED VERSION
echo Checking PostgreSQL Docker container...
for /f %%i in ('docker ps --filter name=postgres_container --filter status=running --quiet 2^>nul') do set "running_container=%%i"

if "%running_container%"=="" (
    echo PostgreSQL container not running. Checking if container exists...

    REM Check if container exists but is stopped
    for /f %%i in ('docker ps -a --filter name=postgres_container --quiet 2^>nul') do set "existing_container=%%i"

    if not "%existing_container%"=="" (
        echo Found stopped PostgreSQL container. Starting it...
        docker start postgres_container
        if errorlevel 1 (
            echo Error: Failed to start existing PostgreSQL container
            pause
            exit /b 1
        )
    ) else (
        echo No PostgreSQL container found. Creating new one...

        REM Check if docker-compose.yml exists
        if not exist "pg_docker\docker-compose.yml" (
            echo Error: pg_docker\docker-compose.yml not found
            echo Please ensure the PostgreSQL Docker setup is in place
            pause
            exit /b 1
        )

        REM Start PostgreSQL container
        echo Starting PostgreSQL with Docker Compose...
        pushd pg_docker
        docker compose up -d postgres
        if errorlevel 1 (
            echo Error: Failed to start PostgreSQL with Docker Compose
            popd
            pause
            exit /b 1
        )
        popd
    )

    echo Waiting for PostgreSQL to be ready...
    C:\Windows\System32\timeout.exe /t 10 /nobreak >nul
) else (
    echo PostgreSQL container is already running!
)

REM Test PostgreSQL connection with better error handling
echo Testing PostgreSQL connection...
set "max_attempts=30"
set "attempt=1"
:wait_loop
docker exec postgres_container pg_isready -U postgres >nul 2>&1
if not errorlevel 1 (
    echo PostgreSQL is ready!
    goto :postgres_ready
)
echo Waiting for PostgreSQL... (attempt !attempt!/!max_attempts!)
C:\Windows\System32\timeout.exe /t 2 /nobreak >nul
set /a attempt+=1
if !attempt! leq !max_attempts! goto :wait_loop

echo Error: PostgreSQL failed to start within expected time
echo Checking container status...
docker ps -a --filter name=postgres_container
echo.
echo Container logs:
docker logs postgres_container --tail 10
pause
exit /b 1

:postgres_ready

echo ----------------------------------------
echo Development Configuration:
echo - Platform: Windows
echo - Database: PostgreSQL (Docker)
echo - Profile: dev
echo - API Keys: Mocked
echo - Email: Console logging
echo - File Storage: Local
echo - Docker: Docker Desktop
echo ----------------------------------------

echo Starting Spring Boot application...
set SPRING_PROFILES_ACTIVE=prod

REM Use Maven wrapper for Windows
call mvnw.cmd spring-boot:run 

echo Application stopped.
pause
