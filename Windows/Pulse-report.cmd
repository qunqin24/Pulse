@echo off
setlocal
set "ELECTRON_RUN_AS_NODE=1"
"%~dp0node_modules\electron\dist\electron.exe" "%~dp0src\usage-report-cli.js"
