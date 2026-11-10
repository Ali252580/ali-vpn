@echo off
chcp 65001 >nul
title Firefox VPN (Foxy) - Netherlands - SOCKS5 on 127.0.0.1:1080
cd /d "%~dp0"
echo ============================================
echo   Firefox VPN proxy - exit: Netherlands
echo   SOCKS5 address: 127.0.0.1 : 1080
echo   CLOSE this window to disconnect.
echo ============================================
fox-proxy.exe -country "Netherlands" -listen "127.0.0.1:1080"
pause
