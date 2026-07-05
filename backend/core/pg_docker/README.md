# CareConnect PostgreSQL Development Setup

This directory contains the PostgreSQL development environment for CareConnect.

## Quick Start

```bash
# Start PostgreSQL and PgAdmin
docker-compose up -d

# Reset database (clean slate)
./scripts/reset-database.sh

# Run Flyway migrations manually
./scripts/run-migrations.sh

# Create database backup
./scripts/dump-database.sh
```

## Available Services

### PostgreSQL Database
- **Host**: localhost
- **Port**: 5432 (default, configurable via `POSTGRES_PORT`)
- **Database**: careconnect
- **Username**: postgres
- **Password**: changeme

### PgAdmin Web Interface
- **URL**: http://localhost:5050
- **Email**: pgadmin4@pgadmin.org
- **Password**: admin

## Database Management Scripts

### `./scripts/reset-database.sh`
- Stops PostgreSQL containers
- Removes all data (complete reset)
- Starts fresh PostgreSQL container
- Ready for new migrations

### `./scripts/run-migrations.sh`
- Runs Flyway migrations against PostgreSQL
- Uses migration files from `../src/main/resources/db/migration/`
- Ensures database schema is up to date

### `./scripts/dump-database.sh`
- Creates timestamped database backup
- Saves to `./backups/` directory
- Creates `latest.sql` symlink for convenience

## Development Workflow

1. **Initial Setup**:
   ```bash
   cd pg_docker
   docker-compose up -d
   ./scripts/reset-database.sh
   ```

2. **Run Application**:
   ```bash
   cd ..
   ./mvnw spring-boot:run -Dspring.profiles.active=dev
   ```

3. **Reset When Needed**:
   ```bash
   ./scripts/reset-database.sh
   ```

## Environment Variables

Create a `.env` file in this directory to customize:

```env
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=changeme
POSTGRES_DB=careconnect
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=admin
PGADMIN_PORT=5050
```

If you need to run PostgreSQL on a different host port (for example `5433`), set
`POSTGRES_PORT=5433` and make sure your backend `JDBC_URI` uses the same port.

## Migration Files

Flyway migration files are located in:
```
../src/main/resources/db/migration/
```

These files are automatically mounted in the PostgreSQL container for reference but are applied by the Spring Boot application or manual Flyway commands.

## Troubleshooting

### PostgreSQL won't start
```bash
docker-compose down
docker volume rm pg_docker_postgres
docker-compose up -d
```

### Reset everything
```bash
./scripts/reset-database.sh
```

### Check PostgreSQL logs
```bash
docker logs postgres_container
```

### Connect via psql
```bash
docker exec -it postgres_container psql -U postgres -d careconnect
```