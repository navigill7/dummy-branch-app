# Monitoring & Observability Guide

This guide covers the complete monitoring setup for the Branch Loan API, including structured logging, Prometheus metrics, and Grafana dashboards.

## 📊 Table of Contents

- [Overview](#overview)
- [Components](#components)
- [Quick Start](#quick-start)
- [Structured Logging](#structured-logging)
- [Prometheus Metrics](#prometheus-metrics)
- [Grafana Dashboards](#grafana-dashboards)
- [Health Checks](#health-checks)
- [Troubleshooting](#troubleshooting)

## Overview

The monitoring stack consists of three main components:

1. **Structured JSON Logging** - Context-rich logs with request tracing
2. **Prometheus Metrics** - Time-series metrics for performance monitoring
3. **Grafana Dashboards** - Visual representation of metrics

### Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────┐     Logs        ┌─────────────┐
│  Flask API  ├────────────────▶│   stdout    │
│             │                  └─────────────┘
│             │     Metrics
│             ├────────────────▶ /metrics
└──────┬──────┘
       │
       │ Scrape
       ▼
┌─────────────┐
│ Prometheus  │
└──────┬──────┘
       │
       │ Query
       ▼
┌─────────────┐
│   Grafana   │
└─────────────┘
```

## Components

### 1. Flask API
- **Port**: 8000
- **Endpoints**:
  - `/health` - Enhanced health check with DB verification
  - `/readiness` - Kubernetes-style readiness probe
  - `/liveness` - Kubernetes-style liveness probe
  - `/metrics` - Prometheus metrics endpoint

### 2. Prometheus
- **Port**: 9090
- **UI**: http://localhost:9090
- **Scrape Interval**: 10 seconds
- **Retention**: 15 days (default)

### 3. Grafana
- **Port**: 3000
- **UI**: http://localhost:3000
- **Default Credentials**: admin / admin
- **Pre-configured**: Datasource and dashboard automatically loaded

## Quick Start

### 1. Start the Monitoring Stack

```bash
# Start all services including monitoring
docker compose --env-file .env.dev up -d

# Verify all containers are running
docker compose --env-file .env.dev ps

# Expected output:
# NAME                         STATUS
# branch-dev_api               Up
# branch-dev_db                Up (healthy)
# branch-dev_nginx             Up
# branch-dev_prometheus        Up
# branch-dev_grafana           Up
```

### 2. Access Monitoring UIs

**Grafana Dashboard** (Recommended starting point)
- URL: http://localhost:3000
- Username: `admin`
- Password: `admin`
- Navigate to: Dashboards → Branch Loan API - Monitoring Dashboard

**Prometheus**
- URL: http://localhost:9090
- Try queries like:
  - `rate(http_requests_total[5m])`
  - `http_request_duration_seconds`
  - `active_loans`

**API Metrics Endpoint**
```bash
# View raw Prometheus metrics
curl -k https://branchloans.com/metrics

# Or via localhost
curl http://localhost:8000/metrics
```

### 3. Generate Test Traffic

```bash
# Create some loans to generate metrics
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
  sleep 1
done

# List loans repeatedly to generate traffic
for i in {1..20}; do
  curl -k https://branchloans.com/api/loans > /dev/null 2>&1
  sleep 0.5
done

# Check stats endpoint
curl -k https://branchloans.com/api/stats
```

## Structured Logging

### Log Format

All logs are output in JSON format with the following structure:

```json
{
  "timestamp": "2025-11-06T10:30:45.123456Z",
  "level": "INFO",
  "logger": "branch.api",
  "message": "Request completed",
  "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "method": "POST",
  "path": "/api/loans",
  "status_code": 201,
  "duration_ms": 45.67,
  "ip": "172.18.0.1"
}
```

### Log Levels by Environment

| Environment | Log Level | Purpose |
|------------|-----------|---------|
| Development | DEBUG | Detailed debugging information |
| Staging | INFO | General informational messages |
| Production | WARNING | Only warnings and errors |

### Viewing Logs

```bash
# View all API logs
docker compose --env-file .env.dev logs -f api

# View logs with jq for better formatting
docker compose --env-file .env.dev logs api | grep -o '{.*}' | jq .

# Filter by log level
docker compose --env-file .env.dev logs api | grep -o '{.*}' | jq 'select(.level == "ERROR")'

# Filter by request ID (for tracing a specific request)
docker compose --env-file .env.dev logs api | grep -o '{.*}' | jq 'select(.request_id == "YOUR-REQUEST-ID")'
```

### Request Tracing

Every request gets a unique `request_id` that's:
1. Logged in all related log entries
2. Returned in the `X-Request-ID` response header
3. Used for end-to-end request tracing

**Example: Trace a specific request**

```bash
# Make a request and capture the request ID
RESPONSE=$(curl -i -k https://branchloans.com/api/loans)
REQUEST_ID=$(echo "$RESPONSE" | grep -i x-request-id | cut -d' ' -f2 | tr -d '\r')

# View all logs for this request
docker compose --env-file .env.dev logs api | grep "$REQUEST_ID"
```

### Log Fields

| Field | Description | Always Present |
|-------|-------------|----------------|
| `timestamp` | ISO 8601 UTC timestamp | ✅ |
| `level` | Log level (DEBUG/INFO/WARNING/ERROR) | ✅ |
| `logger` | Logger name | ✅ |
| `message` | Log message | ✅ |
| `request_id` | Unique request identifier | For HTTP requests |
| `method` | HTTP method | For HTTP requests |
| `path` | Request path | For HTTP requests |
| `status_code` | HTTP response code | For completed requests |
| `duration_ms` | Request duration in milliseconds | For completed requests |
| `ip` | Client IP address | For HTTP requests |
| `user_agent` | Client user agent | For HTTP requests |
| `exception` | Stack trace | For errors |

## Prometheus Metrics

### Available Metrics

#### HTTP Metrics

**`http_requests_total`** (Counter)
- **Description**: Total number of HTTP requests
- **Labels**: `method`, `endpoint`, `status`
- **Example Query**:
  ```promql
  # Request rate per second
  rate(http_requests_total[5m])
  
  # Requests by status code
  sum(rate(http_requests_total[5m])) by (status)
  ```

**`http_request_duration_seconds`** (Histogram)
- **Description**: HTTP request latency distribution
- **Labels**: `method`, `endpoint`
- **Example Query**:
  ```promql
  # 95th percentile response time
  histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
  
  # Average response time per endpoint
  rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])
  ```

**`http_requests_in_progress`** (Gauge)
- **Description**: Number of HTTP requests currently being processed
- **Labels**: `method`, `endpoint`
- **Example Query**:
  ```promql
  # Current requests in progress
  http_requests_in_progress
  ```

**`http_errors_total`** (Counter)
- **Description**: Total HTTP errors (4xx and 5xx)
- **Labels**: `method`, `endpoint`, `status`
- **Example Query**:
  ```promql
  # Error rate
  rate(http_errors_total[5m])
  
  # Error percentage
  (rate(http_errors_total[5m]) / rate(http_requests_total[5m])) * 100
  ```

#### Business Metrics

**`loans_created_total`** (Counter)
- **Description**: Total number of loans created
- **Labels**: `currency`, `status`
- **Example Query**:
  ```promql
  # Loans created per minute
  rate(loans_created_total[1m]) * 60
  
  # Loans by currency
  sum(loans_created_total) by (currency)
  ```

**`loan_amount_total`** (Counter)
- **Description**: Total loan amount disbursed
- **Labels**: `currency`
- **Example Query**:
  ```promql
  # Total amount disbursed
  loan_amount_total
  
  # Amount disbursed per currency
  sum(loan_amount_total) by (currency)
  ```

**`active_loans`** (Gauge)
- **Description**: Current number of active loans
- **Labels**: `status`
- **Example Query**:
  ```promql
  # Loans by status
  active_loans
  
  # Total active loans
  sum(active_loans)
  ```

### Useful Prometheus Queries

#### Performance Monitoring

```promql
# Request rate (requests per second)
sum(rate(http_requests_total[5m]))

# P50, P95, P99 latency
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Slowest endpoints
topk(5, avg(rate(http_request_duration_seconds_sum[5m])) by (endpoint))
```

#### Error Monitoring

```promql
# Error rate (errors per second)
sum(rate(http_errors_total[5m]))

# Error percentage
(sum(rate(http_errors_total[5m])) / sum(rate(http_requests_total[5m]))) * 100

# 5xx errors
sum(rate(http_requests_total{status=~"5.."}[5m]))
```

#### Business Metrics

```promql
# Loan creation rate (loans per hour)
rate(loans_created_total[1h]) * 3600

# Distribution by status
sum(active_loans) by (status)

# Total loan volume
sum(loan_amount_total)
```

### Accessing Prometheus

**Web UI**
```bash
# Open Prometheus in browser
open http://localhost:9090

# Or
xdg-open http://localhost:9090  # Linux
```

**API Queries**
```bash
# Query via HTTP API
curl -G http://localhost:9090/api/v1/query \
  --data-urlencode 'query=rate(http_requests_total[5m])'

# Query with time range
curl -G http://localhost:9090/api/v1/query_range \
  --data-urlencode 'query=rate(http_requests_total[5m])' \
  --data-urlencode 'start=2025-11-06T10:00:00Z' \
  --data-urlencode 'end=2025-11-06T11:00:00Z' \
  --data-urlencode 'step=15s'
```

## Grafana Dashboards

### Pre-configured Dashboard

The **Branch Loan API - Monitoring Dashboard** includes:

#### Panels

1. **Request Rate Gauge** - Current requests per second
2. **Requests by Status Code** - Time series of HTTP status codes
3. **Response Time Percentiles** - P50 and P95 latency by endpoint
4. **Active Loans by Status** - Distribution of loan statuses
5. **Total Loans Created** - Cumulative loan count
6. **Error Rate** - Current error rate (threshold: red if > 10)
7. **Loan Creation Rate** - Rate of new loans by currency and status

### Accessing Grafana

```bash
# Open Grafana in browser
open http://localhost:3000

# Default credentials
Username: admin
Password: admin

# You'll be prompted to change password on first login (optional)
```

### Navigating the Dashboard

1. **Login** to Grafana (admin/admin)
2. Click **Dashboards** (left sidebar, four squares icon)
3. Select **Branch Loan API - Monitoring Dashboard**
4. Use the time range selector (top right) to adjust the viewing window
5. Click **Refresh** icon or enable auto-refresh (e.g., "10s")

### Creating Custom Dashboards

1. Click **+** (Create) → **Dashboard**
2. Click **Add new panel**
3. Select **Prometheus** as datasource
4. Enter your PromQL query
5. Configure visualization type (Time series, Gauge, Stat, etc.)
6. Click **Apply** and **Save**

### Dashboard Features

**Time Range Selector**
- Default: Last 15 minutes
- Options: 5m, 15m, 30m, 1h, 6h, 24h, 7d, 30d
- Custom: Select specific start/end times

**Auto-refresh**
- Default: 10 seconds
- Adjustable: 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h, 2h, 1d

**Variables** (can be added for filtering)
- Environment (dev/staging/prod)
- Endpoint
- Status code
- Currency

## Health Checks

### Enhanced Health Check

The `/health` endpoint now verifies:
1. ✅ API service is running
2. ✅ Database connection is established
3. ✅ Database can execute queries

**Example Response (Healthy)**:
```json
{
  "status": "ok",
  "timestamp": 1699276800.123,
  "checks": {
    "api": {
      "status": "healthy",
      "message": "API service is running"
    },
    "database": {
      "status": "healthy",
      "message": "Database connection successful"
    }
  }
}
```

**Example Response (Unhealthy)**:
```json
{
  "status": "degraded",
  "timestamp": 1699276800.123,
  "checks": {
    "api": {
      "status": "healthy",
      "message": "API service is running"
    },
    "database": {
      "status": "unhealthy",
      "message": "Database connection failed: connection refused"
    }
  }
}
```

### Readiness Probe

**Endpoint**: `/readiness`

Use this for:
- Kubernetes readiness probes
- Load balancer health checks
- Determining if service can accept traffic

```bash
# Check readiness
curl -k https://branchloans.com/readiness

# Response (ready):
{"status": "ready"}  # HTTP 200

# Response (not ready):
{"status": "not_ready", "reason": "database unavailable"}  # HTTP 503
```

### Liveness Probe

**Endpoint**: `/liveness`

Use this for:
- Kubernetes liveness probes
- Determining if service should be restarted

```bash
# Check liveness
curl -k https://branchloans.com/liveness

# Response:
{"status": "alive"}  # HTTP 200
```

### Using Health Checks

**Docker Compose Health Check**:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Kubernetes Probes**:
```yaml
livenessProbe:
  httpGet:
    path: /liveness
    port: 8000
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /readiness
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5
```

## Troubleshooting

### Prometheus Not Scraping Metrics

**Symptom**: No data in Grafana, Prometheus shows target as "DOWN"

**Solution**:
```bash
# 1. Check Prometheus targets
open http://localhost:9090/targets

# 2. Verify API metrics endpoint is accessible
curl http://localhost:8000/metrics

# 3. Check Prometheus logs
docker compose --env-file .env.dev logs prometheus

# 4. Restart Prometheus
docker compose --env-file .env.dev restart prometheus
```

### Grafana Shows "No Data"

**Symptom**: Dashboard panels show "No data"

**Solution**:
```bash
# 1. Verify Prometheus datasource
# Go to Grafana → Configuration → Data Sources → Prometheus
# Click "Test" - should show "Data source is working"

# 2. Check if Prometheus has data
# Go to http://localhost:9090 and run query: http_requests_total

# 3. Generate some traffic
curl -k https://branchloans.com/api/loans

# 4. Wait 10-15 seconds for metrics to be scraped
```

### Logs Not in JSON Format

**Symptom**: Logs appear as plain text instead of JSON

**Solution**:
```bash
# Check LOG_LEVEL environment variable
docker compose --env-file .env.dev exec api printenv LOG_LEVEL

# Should output: DEBUG, INFO, or WARNING

# If empty, check .env.dev file
cat .env.dev | grep LOG_LEVEL

# Restart API to apply changes
docker compose --env-file .env.dev restart api
```

### High Memory Usage

**Symptom**: Containers using too much memory

**Solution**:
```bash
# Check resource usage
docker stats

# Prometheus retention can be adjusted
# Edit docker-compose.yml and add to prometheus command:
# - '--storage.tsdb.retention.time=7d'  # Reduce from 15d to 7d

# Reduce scrape interval in docker/prometheus/prometheus.yml
# Change scrape_interval from 10s to 30s

# Restart monitoring stack
docker compose --env-file .env.dev restart prometheus grafana
```

### Missing Request IDs in Logs

**Symptom**: `request_id` field not appearing in logs

**Solution**:
```bash
# This should be automatic. Verify middleware is loaded:
docker compose --env-file .env.dev exec api python -c "
from app import create_app
app = create_app()
print([rule.rule for rule in app.url_map.iter_rules()])
"

# Check if StructuredLoggingMiddleware is initialized
docker compose --env-file .env.dev logs api | grep "Request started"
```

### Metrics Not Updating

**Symptom**: Metrics in Grafana are stale

**Solution**:
```bash
# 1. Check Prometheus scrape status
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets'

# 2. Verify metrics are being updated
curl http://localhost:8000/metrics | grep http_requests_total

# 3. Generate traffic and check again
for i in {1..10}; do curl -k https://branchloans.com/health; done
curl http://localhost:8000/metrics | grep http_requests_total

# 4. Check Prometheus logs for errors
docker compose --env-file .env.dev logs prometheus | grep -i error
```

## Best Practices

### 1. Alerting Rules

Create `docker/prometheus/alerts.yml`:

```yaml
groups:
  - name: branch_api_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: (rate(http_errors_total[5m]) / rate(http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }}% over the last 5 minutes"

      - alert: SlowResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1.0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow response times detected"
          description: "95th percentile response time is {{ $value }}s"
```

### 2. Log Retention

For production, consider using a log aggregation service:
- **Elasticsearch + Kibana** (ELK Stack)
- **Loki + Grafana**
- **AWS CloudWatch**
- **Google Cloud Logging**

### 3. Metric Retention

Adjust Prometheus retention based on your needs:

```yaml
# In docker-compose.yml, add to prometheus command:
command:
  - '--storage.tsdb.retention.time=30d'  # Keep metrics for 30 days
  - '--storage.tsdb.retention.size=10GB'  # Or limit by size
```

### 4. Security

For production:
- Enable authentication on Grafana (beyond default admin/admin)
- Restrict Prometheus access (not publicly exposed)
- Use HTTPS for Grafana with valid certificates
- Implement role-based access control (RBAC)

---

## Summary

You now have a complete monitoring solution:

✅ **Structured JSON logging** with request tracing  
✅ **Prometheus metrics** for performance monitoring  
✅ **Grafana dashboards** for visualization  
✅ **Enhanced health checks** with database verification  
✅ **Business metrics** tracking loan creation and volume  

**Next Steps**:
1. Generate traffic and explore the dashboard
2. Create custom queries in Prometheus
3. Set up alerting rules for production
4. Integrate with external monitoring services (optional)

For questions or issues, refer to the troubleshooting section or check the container logs!