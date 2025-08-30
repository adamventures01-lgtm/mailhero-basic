# MailHero Basic

Minimal, reliable email service for @mailhero.in with Bhindi agent integration.

## Project Overview

MailHero Basic is a production-ready MVP email service that provides:
- User mailbox provisioning on @mailhero.in
- Authentication (signup, login, password management)
- Webmail interface (Gmail-like)
- Admin console for user management
- SMTP/IMAP endpoints for desktop/mobile clients
- Bhindi agent integration for orchestration

## Architecture

- **Mail Stack**: Postfix (SMTP) + Dovecot (IMAP) + Rspamd (spam filtering)
- **Database**: PostgreSQL for users, aliases, audit logs
- **Webmail**: React-based UI calling Bhindi agent tools
- **Containerization**: Docker Compose
- **Security**: TLS, SPF, DKIM, DMARC configured

## Quick Start

```bash
# Clone repository
git clone https://github.com/adamventures01-lgtm/mailhero-basic.git
cd mailhero-basic

# Run setup
./scripts/bootstrap.sh

# Start services
docker-compose up -d
```

## Project Structure

```
mailhero-basic/
├── agent/              # Bhindi agent implementation
├── webmail/           # React webmail UI
├── admin/             # Admin console
├── mail-stack/        # Postfix/Dovecot configs
├── docker/            # Docker configurations
├── scripts/           # Setup and deployment scripts
├── docs/              # Documentation
└── tests/             # Test suites
```

## Development Status

🚧 **In Development** - See [Project Board](https://github.com/adamventures01-lgtm/mailhero-basic/projects) for current progress.

## Documentation

- [API Documentation](docs/api.md)
- [Deployment Guide](docs/deployment.md)
- [DNS Configuration](docs/dns.md)
- [Security Guide](docs/security.md)