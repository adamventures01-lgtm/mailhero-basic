#!/bin/bash

# MailHero Basic Bootstrap Script
# This script sets up the complete MailHero email service

set -e

echo "🚀 Starting MailHero Basic Bootstrap..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "❌ This script should not be run as root"
   exit 1
fi

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Create directories
echo "📁 Creating directory structure..."
mkdir -p secrets/{ssl,dkim}
mkdir -p mail-stack/{postfix,dovecot,rspamd}
mkdir -p database
mkdir -p monitoring/{grafana/{dashboards,datasources},prometheus}
mkdir -p nginx
mkdir -p logs

# Generate environment file if it doesn't exist
if [ ! -f .env ]; then
    echo "🔐 Generating environment configuration..."
    cat > .env << EOF
# Database
DB_PASSWORD=$(openssl rand -base64 32)

# JWT Secret
JWT_SECRET=$(openssl rand -base64 64)

# Grafana
GRAFANA_PASSWORD=$(openssl rand -base64 16)

# Domain Configuration
DOMAIN=mailhero.in
HOSTNAME=mail.mailhero.in

# SMTP Configuration
SMTP_HOST=mail.mailhero.in
SMTP_PORT=587
IMAP_HOST=mail.mailhero.in
IMAP_PORT=993

# Web URLs
WEB_BASE_URL=https://mail.mailhero.in
AGENT_URL=https://api.mailhero.in
EOF
    echo "✅ Environment file created (.env)"
fi

# Generate DKIM keys
echo "🔑 Generating DKIM keys..."
if [ ! -f secrets/dkim/s1.private ]; then
    openssl genrsa -out secrets/dkim/s1.private 2048
    openssl rsa -in secrets/dkim/s1.private -pubout -out secrets/dkim/s1.public
    
    # Extract public key for DNS
    DKIM_PUBLIC=$(grep -v "BEGIN\|END" secrets/dkim/s1.public | tr -d '\n')
    echo "DKIM_PUBLIC_KEY=$DKIM_PUBLIC" >> .env
    echo "✅ DKIM keys generated"
fi

# Generate SSL certificates (self-signed for development)
echo "🔒 Generating SSL certificates..."
if [ ! -f secrets/ssl/mailhero.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout secrets/ssl/mailhero.key \
        -out secrets/ssl/mailhero.crt \
        -subj "/C=US/ST=State/L=City/O=MailHero/CN=mail.mailhero.in"
    echo "✅ SSL certificates generated"
fi

# Create database initialization script
echo "🗄️ Creating database schema..."
cat > database/init.sql << 'EOF'
-- MailHero Database Schema

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    quota_mb INTEGER DEFAULT 5120,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Aliases table
CREATE TABLE aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    alias_email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Forwarding rules
CREATE TABLE forwarding (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    forward_to TEXT[] NOT NULL,
    keep_copy BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Email filters
CREATE TABLE filters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    conditions JSONB NOT NULL,
    actions JSONB NOT NULL,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Auto-reply settings
CREATE TABLE autoreplies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT false,
    subject VARCHAR(255),
    message TEXT,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Audit log
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_aliases_email ON aliases(alias_email);
CREATE INDEX idx_audit_log_user_id ON audit_log(user_id);
CREATE INDEX idx_audit_log_created_at ON audit_log(created_at);

-- Insert default admin user
INSERT INTO users (email, display_name, password_hash, quota_mb, status) 
VALUES ('admin@mailhero.in', 'MailHero Admin', '$2b$10$dummy.hash.for.initial.setup', 10240, 'active');
EOF

# Create Postfix configuration
echo "📧 Creating Postfix configuration..."
mkdir -p mail-stack/postfix
cat > mail-stack/postfix/main.cf << 'EOF'
# Postfix main configuration for MailHero
myhostname = mail.mailhero.in
mydomain = mailhero.in
myorigin = $mydomain
mydestination = $mydomain, localhost
relayhost = 
mynetworks = 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16

# TLS Configuration
smtpd_use_tls = yes
smtpd_tls_cert_file = /etc/ssl/certs/mailhero.crt
smtpd_tls_key_file = /etc/ssl/certs/mailhero.key
smtpd_tls_security_level = may
smtp_tls_security_level = may

# SASL Authentication
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth

# Virtual domains
virtual_mailbox_domains = mailhero.in
virtual_mailbox_base = /var/mail
virtual_mailbox_maps = pgsql:/etc/postfix/pgsql-virtual-mailbox-maps.cf
virtual_alias_maps = pgsql:/etc/postfix/pgsql-virtual-alias-maps.cf

# DKIM
milter_default_action = accept
milter_protocol = 6
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891

# Security
smtpd_helo_required = yes
smtpd_recipient_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination,
    reject_rbl_client zen.spamhaus.org
EOF

# Create Dovecot configuration
echo "📬 Creating Dovecot configuration..."
mkdir -p mail-stack/dovecot/conf.d
cat > mail-stack/dovecot/dovecot.conf << 'EOF'
# Dovecot configuration for MailHero
protocols = imap pop3 lmtp
listen = *

# SSL Configuration
ssl = required
ssl_cert = </etc/ssl/certs/mailhero.crt
ssl_key = </etc/ssl/certs/mailhero.key

# Authentication
auth_mechanisms = plain login
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}

# Mail location
mail_location = maildir:/var/mail/%d/%n

# Namespace
namespace inbox {
  inbox = yes
  location = 
  mailbox Drafts {
    special_use = \Drafts
  }
  mailbox Junk {
    special_use = \Junk
  }
  mailbox Sent {
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
  mailbox Trash {
    special_use = \Trash
  }
}

# Protocols
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

service pop3-login {
  inet_listener pop3 {
    port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

# LMTP
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    group = postfix
    mode = 0600
    user = postfix
  }
}

# Auth
service auth {
  unix_listener /var/spool/postfix/private/auth {
    group = postfix
    mode = 0666
    user = postfix
  }
}
EOF

# Create Nginx configuration
echo "🌐 Creating Nginx configuration..."
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream agent {
        server agent:3001;
    }
    
    upstream webmail {
        server webmail:80;
    }
    
    upstream admin {
        server admin:80;
    }

    server {
        listen 80;
        server_name mail.mailhero.in api.mailhero.in admin.mailhero.in;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name mail.mailhero.in;
        
        ssl_certificate /etc/ssl/certs/mailhero.crt;
        ssl_certificate_key /etc/ssl/certs/mailhero.key;
        
        location / {
            proxy_pass http://webmail;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }

    server {
        listen 443 ssl http2;
        server_name api.mailhero.in;
        
        ssl_certificate /etc/ssl/certs/mailhero.crt;
        ssl_certificate_key /etc/ssl/certs/mailhero.key;
        
        location / {
            proxy_pass http://agent;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }

    server {
        listen 443 ssl http2;
        server_name admin.mailhero.in;
        
        ssl_certificate /etc/ssl/certs/mailhero.crt;
        ssl_certificate_key /etc/ssl/certs/mailhero.key;
        
        location / {
            proxy_pass http://admin;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

# Create monitoring configuration
echo "📊 Creating monitoring configuration..."
cat > monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'mailhero-agent'
    static_configs:
      - targets: ['agent:3001']
  
  - job_name: 'postfix'
    static_configs:
      - targets: ['postfix:9154']
  
  - job_name: 'dovecot'
    static_configs:
      - targets: ['dovecot:9166']
EOF

# Set permissions
echo "🔐 Setting permissions..."
chmod 600 secrets/dkim/s1.private
chmod 644 secrets/dkim/s1.public
chmod 600 secrets/ssl/mailhero.key
chmod 644 secrets/ssl/mailhero.crt
chmod +x scripts/*.sh

echo "✅ Bootstrap completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Review and update .env file with your settings"
echo "2. Configure DNS records (see docs/dns.md)"
echo "3. Run: docker-compose up -d"
echo "4. Access webmail at: https://mail.mailhero.in"
echo "5. Access admin at: https://admin.mailhero.in"
echo ""
echo "🔑 DKIM Public Key for DNS:"
echo "s1._domainkey.mailhero.in TXT \"v=DKIM1; k=rsa; p=$(grep -v "BEGIN\|END" secrets/dkim/s1.public | tr -d '\n')\""
echo ""
echo "📧 Default admin credentials:"
echo "Email: admin@mailhero.in"
echo "Password: (set during first login)"