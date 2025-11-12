# WebRTC Dialer Backend

Production-ready backend services for the iOS WebRTC Dialer application.

## Overview

This backend provides:
- **REST API** for user authentication and management (Port 3000)
- **WebSocket Signaling Server** for real-time call signaling (Port 3001)
- **Database** with PostgreSQL for persistent storage
- **VoIP Push Notifications** via Apple Push Notification service
- **SMS Verification** via Twilio, AWS SNS, or Firebase

## Quick Start

### Prerequisites

- Node.js 18+ and npm
- PostgreSQL 14+
- (Optional) Redis for production caching

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```bash
# Database
DB_HOST=localhost
DB_NAME=webrtc_dialer
DB_USER=postgres
DB_PASSWORD=your_password

# JWT Secrets (generate with: openssl rand -base64 32)
JWT_SECRET=your-secret-here
JWT_REFRESH_SECRET=your-refresh-secret-here

# SMS Provider (mock for development, twilio/aws-sns for production)
SMS_PROVIDER=mock

# For production, configure Twilio:
# TWILIO_ACCOUNT_SID=ACxxxxxx
# TWILIO_AUTH_TOKEN=xxxxxx
# TWILIO_VERIFY_SERVICE_SID=VAxxxxxx
```

### 3. Setup Database

```bash
# Create database
npm run db:create

# Run migrations
npm run db:migrate
```

### 4. Start Development Server

```bash
npm run dev
```

The servers will start:
- API: http://localhost:3000
- Signaling: http://localhost:3001

### 5. Test the API

```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "uptime": 10.5,
  "environment": "development"
}
```

## Project Structure

```
backend/
├── src/
│   ├── index.js                 # Main entry point
│   ├── api-server.js            # REST API server
│   ├── signaling-server.js      # WebSocket server
│   │
│   ├── routes/
│   │   ├── auth.js              # Authentication endpoints
│   │   └── user.js              # User management endpoints
│   │
│   ├── middleware/
│   │   ├── auth.js              # JWT authentication
│   │   └── errorHandler.js     # Error handling
│   │
│   ├── services/
│   │   ├── sms-verification.js  # SMS sending/verification
│   │   └── voip-push.js         # VoIP push notifications
│   │
│   ├── database/
│   │   ├── models/              # Sequelize models
│   │   │   ├── index.js
│   │   │   ├── user.js
│   │   │   ├── call.js
│   │   │   ├── voipToken.js
│   │   │   └── refreshToken.js
│   │   ├── migrations/          # Database migrations
│   │   ├── config/
│   │   │   └── config.js        # Sequelize config
│   │   └── create-db.js         # Database creation script
│   │
│   └── utils/
│       ├── logger.js            # Winston logger
│       └── cache.js             # Cache utility
│
├── docs/
│   └── DEPLOYMENT.md            # Deployment guide
│
├── .env.example                 # Environment template
├── .sequelizerc                 # Sequelize configuration
├── package.json
├── Dockerfile                   # Docker image
├── docker-compose.yml           # Docker Compose setup
└── ecosystem.config.js          # PM2 configuration
```

## API Documentation

### Authentication Endpoints

#### Send Verification Code
```http
POST /api/auth/send-code
Content-Type: application/json

{
  "phoneNumber": "+1234567890"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Verification code sent successfully"
}
```

**Note:** In `mock` mode, the code is printed to console.

#### Verify Code
```http
POST /api/auth/verify-code
Content-Type: application/json

{
  "phoneNumber": "+1234567890",
  "code": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "uuid",
    "phoneNumber": "+1234567890",
    "displayName": null,
    "createdAt": "2024-01-01T12:00:00.000Z"
  }
}
```

#### Refresh Token
```http
POST /api/auth/refresh
Content-Type: application/json

{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

#### Logout
```http
POST /api/auth/logout
Content-Type: application/json

{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### User Endpoints

All user endpoints require authentication header:
```http
Authorization: Bearer <token>
```

#### Get Profile
```http
GET /api/user/profile
```

#### Update Profile
```http
PUT /api/user/profile
Content-Type: application/json

{
  "displayName": "John Doe"
}
```

#### Register VoIP Token
```http
POST /api/user/voip-token
Content-Type: application/json

{
  "token": "device-push-token-here",
  "deviceId": "optional-device-id"
}
```

#### Get Call History
```http
GET /api/user/call-history?limit=50&offset=0
```

#### Delete Account
```http
DELETE /api/user/account
```

## WebSocket Signaling Events

Connect to signaling server:
```javascript
const socket = io('ws://localhost:3001', {
  auth: {
    token: 'your-jwt-token'
  }
});
```

### Client → Server Events

#### Register Connection
```javascript
socket.emit('register');
```

#### Initiate Call
```javascript
socket.emit('call-initiate', {
  to: '+1234567890',
  callId: 'uuid',
  hasVideo: true
});
```

#### Answer Call
```javascript
socket.emit('call-answer', {
  callId: 'uuid'
});
```

#### Reject Call
```javascript
socket.emit('call-reject', {
  callId: 'uuid',
  reason: 'busy'
});
```

#### End Call
```javascript
socket.emit('call-end', {
  callId: 'uuid'
});
```

#### Send SDP Offer
```javascript
socket.emit('offer', {
  callId: 'uuid',
  sdp: { type: 'offer', sdp: '...' },
  to: '+1234567890'
});
```

#### Send SDP Answer
```javascript
socket.emit('answer', {
  callId: 'uuid',
  sdp: { type: 'answer', sdp: '...' }
});
```

#### Send ICE Candidate
```javascript
socket.emit('ice-candidate', {
  callId: 'uuid',
  candidate: { ... },
  to: '+1234567890'
});
```

### Server → Client Events

#### Registration Confirmed
```javascript
socket.on('registered', (data) => {
  console.log('Registered:', data.phoneNumber);
});
```

#### Incoming Call
```javascript
socket.on('incoming-call', (data) => {
  console.log('Call from:', data.from);
  console.log('Call ID:', data.callId);
  console.log('Has video:', data.hasVideo);
});
```

#### Call Answered
```javascript
socket.on('call-answered', (data) => {
  console.log('Call answered by:', data.by);
});
```

#### Call Rejected
```javascript
socket.on('call-rejected', (data) => {
  console.log('Call rejected:', data.reason);
});
```

#### Call Ended
```javascript
socket.on('call-ended', (data) => {
  console.log('Call ended by:', data.by);
});
```

#### Receive SDP Offer
```javascript
socket.on('offer', (data) => {
  console.log('Received offer:', data.sdp);
});
```

#### Receive SDP Answer
```javascript
socket.on('answer', (data) => {
  console.log('Received answer:', data.sdp);
});
```

#### Receive ICE Candidate
```javascript
socket.on('ice-candidate', (data) => {
  console.log('Received ICE candidate:', data.candidate);
});
```

#### Call Error
```javascript
socket.on('call-error', (data) => {
  console.error('Call error:', data.error);
});
```

## Development

### Run in Development Mode

```bash
npm run dev
```

This uses `nodemon` for auto-restart on file changes.

### Run API and Signaling Separately

```bash
# Terminal 1
npm run dev:api

# Terminal 2
npm run dev:signaling
```

### Run Tests

```bash
npm test

# Watch mode
npm run test:watch
```

### Linting

```bash
npm run lint

# Auto-fix
npm run lint:fix
```

### Database Commands

```bash
# Create database
npm run db:create

# Run migrations
npm run db:migrate

# Undo last migration
npm run db:migrate:undo

# Run seeders
npm run db:seed
```

## Production Deployment

### Option 1: Docker (Recommended)

```bash
# Build and start
docker-compose up -d

# View logs
docker-compose logs -f backend

# Stop
docker-compose down
```

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed instructions.

### Option 2: PM2 (Without Docker)

```bash
# Install PM2
npm install -g pm2

# Start
pm2 start ecosystem.config.js

# Monitor
pm2 monit

# Logs
pm2 logs

# Restart
pm2 restart webrtc-backend

# Stop
pm2 stop webrtc-backend
```

### Option 3: Cloud Platforms

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for:
- AWS (EC2 + RDS)
- DigitalOcean
- Heroku
- Railway
- VPS manual setup

## Configuration

### SMS Providers

#### Mock (Development)
```bash
SMS_PROVIDER=mock
```
Codes are printed to console.

#### Twilio
```bash
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=ACxxxxxx
TWILIO_AUTH_TOKEN=xxxxxx
TWILIO_VERIFY_SERVICE_SID=VAxxxxxx
```

#### AWS SNS
```bash
SMS_PROVIDER=aws-sns
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=xxxxxx
AWS_SECRET_ACCESS_KEY=xxxxxx
```

#### Firebase
```bash
SMS_PROVIDER=firebase
# Firebase Phone Auth is handled client-side
```

### VoIP Push Notifications

#### Token-Based (Recommended)
```bash
APN_AUTH_METHOD=token
APN_KEY_PATH=./certs/AuthKey_XXXXXXXXXX.p8
APN_KEY_ID=XXXXXXXXXX
APN_TEAM_ID=XXXXXXXXXX
VOIP_BUNDLE_ID=com.yourcompany.webrtcdialer.voip
```

#### Certificate-Based
```bash
APN_AUTH_METHOD=cert
APN_CERT_PATH=./certs/voip_cert.pem
APN_KEY_PATH=./certs/voip_key.pem
VOIP_BUNDLE_ID=com.yourcompany.webrtcdialer.voip
```

### Redis (Optional - Production)

```bash
USE_REDIS=true
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=optional
```

## Monitoring

### Health Check

```bash
curl http://localhost:3000/health
```

### Logs

**Development:**
```bash
npm run dev  # Logs to console
```

**Production with PM2:**
```bash
pm2 logs webrtc-backend
```

**Production with Docker:**
```bash
docker-compose logs -f backend
```

### Log Levels

Set in `.env`:
```bash
LOG_LEVEL=debug  # debug, info, warn, error
```

## Security

### Best Practices

1. **Change default secrets:**
   ```bash
   JWT_SECRET=$(openssl rand -base64 32)
   JWT_REFRESH_SECRET=$(openssl rand -base64 32)
   ```

2. **Use environment variables** - Never commit `.env`

3. **Enable SSL/TLS** in production

4. **Configure CORS:**
   ```bash
   ALLOWED_ORIGINS=https://yourdomain.com
   ```

5. **Rate limiting** is enabled by default

6. **Database encryption** - Use SSL connections in production:
   ```bash
   DB_SSL=true
   ```

7. **Regular updates:**
   ```bash
   npm audit
   npm update
   ```

## Troubleshooting

### Database Connection Failed

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection
psql -h localhost -U postgres -d webrtc_dialer
```

### Port Already in Use

```bash
# Find process using port
lsof -i :3000

# Kill process
kill -9 <PID>
```

### VoIP Push Not Working

1. Check APNs credentials are correct
2. Verify bundle ID matches iOS app
3. Test in production mode (APNs sandbox doesn't work with production certs)
4. Check logs for errors:
   ```bash
   LOG_LEVEL=debug npm run dev
   ```

### SMS Not Sending

1. Verify provider credentials
2. Check phone number format (E.164: +1234567890)
3. In development, use `SMS_PROVIDER=mock` and check console

## Testing with iOS App

1. **Start backend:**
   ```bash
   npm run dev
   ```

2. **Update iOS app constants** (`ios/WebRTCDialer/Utilities/Constants.swift`):
   ```swift
   enum API {
       static let baseURL = "http://localhost:3000"
       static let signalingURL = "ws://localhost:3001"
   }
   ```

3. **For device testing** (not simulator):
   - Get your computer's local IP: `ifconfig | grep inet`
   - Update iOS constants:
     ```swift
     static let baseURL = "http://192.168.1.100:3000"
     static let signalingURL = "ws://192.168.1.100:3001"
     ```

## Support

For issues:
- Check logs for errors
- Enable debug logging: `LOG_LEVEL=debug`
- Review [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- Check troubleshooting section above

## License

MIT
