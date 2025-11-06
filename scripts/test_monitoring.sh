#!/bin/bash


set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

API_URL="https://branchloans.com"

echo "🧪 Branch Loan API - Monitoring Test Script"
echo "============================================"
echo ""


print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}


print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}


print_step "Checking API availability..."
if ! curl -s -k "$API_URL/health" > /dev/null; then
    echo "❌ API is not accessible at $API_URL"
    echo "Make sure the API is running: docker compose --env-file .env.dev up -d"
    exit 1
fi
print_success "API is accessible"
echo ""


print_step "Test 1: Health Check Endpoints"
echo "Testing /health endpoint..."
curl -s -k "$API_URL/health" | jq .
echo ""
echo "Testing /readiness endpoint..."
curl -s -k "$API_URL/readiness" | jq .
echo ""
echo "Testing /liveness endpoint..."
curl -s -k "$API_URL/liveness" | jq .
print_success "Health checks completed"
echo ""


print_step "Test 2: Creating Loans (Success Cases)"
CURRENCIES=("INR" "USD" "EUR" "GBP" "KES")
for i in {1..10}; do
    CURRENCY=${CURRENCIES[$RANDOM % ${#CURRENCIES[@]}]}
    AMOUNT=$((5000 + RANDOM % 45000))
    
    echo "  Creating loan $i: $AMOUNT $CURRENCY"
    RESPONSE=$(curl -s -k -X POST "$API_URL/api/loans" \
        -H 'Content-Type: application/json' \
        -d "{
            \"borrower_id\": \"perf_test_user_$i\",
            \"amount\": $AMOUNT,
            \"currency\": \"$CURRENCY\",
            \"term_months\": $((6 + RANDOM % 18)),
            \"interest_rate_apr\": $((10 + RANDOM % 20))
        }")
    
    LOAN_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "    Created loan ID: $LOAN_ID"
    sleep 0.2
done
print_success "Created 10 loans successfully"
echo ""


print_step "Test 3: Rapid List Operations"
echo "Making 50 rapid requests to /api/loans..."
for i in {1..50}; do
    curl -s -k "$API_URL/api/loans" > /dev/null &
    if (( i % 10 == 0 )); then
        echo "  Completed $i requests..."
    fi
done
wait
print_success "Completed rapid list operations"
echo ""

print_step "Test 4: Statistics Queries"
echo "Requesting /api/stats (tests database aggregations)..."
for i in {1..5}; do
    echo "  Request $i..."
    curl -s -k "$API_URL/api/stats" | jq .
    sleep 1
done
print_success "Completed stats queries"
echo ""


print_step "Test 5: Individual Loan Lookups"
echo "Getting first 5 loans..."
LOANS=$(curl -s -k "$API_URL/api/loans" | jq -r '.[0:5] | .[].id')
for LOAN_ID in $LOANS; do
    echo "  Fetching loan $LOAN_ID..."
    curl -s -k "$API_URL/api/loans/$LOAN_ID" > /dev/null
    sleep 0.3
done
print_success "Completed individual lookups"
echo ""


print_step "Test 6: Generating Validation Errors (4xx)"
echo "Submitting invalid loan requests..."


echo "  Test 1: Amount too high (> 50000)"
curl -s -k -X POST "$API_URL/api/loans" \
    -H 'Content-Type: application/json' \
    -d '{"borrower_id": "test", "amount": 100000, "currency": "INR", "term_months": 12}' \
    | jq .


echo "  Test 2: Invalid currency"
curl -s -k -X POST "$API_URL/api/loans" \
    -H 'Content-Type: application/json' \
    -d '{"borrower_id": "test", "amount": 10000, "currency": "INVALID", "term_months": 12}' \
    | jq .


echo "  Test 3: Missing required field"
curl -s -k -X POST "$API_URL/api/loans" \
    -H 'Content-Type: application/json' \
    -d '{"borrower_id": "test", "amount": 10000}' \
    | jq .


echo "  Test 4: Invalid loan ID (404)"
curl -s -k "$API_URL/api/loans/invalid-uuid" | jq .

print_success "Generated validation errors"
echo ""


print_step "Test 7: Sustained Load Test"
echo "Generating sustained traffic for 30 seconds..."
END=$((SECONDS+30))
REQUEST_COUNT=0
while [ $SECONDS -lt $END ]; do
    
    case $((RANDOM % 3)) in
        0)
            curl -s -k "$API_URL/api/loans" > /dev/null &
            ;;
        1)
            curl -s -k "$API_URL/api/stats" > /dev/null &
            ;;
        2)
            curl -s -k "$API_URL/health" > /dev/null &
            ;;
    esac
    REQUEST_COUNT=$((REQUEST_COUNT + 1))
    
    if (( REQUEST_COUNT % 20 == 0 )); then
        echo "  Sent $REQUEST_COUNT requests..."
    fi
    
    sleep 0.1
done
wait
print_success "Completed load test - sent $REQUEST_COUNT requests"
echo ""


echo ""
echo "🎉 Monitoring Test Complete!"
echo "============================"
echo ""
echo -e "${YELLOW}📊 Next Steps:${NC}"
echo "1. Open Grafana: http://localhost:3000"
echo "2. View the 'Branch Loan API - Monitoring Dashboard'"
echo "3. Check Prometheus: http://localhost:9090"
echo "4. Query metrics like: rate(http_requests_total[5m])"
echo ""
echo -e "${YELLOW}📈 Expected Metrics:${NC}"
echo "- Request rate: ~$((REQUEST_COUNT / 30)) req/s during load test"
echo "- Total loans created: 10"
echo "- Error count: 4 (validation errors)"
echo "- Status codes: 200, 201, 400, 404"
echo ""
echo -e "${YELLOW}📋 View Logs:${NC}"
echo "docker compose --env-file .env.dev logs api | grep -o '{.*}' | jq ."
echo ""
echo "Happy monitoring! 🚀"