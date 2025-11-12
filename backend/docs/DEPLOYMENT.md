# Backend Deployment Guide

This guide covers deploying the WebRTC Dialer backend to various platforms.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Configuration](#environment-configuration)
- [Docker Deployment](#docker-deployment)
- [Cloud Platform Deployment](#cloud-platform-deployment)
  - [AWS (EC2 + RDS)](#aws-ec2--rds)
  - [DigitalOcean](#digitalocean)
  - [Heroku](#heroku)
  - [Railway](#railway)
- [VPS Manual Setup](#vps-manual-setup)
- [SSL/TLS Configuration](#ssltls-configuration)
- [Monitoring & Logging](#monitoring--logging)

## Prerequisites

Before deploying, ensure you have:

- [ ] PostgreSQL database (14+)
- [ ] Node.js 18+ installed (if not using Docker)
- [ ] SMS provider configured (Twilio, AWS SNS, or Firebase)
- [ ] Apple APNs certificate/key for VoIP pushes
- [ ] TURN server for NAT traversal (optional but recommended)
- [ ] Domain name with SSL certificate (for production)

## Environment Configuration

### 1. Copy Environment Template

```bash
cp .env.example .env
```

### 2. Configure Required Variables

**Critical - Must Change:**
```bash
# Generate strong secrets
JWT_SECRET=$(openssl rand -base64 32)
JWT_REFRESH_SECRET=$(openssl rand -base64 32)

# Database
DB_HOST=your-db-host
DB_NAME=webrtc_dialer
DB_USER=your-db-user
DB_PASSWORD=strong-password-here
```

**SMS Provider (choose one):**
```bash
# For Twilio
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=ACxxxxxxxxxx
TWILIO_AUTH_TOKEN=your-auth-token
TWILIO_VERIFY_SERVICE_SID=VAxxxxxxxxxx

# OR for AWS SNS
SMS_PROVIDER=aws-sns
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

**Apple Push Notifications:**
```bash
# Token-based (recommended)
APN_AUTH_METHOD=token
APN_KEY_PATH=./certs/AuthKey_XXXXXXXXXX.p8
APN_KEY_ID=XXXXXXXXXX
APN_TEAM_ID=XXXXXXXXXX
VOIP_BUNDLE_ID=com.yourcompany.webrtcdialer.voip

# OR Certificate-based
APN_AUTH_METHOD=cert
APN_CERT_PATH=./certs/voip_cert.pem
APN_KEY_PATH=./certs/voip_key.pem
```

## Docker Deployment

### Option 1: Docker Compose (Recommended for Quick Deploy)

**1. Create Environment File:**
```bash
cp .env.example .env
# Edit .env with your configuration
```

**2. Start All Services:**
```bash
# Basic setup (API + Postgres)
docker-compose up -d

# With Redis caching
docker-compose --profile with-redis up -d

# With Nginx reverse proxy
docker-compose --profile with-nginx up -d

# Everything
docker-compose --profile with-redis --profile with-nginx up -d
```

**3. Run Database Migrations:**
```bash
docker-compose exec backend npm run db:migrate
```

**4. View Logs:**
```bash
docker-compose logs -f backend
```

**5. Stop Services:**
```bash
docker-compose down
```

### Option 2: Docker Build Only

**1. Build Image:**
```bash
docker build -t webrtc-backend:latest .
```

**2. Run Container:**
```bash
docker run -d \
  --name webrtc-backend \
  -p 3000:3000 \
  -p 3001:3001 \
  -e NODE_ENV=production \
  -e DB_HOST=your-db-host \
  -e DB_NAME=webrtc_dialer \
  -e DB_USER=postgres \
  -e DB_PASSWORD=your-password \
  -e JWT_SECRET=your-secret \
  -e JWT_REFRESH_SECRET=your-refresh-secret \
  --restart unless-stopped \
  webrtc-backend:latest
```

## Cloud Platform Deployment

### AWS (EC2 + RDS)

**1. Create RDS PostgreSQL Instance:**
```bash
# Via AWS Console or CLI
aws rds create-db-instance \
  --db-instance-identifier webrtc-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password YOUR_PASSWORD \
  --allocated-storage 20
```

**2. Launch EC2 Instance:**
- AMI: Amazon Linux 2 or Ubuntu 22.04
- Instance Type: t3.small or larger
- Security Group: Allow ports 22, 80, 443, 3000, 3001

**3. SSH into EC2 and Setup:**
```bash
# Install Node.js
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Install PM2
sudo npm install -g pm2

# Clone repository
git clone https://github.com/yourusername/iOS-WebRTC-Demo.git
cd iOS-WebRTC-Demo/backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env
nano .env  # Edit with your RDS endpoint

# Run migrations
npm run db:migrate

# Start with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

**4. Setup Nginx as Reverse Proxy:**
```bash
sudo yum install -y nginx

# Configure Nginx
sudo nano /etc/nginx/conf.d/webrtc.conf
```

```nginx
upstream api_backend {
    server 127.0.0.1:3000;
}

upstream signaling_backend {
    server 127.0.0.1:3001;
}

server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

server {
    listen 80;
    server_name signaling.yourdomain.com;

    location / {
        proxy_pass http://signaling_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo systemctl start nginx
sudo systemctl enable nginx
```

### DigitalOcean

**Option 1: App Platform (Easiest)**

1. Fork repository on GitHub
2. Go to DigitalOcean App Platform
3. Create New App → GitHub → Select repo
4. Add Database Component:
   - Type: PostgreSQL
   - Plan: Basic ($15/month)
5. Configure Environment Variables in dashboard
6. Deploy!

**Estimated Cost:** $17-25/month

**Option 2: Droplet + Managed Database**

```bash
# Create droplet (Ubuntu 22.04)
# SSH into droplet

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2
sudo npm install -g pm2

# Clone and setup
git clone https://github.com/yourusername/iOS-WebRTC-Demo.git
cd iOS-WebRTC-Demo/backend
npm install

# Configure with Managed Database connection string
cp .env.example .env
nano .env

# Start
pm2 start ecosystem.config.js
pm2 startup
pm2 save
```

### Heroku

**1. Install Heroku CLI:**
```bash
brew install heroku/brew/heroku  # macOS
```

**2. Login and Create App:**
```bash
heroku login
heroku create webrtc-dialer-backend
```

**3. Add PostgreSQL:**
```bash
heroku addons:create heroku-postgresql:mini
```

**4. Set Environment Variables:**
```bash
heroku config:set NODE_ENV=production
heroku config:set JWT_SECRET=$(openssl rand -base64 32)
heroku config:set JWT_REFRESH_SECRET=$(openssl rand -base64 32)
heroku config:set SMS_PROVIDER=twilio
heroku config:set TWILIO_ACCOUNT_SID=ACxxxxxx
# ... set all required vars
```

**5. Create Procfile:**
```bash
echo "web: node src/index.js" > Procfile
```

**6. Deploy:**
```bash
git add .
git commit -m "Deploy to Heroku"
git push heroku main
```

**7. Run Migrations:**
```bash
heroku run npm run db:migrate
```

**Estimated Cost:** $7-25/month

### Railway

**1. Install Railway CLI:**
```bash
npm install -g @railway/cli
```

**2. Login and Initialize:**
```bash
railway login
railway init
```

**3. Add PostgreSQL:**
```bash
railway add --plugin postgresql
```

**4. Deploy:**
```bash
railway up
```

**5. Set Environment Variables:**
```bash
railway variables set JWT_SECRET=$(openssl rand -base64 32)
railway variables set SMS_PROVIDER=twilio
# ... set all vars
```

**Or use railway.json:**
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "NIXPACKS"
  },
  "deploy": {
    "startCommand": "node src/index.js",
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

**Estimated Cost:** $5-20/month

## VPS Manual Setup

For VPS providers like Linode, Vultr, or generic VPS:

**1. Initial Setup:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PostgreSQL 14
sudo apt install -y postgresql postgresql-contrib

# Install Nginx
sudo apt install -y nginx

# Install PM2
sudo npm install -g pm2
```

**2. Setup PostgreSQL:**
```bash
sudo -u postgres psql

CREATE DATABASE webrtc_dialer;
CREATE USER webrtc_user WITH ENCRYPTED PASSWORD 'strong-password';
GRANT ALL PRIVILEGES ON DATABASE webrtc_dialer TO webrtc_user;
\q
```

**3. Deploy Application:**
```bash
# Create app directory
sudo mkdir -p /var/www/webrtc-backend
sudo chown $USER:$USER /var/www/webrtc-backend

# Clone repository
cd /var/www/webrtc-backend
git clone https://github.com/yourusername/iOS-WebRTC-Demo.git .
cd backend

# Install dependencies
npm install --production

# Setup environment
cp .env.example .env
nano .env  # Configure all variables

# Run migrations
npm run db:migrate

# Start with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

**4. Setup Nginx (see AWS section above)**

**5. Setup Firewall:**
```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## SSL/TLS Configuration

### Option 1: Let's Encrypt (Free)

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d api.yourdomain.com -d signaling.yourdomain.com

# Auto-renewal
sudo certbot renew --dry-run
```

### Option 2: CloudFlare (Free)

1. Add domain to CloudFlare
2. Enable "Full (strict)" SSL mode
3. Point DNS to your server
4. CloudFlare handles SSL automatically

## Monitoring & Logging

### PM2 Monitoring

```bash
# View logs
pm2 logs

# Monitor resources
pm2 monit

# Web dashboard
pm2 install pm2-logrotate
pm2 web
```

### Production Logging

Add logging service (choose one):

**1. Papertrail:**
```bash
npm install winston-papertrail
```

**2. Loggly:**
```bash
npm install winston-loggly-bulk
```

**3. CloudWatch (AWS):**
```bash
npm install winston-cloudwatch
```

### Health Monitoring

Use services like:
- UptimeRobot (free)
- Pingdom
- Datadog
- New Relic

Setup health check endpoint:
```
GET https://api.yourdomain.com/health
```

## Post-Deployment Checklist

- [ ] SSL/TLS certificates configured
- [ ] Database migrations run successfully
- [ ] Environment variables all set
- [ ] SMS verification working
- [ ] VoIP push notifications working
- [ ] Logs being captured
- [ ] Health checks passing
- [ ] Firewall configured
- [ ] Backups configured for database
- [ ] Monitoring setup
- [ ] DNS records configured
- [ ] iOS app updated with production URLs

## Scaling Considerations

### Horizontal Scaling

```bash
# Increase PM2 instances
pm2 scale webrtc-backend 4

# Or in ecosystem.config.js
instances: 'max'  # Use all CPU cores
```

### Load Balancing

Use Nginx for load balancing multiple backend instances:

```nginx
upstream api_backend {
    least_conn;
    server 127.0.0.1:3000;
    server 127.0.0.1:3002;
    server 127.0.0.1:3004;
}
```

### Database Optimization

- Enable connection pooling
- Add read replicas for heavy read loads
- Use Redis for session caching
- Implement database indexes

## Troubleshooting

**Port already in use:**
```bash
lsof -i :3000
kill -9 <PID>
```

**Database connection failed:**
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check firewall
sudo ufw status

# Test connection
psql -h localhost -U postgres -d webrtc_dialer
```

**PM2 not starting:**
```bash
pm2 delete all
pm2 flush
pm2 start ecosystem.config.js
```

## Cost Estimates

| Platform | Monthly Cost | Notes |
|----------|-------------|-------|
| Railway | $5-20 | Hobby to Pro plan |
| Heroku | $7-25 | Eco to Basic |
| DigitalOcean | $17-30 | Droplet + Managed DB |
| AWS | $20-50 | t3.small + RDS t3.micro |
| VPS (Linode/Vultr) | $10-20 | 2GB RAM instance |

Plus external costs:
- SMS: $0.05/verification (Twilio)
- TURN: $10-50/month or self-hosted
- Domain: $10-15/year

## Support

For deployment issues:
- Check logs: `pm2 logs` or `docker-compose logs`
- Enable debug: `LOG_LEVEL=debug`
- Review troubleshooting section above
