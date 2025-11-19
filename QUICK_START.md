# Quick Start Guide

Get the app running in 5 minutes without PostgreSQL setup.

## Backend Setup (2 minutes)

1. **Install dependencies:**
   ```bash
   cd backend
   npm install
   ```

2. **Create environment file:**
   ```bash
   cp .env.example .env
   ```

   The default `.env.example` is already configured for quick start with:
   - `SKIP_DATABASE=true` (no PostgreSQL needed)
   - `SMS_PROVIDER=mock` (verification codes printed to console)

3. **Start the backend:**
   ```bash
   npm run dev
   ```

   You should see:
   ```
   ⚠️  Running WITHOUT database (SKIP_DATABASE=true)
   ⚠️  User data will NOT persist. For production, set up PostgreSQL.
   ✓ API Server running on port 3000
   ✓ Signaling Server running on port 3001
   ```

## iOS App Setup (3 minutes)

1. **Open in Xcode:**
   ```bash
   cd ios
   open WebRTCDialer.xcodeproj
   ```

2. **Add Swift Package Dependencies:**
   - File → Add Package Dependencies
   - Add these three packages:
     - `https://github.com/stasel/WebRTC.git`
     - `https://github.com/socketio/socket.io-client-swift.git`
     - `https://github.com/marmelroy/PhoneNumberKit.git`

3. **Configure App Transport Security:**
   - Select WebRTCDialer target → Info tab
   - Add `App Transport Security Settings` (Dictionary)
   - Add `Allow Arbitrary Loads` (Boolean = YES)

4. **Set signing team:**
   - Select WebRTCDialer target → Signing & Capabilities
   - Choose your development team

5. **Build and run:**
   - Press ⌘R

## Testing Authentication

1. **Enter any phone number** in the app (e.g., `+1234567890`)

2. **Get verification code** from backend console:
   ```
   [SMS Mock] Verification code for +1234567890: 123456
   ```

3. **Enter the code** in the app

4. **You're in!** You should see the main app interface.

## Important Notes

⚠️ **Data does NOT persist** - Users and sessions are lost when you restart the backend

⚠️ **For production**, you'll need to:
- Set `SKIP_DATABASE=false` in `.env`
- Install and configure PostgreSQL
- Run database migrations
- See `backend/README.md` for full setup

## Next Steps

- See `GETTING_STARTED.md` for full documentation
- See `docs/IMPLEMENTATION_ROADMAP.md` to continue building features
- See `backend/README.md` for PostgreSQL setup when ready

## Troubleshooting

**"Could not connect to the server"**
- Make sure backend is running: `cd backend && npm run dev`
- Check `ios/WebRTCDialer/Utilities/Constants.swift` has correct URLs
- Verify App Transport Security is configured in Xcode

**"Certificate is invalid"**
- Make sure you're using `http://` not `https://` in Constants.swift
- Backend URL should be `http://localhost:3000`

**Can't find verification code**
- Check the terminal where `npm run dev` is running
- Look for `[SMS Mock] Verification code for...`
