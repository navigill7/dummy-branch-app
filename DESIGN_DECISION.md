# Design Decisions & Trade-offs

This document explains the key architectural and implementation decisions made during this project.

## 1. Containerization Strategy

### Multi-Stage Docker Build

**Decision:** Implemented a two-stage Dockerfile with separate build and runtime stages.

**Rationale:**
- **Security:** Build tools and compilers are not included in the final image, reducing the attack surface
- **Size Optimization:** Final image is ~200MB vs ~400MB with single-stage
- **Dependency Separation:** Build dependencies (gcc, build-essential) are isolated from runtime
- **Cache Efficiency:** Python packages are cached in the build stage, speeding up subsequent builds

**Implementation:**
```dockerfile
FROM python:3.11-slim AS base
# Install build dependencies
# Install Python packages

FROM python:3.11-slim
# Copy only built packages from base
# Add runtime dependencies only
```

**Trade-offs:**
- ✅ Smaller, more secure images
- ✅ Faster deployments
- ❌ Slightly more complex Dockerfile
- ❌ Initial build takes longer (but subsequent builds are fast due to caching)

### Container Startup Order

**Decision:** Use health checks and dependency conditions in docker-compose

**Rationale:**
- PostgreSQL must be fully ready before API starts
- `depends_on` with `condition: service_healthy` ensures proper startup order
- Custom `start_api.sh` script adds additional verification

**Implementation:**
```yaml
depends_on:
  db:
    condition: service_healthy
```

**Alternative Considered:**
- Sleep timers: Too fragile and unpredictable
- No dependency management: Would cause intermittent failures

---

## 2. Multi-Environment Configuration

### Single Compose File + Environment Files

**Decision:** One `docker-compose.yml` with multiple `.env` files (`.env.dev`, `.env.stage`, `.env.prod`)

**Rationale:**
- **DRY Principle:** Infrastructure definition is maintained in one place
- **Clarity:** Environment differences are explicit in separate files
- **Simplicity:** Easy to switch environments: `--env-file .env.stage`
- **No Duplication:** Changes to services automatically apply to all environments
- **Version Control:** .env files can be committed (for non-production secrets)

**Trade-offs:**
- ✅ Single source of truth
- ✅ Easy to compare environment differences
- ❌ Must remember to specify `--env-file`
- ❌ All environments must use same service structure

**Alternatives Considered:**

1. **Separate Compose Files per Environment**
   - ❌ Too much duplication
   - ❌ Changes need to be made in 3 places
   - ✅ More explicit, harder to mix up environments

2. **Docker Compose Override Files**
   - ❌ Less explicit about which overrides apply
   - ❌ Harder to understand full configuration
   - ✅ Standard Docker Compose pattern

3. **Environment Variables Only (no .env files)**
   - ❌ Harder to manage many variables
   - ❌ No documentation of expected values
   - ✅ More "cloud-native"

### Environment-Specific Configurations

| Configuration | Development | Staging | Production |
|--------------|-------------|---------|------------|
| **Credentials** | Default (postgres/postgres) | Staging-specific | Secure credentials |
| **Logging** | DEBUG | INFO | WARNING |
| **Persistence** | No volume | No volume | Persistent volume |
| **Resources** | Minimal (0.5 CPU, 512M) | Medium (1 CPU, 1G) | Production (2 CPU, 2G) |
| **Port** | 8000 | 8080 | 80 |

**Rationale for Differences:**

**Development:**
- Default credentials for quick setup
- Debug logging to help developers troubleshoot
- No persistence so developers start fresh easily
- Minimal resources to run on laptops

**Staging:**
- Separate credentials to catch config issues
- INFO logging (balance between detail and noise)
- No persistence to easily reset for testing
- Should mirror production as closely as possible
- Different port to run alongside dev

**Production:**
- Secure credentials (should be in secrets management in real deployment)
- WARNING-level logging (only important events)
- Persistent data (critical for production)
- Higher resources for production load
- Standard HTTP port (80) behind HTTPS

---

## 3. SSL/HTTPS Implementation

### Nginx as Reverse Proxy

**Decision:** Use Nginx for SSL termination instead of handling SSL in Flask

**Rationale:**
- **Industry Standard:** Nginx is battle-tested for SSL termination
- **Performance:** Nginx handles SSL more efficiently than Python
- **Separation of Concerns:** Flask focuses on business logic, Nginx handles networking
- **Flexibility:** Easy to add caching, load balancing, rate limiting later
- **Security:** Centralized SSL configuration and cipher management

**Implementation:**
```
Client (HTTPS) → Nginx (SSL termination) → Flask (HTTP)
```

**Trade-offs:**
- ✅ Better performance and security
- ✅ Industry best practice
- ❌ Additional container to manage
- ❌ Slightly more complex setup

**Alternative Considered:**
- Flask with SSL: Possible but not recommended for production

### Self-Signed Certificates for Local Development

**Decision:** Generate self-signed certificates with OpenSSL

**Rationale:**
- **Offline Development:** Works without internet connection
- **Zero Cost:** No need for paid certificates or rate-limited free services
- **Good Enough:** Tests HTTPS functionality locally
- **Simple:** Single OpenSSL command to generate

**Production Recommendation:** Use Let's Encrypt with Certbot for free, trusted certificates

---

## 4. CI/CD Pipeline Architecture

### GitHub Actions

**Decision:** Use GitHub Actions for CI/CD pipeline

**Rationale:**
- **Native Integration:** Built into GitHub, no external account needed
- **Free for Public Repos:** Unlimited minutes for public repositories
- **YAML Configuration:** Easy to version control and review
- **Rich Ecosystem:** Thousands of pre-built actions available
- **GitHub Container Registry:** Seamless authentication with `GITHUB_TOKEN`

**Alternatives Considered:**
- **Jenkins:** Too heavy for this use case, requires separate server
- **GitLab CI:** Would require moving to GitLab
- **CircleCI:** Requires external account, limited free tier

### Pipeline Stages

**Decision:** Four-stage pipeline: Test → Build → Security Scan → Push

**Rationale:**

1. **Test First:** Fail fast if code is broken, save compute time
2. **Build:** Only build if tests pass
3. **Security Scan:** Catch vulnerabilities before pushing
4. **Push:** Only push verified, scanned images

**Sequential vs. Parallel:**
- Stages run sequentially to fail fast
- Within stages, parallelization is used where possible (e.g., multiple tests)

### Security Scanning with Trivy

**Decision:** Use Aqua Trivy for container vulnerability scanning

**Rationale:**
- **Comprehensive:** Scans OS packages and application dependencies
- **Fast:** Completes in ~30 seconds
- **Free & Open Source:** No licensing costs
- **GitHub Integration:** Uploads results to Security tab (SARIF format)
- **Fail on Critical:** Can block deployment if critical vulnerabilities found
- **Actively Maintained:** Regular database updates

**Configuration:**
```yaml
severity: 'CRITICAL,HIGH'
exit-code: '1'  # Fail pipeline on vulnerabilities
```

**Trade-offs:**
- ✅ Automated security checks
- ✅ Prevents deploying vulnerable images
- ❌ May block deployments (by design)
- ❌ Requires vulnerability remediation workflow

**Alternatives Considered:**
- **Snyk:** Requires account, paid for teams
- **Clair:** More complex setup
- **Docker Scout:** Newer, less mature

### Container Registry Choice

**Decision:** Use GitHub Container Registry (ghcr.io)

**Rationale:**
- **Free Unlimited Private Repos:** No storage limits for private images
- **Automatic Authentication:** Uses `GITHUB_TOKEN`, no manual secrets
- **Single Platform:** Code, CI/CD, and registry in one place
- **Good for OSS:** Public images are free and unlimited
- **Build Attestation:** Supports supply chain security features

**Trade-offs:**
- ✅ Zero configuration for authentication
- ✅ Unlimited storage
- ❌ Less known than Docker Hub
- ❌ GitHub dependency

**For Docker Hub:**
```yaml
# Would require manual secrets:
# DOCKERHUB_USERNAME
# DOCKERHUB_TOKEN
```

---

## 5. Database Strategy

### PostgreSQL Choice

**Decision:** Use PostgreSQL as the database

**Rationale:**
- **Production-Ready:** Industry standard for microservices
- **ACID Compliance:** Ensures data integrity for financial data
- **JSON Support:** Can store semi-structured data if needed later
- **Rich Extensions:** PostGIS, full-text search, etc.
- **Docker Official Image:** Well-maintained, optimized

**Alternatives Considered:**
- **MySQL:** Comparable, but PostgreSQL has better JSON support
- **SQLite:** Not suitable for production microservices
- **MongoDB:** Overkill for this structured data

### Migration Strategy with Alembic

**Decision:** Use Alembic for database migrations

**Rationale:**
- **Version Control for Schema:** Migrations are code
- **Rollback Support:** Can undo changes if needed
- **Team Collaboration:** Multiple developers can work on schema
- **Autogenerate:** Can detect model changes automatically
- **SQLAlchemy Integration:** Works seamlessly with our ORM

**Implementation:**
```bash
alembic upgrade head  # Apply all migrations
alembic revision --autogenerate -m "add column"  # Create new migration
```

### Persistence Strategy

**Decision:** Conditional persistence based on environment

**Rationale:**

**Development/Staging (No Persistence):**
- Fresh start on each restart aids testing
- No old data interfering with development
- Faster iterations (no need to clean up data)

**Production (Persistent Volume):**
- Data must survive container restarts
- Deployments don't lose data
- Backup and restore possible

**Implementation:**
```yaml
volumes:
  - type: volume
    source: ${DB_VOLUME:-none}  # "none" or "db_data_prod"
```

---

## 6. Application Architecture

### Flask + Gunicorn

**Decision:** Use Flask as framework with Gunicorn as WSGI server

**Rationale:**

**Flask:**
- Lightweight and flexible
- Perfect for microservices
- Rich ecosystem (SQLAlchemy, Alembic, etc.)
- Easy to understand and maintain

**Gunicorn:**
- Production-ready WSGI server
- Multi-worker support (handles concurrent requests)
- Better performance than Flask dev server
- Industry standard

**Configuration:**
```bash
gunicorn -w 2 -b 0.0.0.0:8000 wsgi:app
# 2 workers = good for small services
# More workers = better concurrency but more memory
```

**Trade-offs:**
- ✅ Production-ready
- ✅ Good performance
- ❌ No auto-reload in production (by design)

**Alternatives Considered:**
- **uWSGI:** More features but more complex
- **Flask dev server:** Not production-ready
- **Uvicorn/FastAPI:** Modern but Flask is more established

### Blueprint Architecture

**Decision:** Organize routes using Flask Blueprints

**Rationale:**
- **Modularity:** Each feature in separate file
- **Scalability:** Easy to add new endpoints
- **Testing:** Can test blueprints in isolation
- **Clarity:** Clear separation of concerns

**Structure:**
```
app/routes/
  ├── health.py    # Health checks
  ├── loans.py     # CRUD operations
  └── stats.py     # Analytics
```

### Pydantic for Validation

**Decision:** Use Pydantic for request/response validation

**Rationale:**
- **Type Safety:** Catch errors at validation time
- **Clear Schemas:** Self-documenting API
- **Automatic Validation:** No manual type checking
- **JSON Serialization:** Easy conversion to/from JSON

**Example:**
```python
class CreateLoanRequest(BaseModel):
    amount: condecimal(gt=0, le=50000)  # Automatic validation
```

---

## 7. Secrets Management

### Development vs. Production

**Decision:** Different approaches for dev and prod

**Development:**
- Commit `.env.dev` to repository
- Use default credentials
- Focus on ease of setup

**Production:**
- DO NOT commit `.env.prod` with real secrets
- Use environment variables or secrets management
- Separate secrets per environment

**Best Practices Implemented:**

1. **GitHub Actions:** Uses `GITHUB_TOKEN` (automatically provided)
2. **No Hardcoded Secrets:** All credentials in environment variables
3. **Clear Documentation:** README explains how to handle secrets

**For Real Production:**
- Use AWS Secrets Manager, HashiCorp Vault, or similar
- Rotate credentials regularly
- Use principle of least privilege
- Enable audit logging

---

## 8. Resource Management

### CPU and Memory Limits

**Decision:** Set explicit resource limits in docker-compose

**Rationale:**
- **Prevent Resource Exhaustion:** One container can't consume all resources
- **Predictable Performance:** Consistent behavior across environments
- **Cost Control:** Important in cloud environments
- **Production Sizing:** Forces consideration of actual needs

**Configuration:**
```yaml
deploy:
  resources:
    limits:
      cpus: "${DB_CPU_LIMIT}"  # 0.5 (dev) to 2.0 (prod)
      memory: "${DB_MEM_LIMIT}"  # 512M (dev) to 2G (prod)
```

**Trade-offs:**
- ✅ Prevents runaway processes
- ✅ Production-like constraints in dev
- ❌ May need tuning based on load
- ❌ Limits may be too restrictive or too lenient

---

## 9. Logging Strategy

### Environment-Based Log Levels

**Decision:** Different log levels per environment

| Environment | Level | Rationale |
|------------|-------|-----------|
| Development | DEBUG | See everything for troubleshooting |
| Staging | INFO | Balance detail and noise |
| Production | WARNING | Only important events |

**Rationale:**
- **Development:** Need maximum detail for debugging
- **Staging:** Test production-like logging without overwhelming output
- **Production:** Reduce noise, focus on problems

**Future Improvement:** Structured JSON logging with:
- Timestamps
- Correlation IDs
- Context (user, request)
- Centralized logging (ELK, DataDog)

---

## 10. Testing Strategy

### Basic Smoke Tests

**Decision:** Create minimal tests in CI pipeline if none exist

**Rationale:**
- **Fail Safe:** Pipeline won't break if tests are missing
- **Example for Developers:** Shows what tests should look like
- **CI/CD Requirement:** Test stage should always do something

**Implementation:**
```python
def test_health_endpoint(client):
    response = client.get('/health')
    assert response.status_code == 200
```

**Future Improvements:**
- Unit tests for models and business logic
- Integration tests with test database
- End-to-end tests with full stack
- Load testing (locust, k6)
- Contract testing for APIs

---

## What Would I Do Differently with More Time?

### 1. **Kubernetes Instead of Docker Compose**
- More production-realistic
- Better scaling and orchestration
- Helm charts for configuration
- But: More complex for 4-6 hour assignment

### 2. **Infrastructure as Code**
- Terraform for cloud resources
- Automated cloud deployment
- Environment provisioning
- But: Outside scope of assignment

### 3. **Comprehensive Monitoring**
- Prometheus + Grafana stack
- Application metrics
- Distributed tracing
- But: Significant additional time

### 4. **Advanced Security**
- mTLS between services
- Network policies
- Pod security policies
- Secret scanning in commits
- But: Complex to set up properly

### 5. **Blue-Green or Canary Deployments**
- Zero-downtime deployments
- Gradual rollouts
- Automatic rollback
- But: Requires orchestration platform

### 6. **Database Backups**
- Automated backup schedule
- Point-in-time recovery
- Off-site backup storage
- But: Production concern, not needed for demo

---

## Key Takeaways

### What Went Well

1. **Multi-environment support** works smoothly with single compose file
2. **CI/CD pipeline** is comprehensive and secure
3. **HTTPS setup** mimics production while keeping development simple
4. **Documentation** is thorough and includes troubleshooting

### What I Learned

1. Balancing simplicity vs. production-readiness is challenging
2. Self-signed certificates are good enough for local HTTPS
3. GitHub Container Registry is underrated
4. Resource limits are important even in development

### If Starting Over

1. Would consider Kubernetes from the start if aiming for "production-ready"
2. Might use Makefile earlier to simplify commands
3. Would set up pre-commit hooks for code quality
4. Could explore DevContainers for consistent dev environment

---

**This design prioritizes:**
- ✅ Production-like architecture
- ✅ Developer experience
- ✅ Security best practices
- ✅ Clear documentation
- ✅ Practical trade-offs for a 4-6 hour assignment