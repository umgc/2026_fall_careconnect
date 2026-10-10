# Backend Local Startup Performance

_Research note — why `run-local-bedrock.ps1` is slow to start the backend on Windows, and how
`run-fast.ps1` addresses it. Investigated 2026-09-17._

## Summary

Launching the backend with `run-local-bedrock.ps1` is slow because its final step,
`.\mvnw.cmd spring-boot:run`, runs a full Maven build on **every** launch (dependency
resolution + recompile) before Spring even boots, and the app itself has a heavy dev-profile
startup. The Maven build cost is the avoidable part. `run-fast.ps1` builds the executable jar
once (only when sources change) and then boots with `java -jar`, removing recompile and
dependency resolution from repeat launches.

## Contributing causes (ordered by impact)

### 1. `mvnw.cmd spring-boot:run` = full Maven lifecycle every launch
`run-local-bedrock.ps1:62` ends with `.\mvnw.cmd spring-boot:run`. This runs validate →
resolve/check dependencies (online metadata checks unless offline) → recompile sources → fork
JVM → boot Spring, on every single launch. It is not "start a prebuilt app."

### 2. Hibernate `ddl-auto=update` over 116 entities
`application-dev.properties:48` sets `spring.jpa.hibernate.ddl-auto=update`, and the project has
**116 `@Entity` classes** (`backend/core/src/main/java/com/careconnect/model/**`). On every boot
Hibernate builds all 116 metamodels and diffs each table/column/index against Postgres — many
metadata round-trips to the DB container on port 5433. A large recurring cost, independent of
Maven.

### 3. Eleven startup runners seed/patch on every boot
`CommandLineRunner` / `ApplicationRunner` / `@PostConstruct` components run after context load
and hit the DB each restart. Notably:
- `config/SchemaPatchRunner.java` (`@Order(1)`) — idempotent DDL patches on every restart
- `service/DataInitializer.java`, `config/DevDataLoader.java`, `config/QuestionInitializer.java`,
  `config/FormDefinitionInitializer.java`, `config/AchievementInitializer.java`

### 4. `aws sts get-caller-identity` preflight through Norton TLS
`run-local-bedrock.ps1:44` makes a live HTTPS call to AWS STS before Maven starts, as a
fail-fast credential check. On this machine that traverses Norton's TLS interception (see
[Norton TLS interception](#norton-tls-interception)), adding latency (and retry/timeout risk).

### 5. Norton real-time protection (machine-specific; likely the biggest hidden tax)
Norton scans file I/O and intercepts outbound TLS. Maven touches thousands of jars/class files
in `~/.m2` and recompiles hundreds of `.java` → `.class`, and every outbound HTTPS (STS,
Bedrock, Epic) is MITM'd. This overhead lands on class loading, dependency resolution, and every
TLS handshake at boot.
<a id="norton-tls-interception"></a>
> Norton Web/Mail Shield MITMs HTTPS on this box. The AWS CLI needs a combined CA bundle
> (`AWS_CA_BUNDLE`), and the JVM needs the Norton root imported into a truststore
> (`-Djavax.net.ssl.trustStore=...careconnect-truststore.jks`). See the header comments in
> `run-local-bedrock.ps1:50-58` and `run-dev.sh:121-137` for how these are built once.

### 6. Bedrock/AWS/AI + DEBUG logging
`CARECONNECT_AI_ENABLED=true` initializes the AWS SDK/Bedrock client and resolves the credential
chain at boot; DEBUG logging on `com.careconnect` and `org.springframework.security`
(`application-dev.properties:69-70`) adds overhead.

### First-run only
`mvnw` downloads Maven 3.9.11 and all dependencies into `~/.m2` on the first build; cached after.

## Mitigations

Ordered by expected win:

1. **Add Norton exclusions** for the project folder, `~/.m2`, the JDK folder, and
   `java.exe`/`javaw.exe`. On a MITM/AV machine this is usually the single largest speedup.
2. **Build once, run the jar** — see `run-fast.ps1` below (removes per-launch compile/resolve).
3. **Maven offline** — `.\mvnw.cmd -o ...` (or `run-fast.ps1 -Offline`) skips remote metadata
   checks once `~/.m2` is populated.
4. **Skip the STS preflight** when not testing Bedrock (use `run-fast.ps1`, or `run-dev.sh` which
   has no STS check).
5. **Cut the entity diff** once the schema is stable: `spring.jpa.hibernate.ddl-auto=none`.
   Caveat: `SchemaPatchRunner` assumes `ddl-auto=update` created the entity tables, so only do
   this against an already-migrated DB — otherwise new tables won't be created.

## `run-fast.ps1`

Added at `backend/core/run-fast.ps1`. It builds the executable fat jar
(`target\careconnect-backend-0.0.1-SNAPSHOT.jar`) only when a `src\main` file or `pom.xml` is
newer than the jar (or `-Build` is passed), then launches with `java -jar`.

> **Build profile gotcha:** the default `mvn package` activates the `assembly-zip` /
> `assembly-zip-dev` profiles (`pom.xml`, both `activeByDefault=true`), which **disable
> spring-boot repackage** and produce a Lambda zip + `lib/` instead of a runnable jar — so
> `java -jar target\...jar` fails with "Unable to access jarfile". The build must use
> **`-Pdocker`** (`pom.xml:972`), which re-enables `jar` + `repackage` and skips the zip.
> Activating any `-P` profile also deactivates the two `activeByDefault` ones. `run-fast.ps1`
> passes `-Pdocker` for this reason. It keeps the same env
wiring as `run-local-bedrock.ps1` (AWS `careconnect` profile + region, Norton truststore/CA
bundle, `SERVER_PORT=8081`, dev profile). `.env` is still auto-loaded by Spring via
`spring.config.import=optional:file:.env[.properties]` (`application-dev.properties:4`).

Usage (from `backend/core`):
```powershell
docker compose -f pg_docker/docker-compose.yml up -d postgres   # if DB not already up
.\run-fast.ps1            # reuse jar if up to date, else build once, then run
.\run-fast.ps1 -Build     # force a rebuild first
.\run-fast.ps1 -Offline   # Maven offline build (after ~/.m2 is populated)
```

Trade-offs:
- First run still does a full `package` (downloads deps, compiles); the payoff is every run after.
- No `aws sts` preflight — bad Bedrock creds surface in the app log, not upfront. Use
  `run-local-bedrock.ps1` when you want the fail-fast credential check.
- `-Ddependency-check.skip=true` guards against the OWASP plugin (`autoUpdate=true` in `pom.xml`)
  running during `package`.
- Does not start Postgres — start the container first.

`run-fast.ps1` only removes the Maven build overhead. Causes 2, 3, and 5 above still apply to
every boot; Norton exclusions (mitigation 1) remain the other major lever.

## Key references
- `backend/core/run-local-bedrock.ps1` — the original launcher (env wiring + STS preflight)
- `backend/core/run-fast.ps1` — the fast launcher added here
- `backend/core/run-dev.sh` — Git Bash launcher; auto-starts Postgres, no STS check
- `backend/core/src/main/resources/application-dev.properties` — dev profile config
- `backend/core/pg_docker/.env` — `POSTGRES_PORT=5433`
