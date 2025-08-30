#!/bin/bash

# DNS Verification Script for MailHero
# Checks all required DNS records for proper email setup

DOMAIN="mailhero.in"
MAIL_SERVER="mail.mailhero.in"

echo "🔍 Verifying DNS configuration for $DOMAIN"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required tools
if ! command_exists dig; then
    echo -e "${RED}❌ dig command not found. Please install dnsutils${NC}"
    exit 1
fi

# Check MX Records
echo -e "\n📧 Checking MX Records..."
MX_RESULT=$(dig +short MX $DOMAIN)
if [ -n "$MX_RESULT" ]; then
    echo -e "${GREEN}✅ MX Records found:${NC}"
    echo "$MX_RESULT" | while read line; do
        echo "   $line"
    done
    
    # Check if our mail server is in MX records
    if echo "$MX_RESULT" | grep -q "$MAIL_SERVER"; then
        echo -e "${GREEN}✅ Mail server $MAIL_SERVER found in MX records${NC}"
    else
        echo -e "${YELLOW}⚠️  Mail server $MAIL_SERVER not found in MX records${NC}"
    fi
else
    echo -e "${RED}❌ No MX records found${NC}"
fi

# Check A Record for mail server
echo -e "\n🌐 Checking A Record for $MAIL_SERVER..."
A_RESULT=$(dig +short A $MAIL_SERVER)
if [ -n "$A_RESULT" ]; then
    echo -e "${GREEN}✅ A Record found: $A_RESULT${NC}"
else
    echo -e "${RED}❌ No A record found for $MAIL_SERVER${NC}"
fi

# Check SPF Record
echo -e "\n🛡️  Checking SPF Record..."
SPF_RESULT=$(dig +short TXT $DOMAIN | grep "v=spf1")
if [ -n "$SPF_RESULT" ]; then
    echo -e "${GREEN}✅ SPF Record found:${NC}"
    echo "   $SPF_RESULT"
    
    # Validate SPF syntax
    if echo "$SPF_RESULT" | grep -q "include:\|a:\|mx\|ip4:\|ip6:"; then
        echo -e "${GREEN}✅ SPF record appears valid${NC}"
    else
        echo -e "${YELLOW}⚠️  SPF record may need review${NC}"
    fi
else
    echo -e "${RED}❌ No SPF record found${NC}"
    echo -e "${YELLOW}💡 Add this SPF record:${NC}"
    echo "   $DOMAIN TXT \"v=spf1 mx a:$MAIL_SERVER -all\""
fi

# Check DKIM Records
echo -e "\n🔐 Checking DKIM Records..."
DKIM_SELECTORS=("s1" "default" "selector1" "mail")
DKIM_FOUND=false

for selector in "${DKIM_SELECTORS[@]}"; do
    DKIM_DOMAIN="${selector}._domainkey.${DOMAIN}"
    DKIM_RESULT=$(dig +short TXT $DKIM_DOMAIN | grep "v=DKIM1")
    
    if [ -n "$DKIM_RESULT" ]; then
        echo -e "${GREEN}✅ DKIM Record found for selector '$selector':${NC}"
        echo "   $DKIM_RESULT" | cut -c1-80
        if [ ${#DKIM_RESULT} -gt 80 ]; then
            echo "   ... (truncated)"
        fi
        DKIM_FOUND=true
    fi
done

if [ "$DKIM_FOUND" = false ]; then
    echo -e "${RED}❌ No DKIM records found${NC}"
    echo -e "${YELLOW}💡 Generate DKIM keys and add DNS record:${NC}"
    echo "   s1._domainkey.$DOMAIN TXT \"v=DKIM1; k=rsa; p=<your-public-key>\""
fi

# Check DMARC Record
echo -e "\n🔒 Checking DMARC Record..."
DMARC_DOMAIN="_dmarc.${DOMAIN}"
DMARC_RESULT=$(dig +short TXT $DMARC_DOMAIN | grep "v=DMARC1")
if [ -n "$DMARC_RESULT" ]; then
    echo -e "${GREEN}✅ DMARC Record found:${NC}"
    echo "   $DMARC_RESULT"
    
    # Check DMARC policy
    if echo "$DMARC_RESULT" | grep -q "p=reject\|p=quarantine"; then
        echo -e "${GREEN}✅ DMARC policy is enforced${NC}"
    else
        echo -e "${YELLOW}⚠️  DMARC policy is set to 'none' - consider strengthening${NC}"
    fi
else
    echo -e "${RED}❌ No DMARC record found${NC}"
    echo -e "${YELLOW}💡 Add this DMARC record:${NC}"
    echo "   _dmarc.$DOMAIN TXT \"v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@$DOMAIN\""
fi

# Check PTR Record (Reverse DNS)
echo -e "\n🔄 Checking PTR Record (Reverse DNS)..."
if [ -n "$A_RESULT" ]; then
    PTR_RESULT=$(dig +short -x $A_RESULT)
    if [ -n "$PTR_RESULT" ]; then
        echo -e "${GREEN}✅ PTR Record found: $PTR_RESULT${NC}"
        if echo "$PTR_RESULT" | grep -q "$MAIL_SERVER"; then
            echo -e "${GREEN}✅ PTR record matches mail server${NC}"
        else
            echo -e "${YELLOW}⚠️  PTR record doesn't match mail server${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No PTR record found for $A_RESULT${NC}"
        echo -e "${YELLOW}💡 Contact your hosting provider to set up reverse DNS${NC}"
    fi
fi

# Summary
echo -e "\n📊 DNS Configuration Summary"
echo "================================================"

# Calculate score
SCORE=0
TOTAL=5

if [ -n "$MX_RESULT" ]; then ((SCORE++)); fi
if [ -n "$A_RESULT" ]; then ((SCORE++)); fi
if [ -n "$SPF_RESULT" ]; then ((SCORE++)); fi
if [ "$DKIM_FOUND" = true ]; then ((SCORE++)); fi
if [ -n "$DMARC_RESULT" ]; then ((SCORE++)); fi

echo "Score: $SCORE/$TOTAL"

if [ $SCORE -eq $TOTAL ]; then
    echo -e "${GREEN}🎉 Excellent! All DNS records are configured${NC}"
elif [ $SCORE -ge 3 ]; then
    echo -e "${YELLOW}⚠️  Good configuration, but some records need attention${NC}"
else
    echo -e "${RED}❌ DNS configuration needs significant work${NC}"
fi

# Test mail server connectivity
echo -e "\n🔌 Testing Mail Server Connectivity..."
if [ -n "$A_RESULT" ]; then
    # Test SMTP
    if timeout 5 bash -c "</dev/tcp/$A_RESULT/25" 2>/dev/null; then
        echo -e "${GREEN}✅ SMTP port 25 is reachable${NC}"
    else
        echo -e "${RED}❌ SMTP port 25 is not reachable${NC}"
    fi
    
    # Test SMTP Submission
    if timeout 5 bash -c "</dev/tcp/$A_RESULT/587" 2>/dev/null; then
        echo -e "${GREEN}✅ SMTP submission port 587 is reachable${NC}"
    else
        echo -e "${RED}❌ SMTP submission port 587 is not reachable${NC}"
    fi
    
    # Test IMAP
    if timeout 5 bash -c "</dev/tcp/$A_RESULT/993" 2>/dev/null; then
        echo -e "${GREEN}✅ IMAPS port 993 is reachable${NC}"
    else
        echo -e "${RED}❌ IMAPS port 993 is not reachable${NC}"
    fi
fi

echo -e "\n✅ DNS verification complete!"
echo -e "💡 Run this script again after making DNS changes"