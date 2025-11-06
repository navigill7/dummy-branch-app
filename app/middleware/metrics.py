from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from flask import request, Response
import time
from functools import wraps

http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency in seconds',
    ['method', 'endpoint']
)

http_requests_in_progress = Gauge(
    'http_requests_in_progress',
    'Number of HTTP requests in progress',
    ['method', 'endpoint']
)


loans_created_total = Counter(
    'loans_created_total',
    'Total number of loans created',
    ['currency', 'status']
)

loan_amount_total = Counter(
    'loan_amount_total',
    'Total loan amount disbursed',
    ['currency']
)

active_loans_gauge = Gauge(
    'active_loans',
    'Number of active loans by status',
    ['status']
)

database_connections = Gauge(
    'database_connections',
    'Number of database connections'
)


http_errors_total = Counter(
    'http_errors_total',
    'Total HTTP errors',
    ['method', 'endpoint', 'status']
)


class MetricsMiddleware:
    """Flask middleware for collecting Prometheus metrics."""
    
    def __init__(self, app):
        self.app = app
        
        @app.before_request
        def before_request():
            request._start_time = time.time()
            endpoint = request.endpoint or 'unknown'
            http_requests_in_progress.labels(
                method=request.method,
                endpoint=endpoint
            ).inc()
        
        @app.after_request
        def after_request(response):
            request_latency = time.time() - request._start_time
            endpoint = request.endpoint or 'unknown'
            
            
            http_requests_total.labels(
                method=request.method,
                endpoint=endpoint,
                status=response.status_code
            ).inc()
            
            http_request_duration_seconds.labels(
                method=request.method,
                endpoint=endpoint
            ).observe(request_latency)
            
            http_requests_in_progress.labels(
                method=request.method,
                endpoint=endpoint
            ).dec()
            
            
            if response.status_code >= 400:
                http_errors_total.labels(
                    method=request.method,
                    endpoint=endpoint,
                    status=response.status_code
                ).inc()
            
            return response


def track_loan_creation(currency: str, status: str = "pending"):
    """Track loan creation metrics."""
    loans_created_total.labels(currency=currency, status=status).inc()


def track_loan_amount(amount: float, currency: str):
    """Track loan amount metrics."""
    loan_amount_total.labels(currency=currency).inc(amount)


def update_active_loans_gauge(status_counts: dict):
    """Update active loans gauge with current counts."""
    for status, count in status_counts.items():
        active_loans_gauge.labels(status=status).set(count)


def metrics_endpoint():
    """Endpoint to expose Prometheus metrics."""
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)