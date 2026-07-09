module.exports = {
  apps: [
    {
      name: 'kuratracker-web',
      script: 'python3',
      args: '-m http.server 3000 --directory build/web',
      watch: false,
      instances: 1,
      exec_mode: 'fork'
    }
  ]
}
