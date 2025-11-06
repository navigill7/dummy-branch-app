#!/bin/bash


set -e

echo "🚀 Branch Loan API - Monitoring Setup"
echo "======================================"
echo ""


GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 


echo "📋 Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo "Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

echo -e "${GREEN}✅ Docker and Docker Compose are installed${NC}"
echo ""

echo "🔧 Select environment:"
echo "1) Development (default)"
echo "2) Staging"
echo "3) Production"
read -p "Enter choice [1-3] (default: 1): " env_choice

case $env_choice in
    2)
        ENV_FILE=".env.stage"
        ENV_NAME="staging"
        ;;
    3)
        ENV_FILE=".env.prod"
        ENV_NAME="production"
        ;;
    *)
        ENV_FILE=".env.dev"
        ENV_NAME="development"
        ;;
esac

echo -e "${GREEN}✅ Selected: $ENV_NAME environment${NC}"
echo ""


if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Environment file $ENV_FILE not found${NC}"
    exit 1
fi

echo "🛑 Stopping existing containers..."
docker-compose --env-file "$ENV_FILE" down > /dev/null 2>&1 || true
echo -e "${GREEN}✅ Stopped existing containers${NC}"
echo ""


echo "🐳 Starting monitoring stack..."
docker-compose --env-file "$ENV_FILE" up -d --build

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5


echo "   Waiting for database..."
timeout=30
counter=0
until docker-compose --env-file "$ENV_FILE" exec -T db pg_isready -U postgres > /dev/null 2>&1; do
    if [ $counter -gt $timeout ]; then
        echo -e "${RED}❌ Database failed to start${NC}"
        exit 1
    fi
    counter=$((counter + 1))
    sleep 1
done
echo -e "${GREEN}   ✅ Database is ready${NC}"


echo "   Waiting for API..."
timeout=30
counter=0
until curl -s -k https://branchloans.com/health > /dev/null 2>&1; do
    if [ $counter -gt $timeout ]; then
        echo -e "${RED}❌ API failed to start${NC}"
        exit 1
    fi
    counter=$((counter + 1))
    sleep 1
done
echo -e "${GREEN}   ✅ API is ready${NC}"


echo "   Waiting for Prometheus..."
timeout=30
counter=0
until curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; do
    if [ $counter -gt $timeout ]; then
        echo -e "${YELLOW}⚠️  Prometheus might not be ready${NC}"
        break
    fi
    counter=$((counter + 1))
    sleep 1
done
echo -e "${GREEN}   ✅ Prometheus is ready${NC}"


echo "   Waiting for Grafana..."
timeout=30
counter=0
until curl -s http://localhost:3000/api/health > /dev/null 2>&1; do
    if [ $counter -gt $timeout ]; then
        echo -e "${YELLOW}⚠️  Grafana might not be ready${NC}"
        break
    fi
    counter=$((counter + 1))
    sleep 1
done
echo -e "${GREEN}   ✅ Grafana is ready${NC}"

echo ""
echo "🎯 Running database migrations..."
docker-compose --env-file "$ENV_FILE" exec -T api alembic upgrade head
echo -e "${GREEN}✅ Migrations applied${NC}"
echo ""

read -p "📦 Would you like to seed dummy data? [y/N]: " seed_choice
if [[ $seed_choice =~ ^[Yy]$ ]]; then
    echo "🌱 Seeding database..."
    docker-compose --env-file "$ENV_FILE" exec -T api python scripts/seed.py
    echo -e "${GREEN}✅ Database seeded${NC}"
    echo ""
fi


read -p "🔄 Would you like to generate test traffic for metrics? [y/N]: " traffic_choice
if [[ $traffic_choice =~ ^[Yy]$ ]]; then
    echo "🚦 Generating test traffic..."
    
    
    echo "   Creating loans..."
    for i in {1..5}; do
        curl -s -k -X POST https://branchloans.com/api/loans \
            -H 'Content-Type: application/json' \
            -d "{
                \"borrower_id\": \"test_user_$i\",
                \"amount\": $((10000 + RANDOM % 40000)),
                \"currency\": \"INR\",
                \"term_months\": 12,
                \"interest_rate_apr\": 18.5
            }" > /dev/null 2>&1
    done
    
    
    echo "   Making API requests..."
    for i in {1..20}; do
        curl -s -k https://branchloans.com/api/loans > /dev/null 2>&1
        sleep 0.2
    done
    
    echo -e "${GREEN}✅ Test traffic generated${NC}"
    echo ""
fi

echo ""
echo "🎉 Monitoring Stack is Ready!"
echo "======================================"
echo ""
echo -e "${GREEN}✅ Services Status:${NC}"
docker-compose --env-file "$ENV_FILE" ps
echo ""
echo -e "${GREEN}📊 Access Points:${NC}"
echo ""
echo "  🌐 API (HTTPS):        https://branchloans.com"
echo "  🏥 Health Check:       https://branchloans.com/health"
echo "  📈 Metrics:            https://branchloans.com/metrics"
echo ""
echo "  📊 Grafana Dashboard:  http://localhost:3000"
echo "     Username: admin"
echo "     Password: admin"
echo ""
echo "  🔍 Prometheus:         http://localhost:9090"
echo ""
echo -e "${YELLOW}📚 Documentation:${NC}"
echo "  Read MONITORING.md for detailed usage guide"
echo ""
echo -e "${YELLOW}💡 Quick Commands:${NC}"
echo "  View logs:             docker-compose --env-file $ENV_FILE logs -f api"
echo "  View JSON logs:        docker-compose --env-file $ENV_FILE logs api | grep -o '{.*}' | jq ."
echo "  Stop services:         docker-compose --env-file $ENV_FILE down"
echo "  Restart API:           docker-compose --env-file $ENV_FILE restart api"
echo ""
echo -e "${GREEN}🎯 Next Steps:${NC}"
echo "  1. Open Grafana: http://localhost:3000"
echo "  2. Navigate to 'Branch Loan API - Monitoring Dashboard'"
echo "  3. Explore the metrics and graphs"
echo "  4. Try making API requests and watch the metrics update"
echo ""
echo "Happy monitoring! 🚀"