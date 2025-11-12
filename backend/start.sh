#!/bin/bash

# Quick start script for development

echo "🚀 Starting WebRTC Dialer Backend..."
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "⚠️  .env file not found!"
    echo "📝 Creating from template..."
    cp .env.example .env
    echo "✅ Created .env file"
    echo "⚠️  Please edit .env with your configuration before continuing"
    exit 1
fi

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Check if database exists
echo "🗄️  Checking database..."
npm run db:create 2>/dev/null || true

# Run migrations
echo "🔄 Running migrations..."
npm run db:migrate

# Start servers
echo ""
echo "✅ Starting development servers..."
echo "   API Server: http://localhost:3000"
echo "   Signaling Server: http://localhost:3001"
echo ""
echo "Press Ctrl+C to stop"
echo ""

npm run dev
