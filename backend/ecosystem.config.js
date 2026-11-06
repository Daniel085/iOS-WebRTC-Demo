/**
 * PM2 Ecosystem Configuration
 * For production deployments without Docker
 */

module.exports = {
  apps: [{
    name: 'webrtc-backend',
    script: './src/index.js',
    // Signaling keeps connected users / active calls in process memory, so run a
    // single instance. Scale out only after moving that state to Redis.
    instances: 1,
    exec_mode: 'fork',
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/pm2-error.log',
    out_file: './logs/pm2-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s',
    listen_timeout: 10000,
    kill_timeout: 5000
  }]
};
