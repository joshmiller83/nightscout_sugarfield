module.exports = {
  apps: [{
    name: 'nightscout',
    script: 'lib/server/server.js',
    cwd: '/opt/nightscout',
    env_file: '/opt/nightscout/.env',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '400M',
    error_file: '/var/log/nightscout/error.log',
    out_file: '/var/log/nightscout/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
  }],
};
