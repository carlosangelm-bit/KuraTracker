module.exports = {
  apps: [
    {
      name: 'kuratracker-web',
      script: 'python3',
      args: 'serve_spa.py',
      watch: false,
      instances: 1,
      exec_mode: 'fork'
    }
  ]
}
