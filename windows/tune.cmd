@echo off
rem Runs tune.ps1 (performance and cleanup) with admin rights; Windows asks for permission first.
net session >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tune.ps1"
echo.
pause
