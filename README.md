# Branch Loan API - Production-Ready DevOps Setup

A containerized microloans REST API with multi-environment support, CI/CD pipeline, and HTTPS security.

# 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Architecture](#-architecture)
- [Environment Configuration](#-environment-configuration)
- [Local Development](#-local-development)
- [CI/CD Pipeline](#-cicd-pipeline)
- [API Documentation](#-api-documentation)
- [Troubleshooting](#-troubleshooting)
- [Design Decisions](#-design-decisions)

## 🚀 Quick Start

# Prerequisites

- Docker (20.10+) and Docker Compose (v2.0+)
- Git
- 4GB RAM minimum

# Running Locally (Development)

```bash
# 1. Clone the repository
git clone https://github.com/navigill7/dummy-branch-app
cd dummy-branch-app

# 2. Add branchloans.com to your hosts file
echo "127.0.0.1 branchloans.com" | sudo tee -a /etc/hosts

# On Windows (as Administrator):
# echo 127.0.0.1 branchloans.com >> C:\Windows\System32\drivers\etc\hosts

# 3. Generate SSL certificates (self-signed)
mkdir -p docker/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout docker/certs/branchloans.key \
  -out docker/certs/branchloans.crt \
  -subj "/CN=branchloans.com/O=BranchLocal"

# 4. Start the application in development mode
docker compose --env-file .env.dev up -d --build

# 5. Run database migrations
docker compose --env-file .env.dev exec api alembic upgrade head

# 6. Seed dummy data
docker compose --env-file .env.dev exec api python scripts/seed.py

# 7. Access the application
# Visit: https://branchloans.com
# (Accept the self-signed certificate warning in your browser)

# Test the API
curl -k https://branchloans.com/health
curl -k https://branchloans.com/api/loans
```

## 🏗️ Architecture

<img width="1225" height="777" alt="image" src="https://github.com/user-attachments/assets/8a68c5d3-ab9d-4f34-b507-b4c82d2a1b0a" />

### Container Communication Flow

1. **Client Request** → Browser sends HTTPS request to branchloans.com:443
2. **Nginx** → Terminates SSL, forwards to API container via HTTP
3. **API** → Processes request, queries PostgreSQL on internal network
4. **PostgreSQL** → Returns data to API container
5. **Response** → API → Nginx → Client (encrypted via HTTPS)

## 🔧 Environment Configuration

### Available Environments

| Environment | Port | Database | Logging | Resource Limits | Persistence |
|------------|------|----------|---------|-----------------|-------------|
| **Development** | 8000 | postgres/postgres | DEBUG | 0.5 CPU / 512M RAM | No |
| **Staging** | 8080 | staging_user/staging_pass | INFO | 1.0 CPU / 1G RAM | No |
| **Production** | 80 | prod_user/supersecurepass | WARNING | 2.0 CPU / 2G RAM | Yes |

### Environment Variables

#### Common Variables (`.env.common`)
```bash
POSTGRES_USER         # Database username
POSTGRES_PASSWORD     # Database password
POSTGRES_DB          # Database name
DATABASE_URL         # Full connection string
PORT                 # API port
PYTHONPATH           # Python module path
```

#### Environment-Specific Variables
```bash
COMPOSE_PROJECT_NAME # Unique project identifier per environment
DB_PORT             # Host port for PostgreSQL
API_PORT            # Host port for API
FLASK_ENV           # Flask environment mode
LOG_LEVEL           # Logging level (DEBUG/INFO/WARNING)
DB_CPU_LIMIT        # CPU limit for database
DB_MEM_LIMIT        # Memory limit for database
API_CPU_LIMIT       # CPU limit for API
API_MEM_LIMIT       # Memory limit for API
DB_VOLUME           # Volume name for persistence ("none" for no persistence)
```

### Switching Between Environments

```bash
# Development
docker compose --env-file .env.dev up -d

# Staging
docker compose --env-file .env.stage up -d

# Production
docker compose --env-file .env.prod up -d

# Stop current environment before switching
docker compose --env-file .env.dev down  # Stop dev
docker compose --env-file .env.prod up -d  # Start prod
```

### Environment Differences Explained

**Development**
- Uses default credentials (postgres/postgres)
- Debug logging for detailed troubleshooting
- No volume persistence (fresh DB on restart)
- Minimal resource limits for laptop development
- Exposed on port 8000

**Staging**
- Separate credentials from dev/prod
- INFO-level logging (balance between detail and noise)
- No persistence (can reset easily for testing)
- Medium resource limits
- Exposed on port 8080
- Should mirror production configuration

**Production**
- Secure credentials (change in real deployment!)
- WARNING-level logging (only important events)
- Persistent volume (data survives container restarts)
- Higher resource limits for load
- Exposed on port 80 (behind HTTPS)

## 💻 Local Development

### Development Workflow

```bash
# Start development environment
docker compose --env-file .env.dev up -d

# View logs
docker compose --env-file .env.dev logs -f api

# Access container shell
docker compose --env-file .env.dev exec api bash

# Run migrations
docker compose --env-file .env.dev exec api alembic upgrade head

# Create new migration
docker compose --env-file .env.dev exec api alembic revision --autogenerate -m "description"

# Access database directly
docker compose --env-file .env.dev exec db psql -U postgres -d microloans

# Restart API after code changes
docker compose --env-file .env.dev restart api

# Stop all services
docker compose --env-file .env.dev down

# Stop and remove volumes
docker compose --env-file .env.dev down -v
```

### Testing API Endpoints

```bash
# Health check
curl -k https://branchloans.com/health

# List all loans
curl -k https://branchloans.com/api/loans

# Get specific loan
curl -k https://branchloans.com/api/loans/00000000-0000-0000-0000-000000000001

# Create new loan
curl -k -X POST https://branchloans.com/api/loans \
  -H 'Content-Type: application/json' \
  -d '{
    "borrower_id": "usr_test_123",
    "amount": 15000.00,
    "currency": "INR",
    "term_months": 12,
    "interest_rate_apr": 18.5
  }'

# Get statistics
curl -k https://branchloans.com/api/stats
```

## 🔄 CI/CD Pipeline

### Pipeline Overview

The GitHub Actions pipeline automates the entire build, test, and deployment process.



### Pipeline Stages

#### 1. Test Stage
- Spins up PostgreSQL service container
- Installs Python dependencies with caching
- Runs database migrations
- Executes test suite (creates basic smoke tests if none exist)
- **Fails if:** Tests fail

#### 2. Build Stage
- Uses Docker Buildx for efficient builds
- Extracts metadata (branch, SHA, tags)
- Builds Docker image
- Caches layers for faster subsequent builds
- Uploads image as artifact for next stages
- **Fails if:** Build fails

#### 3. Security Scan Stage
- Downloads built image from artifacts
- Runs Trivy vulnerability scanner
- Checks for CRITICAL and HIGH severity vulnerabilities
- Uploads results to GitHub Security tab
- **Fails if:** Critical vulnerabilities found

#### 4. Push Stage
- Only runs on push to `main` branch (not on PRs)
- Logs into GitHub Container Registry
- Tags image with:
  - Branch name
  - Git commit SHA
  - `latest` tag
- Pushes to `ghcr.io/<your-username>/<repo-name>`
- Creates build attestation for supply chain security

### Pipeline Triggers

- **Push to main:** Runs all stages including push
- **Pull Requests:** Runs test, build, and security scan (no push)

### Setting Up CI/CD

#### 1. Enable GitHub Container Registry

```bash
# Nothing to do! The pipeline uses GITHUB_TOKEN automatically
# Images will be pushed to: ghcr.io/<your-username>/branch-loan-api
```

#### 2. Repository Secrets

The pipeline uses `GITHUB_TOKEN` which is automatically provided by GitHub Actions. No manual secret setup required!

**For production deployments with Docker Hub:**

1. Go to Settings → Secrets and variables → Actions
2. Add secrets:
   - `DOCKERHUB_USERNAME`: Your Docker Hub username
   - `DOCKERHUB_TOKEN`: Docker Hub access token

Then modify `.github/workflows/ci-cd.yml`:
```yaml
- name: Log in to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}
```

#### 3. Viewing Pipeline Results

- Go to **Actions** tab in your GitHub repository
- Click on any workflow run to see details
- View security scan results in **Security** → **Code scanning**

### Security Best Practices

✅ **What the pipeline does right:**
- Never exposes credentials in logs
- Uses GitHub's automatic token for authentication
- Scans for vulnerabilities before deployment
- Only pushes images from main branch
- Uses image attestation for supply chain security

✅ **Additional recommendations:**
- Rotate credentials regularly
- Use environment-specific credentials
- Enable branch protection on main
- Require PR reviews before merge
- Use signed commits

## 📚 API Documentation

### Endpoints

#### `GET /health`
Health check endpoint.

**Response:**
```json
{
  "status": "ok"
}
```

#### `GET /api/loans`
List all loans.

**Response:**
```json
[
  {
    "id": "uuid",
    "borrower_id": "usr_india_001",
    "amount": 15000.00,
    "currency": "INR",
    "status": "pending",
    "term_months": 12,
    "interest_rate_apr": 18.50,
    "created_at": "2025-01-01T00:00:00Z",
    "updated_at": "2025-01-01T00:00:00Z"
  }
]
```

#### `GET /api/loans/:id`
Get specific loan by ID.

**Response:** Single loan object (same structure as above)

#### `POST /api/loans`
Create new loan application.

**Request:**
```json
{
  "borrower_id": "usr_india_123",
  "amount": 15000.00,
  "currency": "INR",
  "term_months": 12,
  "interest_rate_apr": 18.50
}
```

**Validation Rules:**
- `amount`: 0 < amount ≤ 50,000
- `currency`: 3-character code (e.g., INR, USD)
- `term_months`: ≥ 1
- `interest_rate_apr`: 0 ≤ rate ≤ 100

**Response:** Created loan object with `201` status

#### `GET /api/stats`
Get loan statistics.

**Response:**
```json
{
  "total_loans": 25,
  "total_amount": 450000.00,
  "avg_amount": 18000.00,
  "by_status": {
    "pending": 5,
    "approved": 10,
    "disbursed": 8,
    "repaid": 2
  },
  "by_currency": {
    "INR": 15,
    "USD": 10
  }
}
```

## 🔍 Troubleshooting

### Common Issues

#### 1. "Connection refused" when accessing branchloans.com

**Cause:** Domain not added to hosts file

**Solution:**
```bash
# Linux/Mac
echo "127.0.0.1 branchloans.com" | sudo tee -a /etc/hosts

# Windows (as Administrator)
echo 127.0.0.1 branchloans.com >> C:\Windows\System32\drivers\etc\hosts
```

#### 2. SSL Certificate Warning in Browser

**Cause:** Self-signed certificate not trusted

**Solution:** This is expected for local development. Click "Advanced" → "Proceed to branchloans.com" in your browser. For curl, use `-k` flag.

**For production:** Use Let's Encrypt or a commercial CA for trusted certificates.

#### 3. "Port already in use" Error

**Cause:** Another service using the same port

**Solution:**
```bash
# Check what's using the port
sudo lsof -i :8000  # or :443, :80, etc.

# Either stop that service or change ports in .env file
# Edit .env.dev and change API_PORT or DB_PORT
```

#### 4. Database Connection Failed

**Cause:** Database not ready when API starts

**Solution:** The startup script waits for PostgreSQL, but you can manually check:
```bash
# Check database health
docker compose --env-file .env.dev exec db pg_isready -U postgres

# View database logs
docker compose --env-file .env.dev logs db

# Restart API
docker compose --env-file .env.dev restart api
```

#### 5. Migrations Not Applied

**Symptom:** "Table 'loans' doesn't exist" error

**Solution:**
```bash
# Apply migrations
docker compose --env-file .env.dev exec api alembic upgrade head

# Check migration status
docker compose --env-file .env.dev exec api alembic current
```

#### 6. Changes Not Reflected After Code Update

**Cause:** Container needs rebuild

**Solution:**
```bash
# Rebuild and restart
docker compose --env-file .env.dev up -d --build

# Or force recreation
docker compose --env-file .env.dev up -d --force-recreate
```

#### 7. Volume Permissions Issues (Linux)

**Cause:** Docker volume ownership mismatch

**Solution:**
```bash
# Reset volumes
docker compose --env-file .env.dev down -v
docker compose --env-file .env.dev up -d
```

### Health Checks

```bash
# 1. Check all containers are running
docker compose --env-file .env.dev ps

# 2. Check API health
curl -k https://branchloans.com/health

# 3. Check database connection
docker compose --env-file .env.dev exec db psql -U postgres -d microloans -c "SELECT 1;"

# 4. Check nginx configuration
docker compose --env-file .env.dev exec nginx nginx -t

# 5. View application logs
docker compose --env-file .env.dev logs -f api

# 6. Check resource usage
docker stats
```

### Debug Mode

Enable detailed logging:
```bash
# Set LOG_LEVEL=DEBUG in .env.dev (already default)
docker compose --env-file .env.dev restart api
docker compose --env-file .env.dev logs -f api
```

## 📖 Design Decisions

### 1. Multi-Stage Docker Build

**Decision:** Use multi-stage Dockerfile

**Rationale:**
- Separates build dependencies from runtime
- Reduces final image size (~200MB vs ~400MB)
- Faster deployments and pulls
- Security: fewer packages = smaller attack surface

**Trade-offs:**
- Slightly more complex Dockerfile
- Longer initial build time (but cached well)

### 2. Docker Compose for Multi-Environment

**Decision:** Single docker-compose.yml with environment-specific .env files

**Rationale:**
- DRY principle: one compose file to maintain
- Easy to switch: `--env-file .env.stage`
- Clear separation of config from infrastructure
- Same structure works locally and in CI

**Trade-offs:**
- Must remember to specify env file
- Could use docker-compose.override.yml but less explicit

**Alternatives considered:**
- Separate compose files per environment (too much duplication)
- Environment variables only (harder to manage)

### 3. GitHub Container Registry

**Decision:** Use ghcr.io instead of Docker Hub

**Rationale:**
- Free unlimited private repositories
- Automatic authentication via GITHUB_TOKEN
- Integrated with GitHub (no external account needed)
- Better for open-source and private projects

**Trade-offs:**
- Less well-known than Docker Hub
- GitHub dependency

### 4. Trivy for Security Scanning

**Decision:** Use Aqua Trivy for vulnerability scanning

**Rationale:**
- Free and open-source
- Comprehensive: OS and language-level vulnerabilities
- Fast scanning (~30 seconds)
- GitHub Security integration (SARIF format)
- Actively maintained

**Alternatives considered:**
- Snyk (requires account, paid for advanced features)
- Clair (more complex setup)

### 5. Self-Signed SSL for Local Development

**Decision:** Generate self-signed certificates

**Rationale:**
- Works offline
- No cost or external dependencies
- Good enough for local HTTPS testing
- Easy to generate with openssl

**For production:** Use Let's Encrypt with certbot for free, trusted certificates

### 6. Gunicorn as WSGI Server

**Decision:** Use Gunicorn instead of Flask development server

**Rationale:**
- Production-ready
- Multi-worker support
- Better performance
- Handles concurrent requests
- Industry standard

### 7. Volume Strategy

**Decision:** Production uses persistent volume, dev/staging don't

**Rationale:**
- **Dev/Staging:** Fresh data on restart aids testing
- **Production:** Data must persist across deployments
- Easy to switch: DB_VOLUME environment variable

## 📊 Monitoring & Observability

The Branch Loan API includes a comprehensive monitoring stack with structured logging, Prometheus metrics, and Grafana dashboards.

### Quick Start with Monitoring

```bash
# Automated setup (recommended)
chmod +x scripts/setup_monitoring.sh
./scripts/setup_monitoring.sh

# Or manual setup
docker compose --env-file .env.dev up -d
docker compose --env-file .env.dev exec api alembic upgrade head
docker compose --env-file .env.dev exec api python scripts/seed.py
```

### Access Monitoring Tools

| Tool | URL | Credentials |
|------|-----|-------------|
| **Grafana Dashboard** | http://localhost:3000 | admin / admin |
| **Prometheus** | http://localhost:9090 | No auth |
| **API Metrics** | https://branchloans.com/metrics | No auth |

### Key Features

#### 1. Structured JSON Logging

All logs are output in JSON format with contextual information:

```json
{
  "timestamp": "2025-11-06T10:30:45.123456Z",
  "level": "INFO",
  "message": "Request completed",
  "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "method": "POST",
  "path": "/api/loans",
  "status_code": 201,
  "duration_ms": 45.67
}
```

**View formatted logs:**
```bash
docker compose --env-file .env.dev logs api | grep -o '{.*}' | jq .
```

#### 2. Prometheus Metrics

Available metrics include:

- **HTTP Metrics**: Request count, duration, errors, in-progress requests
- **Business Metrics**: Loans created, loan amounts, active loans by status
- **System Metrics**: Database connections, error rates

**Example queries:**
```promql
# Request rate (requests/second)
rate(http_requests_total[5m])

# 95th percentile response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Loan creation rate
rate(loans_created_total[5m])
```

#### 3. Grafana Dashboard

Pre-configured dashboard showing:

- ✅ Request rate and response times
- ✅ HTTP status code distribution
- ✅ Active loans by status
- ✅ Error rates and trends
- ✅ Business metrics (loan creation, amounts)

**Access Dashboard:**
1. Go to http://localhost:3000
2. Login with admin/admin
3. Navigate to: Dashboards → Branch Loan API - Monitoring Dashboard

#### 4. Enhanced Health Checks

Three health check endpoints for different purposes:

```bash
# Comprehensive health check (verifies DB connectivity)
curl -k https://branchloans.com/health

# Kubernetes-style readiness probe
curl -k https://branchloans.com/readiness

# Kubernetes-style liveness probe
curl -k https://branchloans.com/liveness
```

**Response example:**
```json
{
  "status": "ok",
  "timestamp": 1699276800.123,
  "checks": {
    "api": {"status": "healthy", "message": "API service is running"},
    "database": {"status": "healthy", "message": "Database connection successful"}
  }
}
```

### Generate Test Data

Create test traffic to populate metrics:

```bash
# Create sample loans
for i in {1..10}; do
  curl -k -X POST https://branchloans.com/api/loans \
    -H 'Content-Type: application/json' \
    -d "{
      \"borrower_id\": \"test_user_$i\",
      \"amount\": $((10000 + RANDOM % 40000)),
      \"currency\": \"INR\",
      \"term_months\": 12,
      \"interest_rate_apr\": 18.5
    }"
done

# Generate API traffic
for i in {1..50}; do
  curl -k https://branchloans.com/api/loans > /dev/null 2>&1
  sleep 0.1
done
```

### Monitoring Architecture

<img width="1005" height="693" alt="image" src="https://github.com/user-attachments/assets/612d588a-67b6-46b2-85ab-4a4cf4a30146" />

### Log Levels by Environment

| Environment | LOG_LEVEL | Usage |
|------------|-----------|-------|
| Development | DEBUG | Detailed debugging, all requests logged |
| Staging | INFO | General info, important events |
| Production | WARNING | Only warnings and errors |

### Request Tracing

Every request gets a unique ID for end-to-end tracing:

```bash
# Make request and capture Request ID
RESPONSE=$(curl -i -k https://branchloans.com/api/loans)
REQUEST_ID=$(echo "$RESPONSE" | grep -i x-request-id | cut -d' ' -f2)

# Find all logs for this specific request
docker compose --env-file .env.dev logs api | grep "$REQUEST_ID"
```

### Monitoring Best Practices

1. **Set up alerts** for critical metrics (error rate, response time)
2. **Monitor trends** over time to identify performance degradation
3. **Use request IDs** for debugging production issues
4. **Review logs regularly** to catch issues early
5. **Track business metrics** (loan creation rate, amounts) alongside technical metrics

### Stopping Monitoring Stack

```bash
# Stop all services
docker compose --env-file .env.dev down

# Stop and remove volumes (clean slate)
docker compose --env-file .env.dev down -v
```

### Detailed Documentation

For comprehensive monitoring documentation, see **[MONITORING.md](MONITORING.md)**:

- Complete metrics reference
- Prometheus query examples
- Grafana dashboard customization
- Troubleshooting guide
- Production best practices

---

**Continue to the next section: [API Documentation](#-api-documentation)**

## 🎯 Future Improvements

Given more time, I would add:

### 1. **Hot Reload for Development**
- Mount source code as volume in dev mode
- Use Flask auto-reload or watchdog
- Faster development iteration

### 2. **Comprehensive Test Suite**
- Unit tests for models and schemas
- Integration tests for API endpoints
- End-to-end tests with test database
- Load testing with locust/k6

### 3. **Observability** (Bonus Features)
- Structured JSON logging with correlation IDs
- Prometheus metrics endpoint (/metrics)
- Grafana dashboards
- Distributed tracing with Jaeger

### 4. **Advanced Security**
- OWASP dependency check in CI
- Secret scanning with GitLeaks
- Container image signing
- Network policies and security contexts

### 5. **Production Readiness**
- Kubernetes manifests (Helm charts)
- Database backups and restore procedures
- Rolling deployments with health checks
- Auto-scaling configuration
- Rate limiting and API authentication

### 6. **Developer Experience**
- Makefile for common commands
- Pre-commit hooks (linting, formatting)
- Development containers (VS Code)
- Automated changelog generation

### 7. **Monitoring & Alerting**
- Application Performance Monitoring (APM)
- Error tracking with Sentry
- Uptime monitoring
- PagerDuty/Slack integration

### 8. **Database Optimizations**
- Connection pooling configuration
- Read replicas for scaling
- Query performance monitoring
- Automated backups to S3/GCS

## 🤝 Contributing

```bash
# 1. Fork and clone
git clone .....

# 2. Create feature branch
git checkout -b feature/amazing-feature

# 3. Make changes and test locally
docker compose --env-file .env.dev up -d --build

# 4. Commit with conventional commits
git commit -m "feat: add amazing feature"

# 5. Push and create PR
git push origin feature/amazing-feature
```

## 📝 License

This project is for educational purposes as part of Branch's DevOps Intern assignment.

## 🙏 Acknowledgments

- Branch's DevOps team for the assignment
- Flask and SQLAlchemy communities
- Docker and GitHub Actions documentation

---

**Built with ❤️ for Branch's DevOps Intern Assignment 2025**
