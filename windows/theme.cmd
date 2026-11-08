@echo off
rem Runs theme.ps1 (the Majula theme) with admin rights; Windows asks for permission first.
net session >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0theme.ps1"
echo.
pause
