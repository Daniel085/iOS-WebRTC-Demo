/**
 * PM2 Ecosystem Configuration
 * For production deployments without Docker
 */

module.exports = {
  apps: [{
    name: 'webrtc-backend',
    script: './src/index.js',
    instances: process.env.PM2_INSTANCES || 2,
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      API_PORT: 3000,
      SIGNALING_PORT: 3001
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
