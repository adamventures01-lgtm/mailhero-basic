#!/bin/bash

# MailHero Deployment Test Script
# Tests all components after deployment

set -e

echo "🧪 Testing MailHero Basic Deployment"
echo "===================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
DOMAIN="mailhero.in"
AGENT_URL="http://localhost:3001"
WEBMAIL_URL="http://localhost:3000"
ADMIN_URL="http://localhost:3002"

# Test counter
TESTS_PASSED=0
TESTS_TOTAL=0

# Function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n🔍 Testing: $test_name"
    ((TESTS_TOTAL++))
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}❌ FAIL${NC}"
        echo -e "${YELLOW}Command: $test_command${NC}"
    fi
}

# Test Docker services
echo -e "\n🐳 Testing Docker Services..."
run_test "PostgreSQL Container" "docker-compose ps postgres | grep -q 'Up'"
run_test "Postfix Container" "docker-compose ps postfix | grep -q 'Up'"
run_test "Dovecot Container" "docker-compose ps dovecot | grep -q 'Up'"
run_test "Agent Container" "docker-compose ps agent | grep -q 'Up'"
run_test "Webmail Container" "docker-compose ps webmail | grep -q 'Up'"
run_test "Admin Container" "docker-compose ps admin | grep -q 'Up'"

# Test network connectivity
echo -e "\n🌐 Testing Network Connectivity..."
run_test "Agent Health Endpoint" "curl -f $AGENT_URL/health"
run_test "Webmail Accessibility" "curl -f $WEBMAIL_URL"
run_test "Admin Console Accessibility" "curl -f $ADMIN_URL"

# Test database connectivity
echo -e "\n🗄️ Testing Database..."
run_test "Database Connection" "docker-compose exec -T postgres pg_isready -U mailhero"
run_test "Database Schema" "docker-compose exec -T postgres psql -U mailhero -d mailhero -c 'SELECT COUNT(*) FROM users;'"

# Test Bhindi Agent Tools
echo -e "\n🔧 Testing Bhindi Agent Tools..."
run_test "List Tools Endpoint" "curl -f $AGENT_URL/tools"
run_test "Health Tool" "curl -f -X POST $AGENT_URL/tools/health -H 'Content-Type: application/json' -d '{}'"
run_test "DNS Status Tool" "curl -f -X POST $AGENT_URL/tools/dnsStatus -H 'Content-Type: application/json' -d '{\"domain\":\"$DOMAIN\"}'"

# Test mail server ports
echo -e "\n📧 Testing Mail Server Ports..."
run_test "SMTP Port 25" "timeout 5 bash -c '</dev/tcp/localhost/25'"
run_test "SMTP Submission Port 587" "timeout 5 bash -c '</dev/tcp/localhost/587'"
run_test "IMAPS Port 993" "timeout 5 bash -c '</dev/tcp/localhost/993'"

# Test SSL certificates
echo -e "\n🔒 Testing SSL Configuration..."
run_test "SSL Certificate Exists" "test -f secrets/ssl/mailhero.crt"
run_test "SSL Private Key Exists" "test -f secrets/ssl/mailhero.key"
run_test "DKIM Private Key Exists" "test -f secrets/dkim/s1.private"
run_test "DKIM Public Key Exists" "test -f secrets/dkim/s1.public"

# Test user provisioning
echo -e "\n👤 Testing User Management..."
TEST_USER="test.user@$DOMAIN"
TEST_PASSWORD="TestPassword123!"

# Create test user
echo "Creating test user: $TEST_USER"
CREATE_USER_RESPONSE=$(curl -s -X POST $AGENT_URL/tools/provisionUser \
    -H 'Content-Type: application/json' \
    -d "{
        \"email\": \"$TEST_USER\",
        \"displayName\": \"Test User\",
        \"password\": \"$TEST_PASSWORD\",
        \"quotaMB\": 1024
    }")

if echo "$CREATE_USER_RESPONSE" | grep -q '"status":"created"'; then
    echo -e "${GREEN}✅ User creation successful${NC}"
    ((TESTS_PASSED++))
    
    # Test password change
    run_test "Password Change" "curl -f -X POST $AGENT_URL/tools/setPassword -H 'Content-Type: application/json' -d '{\"email\":\"$TEST_USER\",\"newPassword\":\"NewPassword123!\"}'"
    
    # Test quota setting
    run_test "Quota Setting" "curl -f -X POST $AGENT_URL/tools/setQuota -H 'Content-Type: application/json' -d '{\"email\":\"$TEST_USER\",\"quotaMB\":2048}'"
    
    # Test alias creation
    run_test "Alias Creation" "curl -f -X POST $AGENT_URL/tools/createAlias -H 'Content-Type: application/json' -d '{\"email\":\"$TEST_USER\",\"alias\":\"testalias@$DOMAIN\"}'"
    
    # Clean up test user
    echo "Cleaning up test user..."
    curl -s -X POST $AGENT_URL/tools/suspendUser \
        -H 'Content-Type: application/json' \
        -d "{\"email\":\"$TEST_USER\",\"mode\":\"delete\"}" >/dev/null
else
    echo -e "${RED}❌ User creation failed${NC}"
    echo "Response: $CREATE_USER_RESPONSE"
fi

((TESTS_TOTAL++))

# Test log files
echo -e "\n📝 Testing Log Files..."
run_test "Agent Logs Accessible" "docker-compose logs agent | head -1"
run_test "Postfix Logs Accessible" "docker-compose logs postfix | head -1"
run_test "Dovecot Logs Accessible" "docker-compose logs dovecot | head -1"

# Performance tests
echo -e "\n⚡ Testing Performance..."
echo "Testing agent response time..."
RESPONSE_TIME=$(curl -o /dev/null -s -w '%{time_total}' $AGENT_URL/health)
if (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
    echo -e "${GREEN}✅ Agent response time: ${RESPONSE_TIME}s${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ Agent response time too slow: ${RESPONSE_TIME}s${NC}"
fi
((TESTS_TOTAL++))

# Security tests
echo -e "\n🛡️ Testing Security..."
run_test "Environment File Secured" "test $(stat -c '%a' .env) = '600'"
run_test "DKIM Key Secured" "test $(stat -c '%a' secrets/dkim/s1.private) = '600'"
run_test "SSL Key Secured" "test $(stat -c '%a' secrets/ssl/mailhero.key) = '600'"

# Final summary
echo -e "\n📊 Test Results Summary"
echo "======================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Total: $TESTS_TOTAL"

PASS_RATE=$(( TESTS_PASSED * 100 / TESTS_TOTAL ))

if [ $PASS_RATE -eq 100 ]; then
    echo -e "${GREEN}🎉 All tests passed! Deployment is successful.${NC}"
    exit 0
elif [ $PASS_RATE -ge 80 ]; then
    echo -e "${YELLOW}⚠️  Most tests passed ($PASS_RATE%). Review failed tests.${NC}"
    exit 1
else
    echo -e "${RED}❌ Many tests failed ($PASS_RATE%). Deployment needs attention.${NC}"
    exit 1
fi