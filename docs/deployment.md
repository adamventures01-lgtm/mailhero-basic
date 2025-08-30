# MailHero Basic Deployment Guide

## Prerequisites

- Ubuntu 20.04+ or CentOS 8+ server
- Docker and Docker Compose installed
- Domain name (mailhero.in) with DNS access
- Minimum 4GB RAM, 2 CPU cores, 50GB storage

## Quick Deployment

### 1. Clone Repository

```bash
git clone https://github.com/adamventures01-lgtm/mailhero-basic.git
cd mailhero-basic
```

### 2. Run Bootstrap Script

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

This script will:
- Create directory structure
- Generate SSL certificates (self-signed for dev)
- Generate DKIM keys
- Create database schema
- Set up configuration files
- Generate environment variables

### 3. Configure Environment

Edit `.env` file with your specific settings:

```bash
# Update domain settings
DOMAIN=your-domain.com
HOSTNAME=mail.your-domain.com

# Update URLs
WEB_BASE_URL=https://mail.your-domain.com
AGENT_URL=https://api.your-domain.com

# Review generated passwords
DB_PASSWORD=<generated>
JWT_SECRET=<generated>
GRAFANA_PASSWORD=<generated>
```

### 4. Configure DNS Records

Add these DNS records for your domain:

```dns
# MX Record
@ MX 10 mail.your-domain.com

# A Records
mail.your-domain.com A <your-server-ip>
api.your-domain.com A <your-server-ip>
admin.your-domain.com A <your-server-ip>

# SPF Record
@ TXT "v=spf1 mx a:mail.your-domain.com -all"

# DKIM Record (use key from bootstrap output)
s1._domainkey TXT "v=DKIM1; k=rsa; p=<your-dkim-public-key>"

# DMARC Record
_dmarc TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@your-domain.com"
```

### 5. Start Services

```bash
docker-compose up -d
```

### 6. Verify Deployment

Check service status:
```bash
docker-compose ps
```

Test endpoints:
```bash
# Agent health
curl https://api.your-domain.com/health

# Webmail
curl https://mail.your-domain.com

# Admin console
curl https://admin.your-domain.com
```

## Production Setup

### SSL Certificates

Replace self-signed certificates with Let's Encrypt:

```bash
# Install certbot
sudo apt install certbot

# Get certificates
sudo certbot certonly --standalone -d mail.your-domain.com
sudo certbot certonly --standalone -d api.your-domain.com
sudo certbot certonly --standalone -d admin.your-domain.com

# Copy certificates
sudo cp /etc/letsencrypt/live/mail.your-domain.com/fullchain.pem secrets/ssl/mailhero.crt
sudo cp /etc/letsencrypt/live/mail.your-domain.com/privkey.pem secrets/ssl/mailhero.key

# Restart services
docker-compose restart nginx
```

### Firewall Configuration

```bash
# Allow required ports
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 25/tcp    # SMTP
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 143/tcp   # IMAP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 587/tcp   # SMTP Submission
sudo ufw allow 993/tcp   # IMAPS
sudo ufw enable
```

### Backup Configuration

Set up automated backups:

```bash
# Create backup script
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups/mailhero"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Database backup
docker-compose exec -T postgres pg_dump -U mailhero mailhero > $BACKUP_DIR/db_$DATE.sql

# Mail data backup
tar -czf $BACKUP_DIR/mail_$DATE.tar.gz mail-stack/

# Encrypt backup
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/db_$DATE.sql
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/mail_$DATE.tar.gz

# Clean old backups (keep 30 days)
find $BACKUP_DIR -name "*.gpg" -mtime +30 -delete
EOF

chmod +x scripts/backup.sh

# Add to crontab
echo "0 2 * * * /path/to/mailhero-basic/scripts/backup.sh" | crontab -
```

## Monitoring

### Access Grafana Dashboard

1. Open https://your-domain.com:3003
2. Login with admin / <GRAFANA_PASSWORD from .env>
3. Import dashboard from `monitoring/grafana/dashboards/mailhero.json`

### Key Metrics to Monitor

- SMTP queue depth
- IMAP connection count
- Disk usage
- Memory usage
- Failed authentication attempts
- Spam detection rate

## Troubleshooting

### Check Service Logs

```bash
# All services
docker-compose logs

# Specific service
docker-compose logs postfix
docker-compose logs dovecot
docker-compose logs agent
```

### Test Email Flow

```bash
# Test SMTP
telnet mail.your-domain.com 587

# Test IMAP
telnet mail.your-domain.com 993

# Test DNS
dig MX your-domain.com
dig TXT s1._domainkey.your-domain.com
```

### Common Issues

1. **Email not delivered**: Check SPF/DKIM/DMARC records
2. **Can't connect to IMAP**: Verify SSL certificates
3. **High spam score**: Configure reverse DNS (PTR record)
4. **Database connection failed**: Check PostgreSQL container status

## Scaling

### Vertical Scaling

Increase resources in docker-compose.yml:

```yaml
services:
  postgres:
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
```

### Horizontal Scaling

For high-volume deployments:

1. Separate database server
2. Load balancer for multiple SMTP servers
3. Shared storage for mail data
4. Redis for session management

## Security Hardening

### Additional Security Measures

1. **Rate Limiting**: Configure fail2ban
2. **Network Segmentation**: Use Docker networks
3. **Secret Management**: Use Docker secrets
4. **Regular Updates**: Automate security updates
5. **Audit Logging**: Enable comprehensive logging

### Compliance

For GDPR/CCPA compliance:
- Enable data retention policies
- Implement data export tools
- Configure secure deletion
- Maintain audit trails

## Maintenance

### Regular Tasks

1. **Weekly**: Review logs and metrics
2. **Monthly**: Update Docker images
3. **Quarterly**: Security audit
4. **Annually**: Certificate renewal

### Update Procedure

```bash
# Backup before update
./scripts/backup.sh

# Pull latest images
docker-compose pull

# Restart services
docker-compose up -d

# Verify functionality
./scripts/health-check.sh
```