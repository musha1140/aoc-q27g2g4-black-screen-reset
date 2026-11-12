@echo off
title Q27 reset
echo.
echo  ==========================================================
echo   Q27 RESET (no need to pull the plug)
echo  ==========================================================
echo.
echo   The PC will now stop sending a picture to the Q27 for 30 seconds.
echo.
echo   DO THIS NOW:
echo     1. Press the Q27 power button OFF
echo     2. Count to three
echo     3. Press the Q27 power button ON
echo     4. Hands off
echo.
echo   After 30 seconds the PC sends the picture again.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0q27-path.ps1" -Action Cycle -Seconds 30
echo.
echo   Done. If the Q27 is still black, run this again.
echo   If it is still black after that, use the plug-pull method in README.md.
echo.
pause
